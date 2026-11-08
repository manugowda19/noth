import Foundation

// Pure clipboard-history logic, split from ClipboardManager so the security-
// relevant capture decision (never store secrets) and the ring maintenance are
// unit-testable without NSPasteboard.
enum ClipboardHistory {
    /// Pasteboard types password managers / secure fields mark; never capture these.
    static let secretTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "com.apple.is-sensitive",
    ]

    /// Whether a pasteboard change should be captured: not a secret, and a
    /// non-empty string.
    static func shouldCapture(types: Set<String>, text: String?) -> Bool {
        guard types.isDisjoint(with: secretTypes) else { return false }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    /// Insert `text` at the front, de-duplicated, capped at `max` (newest first).
    static func insert(_ text: String, into ring: [String], max: Int) -> [String] {
        var next = ring.filter { $0 != text }
        next.insert(text, at: 0)
        if next.count > max { next.removeLast() }
        return next
    }
}
