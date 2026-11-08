import AppKit

// Pinned snippets and links for the shelf. "+" pins what's on the clipboard —
// no text field needed in the non-key notch panel. Click a snippet to copy it,
// a link to open it; right-click removes. Opt-in card
// (`AppSettings.showPins`); persisted in UserDefaults (plain text, so don't
// pin secrets — concealed/password-manager clips are refused, as in
// ClipboardManager).
final class PinsManager: ObservableObject {
    static let shared = PinsManager()

    @Published private(set) var snippets: [String] =
        UserDefaults.standard.stringArray(forKey: "pinnedSnippets") ?? []
    @Published private(set) var links: [String] =
        UserDefaults.standard.stringArray(forKey: "pinnedLinks") ?? []

    private init() {}

    /// Pins the clipboard: an http(s) URL goes to links, other text to
    /// snippets. Returns false when there was nothing (pinnable) to pin.
    @discardableResult
    func pinClipboard() -> Bool {
        let pb = NSPasteboard.general
        // Password managers mark secrets; never persist those.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pb.types?.contains(concealed) != true,
              let text = pb.string(forType: .string) else { return false }
        if let url = Tools.openableURL(text) {
            links = Pins.adding(url.absoluteString, to: links)
            UserDefaults.standard.set(links, forKey: "pinnedLinks")
        } else {
            let before = snippets
            snippets = Pins.adding(text, to: snippets)
            guard snippets != before else { return false }
            UserDefaults.standard.set(snippets, forKey: "pinnedSnippets")
        }
        return true
    }

    func copy(_ snippet: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
    }

    func open(_ link: String) {
        if let url = Tools.openableURL(link) { NSWorkspace.shared.open(url) }
    }

    func remove(snippet: String) {
        snippets.removeAll { $0 == snippet }
        UserDefaults.standard.set(snippets, forKey: "pinnedSnippets")
    }

    func remove(link: String) {
        links.removeAll { $0 == link }
        UserDefaults.standard.set(links, forKey: "pinnedLinks")
    }
}
