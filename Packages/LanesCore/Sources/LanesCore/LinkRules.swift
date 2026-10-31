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

    public init(fallback: Target = .frontmost, byKind: [LinkKind: Target] = [:]) {
        self.fallback = fallback
        self.byKind = byKind
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fallback, forKey: .fallback)
        var raw: [String: Target] = [:]
        for (kind, target) in byKind { raw[kind.rawValue] = target }
        try container.encode(raw, forKey: .byKind)
    }

    enum CodingKeys: String, CodingKey {
        case fallback, byKind
    }

    public func target(for kind: LinkKind) -> Target {
        byKind[kind] ?? fallback
    }

    /// The account the link goes to. A rule naming an account that no longer
    /// exists falls back to the front account, then the default one.
    public func profile(for route: ClaudeLink.Route, frontmost: ProfileID?, library: ProfileLibrary) -> Profile? {
        let frontProfile = frontmost.flatMap(library.profile(withID:))
        switch target(for: LinkKind(route)) {
        case let .profile(id):
            if let profile = library.profile(withID: id) { return profile }
            return frontProfile ?? library.defaultProfile
        case .frontmost:
            return frontProfile ?? library.defaultProfile
        }
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
    }
}
