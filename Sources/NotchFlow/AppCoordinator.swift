import AppKit
import Combine

// Central app state + the shelf's actions. Owns the FileStore and exposes it
// reactively so SwiftUI views can bind to it directly. Later phases (Now
// Playing, HUD) hang their own published state off this same coordinator
// instead of each inventing their own.
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var isExpanded = false
    // Hover-peek: the compact info strip between the bare notch and the full
    // hub. Driven by NotchWindow's hover poll; a click on the strip promotes it
    // to `isExpanded`. Kept distinct so hover never opens the whole hub — the
    // hub is intentional-interaction only (spec §2).
    @Published var isPeeking = false
    @Published var showSettings = false
    /// Opened from the keyboard or menu (not by hover): stays open until Esc,
    /// or until the pointer has been inside the panel and leaves it.
    @Published var keyboardOpen = false

    func openCommandCenter(tab: CommandTab? = nil) {
        if let tab { self.tab = tab }
        showSettings = false
        keyboardOpen = true
        isExpanded = true
    }

    func closeCommandCenter() {
        keyboardOpen = false
        showSettings = false
        isPeeking = false
        isExpanded = false
    }

    /// Command Center section; remembered across launches.
    @Published var tab: CommandTab =
        CommandTab(rawValue: UserDefaults.standard.string(forKey: "commandTab") ?? "") ?? .home {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "commandTab") }
    }
    // A file drag is hovering the notch — turns it into a drop target (spec §2
    // State 3) instead of opening the full hub. `justAdded` briefly holds the
    // dropped filename to flash a "✓ Added" confirmation, then clears itself.
    @Published var dropActive = false
    @Published var justAdded: String?
    @Published private(set) var files: [URL] = []

    private let store = FileStore()
    private let persistKey = "shelfFiles"

    private init() {
        // Restore parked files across relaunches, dropping any that vanished.
        // ponytail: stores paths, not security-scoped bookmarks — a moved file
        // is dropped rather than followed; add bookmarks if that matters.
        let saved = UserDefaults.standard.stringArray(forKey: persistKey) ?? []
        let existing = saved.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        store.add(contentsOf: existing)
        files = store.files
    }

    private func persist() {
        UserDefaults.standard.set(store.files.map(\.path), forKey: persistKey)
    }

    /// Park dropped files. `confirm` (a user drag onto the notch) flashes a
    /// compact "✓ Added" in the notch and stays collapsed (spec §2 State 3);
    /// otherwise (e.g. a captured screenshot) it opens the hub to show the file.
    func handleDrop(urls: [URL], confirm: Bool = false) {
        let added = store.add(contentsOf: urls)
        if !added.isEmpty {
            files = store.files
            persist()
        }
        if confirm {
            // Flash the last dropped name, then clear — unless a newer drop has
            // replaced it in the meantime.
            let name = added.last?.lastPathComponent ?? urls.last?.lastPathComponent
            justAdded = name
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                if self?.justAdded == name { self?.justAdded = nil }
            }
        } else {
            isExpanded = true
        }
    }

    func clear() {
        store.clear()
        files = []
        persist()
    }

    func remove(_ url: URL) {
        guard store.remove(url) else { return }
        files = store.files
        persist()
    }

    func airdrop() {
        guard !store.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: store.files)
    }

    /// AirDrop dropped files straight out, without parking them on the shelf.
    func airdropURLs(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    /// Copy dropped files' POSIX paths to the pasteboard, without parking them.
    func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func copyPath() {
        guard !store.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.joinedPaths, forType: .string)
        DeviceNoticeManager.shared.show(.init(symbol: "checkmark.circle.fill",
                                              text: store.files.count == 1 ? "Path copied" : "\(store.files.count) paths copied",
                                              style: .success))
    }

    func quickLook() {
        guard !store.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        task.arguments = ["-p"] + store.files.map(\.path)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    func revealInFinder() {
        guard !store.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(store.files)
    }

    // Interactive screen capture straight onto the shelf. `screencapture -i`
    // lets the user pick a region/window; it writes nothing if they hit Escape,
    // so a missing file just means "cancelled". Needs Screen Recording
    // permission, prompted once by macOS on first use.
    func screenshot() {
        let name = "Screenshot \(Self.stamp.string(from: Date())).png"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-i", url.path]
            guard (try? task.run()) != nil else { return }
            task.waitUntilExit()
            guard FileManager.default.fileExists(atPath: url.path) else { return } // cancelled
            DispatchQueue.main.async {
                self?.handleDrop(urls: [url])
                RecentActivityManager.shared.add(.screenshot, title: "Screenshot", detail: url.path)
            }
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}
