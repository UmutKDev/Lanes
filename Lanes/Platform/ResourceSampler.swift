import Darwin
import Foundation
import LanesCore

/// Reads how much memory and CPU each account's Claude uses, with its
/// helper processes, from the kernel's per-process counters. macOS gives
/// these for the user's own processes without any permission, and nothing
/// inside Claude is read.
@MainActor
final class ResourceSampler {
    private var previousCPU: [pid_t: (nanoseconds: UInt64, at: UInt64)] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func sample(roots: [pid_t]) -> [pid_t: ResourceUsage] {
        guard !roots.isEmpty else {
            previousCPU = [:]
            return [:]
        }
        let groups = ProcessTree.groups(roots: roots, parents: Self.parents())
        let now = mach_absolute_time()
        var result: [pid_t: ResourceUsage] = [:]
        var current: [pid_t: (nanoseconds: UInt64, at: UInt64)] = [:]
        for root in roots {
            var memory: UInt64 = 0
            var cpuTicks: UInt64 = 0
            for pid in groups[root] ?? [root] {
                guard let usage = Self.rusage(of: pid) else { continue }
                memory += usage.ri_phys_footprint
                cpuTicks += usage.ri_user_time + usage.ri_system_time
            }
            let cpuNanoseconds = cpuTicks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
            var percent: Double?
            if let previous = previousCPU[root], now > previous.at, cpuNanoseconds >= previous.nanoseconds {
                let wall = Double((now - previous.at) * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1)))
                percent = wall > 0 ? Double(cpuNanoseconds - previous.nanoseconds) / wall * 100 : nil
            }
            current[root] = (cpuNanoseconds, now)
            result[root] = ResourceUsage(memoryBytes: memory, cpuPercent: percent)
        }
        previousCPU = current
        return result
    }

    /// Every process's parent, from proc_listallpids and proc_pidinfo.
    private static func parents() -> [Int32: Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = pids.withUnsafeMutableBytes { raw in
            proc_listallpids(raw.baseAddress, Int32(raw.count))
        }
        guard filled > 0 else { return [:] }
        var parents: [Int32: Int32] = [:]
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size {
                parents[pid] = Int32(info.pbi_ppid)
            }
        }
        return parents
    }

    private static func rusage(of pid: pid_t) -> rusage_info_v2? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { raw in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, raw)
            }
        }
        return result == 0 ? info : nil
    }
}

extension ResourceUsage {
    /// "1,2 GB · %4 işlemci", for tiles and the account page.
    var memory: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: memoryBytes), countStyle: .memory)
    }

    var summary: String {
        guard let cpuPercent else { return memory }
        return String(localized: "\(memory) · %\(Int(cpuPercent.rounded())) işlemci")
    }
}
