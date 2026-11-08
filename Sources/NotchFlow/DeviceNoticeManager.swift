import AppKit
import Combine

// Brief notch notices when an external drive/card/disk image mounts or
// unmounts, or a display connects/disconnects. Opt-in
// (`AppSettings.deviceNotices`). NSWorkspace mount notifications and screen-
// parameter changes — public, no permissions, no polling.
final class DeviceNoticeManager: ObservableObject {
    static let shared = DeviceNoticeManager()

    struct Notice: Equatable {
        enum Style { case info, success, warning }
        let symbol: String
        let text: String
        var style: Style = .info
    }

    @Published private(set) var notice: Notice?

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var displays: Set<String> = []
    private var hideTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        displays = Self.displayNames()
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            (ws, ws.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) {
                [weak self] in self?.volume($0, mounted: true)
            }),
            (ws, ws.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) {
                [weak self] in self?.volume($0, mounted: false)
            }),
            (.default, NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
                [weak self] _ in self?.screensChanged()
            }),
        ]
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
        notice = nil
    }

    private func volume(_ note: Notification, mounted: Bool) {
        let name = note.userInfo?[NSWorkspace.localizedVolumeNameUserInfoKey] as? String ?? "Drive"
        let symbol = mounted ? "externaldrive.fill.badge.checkmark" : "eject.fill"
        show(Notice(symbol: symbol, text: mounted ? name : "Ejected \(name)"))
    }

    private func screensChanged() {
        let now = Self.displayNames()
        defer { displays = now }
        // Resolution/arrangement changes also fire this — only report adds/removes.
        if let added = now.subtracting(displays).sorted().first {
            show(Notice(symbol: "display", text: added))
        } else if let removed = displays.subtracting(now).sorted().first {
            show(Notice(symbol: "display.trianglebadge.exclamationmark", text: "Disconnected \(removed)"))
        }
    }

    private static func displayNames() -> Set<String> {
        Set(NSScreen.screens.map(\.localizedName))
    }

    /// The × on a notice wing.
    func dismiss() {
        hideTask?.cancel()
        notice = nil
    }

    /// Also used by ToolsManager, Copy Path and Pins for confirmations —
    /// works whether or not device notices are on.
    func show(_ n: Notice) {
        notice = n
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
