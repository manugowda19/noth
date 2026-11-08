import Foundation

// Keep the Mac awake (prevent idle system sleep) while on. The activity is
// ended when turned off and goes away with the process on quit. Persists
// across launches (AppSettings re-applies it on init).
final class KeepAwakeManager {
    static let shared = KeepAwakeManager()

    private var activity: NSObjectProtocol?

    private init() {}

    func set(_ on: Bool) {
        if on, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled,
                                                             reason: "NØTH Keep Awake")
        } else if !on, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
