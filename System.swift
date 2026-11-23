import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import Darwin

// MARK: - Systeeminformatie

/// Geheugengebruik per proces, inclusief child-processen (bv. Chrome helpers).
struct ProcTree {
    private var children: [pid_t: [pid_t]] = [:]
    private var mem: [pid_t: UInt64] = [:]

    init() {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(estimate) * 2)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        for pid in pids.prefix(max(0, n)) where pid > 0 {
            var bsd = proc_bsdinfo()
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 {
                children[pid_t(bsd.pbi_ppid), default: []].append(pid)
            }
            var ri = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ri) { p in
                p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            if r == 0 { mem[pid] = ri.ri_phys_footprint }
        }
    }

    func totalMB(_ pid: pid_t) -> Double {
        var total: UInt64 = 0
        var stack = [pid]
        var seen = Set<pid_t>()
        while let p = stack.popLast() {
            guard seen.insert(p).inserted else { continue }
            total += mem[p] ?? 0
            stack += children[p] ?? []
        }
        return Double(total) / 1_048_576
    }
}

