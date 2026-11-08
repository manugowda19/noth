import AppKit
import SwiftUI

// First run: everything is opt-in, which on its own means an empty panel. One
// screen picks a useful starting set, shown once.
final class OnboardingController {
    static let shared = OnboardingController()
    private var window: NSWindow?
    private let key = "didOnboard"
    private init() {}

    func presentIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)   // once, even if closed with ×
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Welcome to NØTH"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: OnboardingView { [weak self] start in
            self?.window?.close()
            if start { AppCoordinator.shared.openCommandCenter() }
        })
        w.contentView = content
        w.setContentSize(content.fittingSize)
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    private struct Feature: Identifiable {
        let path: ReferenceWritableKeyPath<AppSettings, Bool>
        let title: String
        let detail: String
        var id: String { title }
    }

    private static let recommended: [Feature] = [
        Feature(path: \.showQuickNotes, title: "Quick notes", detail: "Type a note right in the notch"),
        Feature(path: \.showPins, title: "Links and snippets", detail: "Pin what you reuse"),
        Feature(path: \.showClipboard, title: "Clipboard history", detail: "Last 8 text copies, in memory only"),
        Feature(path: \.showOutputSwitcher, title: "Sound output", detail: "Switch speakers or AirPods"),
    ]
    private static let optional: [Feature] = [
        Feature(path: \.showSystemStats, title: "System stats", detail: "CPU, memory and network"),
        Feature(path: \.showLyrics, title: "Synced lyrics", detail: "Sends the song title and artist to lrclib.net"),
        Feature(path: \.launchAtLogin, title: "Open at login", detail: "Start NØTH with your Mac"),
    ]

    let onDone: (_ start: Bool) -> Void
    // The recommended set, plus anything already on from an earlier install.
    @State private var chosen = Set(
        OnboardingView.recommended.map(\.title)
            + OnboardingView.optional.filter { AppSettings.shared[keyPath: $0.path] }.map(\.title))

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Welcome to NØTH").font(.system(size: 22, weight: .semibold)).foregroundColor(Theme.Palette.text)
            Text("Choose what lives in your notch. You can change all of it later in Settings.")
                .font(Theme.Typo.body).foregroundColor(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                ForEach(Self.recommended + Self.optional) { row($0) }
            }
            .padding(.vertical, 4)
            Text("Open it any time: hover over the notch or press ⌥⌘J.")
                .font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
            HStack {
                Spacer()
                Button("Not Now") { onDone(false) }
                Button("Start") {
                    let settings = AppSettings.shared
                    for feature in Self.recommended + Self.optional {
                        let on = chosen.contains(feature.title)
                        if settings[keyPath: feature.path] != on { settings[keyPath: feature.path] = on }
                    }
                    onDone(true)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 38, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 440)
        .background(Color.black)
    }

    private func row(_ feature: Feature) -> some View {
        Toggle(isOn: Binding(
            get: { chosen.contains(feature.title) },
            set: { if $0 { chosen.insert(feature.title) } else { chosen.remove(feature.title) } }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title).font(Theme.Typo.bodyEmphasis).foregroundColor(Theme.Palette.text)
                Text(feature.detail).font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.vertical, 3)
    }
}
