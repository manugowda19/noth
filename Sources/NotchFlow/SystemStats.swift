import Foundation

// Pure math + formatting for the system-stats card, split from the mach/
// getifaddrs reads in SystemStatsManager so the swiftc harness covers it.
enum SystemStats {
    /// CPU busy fraction between two cumulative tick samples
    /// [user, system, idle, nice]; nil when no ticks elapsed.
    static func cpuUsage(previous: [UInt32], current: [UInt32]) -> Double? {
        guard previous.count == 4, current.count == 4 else { return nil }
        // Wrapping subtraction: the counters are UInt32 and roll over.
        let d = zip(current, previous).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        guard total > 0 else { return nil }
        return (d[0] + d[1] + d[3]) / total
    }

    /// Bytes/second between two cumulative byte counts over `interval` seconds.
    static func rate(previous: UInt64, current: UInt64, interval: Double) -> Double {
        guard interval > 0, current >= previous else { return 0 }
        return Double(current - previous) / interval
    }

    /// "820 KB/s", "1.4 MB/s" — decimal units like Activity Monitor.
    static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1_000 { return "0 KB/s" }
        if bytesPerSecond < 1_000_000 { return "\(Int(bytesPerSecond / 1_000)) KB/s" }
        return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
    }

    /// "8.2 GB" for a byte count.
    static func formatGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
