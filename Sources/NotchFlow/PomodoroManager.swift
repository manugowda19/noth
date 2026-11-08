import AppKit
import Combine

// A minimal Pomodoro timer surfaced in the notch: work then break, looping,
// with a countdown in the collapsed strip and a beep at each transition.
// ponytail: fixed 5-min break, no long-break-every-4 cycle or persistence —
// add those only if someone actually uses it enough to miss them.
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    enum Phase { case work, rest }

    @Published private(set) var running = false
    @Published private(set) var phase: Phase = .work
    @Published private(set) var remaining = 0   // seconds
    /// Paused mid-phase: the countdown is dropped and `remaining` frozen;
    /// resume re-anchors a new end date from it.
    @Published private(set) var paused = false
    /// Which session of the set (1/4…4/4) and whether this break is the long one.
    @Published private(set) var cycle = PomodoroCycle()

    private var timer: Timer?
    /// The current phase's end, so time stays exact across sleep or a late
    /// tick; `remaining` is derived from it, never decremented.
    private var countdown: Countdown?
    private var workMinutes = 25
    private let restMinutes = 5

    private init() {}

    /// Countdown as `M:SS`.
    var label: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }

    func start(workMinutes: Int) {
        self.workMinutes = workMinutes
        cycle = PomodoroCycle()
        phase = .work
        countdown = Countdown(seconds: Double(workMinutes * 60), from: Date())
        remaining = workMinutes * 60
        running = true
        paused = false
        arm()
    }

    func togglePause() {
        guard running else { return }
        if paused {
            countdown = Countdown(seconds: Double(remaining), from: Date())
            paused = false
            arm()
        } else {
            if let countdown { remaining = countdown.remaining(at: Date()) }
            countdown = nil
            timer?.invalidate()
            timer = nil
            paused = true
        }
    }

    /// Back to the start of the current phase, keeping it running.
    func restartPhase() {
        guard running else { return }
        remaining = cycle.minutes(work: workMinutes, rest: restMinutes) * 60
        countdown = paused ? nil : Countdown(seconds: Double(remaining), from: Date())
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        countdown = nil
        running = false
        paused = false
        remaining = 0
    }

    private func arm() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let countdown else { return }
        let now = Date()
        if !countdown.isFinished(at: now) {
            remaining = countdown.remaining(at: now)
        } else {
            advance()   // hit zero → next phase of the set, beep
        }
    }

    /// Skip to the next phase now (focus → break, break → next focus).
    func skip() {
        guard running else { return }
        advance(sound: false)
    }

    private func advance(sound: Bool = true) {
        let finishedWork = phase == .work
        cycle.advance()
        phase = cycle.phase == .work ? .work : .rest
        remaining = cycle.minutes(work: workMinutes, rest: restMinutes) * 60
        countdown = paused ? nil : Countdown(seconds: Double(remaining), from: Date())
        guard sound else { return }
        // Distinct cue: "Glass" when a work block ends (go rest), "Ping" when a
        // break ends (back to work). Falls back to the system beep.
        if let sound = NSSound(named: finishedWork ? "Glass" : "Ping") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
