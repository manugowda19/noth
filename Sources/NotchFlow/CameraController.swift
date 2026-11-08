import AppKit
import AVFoundation

// "Photo peek": a small camera window with a live preview and a Capture button.
// The shot is written to a temp JPEG and dropped straight onto the shelf.
// A dedicated key window, not the notch panel — the non-activating notch panel
// can't reliably host buttons, and a live preview wants real estate.
// ponytail: single default camera, still photos only. Multi-camera pick and
// video come later if anyone asks.
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    static let shared = CameraController()

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var window: NSWindow?
    private var configured = false

    private override init() { super.init() }

    /// Prompt for camera access (once) then show the preview window. `mirror`
    /// shows a capture-free live preview (a webcam mirror); otherwise the window
    /// has a Capture button that drops a still on the shelf.
    func present(mirror: Bool = false) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard granted, let self else { return }
                self.configureIfNeeded()
                self.showWindow(mirror: mirror)
            }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.sessionPreset = .photo
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        configured = true
    }

    private func showWindow(mirror: Bool) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // Rebuild content each time so switching Photo <-> Mirror shows/hides
        // the Capture button (cheap; the session and preview layer are shared).
        window?.title = mirror ? "Mirror" : "NØTH Camera"
        window?.contentView = buildContent(mirror: mirror)
        // Accessory (LSUIElement) apps must activate to bring up a key window.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startSession()
    }

    private func buildContent(mirror: Bool) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        container.autoresizingMask = [.width, .height]

        let preview = CameraPreviewView(session: session)
        preview.frame = NSRect(x: 0, y: 44, width: 360, height: 256)
        preview.autoresizingMask = [.width, .height]
        container.addSubview(preview)

        if !mirror {
            let capture = NSButton(title: "Capture", target: self, action: #selector(capture))
            capture.frame = NSRect(x: 360 - 112, y: 8, width: 100, height: 28)
            capture.bezelStyle = .rounded
            capture.keyEquivalent = "\r"
            capture.autoresizingMask = [.minXMargin]
            container.addSubview(capture)
        }

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.frame = NSRect(x: 12, y: 8, width: 84, height: 28)
        close.bezelStyle = .rounded
        container.addSubview(close)

        return container
    }

    @objc private func capture() {
        let settings = output.availablePhotoCodecTypes.contains(.jpeg)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            : AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
        stopSession()
    }

    private func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.stopRunning() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let name = "Photo \(Self.stamp.string(from: Date())).jpg"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return }
        DispatchQueue.main.async {
            AppCoordinator.shared.handleDrop(urls: [url])
            self.closeWindow()
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}

// Layer-hosting NSView that shows the live camera feed.
private final class CameraPreviewView: NSView {
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer = preview
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}
