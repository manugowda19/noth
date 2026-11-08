import Foundation

// In-progress downloads, recognized from the partial files browsers leave in
// ~/Downloads. Pure model — no file I/O — so the swiftc harness covers it.
enum Downloads {
    /// Safari `.download` bundle, Chrome/Edge/Brave `.crdownload`,
    /// Firefox `.part`.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part"]

    /// Partial-file names in a directory listing, sorted for stable order.
    static func inProgress(_ names: [String]) -> [String] {
        names.filter { partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
    }

    /// The final file name a partial file becomes ("a.zip.crdownload" → "a.zip").
    static func finalName(_ partial: String) -> String {
        (partial as NSString).deletingPathExtension
    }

    /// Safari keeps byte counts in the bundle's Info.plist; nil when absent
    /// (other browsers, or Safari before the total is known).
    static func safariProgress(_ info: [String: Any]) -> Double? {
        guard let done = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.doubleValue,
              let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.doubleValue,
              total > 0 else { return nil }
        return min(1, max(0, done / total))
    }

    /// Partials that vanished since the last scan and whose final file now
    /// exists — i.e. completed (a cancelled download leaves no final file).
    static func finished(previous: [String], current: [String], files: Set<String>) -> [String] {
        previous.filter { !current.contains($0) && files.contains(finalName($0)) }
            .map(finalName)
    }
}
