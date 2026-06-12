import Combine
import Darwin
import Foundation
import IOKit

/// Memory pressure as reported by the kernel, mapped to the traffic-light
/// indicator shown in the panel.
enum MemoryPressure {
    case normal, warning, critical, unknown

    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

/// One refresh tick of the system monitor. Optionals stay nil when a reading
/// is unavailable on the current hardware, and the UI hides those rows.
struct SystemSnapshot {
    var cpuTemperature: Double?
    var gpuTemperature: Double?
    var batteryTemperature: Double?
    var cpuUsage: Double?          // 0...1
    var gpuUsage: Double?          // 0...1
    var memoryUsed: UInt64?
    var memoryTotal: UInt64?
    var memoryPressure: MemoryPressure = .unknown
}

/// Reads temperatures (SMC), CPU/GPU usage and memory pressure on a background
/// queue while the panel is visible. Each component reports the highest
/// temperature among its sensors — the reading that matters for the user.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = SystemSnapshot()

    private let queue = DispatchQueue(label: "com.vorssaint.utils.system-monitor", qos: .utility)
    private var timer: Timer?
    private var smc: SMCClient?
    private var cpuKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var sensorsPrepared = false
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?

    private init() {}

    // MARK: - Lifecycle

    /// Starts periodic refreshes (panel became visible).
    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops refreshing (panel closed) — no background cost while idle.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareSensorsIfNeeded()

            var next = SystemSnapshot()
            next.cpuTemperature = self.maxTemperature(of: self.cpuKeys)
            next.gpuTemperature = self.maxTemperature(of: self.gpuKeys)
            next.batteryTemperature = self.maxTemperature(of: self.batteryKeys)
            next.cpuUsage = self.readCPUUsage()
            next.gpuUsage = Self.readGPUUsage()
            if let memory = SystemInfo.memoryUsage() {
                next.memoryUsed = memory.used
                next.memoryTotal = memory.total
            }
            next.memoryPressure = Self.readMemoryPressure()

            DispatchQueue.main.async {
                self.snapshot = next
            }
        }
    }

    // MARK: - Temperatures (SMC)

    /// Discovers the relevant SMC keys once. Apple Silicon exposes CPU cores as
    /// `Tp…`/`Te…`, the GPU as `Tg…` and the battery as `TB0T…TB2T`.
    private func prepareSensorsIfNeeded() {
        guard !sensorsPrepared else { return }
        sensorsPrepared = true
        guard let client = SMCClient() else { return }
        smc = client

        let all = client.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        cpuKeys = all.filter { $0.name.hasPrefix("Tp") || $0.name.hasPrefix("Te") }
        gpuKeys = all.filter { $0.name.hasPrefix("Tg") }
        batteryKeys = all.filter { $0.name.hasPrefix("TB") }
    }

    private func maxTemperature(of keys: [SMCClient.Key]) -> Double? {
        guard let smc else { return nil }
        let values = keys.compactMap { key -> Double? in
            guard let v = smc.readValue(key), v > 1, v < 125 else { return nil }
            return v
        }
        return values.max()
    }

    // MARK: - CPU usage

    /// Aggregated load from HOST_CPU_LOAD_INFO; usage is the busy-tick share
    /// since the previous refresh.
    private func readCPUUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total) }
        guard let previous = previousCPUTicks, total > previous.total else { return nil }
        return Double(busy - previous.busy) / Double(total - previous.total)
    }

    // MARK: - GPU usage

    /// "Device Utilization %" published by the graphics accelerator
    /// (AGXAccelerator on Apple Silicon).
    private static func readGPUUsage() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? Int
            else { continue }
            return Double(utilization) / 100.0
        }
        return nil
    }

    // MARK: - Memory pressure

    private static func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(kernelLevel: level)
    }
}
