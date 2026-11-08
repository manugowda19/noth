import AppKit

/// One thing NØTH just did for you that's worth acting on after its brief
/// notice is gone: a finished download, a scanned QR, a picked color, a
/// screenshot. Pure value; the list rules are tested.
struct RecentItem: Equatable, Identifiable {
    enum Kind: Equatable { case download, qr, color, screenshot }

    let kind: Kind
    let title: String
    /// What the action uses: a file path, the QR payload, or a hex string.
    let detail: String
    let date: Date

    var id: String { "\(kind)|\(detail)" }

    var symbol: String {
        switch kind {
        case .download: "arrow.down.circle.fill"
        case .qr: "qrcode"
        case .color: "eyedropper.halffull"
        case .screenshot: "camera.viewfinder"
        }
    }

    /// The one action this item offers.
    var actionTitle: String {
        switch kind {
        case .download, .screenshot: "Reveal"
        case .qr: Tools.openableURL(detail) == nil ? "Copy" : "Open"
        case .color: "Copy"
        }
    }

    /// Newest first; the same thing again moves to the top; capped.
    static func adding(_ item: RecentItem, to list: [RecentItem], max: Int = 8) -> [RecentItem] {
        Array(([item] + list.filter { $0.id != item.id }).prefix(max))
    }
}

/// Session-only (RAM) list of recent results, shown on the Home tab.
final class RecentActivityManager: ObservableObject {
    static let shared = RecentActivityManager()

    @Published private(set) var items: [RecentItem] = []

    private init() {}

    func add(_ kind: RecentItem.Kind, title: String, detail: String) {
        items = RecentItem.adding(RecentItem(kind: kind, title: title, detail: detail, date: Date()), to: items)
    }

    func clear() { items = [] }

    func perform(_ item: RecentItem) {
        switch item.kind {
        case .download, .screenshot:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.detail)])
        case .qr:
            // Opening needs this explicit click and only ever http(s).
            if let url = Tools.openableURL(item.detail) { NSWorkspace.shared.open(url) } else { copy(item.detail) }
        case .color:
            copy(item.detail)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
