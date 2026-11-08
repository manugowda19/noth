import AppKit

// A quick scratchpad in its own key window. The non-activating notch panel is a
// poor host for a real text field, so Notes gets a small key window (like the
// camera). Content persists in UserDefaults — one scratchpad, saved on edit.
// ponytail: single scratchpad, no multi-note list — add that only if the one
// pad proves too small.
final class NotesController: NSObject, NSTextViewDelegate {
    static let shared = NotesController()

    private let key = "scratchpad"
    private var window: NSWindow?
    private var textView: NSTextView?

    private override init() { super.init() }

    func present() {
        if window == nil { build() }
        textView?.string = UserDefaults.standard.string(forKey: key) ?? ""
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Notes"
        w.isReleasedWhenClosed = false
        w.center()

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 320))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]

        let text = NSTextView(frame: scroll.bounds)
        text.autoresizingMask = [.width, .height]
        text.font = .systemFont(ofSize: 13)
        text.isRichText = false
        text.textContainerInset = NSSize(width: 8, height: 8)
        text.delegate = self
        scroll.documentView = text

        w.contentView = scroll
        window = w
        textView = text
    }

    func textDidChange(_ notification: Notification) {
        UserDefaults.standard.set(textView?.string ?? "", forKey: key)
    }
}
