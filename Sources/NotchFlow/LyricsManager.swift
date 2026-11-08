import Combine
import Foundation

// Synced lyrics for the current track from LRCLIB (free, no key). Opt-in
// (`AppSettings.showLyrics`): it sends title/artist/duration to lrclib.net.
// Fetches once per track — the 4 s Now Playing polls dedupe on the key — and
// caches results (misses included) in memory for the session. The panel picks
// the line for its own interpolated position, so no timer lives here.
final class LyricsManager: ObservableObject {
    static let shared = LyricsManager()

    @Published private(set) var lyrics: Lyrics?

    private var cache: [String: Lyrics?] = [:]
    private var currentKey: String?
    private var sub: AnyCancellable?

    private init() {
        sub = NowPlayingManager.shared.$nowPlaying
            .combineLatest(AppSettings.shared.$showLyrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track, enabled in
                self?.update(enabled ? track : nil)
            }
    }

    private func update(_ track: NowPlaying?) {
        guard let track else { currentKey = nil; lyrics = nil; return }
        let key = "\(track.title)\u{1F}\(track.artist)"
        guard key != currentKey else { return }
        currentKey = key
        if let hit = cache[key] { lyrics = hit; return }
        lyrics = nil
        fetch(track, key: key)
    }

    private func fetch(_ track: NowPlaying, key: String) {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                        URLQueryItem(name: "artist_name", value: track.artist)]
        // Duration narrows the match; LRCLIB allows ±2 s of slack.
        if track.duration > 0 {
            c.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        var req = URLRequest(url: c.url!)
        req.setValue("NOTH (macOS notch utility)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let synced = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["syncedLyrics"]
                as? String
            let result = synced.flatMap(Lyrics.parse)
            DispatchQueue.main.async {
                guard let self else { return }
                // Network failure (no data) isn't cached, so the next track
                // change retries; an answered miss is.
                if data != nil { self.cache[key] = result }
                if self.currentKey == key { self.lyrics = result }
            }
        }.resume()
    }
}
