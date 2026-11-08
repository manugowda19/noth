import CoreGraphics
import Foundation

// Pure helpers for pinned snippets/links and window-snap geometry, split out
// so the swiftc harness covers them.
enum Pins {
    /// Adds `item` to the front (trimmed); ignores blanks, de-duplicates, caps.
    static func adding(_ item: String, to list: [String], max: Int = 12) -> [String] {
        let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return list }
        return Array(([t] + list.filter { $0 != t }).prefix(max))
    }

    /// Chip label for a link: host without "www.", plus the first path segment.
    static func linkTitle(_ url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let first = url.pathComponents.dropFirst().first.map { "/" + $0 } ?? ""
        return host + first
    }

    /// Single-line chip label for a snippet (first line, ≤ 28 chars).
    static func snippetTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 28 ? String(line.prefix(27)) + "…" : line
    }
}

enum Snap {
    enum Target { case left, right, maximize, center }

    /// The target window frame in Accessibility coordinates (origin top-left of
    /// the primary display, y down), given the screen's AppKit `visibleFrame`
    /// (origin bottom-left, y up) and the primary display's height.
    static func frame(_ target: Target, visible v: CGRect, primaryHeight: CGFloat,
                      current: CGSize = .zero) -> CGRect {
        let top = primaryHeight - v.maxY   // AppKit → AX flip of the visible top edge
        let full = CGRect(x: v.minX, y: top, width: v.width, height: v.height)
        switch target {
        case .left: return CGRect(x: full.minX, y: top, width: (full.width / 2).rounded(), height: full.height)
        case .right:
            let w = (full.width / 2).rounded()
            return CGRect(x: full.maxX - w, y: top, width: w, height: full.height)
        case .maximize: return full
        case .center:
            let w = min(current.width, full.width), h = min(current.height, full.height)
            return CGRect(x: (full.midX - w / 2).rounded(), y: (full.midY - h / 2).rounded(), width: w, height: h)
        }
    }
}

/// Site-icon helpers (pure, tested): where to look, and the offline monogram.
enum SiteIcon {
    /// Tried in order, only on the pinned site itself — never a third-party
    /// favicon service, so no one else learns which sites you pin.
    static func candidates(for url: URL) -> [URL] {
        guard let scheme = url.scheme, let host = url.host else { return [] }
        return ["/apple-touch-icon.png", "/favicon.ico"].compactMap { URL(string: "\(scheme)://\(host)\($0)") }
    }

    /// Host without "www." — the cache key and tooltip.
    static func host(_ url: URL) -> String {
        var h = url.host ?? url.absoluteString
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// First letter of the host, uppercased ("github.com" → "G").
    static func monogram(_ host: String) -> String {
        String(host.first(where: \.isLetter) ?? "•").uppercased()
    }

    /// Stable palette slot for a host (same site, same color, every launch).
    static func paletteIndex(_ host: String, count: Int) -> Int {
        Int(host.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value } % UInt32(count))
    }
}
