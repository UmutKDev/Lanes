import Foundation

/// "Akıllı Yönlendirme 2.0": rules that send a link by the hour, the day
/// and the app it was clicked in, ahead of the per-kind rules, and a
/// 30-day log that says why each link went where it went.

/// Hours of the day, on some weekdays, when a rule applies.
public struct LinkTimeWindow: Hashable, Codable, Sendable {
    /// Minutes after midnight, 0..<1440. An end before the start crosses
    /// midnight (22:00–02:00); an end equal to the start is the whole day.
    public var startMinute: Int
    public var endMinute: Int
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday, of the day the window
    /// starts on. Empty means every day.
    public var weekdays: Set<Int>

    public init(startMinute: Int, endMinute: Int, weekdays: Set<Int> = []) {
        self.startMinute = min(max(startMinute, 0), 1439)
        self.endMinute = min(max(endMinute, 0), 1439)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
    }

    enum CodingKeys: String, CodingKey {
        case startMinute, endMinute, weekdays
    }

    /// Through the clamping initializer, so a hand-edited file stays valid.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startMinute: (try? container.decode(Int.self, forKey: .startMinute)) ?? 0,
            endMinute: (try? container.decode(Int.self, forKey: .endMinute)) ?? 0,
            weekdays: (try? container.decode(Set<Int>.self, forKey: .weekdays)) ?? []
        )
    }

    private func isOn(weekday: Int) -> Bool {
        weekdays.isEmpty || weekdays.contains(weekday)
    }

    /// Whether `date` falls in the window, by wall clock.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let weekday = parts.weekday ?? 1
        if startMinute == endMinute {
            return isOn(weekday: weekday)
        }
        if startMinute < endMinute {
            return isOn(weekday: weekday) && minute >= startMinute && minute < endMinute
        }
        // Crosses midnight: the evening part belongs to today, the
        // morning part to the day before.
        if minute >= startMinute {
            return isOn(weekday: weekday)
        }
        if minute < endMinute {
            return isOn(weekday: weekday == 1 ? 7 : weekday - 1)
        }
        return false
    }
}

/// An app a link can be clicked in, by bundle identifier, with the name
/// shown in settings.
public struct LinkSourceApp: Hashable, Codable, Sendable {
    public var bundleIdentifier: String
    public var name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// One rule. Every condition it sets has to hold; a condition left empty
/// holds always.
public struct LinkRule: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Empty means every kind of link.
    public var kinds: Set<LinkRules.LinkKind>
    /// Empty means a link from any app.
    public var sourceApps: [LinkSourceApp]
    /// Nil means at any time.
    public var window: LinkTimeWindow?
    public var target: LinkRules.Target
    /// Kinds a newer Lanes wrote that this one does not know. Kept so a
    /// save does not lose them; a rule with only these never matches.
    public var unknownKinds: [String] = []

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        kinds: Set<LinkRules.LinkKind> = [],
        sourceApps: [LinkSourceApp] = [],
        window: LinkTimeWindow? = nil,
        target: LinkRules.Target
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.kinds = kinds
        self.sourceApps = sourceApps
        self.window = window
        self.target = target
    }

    enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, kinds, sourceApps, window, target
    }

    /// Unknown kinds (from a newer Lanes) are kept aside and written back;
    /// a rule whose kinds are all unknown never matches, rather than
    /// widening to every link.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        let rawKinds = (try? container.decode([String].self, forKey: .kinds)) ?? []
        kinds = Set(rawKinds.compactMap(LinkRules.LinkKind.init(rawValue:)))
        unknownKinds = rawKinds.filter { LinkRules.LinkKind(rawValue: $0) == nil }
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
        sourceApps = (try? container.decode([LinkSourceApp].self, forKey: .sourceApps)) ?? []
        window = try? container.decode(LinkTimeWindow.self, forKey: .window)
        target = try container.decode(LinkRules.Target.self, forKey: .target)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(kinds.map(\.rawValue).sorted() + unknownKinds, forKey: .kinds)
        try container.encode(sourceApps, forKey: .sourceApps)
        try container.encodeIfPresent(window, forKey: .window)
        try container.encode(target, forKey: .target)
    }

    public func matches(kind: LinkRules.LinkKind, sourceApp: String?, at date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        if kinds.isEmpty, !unknownKinds.isEmpty { return false }
        if !kinds.isEmpty, !kinds.contains(kind) { return false }
        if !sourceApps.isEmpty {
            guard let sourceApp, sourceApps.contains(where: { $0.bundleIdentifier == sourceApp }) else { return false }
        }
        if let window, !window.contains(date, calendar: calendar) { return false }
        return true
    }
}

