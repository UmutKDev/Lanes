import Foundation

/// Decides when Lanes may quit an account's Claude that sat unused, to free
/// memory. Opt-in per account. An account that is in front, was used
/// recently or is busy (a Claude Code task, a long answer) is never quit.
public enum IdleQuitPolicy {
    /// The choices offered on the account page, in minutes.
    public static let choices: [Int] = [30, 60, 120, 240]

    /// Above this CPU share Claude counts as busy, whatever the clock says.
    public static let busyCPUPercent: Double = 3

    /// "30 dakika", "1 saat", "2 saat".
    public static func describe(minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) saat" : "\(minutes) dakika"
    }

    public static func shouldQuit(
        idleMinutes: Int?,
        lastActive: Date,
        now: Date,
        isFrontmost: Bool,
        cpuPercent: Double?
    ) -> Bool {
        guard let idleMinutes, idleMinutes > 0, !isFrontmost else { return false }
        // Without a CPU reading Lanes can't tell busy from idle.
        guard let cpuPercent, cpuPercent < busyCPUPercent else { return false }
        return now.timeIntervalSince(lastActive) >= TimeInterval(idleMinutes * 60)
    }
}

/// Memory and CPU an account's Claude uses, summed over its helper
/// processes.
public struct ResourceUsage: Equatable, Sendable {
    public var memoryBytes: UInt64
    /// Share of one CPU core since the previous reading, so 150 means one
    /// and a half cores. nil on the first reading.
    public var cpuPercent: Double?

    public init(memoryBytes: UInt64, cpuPercent: Double?) {
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
    }
}

public enum ProcessTree {
    /// Each root with every process below it, from a child-to-parent map.
    /// A process under two roots (which can't happen) goes to the nearer.
    public static func groups(roots: [Int32], parents: [Int32: Int32]) -> [Int32: Set<Int32>] {
        let rootSet = Set(roots)
        var result: [Int32: Set<Int32>] = [:]
        for root in roots { result[root] = [root] }
        for pid in parents.keys where !rootSet.contains(pid) {
            var current = pid
            var seen: Set<Int32> = []
            while let parent = parents[current], parent > 1, !seen.contains(parent) {
                if rootSet.contains(parent) {
                    result[parent, default: []].insert(pid)
                    break
                }
                seen.insert(parent)
                current = parent
            }
        }
        return result
    }
}
