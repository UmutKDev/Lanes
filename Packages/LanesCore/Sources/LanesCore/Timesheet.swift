import Foundation

/// "Zaman Çizelgesi": how long Claude Code worked in each project, per
/// account and day, estimated from when its session files were written.
/// Two writes in the same project at most `joinGap` apart count as one
/// stretch of work; a longer pause is not counted. Nothing in the files is
/// read, only their dates.
public struct ProjectTimeLog: Codable, Equatable, Sendable {
    /// Seconds per day ("2026-11-01"), per account ID, per Claude Code
    /// project folder name.
    public private(set) var days: [String: [String: [String: Double]]]

    /// Kept long enough for last month's weekly reports.
    public static let keptDays = 62
    /// The longest pause between two writes that still counts as work.
    public static let joinGap: TimeInterval = 5 * 60

    public init(days: [String: [String: [String: Double]]] = [:]) {
        self.days = days
    }

    /// Counts the time since the previous write when it was in the same
    /// project and recent enough. Returns whether anything was added.
    @discardableResult
    public mutating func recordWrite(
        _ id: ProfileID,
        folderName: String,
        at date: Date,
        previous: (date: Date, folderName: String)?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let previous, previous.folderName == folderName else { return false }
        let gap = date.timeIntervalSince(previous.date)
        guard gap > 0, gap <= Self.joinGap else { return false }
        var cursor = previous.date
        while cursor < date {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? date
            let stop = min(nextDay, date)
            days[FrontTimeLog.dayKey(cursor, calendar: calendar), default: [:]][id.rawValue, default: [:]][folderName, default: 0] += stop.timeIntervalSince(cursor)
            cursor = stop
        }
        return true
    }

    /// Seconds per project folder name for one account on one day.
    public func projects(for id: ProfileID, on day: Date, calendar: Calendar = .current) -> [String: Double] {
        days[FrontTimeLog.dayKey(day, calendar: calendar)]?[id.rawValue] ?? [:]
    }

    /// Drops days older than `keptDays` and accounts no longer in the list.
    public mutating func prune(now: Date, keeping ids: Set<ProfileID>, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let kept = Set((0..<Self.keptDays).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { FrontTimeLog.dayKey($0, calendar: calendar) }
        })
        let idValues = Set(ids.map(\.rawValue))
        days = days.filter { kept.contains($0.key) }.mapValues { $0.filter { idValues.contains($0.key) } }
    }
}

/// One week of time per account (the "customer") and its Claude Code
/// projects, Monday first.
public struct Timesheet: Equatable, Sendable {
    public struct Project: Equatable, Sendable, Identifiable {
        public var folderName: String
        public var name: String
        /// Seconds per day, Monday first.
        public var seconds: [Double]
        public var id: String { folderName }
        public var total: Double { seconds.reduce(0, +) }
    }

    public struct Account: Equatable, Sendable, Identifiable {
        public var id: ProfileID
        public var name: String
        /// Seconds its Claude was the front app, per day.
        public var front: [Double]
        public var projects: [Project]
        public var frontTotal: Double { front.reduce(0, +) }
        /// Claude Code time per day, all projects together.
        public var code: [Double] {
            (0..<7).map { day in projects.reduce(0) { $0 + $1.seconds[day] } }
        }
        public var codeTotal: Double { projects.reduce(0) { $0 + $1.total } }
        public var isEmpty: Bool { frontTotal < 60 && codeTotal < 60 }
    }

    /// The Monday the week starts on, at midnight.
    public var weekStart: Date
    public var days: [Date]
    public var accounts: [Account]

    /// The Monday at or before `date`, at midnight.
    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        // Calendar weekdays: 1 = Sunday, 2 = Monday.
        let back = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// Builds the week. `todayFront` adds time not yet in the log (the
    /// account in front right now). `projectName` turns a Claude Code
    /// folder name into a readable name.
    public init(
        weekStart: Date,
        accounts: [(id: ProfileID, name: String)],
        front: FrontTimeLog,
        projects: ProjectTimeLog,
        extraFront: [ProfileID: Double] = [:],
        today: Date = Date(),
        calendar: Calendar = .current,
        projectName: (String) -> String
    ) {
        self.weekStart = weekStart
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        self.days = days
        let todayKey = FrontTimeLog.dayKey(today, calendar: calendar)
        self.accounts = accounts.map { account in
            let frontSeconds = days.map { day -> Double in
                var seconds = front.seconds(for: account.id, on: day, calendar: calendar)
                if FrontTimeLog.dayKey(day, calendar: calendar) == todayKey {
                    seconds += extraFront[account.id] ?? 0
                }
                return seconds
            }
            var byFolder: [String: [Double]] = [:]
            for (index, day) in days.enumerated() {
                for (folder, seconds) in projects.projects(for: account.id, on: day, calendar: calendar) {
                    byFolder[folder, default: Array(repeating: 0, count: 7)][index] += seconds
                }
            }
            var rows: [Project] = []
            for (folder, seconds) in byFolder {
                rows.append(Project(folderName: folder, name: projectName(folder), seconds: seconds))
            }
            rows.sort { (a: Project, b: Project) -> Bool in
                if a.total != b.total { return a.total > b.total }
                return a.name < b.name
            }
            return Account(id: account.id, name: account.name, front: frontSeconds, projects: rows)
        }
    }

    /// The accounts with at least a minute of time this week.
    public var usedAccounts: [Account] {
        accounts.filter { !$0.isEmpty }
    }

    /// `1 sa 05 dk`, `12 dk`, or `—` under a minute.
    public static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) dk" }
        return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest < 10 ? "0" : "")\(rest) dk"
    }

    /// One row per account and per project, minutes per day:
    /// `Hesap,Proje,Tür,<7 days>,Toplam`. Each day is rounded to the
    /// minute and the total is the sum of those, so the columns add up.
    public func csv(calendar: Calendar = .current) -> String {
        func field(_ text: String) -> String {
            var text = text
            // A cell starting with these runs as a formula in spreadsheets.
            if let first = text.first, "=+-@".contains(first) { text = "'" + text }
            return text.contains(",") || text.contains("\"") || text.contains("\n")
                ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : text
        }
        func minutes(_ seconds: Double) -> Int {
            Int((seconds / 60).rounded())
        }
        func row(_ cells: [String], _ seconds: [Double]) -> String {
            let days = seconds.map(minutes)
            return (cells + days.map(String.init) + [String(days.reduce(0, +))]).joined(separator: ",")
        }
        let header = ["Hesap", "Proje", "Tür"] + days.map { FrontTimeLog.dayKey($0, calendar: calendar) } + ["Toplam (dk)"]
        var lines = [header.joined(separator: ",")]
        for account in usedAccounts {
            lines.append(row([field(account.name), "", "Claude önde"], account.front))
            for project in account.projects where project.total >= 60 {
                lines.append(row([field(account.name), field(project.name), "Claude Code"], project.seconds))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "İş: 12 sa 30 dk, Claude Code 3 sa · Müşteri A: 4 sa", the busiest first, for the
    /// Monday summary. Nil when nothing was used.
    public var summary: String? {
        let used = usedAccounts.sorted { (a: Account, b: Account) -> Bool in
            let left: Double = a.frontTotal + a.codeTotal
            let right: Double = b.frontTotal + b.codeTotal
            return left > right
        }
        guard !used.isEmpty else { return nil }
        return used.map { account in
            let code = account.codeTotal >= 60 ? ", Claude Code \(Self.duration(account.codeTotal))" : ""
            return "\(account.name): \(Self.duration(account.frontTotal))\(code)"
        }.joined(separator: " · ")
    }
}
