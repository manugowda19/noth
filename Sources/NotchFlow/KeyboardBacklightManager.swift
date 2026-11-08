import Combine
import Foundation
import ObjectiveC.runtime

// Keyboard backlight via CoreBrightness's private `KeyboardBrightnessClient`,
// resolved at runtime through the ObjC runtime (no headers) and degrading
// gracefully: if the class or its selectors vanish in a macOS update,
// `isAvailable` turns false, the interceptor hands the illumination keys back
// to the system, and nothing crashes. Same philosophy as BrightnessManager.
// ponytail: in-process runtime call; isolate into a helper process only if a
// framework-internal crash is ever actually observed.
final class KeyboardBacklightManager: ObservableObject {
    static let shared = KeyboardBacklightManager()

    @Published private(set) var brightness: Float = 0
    /// True briefly after a change — drives the notch HUD.
    @Published private(set) var hudVisible = false

    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Void
    private let selGet = Selector(("brightnessForKeyboard:"))
    private let selSet = Selector(("setBrightness:forKeyboard:"))
    private let client: NSObject?
    private let getFn: GetFn?
    private let setFn: SetFn?
    private let keyboardID: UInt64
    private var hideTask: Task<Void, Never>?

    var isAvailable: Bool { client != nil && getFn != nil && setFn != nil && keyboardID != 0 }

    private init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        let instance = cls?.init()
        client = instance

        if let cls, let instance,
           let ids = instance.perform(Selector(("copyKeyboardBacklightIDs")))?
               .takeRetainedValue() as? [NSNumber],
           let first = ids.first?.uint64Value,
           let getImp = class_getMethodImplementation(cls, selGet),
           let setImp = class_getMethodImplementation(cls, selSet) {
            keyboardID = first
            getFn = unsafeBitCast(getImp, to: GetFn.self)
            setFn = unsafeBitCast(setImp, to: SetFn.self)
        } else {
            keyboardID = 0
            getFn = nil
            setFn = nil
        }
        brightness = read() ?? 0
    }

    func step(up: Bool) {
        guard let setFn, let client, let current = read() else { return }
        let target = min(max(current + (up ? 1.0 : -1.0) / 16.0, 0), 1)
        setFn(client, selSet, target, keyboardID)
        DispatchQueue.main.async {
            self.brightness = target
            self.flashHUD()
        }
    }

    private func read() -> Float? {
        guard let getFn, let client else { return nil }
        return getFn(client, selGet, keyboardID)
    }

    private func flashHUD() {
        // Only replace the system bezel when interception is on, else the
        // system shows its own and this would double it.
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
