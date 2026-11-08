import Foundation

// Pure time logic for the stopwatch and break reminders — no timers here, so
// the swiftc harness can drive it with fixed dates.

/// A pausable stopwatch as a value: accumulated time plus the running span.
struct Stopwatch: Equatable {
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?

    var running: Bool { startedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    mutating func start(at now: Date) {
        if startedAt == nil { startedAt = now }
    }

    mutating func pause(at now: Date) {
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    mutating func reset() { self = Stopwatch() }

    /// "M:SS" under an hour, "H:MM:SS" after.
    static func label(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A countdown anchored to an end date, so it stays exact through sleep,
/// timer coalescing or a busy main thread (no per-tick decrementing).
struct Countdown: Equatable {
    let endsAt: Date

    init(seconds: TimeInterval, from now: Date) { endsAt = now.addingTimeInterval(seconds) }

    /// Whole seconds left, rounded up (shows 0:01 until the last second ends).
    func remaining(at now: Date) -> Int { max(0, Int(ceil(endsAt.timeIntervalSince(now)))) }

    func isFinished(at now: Date) -> Bool { now >= endsAt }
}

/// Pomodoro set: `sessionsPerSet` focus sessions, a short break after each,
/// and a long break after the last one — then a new set starts at 1.
struct PomodoroCycle: Equatable {
    enum Phase: Equatable { case work, rest, longRest }

    var session = 1
    var phase: Phase = .work
    var sessionsPerSet = 4

    func minutes(work: Int, rest: Int = 5, longRest: Int = 15) -> Int {
        switch phase {
        case .work: work
        case .rest: rest
        case .longRest: longRest
        }
    }

    /// Next phase — also what "skip" does.
    mutating func advance() {
        switch phase {
        case .work: phase = session >= sessionsPerSet ? .longRest : .rest
        case .rest: session += 1; phase = .work
        case .longRest: session = 1; phase = .work
        }
    }

    /// "2/4"
    var label: String { "\(session)/\(sessionsPerSet)" }
}

/// Continuous-activity tracking for break reminders: activity starts a
/// session, `idleReset` of inactivity ends it, and `threshold` of unbroken
/// activity fires once (then a new session starts).
struct BreakTimer: Equatable {
    var threshold: TimeInterval = 50 * 60
    var idleReset: TimeInterval = 5 * 60
    private(set) var activeSince: Date?

    /// Feed one sample (`idle` = seconds since the last input event).
    /// Returns true when a reminder should fire.
    mutating func update(now: Date, idle: TimeInterval) -> Bool {
        if idle >= idleReset {           // a real break happened — start over
            activeSince = nil
            return false
        }
        guard let since = activeSince else {
            activeSince = now.addingTimeInterval(-idle)
            return false
        }
        if now.timeIntervalSince(since) >= threshold {
            activeSince = now
            return true
        }
        return false
    }
}
