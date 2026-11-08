import Foundation

// Upcoming-meeting alert logic. Pure model — no EventKit — so the link
// extraction and alert window are covered by the swiftc harness.
struct Meeting: Equatable {
    let id: String
    let title: String
    let start: Date
    let joinURL: URL?

    /// Video-call links worth a "Join" button, matched anywhere in the event's
    /// URL, location or notes. Order is just a tiebreak when several appear.
    private static let linkPattern = try! NSRegularExpression(pattern: #"""
        https://(?:[\w-]+\.)?zoom\.us/(?:j|my|w)/[^\s<>"']+
        |https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s<>"']*
        |https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"']+
        |https://[\w-]+\.webex\.com/[^\s<>"']+
        |https://facetime\.apple\.com/join[^\s<>"']+
        """#, options: [.caseInsensitive, .allowCommentsAndWhitespace])

    /// First call link found across the given texts (nil entries skipped).
    static func joinURL(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = linkPattern.firstMatch(in: text, range: range),
               let r = Range(m.range, in: text) {
                // Sentence punctuation right after a pasted link isn't part of it.
                let link = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:)]"))
                return URL(string: link)
            }
        }
        return nil
    }

    /// The meeting to alert for: earliest one from `lead` seconds before its
    /// start until `grace` seconds after, skipping dismissed ids.
    static func alerting(_ meetings: [Meeting], now: Date, lead: TimeInterval = 300,
                         grace: TimeInterval = 300, dismissed: Set<String> = []) -> Meeting? {
        meetings
            .filter { !dismissed.contains($0.id)
                && now >= $0.start.addingTimeInterval(-lead)
                && now < $0.start.addingTimeInterval(grace) }
            .min { $0.start < $1.start }
    }
}
