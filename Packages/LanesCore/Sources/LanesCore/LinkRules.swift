import Foundation

/// Which account a routable `claude://` link opens in. Sign-in, OAuth and
/// unknown links never reach these rules.
public struct LinkRules: Codable, Equatable, Sendable {
    /// The kinds of link a rule can name.
    public enum LinkKind: String, Codable, CaseIterable, Sendable {
        case newChat
        case code
        case resume
        case cowork
        case settings

        public init(_ route: ClaudeLink.Route) {
            switch route {
            case .newChat: self = .newChat
            case .newCodeSession, .continueCodeSession, .codeNeedsInput: self = .code
            case .resume: self = .resume
            case .cowork: self = .cowork
            case .settings: self = .settings
            }
        }
    }

    public enum Target: Codable, Equatable, Hashable, Sendable {
        /// The account whose Claude is in front, else the default account.
        case frontmost
        case profile(ProfileID)
    }

    public var fallback: Target
    public var byKind: [LinkKind: Target]
    /// "Akıllı Yönlendirme" rules, tried in order before the per-kind ones.
    public var rules: [LinkRule]

    public init(fallback: Target = .frontmost, byKind: [LinkKind: Target] = [:], rules: [LinkRule] = []) {
        self.fallback = fallback
        self.byKind = byKind
        self.rules = rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fallback = (try? container.decode(Target.self, forKey: .fallback)) ?? .frontmost
        let raw = (try? container.decode([String: Target].self, forKey: .byKind)) ?? [:]
        var byKind: [LinkKind: Target] = [:]
        for (key, value) in raw {
            if let kind = LinkKind(rawValue: key) { byKind[kind] = value }
        }
        self.byKind = byKind
        // One by one, so a rule this Lanes cannot read drops only itself.
        rules = ((try? container.decode([LossyLinkRule].self, forKey: .rules)) ?? []).compactMap(\.rule)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fallback, forKey: .fallback)
        var raw: [String: Target] = [:]
        for (kind, target) in byKind { raw[kind.rawValue] = target }
        try container.encode(raw, forKey: .byKind)
        try container.encode(rules, forKey: .rules)
    }

    enum CodingKeys: String, CodingKey {
        case fallback, byKind, rules
    }

    public func target(for kind: LinkKind) -> Target {
        byKind[kind] ?? fallback
    }

    /// The account the link goes to. A rule naming an account that no longer
    /// exists falls back to the front account, then the default one.
    public func profile(for route: ClaudeLink.Route, frontmost: ProfileID?, library: ProfileLibrary) -> Profile? {
        decide(route: route, sourceApp: nil, now: Date(), frontmost: frontmost, library: library).profile
    }

    /// Drops rules for accounts that no longer exist.
    public mutating func prune(profiles: Set<ProfileID>) {
        if case let .profile(id) = fallback, !profiles.contains(id) {
            fallback = .frontmost
        }
        byKind = byKind.filter { _, target in
            if case let .profile(id) = target { return profiles.contains(id) }
            return true
        }
        rules = rules.filter { rule in
            if case let .profile(id) = rule.target { return profiles.contains(id) }
            return true
        }
    }
}

/// Decodes a rule, or nil when it cannot be read, without failing the list.
private struct LossyLinkRule: Decodable {
    let rule: LinkRule?

    init(from decoder: Decoder) throws {
        rule = try? LinkRule(from: decoder)
    }
}
