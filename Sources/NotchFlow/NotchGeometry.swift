import CoreGraphics

// Pure geometry for pinning the shelf under the notch. Kept free of AppKit so
// the placement math and notch-detection rule can be unit-tested directly.
enum NotchGeometry {

    /// Frame that centers a shelf of `size` horizontally on `screenFrame` and
    /// anchors its top edge to the top of the screen (right under the notch).
    ///
    /// Uses AppKit's bottom-left origin convention, so the top edge is at
    /// `maxY` and the frame's origin.y is `maxY - height`.
    static func shelfFrame(screenFrame: CGRect, size: CGSize) -> CGRect {
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A screen "has a notch" when its top safe-area inset is positive.
    /// Factored out so the selection rule is testable without real NSScreens.
    static func hasNotch(topSafeAreaInset: CGFloat) -> Bool {
        topSafeAreaInset > 0
    }

    /// Pick which display to pin the shelf to. Rule, in order: the user's
    /// preferred display if it's still connected; else the first with a notch;
    /// else the main display; else the first available. `preferredID == 0` means
    /// "auto". Pure (operates on plain tuples) so it's unit-testable without
    /// real NSScreens — this is the crux of the multi-display behavior.
    static func chooseDisplay(preferredID: UInt32,
                              candidates: [(id: UInt32, hasNotch: Bool, isMain: Bool)]) -> UInt32? {
        if preferredID != 0, candidates.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        if let notched = candidates.first(where: { $0.hasNotch }) { return notched.id }
        if let main = candidates.first(where: { $0.isMain }) { return main.id }
        return candidates.first?.id
    }

    /// Width of the physical notch, computed from the two safe areas flanking
    /// it (`NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea`). Factored
    /// out from the NSScreen lookup so the math is testable without a real
    /// screen. Negative/zero gaps (no real notch between the areas) clamp to 0.
    static func notchWidth(leftArea: CGRect, rightArea: CGRect) -> CGFloat {
        max(0, rightArea.minX - leftArea.maxX)
    }
}
