import Foundation

/// How long each account's Claude was the front app, per day. Lanes counts
/// it from macOS's "app became active" events only; nothing inside Claude
/// is read. Kept for the last few weeks.
public struct FrontTimeLog: Codable, Equatable, Sendable {
    /// Seconds per account ID, per day ("2026-10-31", local calendar).
    public private(set) var days: [String: [String: Double]]

    public static let keptDays = 30

    public init(days: [String: [String: Double]] = [:]) {
        self.days = days
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
    }

    /// Adds the time from `start` to `end`, split at midnight so each day
    /// gets its own share.
    public mutating func record(_ id: ProfileID, from start: Date, to end: Date, calendar: Calendar = .current) {
        guard end > start else { return }
        var cursor = start
        while cursor < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? end
            let stop = min(nextDay, end)
            days[Self.dayKey(cursor, calendar: calendar), default: [:]][id.rawValue, default: 0] += stop.timeIntervalSince(cursor)
            cursor = stop
        }
    }

    /// Seconds on the given number of days up to and including `now`'s day.
    public func seconds(for id: ProfileID, days count: Int, now: Date, calendar: Calendar = .current) -> Double {
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 0)).reduce(0) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return total }
            return total + (days[Self.dayKey(day, calendar: calendar)]?[id.rawValue] ?? 0)
        }
    }

    /// Seconds on the day that holds `date`.
    public func seconds(for id: ProfileID, on date: Date, calendar: Calendar = .current) -> Double {
        days[Self.dayKey(date, calendar: calendar)]?[id.rawValue] ?? 0
    }

    /// Drops days older than `keptDays` and accounts no longer in the list.
    public mutating func prune(now: Date, keeping ids: Set<ProfileID>, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let kept = Set((0..<Self.keptDays).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Self.dayKey($0, calendar: calendar) }
        })
        let idValues = Set(ids.map(\.rawValue))
        days = days.filter { kept.contains($0.key) }.mapValues { $0.filter { idValues.contains($0.key) } }
    }

    /// "1 sa 25 dk", "12 dk", "1 dk'dan az".
    public static func describe(seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return seconds > 0 ? "1 dk'dan az" : "0 dk" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours) sa \(minutes % 60) dk" : "\(minutes) dk"
    }
}
