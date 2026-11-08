import AppKit
import Vision

// The shelf Tools card: screen color picker (NSColorSampler — no screen-
// recording permission), QR scan of a selected screen region (the existing
// `screencapture -i` flow + Vision), and the system emoji palette. Opt-in
// card (`AppSettings.showTools`). Results go to the pasteboard and flash via
// the shared notice wing.
final class ToolsManager: ObservableObject {
    static let shared = ToolsManager()

    /// Picked colors, most recent first (persisted, small).
    @Published private(set) var colors: [String] =
        UserDefaults.standard.stringArray(forKey: "pickedColors") ?? []
    /// Last QR payload and, for http(s) links, the URL an "Open" button offers.
    @Published private(set) var lastQR: (text: String, url: URL?)?

    private let sampler = NSColorSampler()

    private init() {}

    func pickColor() {
        sampler.show { [weak self] color in
            guard let self, let rgb = color?.usingColorSpace(.sRGB) else { return }
            let hex = Tools.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
            self.copy(hex)
            self.colors = Tools.pushing(hex, onto: self.colors)
            RecentActivityManager.shared.add(.color, title: hex, detail: hex)
            UserDefaults.standard.set(self.colors, forKey: "pickedColors")
            DeviceNoticeManager.shared.show(.init(symbol: "checkmark.circle.fill", text: "\(hex) copied", style: .success))
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Drag a box around a QR code; its payload is copied (never auto-opened).
    func scanQR() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchflow-qr-\(UUID().uuidString).png")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-i", "-x", url.path]   // -x: no shutter sound
            guard (try? task.run()) != nil else { return }
            task.waitUntilExit()
            defer { try? FileManager.default.removeItem(at: url) }
            guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return }   // cancelled
            let payload = Self.decodeQR(image)
            DispatchQueue.main.async { self?.finishScan(payload) }
        }
    }

    func openLastQR() {
        if let url = lastQR?.url { NSWorkspace.shared.open(url) }
    }

    func showEmojiPalette() {
        NSApp.orderFrontCharacterPalette(nil)
    }

    private func finishScan(_ payload: String?) {
        guard let payload else {
            DeviceNoticeManager.shared.show(.init(symbol: "qrcode", text: "No QR code found", style: .warning))
            return
        }
        copy(payload)
        lastQR = (payload, Tools.openableURL(payload))
        RecentActivityManager.shared.add(.qr, title: Tools.openableURL(payload)?.host ?? "QR text", detail: payload)
        DeviceNoticeManager.shared.show(.init(symbol: "checkmark.circle.fill", text: "QR copied", style: .success))
    }

    static func decodeQR(_ image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap(\.payloadStringValue).first
    }
}
