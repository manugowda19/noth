import Foundation

// Time-synced lyrics from LRCLIB's LRC text. Pure model — no networking — so
// the parser is covered by the swiftc test harness.
struct Lyrics: Equatable {
    struct Line: Equatable {
        let time: Double   // seconds from track start
        let text: String
    }

    let lines: [Line]      // sorted by time

    /// Parses LRC lines like "[01:02.34] text". A line may carry several time
    /// tags ("[00:10.00][01:20.00] chorus"); metadata tags ("[ar:…]") and
    /// untimed lines are skipped. nil when nothing is timed.
    static func parse(_ lrc: String) -> Lyrics? {
        var lines: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    times.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines.sorted { $0.time < $1.time })
    }

    /// The line being sung at `position` seconds; nil before the first line.
    /// ponytail: linear scan, fine for a few hundred lines polled at 2 Hz.
    func line(at position: Double) -> String? {
        lines.last { $0.time <= position }?.text
    }

    /// The sung line and the next non-empty one, for a two-line karaoke view.
    /// Before the first line, `current` is nil and `next` is the opener.
    func window(at position: Double) -> (current: String?, next: String?) {
        let i = lines.lastIndex { $0.time <= position }
        let after = lines[(i.map { $0 + 1 } ?? 0)...]
        return (i.map { lines[$0].text }, after.first { !$0.text.isEmpty }?.text)
    }
}
