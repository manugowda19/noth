import Combine
import Foundation

// Shelf stopwatch (start / pause / reset) with a running wing in the notch.
// Opt-in card (`AppSettings.showStopwatch`). No timer: views tick themselves
// with TimelineView from the Stopwatch value.
final class StopwatchManager: ObservableObject {
    static let shared = StopwatchManager()

    @Published private(set) var watch = Stopwatch()
    @Published private(set) var running = false

    private init() {}

    func toggle() {
        if watch.running { watch.pause(at: Date()) } else { watch.start(at: Date()) }
        running = watch.running
    }

    func reset() {
        watch.reset()
        running = false
    }
}
