import AppKit
import Combine
import Foundation

// Now Playing for any player (browsers, Podcasts, …) via the bundled
// mediaremote-adapter: MediaRemote is entitlement-gated in-process since macOS
// 15.4, but Apple's own /usr/bin/perl is entitled, so the adapter's script
// loads its helper framework there and prints JSON. If the adapter is missing
// or fails, fall back to Music/Spotify via their public scripting interfaces
// (first automation of each app prompts once).
// ponytail: polls `get` every 4s like the scripting path; switch to the
// adapter's `stream` command if 4s latency ever matters.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlaying?

    private var pollTimer: Timer?

    /// [script, framework] inside the app bundle; nil when not bundled.
    private let adapter: [String]? = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter")
        else { return nil }
        let paths = [dir.appendingPathComponent("mediaremote-adapter.pl").path,
                     dir.appendingPathComponent("MediaRemoteAdapter.framework").path]
        return paths.allSatisfy(FileManager.default.fileExists) ? paths : nil
    }()

    private init() {
        // Poll continuously: the collapsed notch shows a live activity while
        // music plays, so polling can't be gated on the shelf being open.
        // query() short-circuits on a cheap NSRunningApplication check, so a
        // machine with no music app running spawns zero osascript processes.
        startPolling()
    }

    // Adapter `send` IDs: 2 toggle play/pause, 4 next, 5 previous.
    func playPause() { control("playpause", adapterID: 2) }
    func nextTrack() { control("next track", adapterID: 4) }
    func previousTrack() { control("previous track", adapterID: 5) }

    private func control(_ command: String, adapterID: Int) {
        let app = nowPlaying?.app
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.adapter != nil {
                self.runAdapter(["send", String(adapterID)])
            } else if let app {
                self.runScript("tell application \"\(app.scriptName)\" to \(command)")
            }
            self.refresh()
        }
    }

    private func startPolling() {
        refreshAsync()
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            self?.refreshAsync()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func refreshAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.refresh()
        }
    }

    /// Blocking; call off the main thread.
    private func refresh() {
        let result: NowPlaying?
        if let json = runAdapter(["get", "--now"]) {
            result = NowPlaying.parseAdapter(json)   // `null` → nothing playing
        } else {
            result = MusicApp.allCases.lazy.compactMap { self.query($0) }.first
        }
        DispatchQueue.main.async { self.nowPlaying = result }
    }

    /// Runs the adapter script under /usr/bin/perl; stdout, or nil when the
    /// adapter isn't bundled or exits non-zero (caller falls back).
    @discardableResult
    private func runAdapter(_ args: [String]) -> Data? {
        guard let adapter else { return nil }
        return run("/usr/bin/perl", adapter + args)
    }

    private func query(_ app: MusicApp) -> NowPlaying? {
        // Skip apps that aren't running: no permission prompt, no app launch.
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: app.bundleID).isEmpty else { return nil }

        // Fixed 6-field line: flag, title, artist, artwork, position, duration.
        // Music has no artwork property (empty slot); Spotify's duration is in
        // milliseconds, so normalize it to seconds to match Music.
        let artwork = app == .spotify ? "(artwork url of current track)" : "\"\""
        let durationSecs = app == .spotify
            ? "((duration of current track) / 1000)" : "(duration of current track)"
        let script = """
        tell application "\(app.scriptName)"
            set st to player state
            if st is playing or st is paused then
                set flag to "0"
                if st is playing then set flag to "1"
                set us to character id 31
                return flag & us & (name of current track) & us & (artist of current track) & us & \(artwork) & us & (player position) & us & \(durationSecs)
            end if
        end tell
        return ""
        """
        guard let output = runScript(script), !output.isEmpty else { return nil }
        return NowPlaying.parse(output, app: app)
    }

    /// osascript in a subprocess: thread-safe and crash-isolated, unlike
    /// in-process NSAppleScript.
    @discardableResult
    private func runScript(_ source: String) -> String? {
        run("/usr/bin/osascript", ["-e", source]).flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ tool: String, _ args: [String]) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        // Read before waiting: artwork JSON can exceed the pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? data : nil
    }
}
