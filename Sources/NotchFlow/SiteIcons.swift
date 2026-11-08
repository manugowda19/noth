import AppKit
import SwiftUI

/// Fetches and caches site icons for pinned links when
/// `AppSettings.siteIcons` is on; otherwise views show monograms.
final class SiteIconStore: ObservableObject {
    static let shared = SiteIconStore()

    @Published private(set) var icons: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("com.notchflow.app/site-icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private init() {}

    /// Cached icon, or nil (and a one-time background fetch when enabled).
    func icon(for url: URL) -> NSImage? {
        let host = SiteIcon.host(url)
        if let cached = icons[host] { return cached }
        let file = dir.appendingPathComponent(host + ".png")
        if let img = NSImage(contentsOf: file) {
            DispatchQueue.main.async { self.icons[host] = img }
            return img
        }
        guard AppSettings.shared.siteIcons, !inFlight.contains(host) else { return nil }
        inFlight.insert(host)
        fetch(SiteIcon.candidates(for: url), host: host, file: file)
        return nil
    }

    func clearCache() {
        icons = [:]
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func fetch(_ candidates: [URL], host: String, file: URL) {
        guard let next = candidates.first else { return }   // none worked: monogram stays
        var req = URLRequest(url: next, timeoutInterval: 8)
        req.setValue("NOTH (macOS notch utility)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            // Accept only real, reasonably sized images.
            if ok, let data, data.count < 512_000, let img = NSImage(data: data),
               img.size.width >= 16, let png = img.pngData {
                try? png.write(to: file)
                DispatchQueue.main.async { self.icons[host] = img }
            } else {
                self.fetch(Array(candidates.dropFirst()), host: host, file: file)
            }
        }.resume()
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// A pinned link as an app-icon-style tile: the site's icon, or a monogram.
struct LinkTile: View {
    let link: String
    var size: CGFloat = 30
    @ObservedObject private var store = SiteIconStore.shared

    private static let palette: [Color] = [
        Color(hex: 0x3B82F6), Color(hex: 0x8B5CF6), Color(hex: 0xEC4899),
        Color(hex: 0xF97316), Color(hex: 0x10B981), Color(hex: 0x0EA5E9),
    ]

    var body: some View {
        let url = URL(string: link)
        let host = url.map(SiteIcon.host) ?? link
        Group {
            if let url, let img = store.icon(for: url) {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.12)
                    .background(Color.white)
            } else {
                Text(SiteIcon.monogram(host))
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundColor(Theme.Palette.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Self.palette[SiteIcon.paletteIndex(host, count: Self.palette.count)])
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .help(host)
        .accessibilityLabel(host)
    }
}
