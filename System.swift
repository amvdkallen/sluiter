import AppKit
import ApplicationServices
import Darwin

// MARK: - Systeeminformatie

/// Momentopname van alle processen: geheugen, CPU-tijd en ouder/kind-relaties.
/// Totalen per app tellen child-processen mee (bv. Chrome helpers).
struct ProcTree {
    struct Info {
        let pid: pid_t
        let ppid: pid_t
        let uid: uid_t
        let name: String
        let memory: UInt64      // bytes (phys_footprint, zoals Activiteitenweergave)
        let cpuNanos: UInt64    // totale CPU-tijd sinds start
    }

    private(set) var info: [pid_t: Info] = [:]
    private var children: [pid_t: [pid_t]] = [:]
    let timestamp = DispatchTime.now().uptimeNanoseconds

    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(tb.denom, 1)))
    }()

    init() {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(estimate) * 2)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            var bsd = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { continue }
            var ri = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ri) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            var name = String(cString: nameBuf)
            if name.isEmpty {
                name = withUnsafeBytes(of: bsd.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            }
            let ticks = r == 0 ? ri.ri_user_time &+ ri.ri_system_time : 0
            let ppid = pid_t(bsd.pbi_ppid)
            info[pid] = Info(pid: pid, ppid: ppid, uid: bsd.pbi_uid, name: name,
                             memory: r == 0 ? ri.ri_phys_footprint : 0,
                             cpuNanos: ticks &* Self.timebase.numer / Self.timebase.denom)
            children[ppid, default: []].append(pid)
        }
    }

    /// Het proces zelf plus al zijn (klein)kinderen.
    func family(_ pid: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var stack = [pid]
        var seen = Set<pid_t>()
        while let p = stack.popLast() {
            guard seen.insert(p).inserted else { continue }
            out.append(p)
            stack += children[p] ?? []
        }
        return out
    }

    func totalMB(_ pid: pid_t) -> Double {
        Double(family(pid).reduce(UInt64(0)) { $0 + (info[$1]?.memory ?? 0) }) / 1_048_576
    }

    func totalCPUNanos(_ pid: pid_t) -> UInt64 {
        family(pid).reduce(UInt64(0)) { $0 &+ (info[$1]?.cpuNanos ?? 0) }
    }
}

/// Meetresultaat voor een set apps (wordt op een achtergrondthread gemaakt).
struct Metrics {
    var memoryMB: [pid_t: Double] = [:]
    var cpuNanos: [pid_t: UInt64] = [:]
    var hung: Set<pid_t> = []
    var hangChecked = false
    var timestamp: UInt64 = 0

    static func measure(pids: [pid_t], checkHang: Bool) -> Metrics {
        let tree = ProcTree()
        var m = Metrics()
        m.timestamp = tree.timestamp
        for pid in pids {
            m.memoryMB[pid] = tree.totalMB(pid)
            m.cpuNanos[pid] = tree.totalCPUNanos(pid)
        }
        if checkHang {
            m.hangChecked = true
            m.hung = HangDetector.unresponsive(pids)
        }
        return m
    }
}

/// Herkent apps die niet reageren: een app die binnen 0,5 s geen antwoord geeft op een
/// simpele Toegankelijkheid-vraag hangt vrijwel zeker. Vereist Toegankelijkheid-toegang.
enum HangDetector {
    static func unresponsive(_ pids: [pid_t]) -> Set<pid_t> {
        guard !pids.isEmpty else { return [] }
        let lock = NSLock()
        var hung = Set<pid_t>()
        DispatchQueue.concurrentPerform(iterations: pids.count) { i in
            let el = AXUIElementCreateApplication(pids[i])
            AXUIElementSetMessagingTimeout(el, 0.5)
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) == .cannotComplete {
                lock.lock(); hung.insert(pids[i]); lock.unlock()
            }
        }
        return hung
    }
}

// MARK: - Systeembreed: geheugen, geheugendruk, CPU, swap

struct SystemStats {
    enum Pressure: Int { case normal = 1, warning = 2, critical = 4 }

    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
    var swapUsedGB: Double = 0
    var pressure: Pressure = .normal
    var cpuPercent: Double? = nil      // gemiddeld over alle cores, 0–100
    var cpuTicks: (busy: UInt64, total: UInt64) = (0, 0)

    var memoryFraction: Double { memoryTotalGB > 0 ? min(1, memoryUsedGB / memoryTotalGB) : 0 }

    /// Meet nu; `previous` is nodig om CPU-% over het interval te berekenen.
    static func measure(previous: SystemStats?) -> SystemStats {
        var s = SystemStats()
        s.memoryTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

        // Gebruikt geheugen zoals Activiteitenweergave: app-geheugen + wired + gecomprimeerd.
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let appPages = Double(vm.internal_page_count) - Double(vm.purgeable_count)
            let used = (appPages + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            s.memoryUsedGB = used / 1_073_741_824
        }

        // Geheugendruk (dezelfde indicator als in Activiteitenweergave).
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            s.pressure = Pressure(rawValue: Int(level)) ?? .normal
        }

        // Swap
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            s.swapUsedGB = Double(swap.xsu_used) / 1_073_741_824
        }

        // CPU (alle cores samen)
        var load = host_cpu_load_info()
        var loadCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr2 = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(loadCount)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &loadCount)
            }
        }
        if kr2 == KERN_SUCCESS {
            let t = load.cpu_ticks
            let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
            s.cpuTicks = (user + system + nice, user + system + idle + nice)
            if let p = previous, s.cpuTicks.total > p.cpuTicks.total {
                let busy = Double(s.cpuTicks.busy &- p.cpuTicks.busy)
                s.cpuPercent = busy / Double(s.cpuTicks.total - p.cpuTicks.total) * 100
            }
        }
        return s
    }
}
