import AppKit
import Combine

// Self-tracked screen time: accumulate foreground seconds per app by watching
// NSWorkspace app-activation. No Apple ScreenTime API, no OS blocker; stays on
// this Mac. Opt-in — tracking only runs while enabled. Resets each day; today's
// tallies persist across relaunches.
// ponytail: per-app names only, no category buckets — add categories if the flat
// ranking proves too coarse.
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    @Published private(set) var totals: [String: TimeInterval] = [:]   // appName -> seconds today
    @Published private(set) var switches = 0

    private var current: String?
    private var since: Date?
    private var dayKey = ""
    private var observer: Any?
    private var flushTimer: Timer?

    private init() {}

    /// Top apps by time today, most first.
    var ranked: [(app: String, seconds: TimeInterval)] {
        totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    func start() {
        guard observer == nil else { return }
        loadToday()
        current = NSWorkspace.shared.frontmostApplication?.localizedName
        since = Date()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .localizedName
            self?.switched(to: app)
        }
        // Accrue the current app's time even without switching, so the display
        // and persistence stay fresh.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.flush(); self?.save() }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    func stop() {
        flush()
        save()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        flushTimer?.invalidate()
        flushTimer = nil
    }

    private func switched(to app: String?) {
        flush()
        current = app
        since = Date()
        switches += 1
        save()
    }

    /// Bank the current app's elapsed time into today's totals.
    private func flush() {
        rolloverIfNeeded()
        guard let current, let since else { return }
        totals[current, default: 0] += Date().timeIntervalSince(since)
        self.since = Date()
    }

    private func rolloverIfNeeded() {
        let today = Self.dayString()
        guard today != dayKey else { return }
        dayKey = today
        totals = [:]
        switches = 0
    }

    private static func dayString() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func loadToday() {
        let d = UserDefaults.standard
        dayKey = Self.dayString()
        if d.string(forKey: "screenTimeDay") == dayKey {
            totals = (d.dictionary(forKey: "screenTimeTotals") as? [String: TimeInterval]) ?? [:]
            switches = d.integer(forKey: "screenTimeSwitches")
        } else {
            totals = [:]; switches = 0
        }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(dayKey, forKey: "screenTimeDay")
        d.set(totals, forKey: "screenTimeTotals")
        d.set(switches, forKey: "screenTimeSwitches")
    }
}
