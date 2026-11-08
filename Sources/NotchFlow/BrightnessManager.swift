import Combine
import CoreGraphics
import Foundation

// Screen brightness via the private DisplayServices framework, resolved with
// dlsym at runtime and degrading gracefully: if Apple renames the symbols in
// some macOS update, `isAvailable` turns false, the interceptor passes the
// brightness keys back to the system, and nothing crashes.
// ponytail: in-process dlsym; move into an isolated helper process only if a
// framework-internal crash is ever actually observed.
final class BrightnessManager: ObservableObject {
    static let shared = BrightnessManager()

    @Published private(set) var brightness: Float = 0
    /// True briefly after a brightness change — drives the notch HUD.
    @Published private(set) var hudVisible = false

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let getFn: GetFn?
    private let setFn: SetFn?
    private var hideTask: Task<Void, Never>?

    var isAvailable: Bool { getFn != nil && setFn != nil }

    private init() {
        let paths = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices",
        ]
        let handle = paths.lazy.compactMap { dlopen($0, RTLD_LAZY) }.first
        getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
            .map { unsafeBitCast($0, to: GetFn.self) }
        setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
            .map { unsafeBitCast($0, to: SetFn.self) }
        brightness = read() ?? 0
    }

    func step(up: Bool) {
        guard let setFn, let current = read() else { return }
        let target = min(max(current + (up ? 1.0 : -1.0) / 16.0, 0), 1)
        guard setFn(CGMainDisplayID(), target) == 0 else { return }
        DispatchQueue.main.async {
            self.brightness = target
            self.flashHUD()
        }
    }

    private func read() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        guard getFn(CGMainDisplayID(), &value) == 0 else { return nil }
        return value
    }

    private func flashHUD() {
        // Only replace the system bezel when interception is on; otherwise the
        // system shows its own brightness bezel and this would double it.
        guard AppSettings.shared.hudReplacement else { return }
        hudVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.hudVisible = false
        }
    }
}
