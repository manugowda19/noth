import AppKit
import ApplicationServices

// Clean mode: swallow all keyboard input for a fixed interval so the user can
// wipe the keyboard without triggering anything. A CGEventTap eats keyDown /
// keyUp / flagsChanged; the mouse is left alone so it stays the escape hatch.
//
// Exit is guaranteed three ways, none of them the keyboard (the keyboard is
// dead while active):
//   1. The countdown timer always stops it — the hard guarantee.
//   2. A mouse "hold to cancel" control in the notch countdown UI.
//   3. It never starts without Accessibility, so it can't silently no-op and
//      leave the user thinking keys are locked when they aren't.
final class CleanModeManager: ObservableObject {
    static let shared = CleanModeManager()

    @Published private(set) var active = false
    @Published private(set) var remaining = 0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var countdown: Timer?

    private init() {}

    /// Returns false when Accessibility isn't granted (prompt is shown).
    @discardableResult
    func start(seconds: Int) -> Bool {
        guard !active, seconds > 0 else { return active }

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        guard trusted else { return false }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue
            | 1 << CGEventType.keyUp.rawValue
            | 1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in CleanModeManager.shared.handle(event) },
            userInfo: nil)
        guard let tap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        active = true
        remaining = seconds
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 { stop() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        countdown?.invalidate()
        countdown = nil
        active = false
        remaining = 0
    }

    private static let escapeKeyCode: Int64 = 53

    private func handle(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Keep the tap alive if macOS disables it mid-interval; the countdown
        // timer is still the hard exit, so re-enabling just keeps keys locked
        // for the remainder rather than unlocking early.
        if cgEvent.type == .tapDisabledByTimeout || cgEvent.type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(cgEvent)
        }
        // Escape is the keyboard escape hatch — cancel immediately so the user
        // is never trapped until the timer ends.
        if cgEvent.type == .keyDown,
           cgEvent.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode {
            DispatchQueue.main.async { self.stop() }
            return nil
        }
        return nil // swallow every other key event
    }
}
