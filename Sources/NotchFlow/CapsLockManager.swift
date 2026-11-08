import AppKit
import Combine

// Caps Lock HUD: a short wing flash when Caps Lock turns on or off. Opt-in
// (`AppSettings.capsLockHUD`). Reads the modifier state with
// CGEventSource.flagsState — no Accessibility/Input Monitoring needed, unlike
// an event monitor.
// ponytail: 0.15 s flag poll; an IOHID LED listener would be event-driven but
// needs Input Monitoring.
final class CapsLockManager: ObservableObject {
    static let shared = CapsLockManager()

    @Published private(set) var isOn = false
    @Published private(set) var hudVisible = false

    private var timer: Timer?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        isOn = Self.read()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hudVisible = false
    }

    private static func read() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    private func poll() {
        let now = Self.read()
        guard now != isOn else { return }
        isOn = now
        hudVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.hudVisible = false
        }
    }
}
