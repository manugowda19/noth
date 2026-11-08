import Foundation

enum MusicApp: String, CaseIterable {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Name used in `tell application "..."`.
    var scriptName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

// What's playing. Pure model — no AppKit — so the script-output parser can be
// unit-tested in the swiftc harness like FileStore/NotchGeometry.
struct NowPlaying: Equatable {
    /// Scriptable source app; nil for tracks read via the MediaRemote adapter
    /// (any player — browsers too), which are controlled through the adapter.
    let app: MusicApp?
    let title: String
    let artist: String
    let playing: Bool
    /// Album-art URL when the app exposes one (Spotify does; Music doesn't).
    let artworkURL: String?
    /// Elapsed / total seconds. 0 when unknown; the panel hides the progress
    /// bar for a zero duration. Both apps report position in seconds; the query
    /// normalizes Spotify's millisecond duration to seconds.
    let position: Double
    let duration: Double
    /// Raw artwork image bytes (adapter only; the scripting path has a URL).
    var artworkData: Data? = nil

    /// Field separator used by the AppleScript we run: ASCII unit separator,
    /// which can't appear in track titles the way "|" or "," could.
    static let separator = "\u{1F}"

    /// Parses the fixed 6-field line the query emits:
    /// "<1|0><US>title<US>artist<US>artwork<US>position<US>duration".
    /// Artwork is empty for Music; position/duration are seconds.
    static func parse(_ line: String, app: MusicApp) -> NowPlaying? {
        let p = line.components(separatedBy: separator)
        guard p.count == 6, p[0] == "1" || p[0] == "0" else { return nil }
        let art = p[3].isEmpty ? nil : p[3]
        return NowPlaying(app: app, title: p[1], artist: p[2],
                          playing: p[0] == "1", artworkURL: art,
                          position: Double(p[4]) ?? 0, duration: Double(p[5]) ?? 0)
    }

    /// Parses the adapter's `get --now` JSON: `null`, or a dictionary whose
    /// `bundleIdentifier`, `playing` and `title` are always present.
    /// `artworkData` is base64; `elapsedTimeNow` is the --now estimate.
    static func parseAdapter(_ data: Data) -> NowPlaying? {
        guard let d = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
                as? [String: Any],
              let title = d["title"] as? String, !title.isEmpty,
              let playing = d["playing"] as? Bool else { return nil }
        let bundle = d["bundleIdentifier"] as? String
        return NowPlaying(
            app: MusicApp.allCases.first { $0.bundleID == bundle },
            title: title, artist: d["artist"] as? String ?? "",
            playing: playing, artworkURL: nil,
            position: (d["elapsedTimeNow"] ?? d["elapsedTime"]) as? Double ?? 0,
            duration: d["duration"] as? Double ?? 0,
            artworkData: (d["artworkData"] as? String).flatMap { Data(base64Encoded: $0) })
    }
}
