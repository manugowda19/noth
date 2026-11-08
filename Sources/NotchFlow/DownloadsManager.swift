import AppKit
import Combine
import Foundation

// Download progress in the notch. Opt-in (`AppSettings.showDownloads`): reading
// ~/Downloads triggers the Downloads-folder permission prompt once. Polls the
// directory listing every second while on — one readdir, no file contents
// except Safari's small Info.plist for its byte counts.
// ponytail: 1 s readdir poll; switch to an FSEvents stream if it ever shows up
// in Energy Impact.
final class DownloadsManager: ObservableObject {
    static let shared = DownloadsManager()

    /// The newest in-progress download (display name, progress or nil when the
    /// browser doesn't expose a total), and how many are running.
    @Published private(set) var active: (name: String, progress: Double?)?
    @Published private(set) var activeCount = 0
    /// Briefly set when a download completes — drives a short "done" flash.
    @Published private(set) var justFinished: String?

    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads")
    private var previous: [String] = []
    private var timer: Timer?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        previous = Downloads.inProgress(listing())
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        active = nil
        activeCount = 0
        justFinished = nil
    }

    /// Reveal a finished download in Finder (tap on the done flash).
    func revealFinished() {
        guard let name = justFinished else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir.appendingPathComponent(name)])
    }

    private func listing() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    private func poll() {
        let names = listing()
        let current = Downloads.inProgress(names)
        if let done = Downloads.finished(previous: previous, current: current,
                                         files: Set(names)).last {
            flash(done)
        }
        previous = current

        // Newest partial by modification date is the one worth showing.
        let newest = current.max { modified($0) < modified($1) }
        let next = newest.map { (Downloads.finalName($0), progress(of: $0)) }
        if next?.0 != active?.name || next?.1 != active?.progress { active = next }
        if activeCount != current.count { activeCount = current.count }
    }

    private func modified(_ name: String) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
        return attrs?[.modificationDate] as? Date ?? .distantPast
    }

    private func progress(of partial: String) -> Double? {
        let plist = dir.appendingPathComponent(partial).appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return nil }
        return Downloads.safariProgress(info)
    }

    private func flash(_ name: String) {
        justFinished = name
        RecentActivityManager.shared.add(.download, title: name,
                                         detail: dir.appendingPathComponent(name).path)
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.justFinished = nil
        }
    }
}
