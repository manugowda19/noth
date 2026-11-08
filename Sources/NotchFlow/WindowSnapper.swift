import AppKit

// Snap the frontmost window with ⌃⌥←/→ (halves), ⌃⌥↑ (maximize) and ⌃⌥↩
// (center), via the public Accessibility API — the same permission the HUD
// replacement and global shortcuts already use. Driven from ShortcutManager's
// key monitor when `AppSettings.windowSnapping` is on. Geometry is in Snap.
// ponytail: no "restore previous size"; add an undo stack if anyone misses it.
enum WindowSnapper {
    static func snap(_ target: Snap.Target) {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else { return }
        let win = window as! AXUIElement   // type checked above

        guard let current = frame(of: win), let primary = NSScreen.screens.first else { return }
        // The screen holding the window's center (AX y-down → AppKit y-up).
        let center = NSPoint(x: current.midX, y: primary.frame.maxY - current.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? primary
        let target = Snap.frame(target, visible: screen.visibleFrame,
                                primaryHeight: primary.frame.maxY, current: current.size)
        set(win, kAXSizeAttribute, target.size)        // size first, so a shrink fits
        set(win, kAXPositionAttribute, target.origin)
        set(win, kAXSizeAttribute, target.size)        // again: some apps clamp size to the old origin
    }

    private static func frame(of win: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &size) == .success
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func set(_ win: AXUIElement, _ attribute: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, attribute as CFString, v) }
    }

    private static func set(_ win: AXUIElement, _ attribute: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, attribute as CFString, v) }
    }
}
