import Darwin
import Foundation

// CPU %, memory in use and network throughput for a shelf card. Opt-in
// (`AppSettings.showSystemStats`); samples every 2 s while on via public mach
// host statistics and getifaddrs — no permissions.
// ponytail: memory "used" = active + wired + compressed pages (close to
// Activity Monitor's figure, not identical).
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    struct Snapshot: Equatable {
        var cpu: Double = 0           // 0…1
        var memoryUsed: UInt64 = 0    // bytes
        var download: Double = 0      // bytes/s
        var upload: Double = 0
    }

    @Published private(set) var snapshot = Snapshot()

    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private var lastTicks: [UInt32]?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastNet = nil
    }

    private func sample() {
        var next = snapshot
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, let usage = SystemStats.cpuUsage(previous: last, current: ticks) {
                next.cpu = usage
            }
            lastTicks = ticks
        }
        next.memoryUsed = Self.memoryUsed() ?? next.memoryUsed
        let (rx, tx) = Self.networkBytes()
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            next.download = SystemStats.rate(previous: last.rx, current: rx, interval: dt)
            next.upload = SystemStats.rate(previous: last.tx, current: tx, interval: dt)
        }
        lastNet = (rx, tx, now)
        if next != snapshot { snapshot = next }
    }

    private static func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return [t.0, t.1, t.2, t.3]   // user, system, idle, nice
    }

    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_kernel_page_size)
    }

    /// Cumulative received/sent bytes over non-loopback interfaces.
    /// ponytail: if_data counters are 32-bit and wrap at 4 GB; a wrap just
    /// reads as one 0 KB/s sample (SystemStats.rate guards it).
    private static func networkBytes() -> (UInt64, UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            rx += UInt64(data.pointee.ifi_ibytes)
            tx += UInt64(data.pointee.ifi_obytes)
        }
        return (rx, tx)
    }
}
