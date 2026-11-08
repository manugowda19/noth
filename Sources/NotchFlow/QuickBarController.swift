import AppKit
import SwiftUI

// Quick bar (⌥⌘K or the shelf button): a Spotlight-style field in its own key
// window — like Notes, because the non-activating notch panel can't host a
// real text field. Arithmetic shows its result live and Enter copies it;
// anything else Enter searches the web. Esc or clicking away closes it.
// ponytail: Google search URL is fixed; make the engine a setting if asked.
final class QuickBarController: NSObject, NSWindowDelegate {
    static let shared = QuickBarController()

    private var panel: NSPanel?

    private override init() { super.init() }

    func present() {
        if panel == nil { build() }
        guard let panel, let screen = NotchWindow.notchScreen() ?? NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - f.height * 0.25))
        panel.contentView = NSHostingView(rootView: QuickBarView(onClose: { [weak self] in self?.close() }))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func build() {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 64),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.delegate = self
        panel = p
    }

    /// Borderless panels refuse key status by default; the field needs it.
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

private struct QuickBarView: View {
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var result: Double? { Calculator.evaluate(text) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result == nil ? "magnifyingglass" : "equal")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 22)
            TextField("Calculate or search the web", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand(perform: onClose)
            if let result {
                Text(Calculator.format(result))
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.nfAccent)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 520, height: 64)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .onAppear { focused = true }
    }

    private func submit() {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        if let result {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Calculator.format(result), forType: .string)
        } else {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            if let url = c.url { NSWorkspace.shared.open(url) }
        }
        onClose()
    }
}
