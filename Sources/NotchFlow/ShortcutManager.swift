import AppKit
import Carbon

// ⌥⌘J (open the Command Center) is a Carbon hotkey: always on and needs no
// permission, so the advertised way in works on a fresh install.
//
// Global action hotkeys (⌥⌘N / ⌥⌘P / ⌥⌘S / ⌥⌘M / ⌥⌘K). One-shot actions only — not a shelf
// toggle, which would fight the hover auto-collapse. Uses a global event
// monitor (needs Input Monitoring / Accessibility, prompted on first enable);
// it only observes, never consumes, so an unbound combo is safe.
// ponytail: three fixed combos, no recorder — add a recorder if anyone rebinds.
final class ShortcutManager {
    static let shared = ShortcutManager()

    private var monitor: Any?
    private var openHotKey: EventHotKeyRef?
    private init() {}

    func registerOpenHotKey() {
        guard openHotKey == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppCoordinator.shared.openCommandCenter() }
            return noErr
        }, 1, &pressed, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(cmdKey | optionKey),
                            EventHotKeyID(signature: 0x4E4F5448, id: 1),  // "NOTH"
                            GetApplicationEventTarget(), 0, &openHotKey)
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        // Exactly Command+Option (ignore capslock/fn/numpad noise).
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if mods == [.control, .option], AppSettings.shared.windowSnapping {
            snap(event.keyCode)
            return
        }
        guard mods == [.command, .option] else { return }
        switch event.keyCode {
        case 45: NotesController.shared.present()        // N
        case 35: togglePomodoro()                        // P
        case 1:  AppCoordinator.shared.screenshot()      // S
        case 40: QuickBarController.shared.present()     // K — quick bar
        case 46:                                         // M — mic mute
            if AppSettings.shared.showPrivacy { PrivacyManager.shared.toggleMute() }
        default: break
        }
    }

    // ⌃⌥ ← → ↑ ↩ — halves, maximize, center.
    private func snap(_ keyCode: UInt16) {
        switch keyCode {
        case 123: WindowSnapper.snap(.left)
        case 124: WindowSnapper.snap(.right)
        case 126: WindowSnapper.snap(.maximize)
        case 36:  WindowSnapper.snap(.center)
        default: break
        }
    }

    private func togglePomodoro() {
        let pomodoro = PomodoroManager.shared
        if pomodoro.running { pomodoro.stop() } else { pomodoro.start(workMinutes: 25) }
    }
}
