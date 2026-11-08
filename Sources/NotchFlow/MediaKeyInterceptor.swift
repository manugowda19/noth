import AppKit
import ApplicationServices

// Intercepts the hardware volume keys via a CGEvent tap so NotchFlow's notch
// HUD replaces the system bezel. Public API, but requires the user to grant
// Accessibility permission. Only volume up/down/mute are touched — every
// other event passes through untouched.
final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private static let systemDefined = CGEventType(rawValue: 14)! // NX_SYSDEFINED

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    var isRunning: Bool { tap != nil }

    /// Try to start intercepting. Returns false when Accessibility isn't
    /// granted — with `promptIfNeeded`, macOS shows its grant dialog and the
    /// user re-enables the toggle after granting.
    @discardableResult
    func start(promptIfNeeded: Bool = true) -> Bool {
        guard tap == nil else { return true }

        let trusted = promptIfNeeded
            ? AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            : AXIsProcessTrusted()
        guard trusted else { return false }

        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << Self.systemDefined.rawValue),
            callback: { _, _, event, _ in MediaKeyInterceptor.shared.handle(event) },
            userInfo: nil)
        guard let tap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps that stall or when a secure field focuses —
        // re-enable instead of silently dying.
        if cgEvent.type == .tapDisabledByTimeout || cgEvent.type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(cgEvent)
        }

        guard cgEvent.type == Self.systemDefined,
              let event = NSEvent(cgEvent: cgEvent),
              event.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }

        // data1 layout: key code in the top 16 bits, key state (0xA down /
        // 0xB up) in the second byte. NX_KEYTYPE_SOUND_UP/DOWN/MUTE = 0/1/7,
        // BRIGHTNESS_UP/DOWN = 2/3, ILLUMINATION_UP/DOWN = 21/22.
        let keyCode = (event.data1 & 0xFFFF_0000) >> 16
        guard [0, 1, 7, 2, 3, 21, 22].contains(keyCode) else { return Unmanaged.passRetained(cgEvent) }

        // If a private bridge is gone (macOS moved the symbols), hand those keys
        // back to the system so the underlying function still works.
        if [2, 3].contains(keyCode), !BrightnessManager.shared.isAvailable {
            return Unmanaged.passRetained(cgEvent)
        }
        if [21, 22].contains(keyCode), !KeyboardBacklightManager.shared.isAvailable {
            return Unmanaged.passRetained(cgEvent)
        }

        if (event.data1 & 0xFF00) >> 8 == 0xA {
            switch keyCode {
            case 0: VolumeManager.shared.stepVolume(up: true)
            case 1: VolumeManager.shared.stepVolume(up: false)
            case 2: BrightnessManager.shared.step(up: true)
            case 3: BrightnessManager.shared.step(up: false)
            case 21: KeyboardBacklightManager.shared.step(up: true)
            case 22: KeyboardBacklightManager.shared.step(up: false)
            default: VolumeManager.shared.toggleMute()
            }
        }
        return nil // swallow down and up so the system bezel never fires
    }
}
