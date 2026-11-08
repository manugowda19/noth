import AppKit

// "Check for Updates…": asks GitHub for the latest release, only when clicked.
// ponytail: tells you and opens the release page; in-place install needs
// Sparkle plus a signing key and a hosted feed, add once releases are regular.
enum UpdateCheck {
    /// True when `latest` is a higher dotted version than `current`. A leading
    /// "v" is ignored and missing parts count as 0, so 3.1 == 3.1.0.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            (version.hasPrefix("v") ? String(version.dropFirst()) : version)
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    static func run() {
        let url = URL(string: "https://api.github.com/repos/manugowda19/noth/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async { report(status: status, release: release) }
        }.resume()
    }

    private static func report(status: Int?, release: Release?) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let alert = NSAlert()
        if let release, status == 200 {
            if isNewer(release.tag_name, than: current) {
                alert.messageText = "NØTH \(release.tag_name) is available"
                alert.informativeText = "You have \(current). Download it from the release page."
                alert.addButton(withTitle: "Open Release Page")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.html_url) }
                return
            }
            alert.messageText = "You're up to date"
            alert.informativeText = "NØTH \(current) is the latest version."
        } else if status == 404 {
            alert.messageText = "No releases published yet"
            alert.informativeText = "You have NØTH \(current)."
        } else {
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "GitHub couldn't be reached. Try again later."
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
