import AppKit
import SwiftUI

// NØTH is an agent app (no Dock icon), so it has no app menu by default.
// This adds what Mac users expect: a menu-bar item (Open NØTH, Settings… ⌘,,
// About, Quit) and an app menu so ⌘, and ⌘Q work whenever a NØTH window is
// key, plus a standard titled Settings window hosting the grouped SettingsView.
final class StatusMenuController: NSObject, NSWindowDelegate {
    static let shared = StatusMenuController()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private override init() { super.init() }

    func install() {
        NSApp.mainMenu = makeAppMenu()
        setMenuBarIconVisible(AppSettings.shared.showMenuBarIcon)
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                         accessibilityDescription: "NØTH")
            item.menu = makeStatusMenu()
            statusItem = item
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: Actions

    @objc func openCommandCenter() {
        AppCoordinator.shared.openCommandCenter()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "NØTH Settings"
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.delegate = self
            // Settings windows don't need minimize/zoom (settings.md › Desktop).
            w.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            w.standardWindowButton(.zoomButton)?.isEnabled = false
            w.contentView = NSHostingView(rootView:
                SettingsView(settings: AppSettings.shared, onBack: nil)
                    .padding(EdgeInsets(top: 34, leading: 18, bottom: 18, trailing: 18))
                    .frame(minWidth: 520, minHeight: 600)
                    .background(Color.black))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "NØTH",
            .credits: NSAttributedString(string: "Your notch, as a command center."),
        ])
    }

    @objc func checkForUpdates() { UpdateCheck.run() }

    // MARK: Menus

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Open NØTH", #selector(openCommandCenter), key: ""))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates), key: ""))
        menu.addItem(item("About NØTH", #selector(showAbout), key: ""))
        let quit = NSMenuItem(title: "Quit NØTH", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func makeAppMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "NØTH")
        appMenu.addItem(item("About NØTH", #selector(showAbout), key: ""))
        appMenu.addItem(item("Check for Updates…", #selector(checkForUpdates), key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(openSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit NØTH", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        // Edit menu so ⌘C/⌘V/⌘A work in the Quick bar and Notes fields.
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }
}
