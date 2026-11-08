import Foundation

// The set of files parked in the shelf. Pure model — no AppKit — so the
// add/dedup/remove/clear behavior can be unit-tested without a running GUI.
final class FileStore {

    private(set) var files: [URL] = []

    /// Append a URL if it isn't already parked.
    /// Returns true when the store actually changed.
    @discardableResult
    func add(_ url: URL) -> Bool {
        guard !files.contains(url) else { return false }
        files.append(url)
        return true
    }

    /// Append several URLs, skipping duplicates.
    /// Returns the URLs that were newly added, in order.
    @discardableResult
    func add(contentsOf urls: [URL]) -> [URL] {
        urls.filter { add($0) }
    }

    /// Remove a specific URL. Returns true if it was present.
    @discardableResult
    func remove(_ url: URL) -> Bool {
        guard let idx = files.firstIndex(of: url) else { return false }
        files.remove(at: idx)
        return true
    }

    func clear() {
        files.removeAll()
    }

    var isEmpty: Bool { files.isEmpty }
    var count: Int { files.count }

    /// Newline-joined POSIX paths — the exact string Copy Path puts on the pasteboard.
    var joinedPaths: String {
        files.map(\.path).joined(separator: "\n")
    }
}
