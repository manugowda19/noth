import AppKit
import Combine

// In-memory clipboard history. NSPasteboard has no change notification, so it's
// polled via `changeCount` (cheap int compare, only while enabled). Opt-in.
// ponytail: text only, no persistence — the common case. Images/files and a
// persisted ring can come later if anyone asks; keeping it RAM-only also means
// history dies on quit, which is the safe default for clipboard contents.
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var clips: [String] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var timer: Timer?
    private let maxClips = 8

    private init() {}

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        clips = []
    }

    func clear() { clips = [] }

    /// Put a clip back on the pasteboard (click-to-reuse). The poll will see the
    /// change and move it to the front via the dedupe below.
    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = Set(pasteboard.types?.map(\.rawValue) ?? [])
        let text = pasteboard.string(forType: .string)
        guard ClipboardHistory.shouldCapture(types: types, text: text), let text else { return }
        clips = ClipboardHistory.insert(text, into: clips, max: maxClips)
    }
}