/// Why a link went to the account it went to.
public enum LinkReason: Equatable, Sendable {
    /// The Focus filter in force names an account.
    case focus
    /// A rule of "Akıllı Yönlendirme" matched.
    case rule(name: String)
    /// The rule for this kind of link.
    case kind(LinkRules.LinkKind)
    /// The "no rule" setting named an account.
    case fallback
    /// The account whose Claude was last in front.
    case frontmost
    /// No account had been in front, so the default account.
    case defaultAccount
}

extension LinkRules {
    /// The account a link goes to and why. The first enabled rule that
    /// matches and names an existing account wins; a smart rule naming an
    /// account that is gone is skipped. Then the kind's rule, else the
    /// general one; when the account they name is gone, the front account,
    /// else the default one, as before smart rules.
    public func decide(
        route: ClaudeLink.Route,
        sourceApp: String?,
        now: Date,
        calendar: Calendar = .current,
        frontmost: ProfileID?,
        library: ProfileLibrary
    ) -> (profile: Profile?, reason: LinkReason) {
        let kind = LinkKind(route)
        for rule in rules where rule.matches(kind: kind, sourceApp: sourceApp, at: now, calendar: calendar) {
            switch rule.target {
            case let .profile(id):
                if let profile = library.profile(withID: id) { return (profile, .rule(name: rule.name)) }
            case .frontmost:
                return frontOrDefault(frontmost: frontmost, library: library, reason: .rule(name: rule.name))
            }
        }
        let reason: LinkReason? = byKind[kind] != nil ? .kind(kind) : (fallback == .frontmost ? nil : .fallback)
        switch target(for: kind) {
        case let .profile(id):
            if let profile = library.profile(withID: id) { return (profile, reason ?? .fallback) }
            return frontOrDefault(frontmost: frontmost, library: library, reason: nil)
        case .frontmost:
            return frontOrDefault(frontmost: frontmost, library: library, reason: reason)
        }
    }

    /// The front account, else the default one. A rule's `reason` is
    /// kept either way, so the log never says no rule matched when one did.
    private func frontOrDefault(frontmost: ProfileID?, library: ProfileLibrary, reason: LinkReason?) -> (profile: Profile?, reason: LinkReason) {
        if let id = frontmost, let profile = library.profile(withID: id) {
            return (profile, reason ?? .frontmost)
        }
        return (library.defaultProfile, reason ?? .defaultAccount)
    }
}

/// One link that reached Lanes. The link itself is never kept, because a
/// sign-in link can carry a one-time code: only its kind, when it came,
/// the app it came from, where it went and why.
public struct LinkLogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: String
    public var receivedAt: Date
    public var outcome: String
    /// The account it went to, when Lanes routed it.
    public var target: ProfileID?
    /// Why it went there, in words.
    public var reason: String?
    /// The name of the app it was clicked in.
    public var source: String?

    public init(id: UUID = UUID(), kind: String, receivedAt: Date, outcome: String, target: ProfileID? = nil, reason: String? = nil, source: String? = nil) {
        self.id = id
        self.kind = kind
        self.receivedAt = receivedAt
        self.outcome = outcome
        self.target = target
        self.reason = reason
        self.source = source
    }
}

/// The last 30 days of links, newest first.
public struct LinkLog: Codable, Equatable, Sendable {
    public static let retention: TimeInterval = 30 * 24 * 3600
    public static let maximumEntries = 2000

    public private(set) var entries: [LinkLogEntry]

    public init(entries: [LinkLogEntry] = []) {
        self.entries = entries.sorted { $0.receivedAt > $1.receivedAt }
    }

    public mutating func add(_ entry: LinkLogEntry, now: Date) {
        entries.insert(entry, at: 0)
        prune(now: now)
    }

    /// Drops entries older than 30 days, or beyond the cap.
    public mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        entries = Array(entries.filter { $0.receivedAt >= cutoff }.prefix(Self.maximumEntries))
    }

    public mutating func removeAll() {
        entries = []
    }

    public static func load(from url: URL, now: Date) -> LinkLog {
        guard let data = try? Data(contentsOf: url),
              var log = try? JSONDecoder.linkLog.decode(LinkLog.self, from: data) else { return LinkLog() }
        log.entries.sort { $0.receivedAt > $1.receivedAt }
        log.prune(now: now)
        return log
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.linkLog.encode(self).write(to: url, options: .atomic)
    }
}

extension JSONDecoder {
    static var linkLog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var linkLog: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
