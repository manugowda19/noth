import AppKit

// NØTH — a background agent app (no Dock icon, LSUIElement=YES).
// Bootstraps NSApplication and pins the shelf window under the notch.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app — never steal focus, never show in the Dock.
        NSApp.setActivationPolicy(.accessory)

        let window = NotchWindow()
        window.orderFrontRegardless()
        self.window = window
        StatusMenuController.shared.install()
        ShortcutManager.shared.registerOpenHotKey()
        OnboardingController.shared.presentIfNeeded()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
