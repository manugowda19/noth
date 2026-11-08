import AppKit
import Combine

// "Time for a break" after 50 minutes of unbroken activity (5 idle minutes
// count as a break). Opt-in (`AppSettings.breakReminders`). Idle time comes
// from CGEventSource — public, no Input Monitoring. The rules live in
// TimeKeeping's BreakTimer.
// ponytail: fixed 50/5 minutes; expose them in Settings if anyone asks.
final class BreakReminderManager: ObservableObject {
    static let shared = BreakReminderManager()

    @Published private(set) var reminderVisible = false

    private var breakTimer = BreakTimer()
    private var timer: Timer?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        breakTimer = BreakTimer()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reminderVisible = false
    }

    private func poll() {
        // kCGAnyInputEventType (0xFFFFFFFF); imported C enums accept any raw value.
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        guard breakTimer.update(now: Date(), idle: idle) else { return }
        reminderVisible = true
        (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.reminderVisible = false
        }
    }
}
