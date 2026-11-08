import Foundation

// Pure helpers for the shelf Tools card (color picker history, QR results),
// split out so the swiftc harness covers them.
enum Tools {
    /// "#RRGGBB" from 0…1 components (clamped, rounded).
    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// 0…1 components back from "#RRGGBB" (for drawing history swatches).
    static func components(_ hex: String) -> (Double, Double, Double)? {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Most-recent-first history: moves an existing entry to the front.
    static func pushing(_ item: String, onto history: [String], max: Int = 8) -> [String] {
        Array(([item] + history.filter { $0 != item }).prefix(max))
    }

    /// A scanned QR payload worth an "Open" button: only http(s) URLs —
    /// never auto-opened, and no other schemes (tel:, file:, custom apps).
    static func openableURL(_ payload: String) -> URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
