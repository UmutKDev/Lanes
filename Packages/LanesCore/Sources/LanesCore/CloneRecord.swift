import Foundation

/// What Lanes notes down next to a clone when it makes one, so it can tell
/// later whether the clone still matches Claude and the profile.
public struct CloneRecord: Codable, Equatable, Sendable {
    /// Claude's version the clone was copied from.
    public var claudeVersion: String?
    /// The profile's name, colour and letter the icon and bundle name show.
    public var name: String
    public var color: ProfileColor
    public var monogram: String
    public var madeAt: Date

    public init(claudeVersion: String?, name: String, color: ProfileColor, monogram: String, madeAt: Date = Date()) {
        self.claudeVersion = claudeVersion
        self.name = name
        self.color = color
        self.monogram = monogram
        self.madeAt = madeAt
    }

    public init(profile: Profile, claudeVersion: String?, madeAt: Date = Date()) {
        self.init(claudeVersion: claudeVersion, name: profile.name, color: profile.color, monogram: profile.monogram, madeAt: madeAt)
    }

    public static func read(from url: URL) -> CloneRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CloneRecord.self, from: data)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: [.atomic])
    }
}

/// Whether a profile's clone is ready to open.
public enum CloneStatus: Equatable, Sendable {
    /// The profile opens with Claude itself.
    case notNeeded
    /// There is no clone on disk.
    case missing
    case ready
    /// The clone works but no longer matches. Lanes renews it the next time
    /// the account opens while it is closed.
    case needsRenewal([CloneRenewalReason])

    public var needsWork: Bool {
        switch self {
        case .missing, .needsRenewal: return true
        case .notNeeded, .ready: return false
        }
    }
}

public enum CloneRenewalReason: Equatable, Sendable {
    /// Claude was updated after the clone was made.
    case claudeUpdated(from: String?, to: String)
    /// The profile was renamed, so the bundle's name is out of date.
    case renamed
    /// The colour or letter changed, so the icon is out of date.
    case iconChanged
    /// The clone has no record, for example one made by an older build.
    case unknownOrigin
}

public enum CloneCheck {
    /// Compares a clone on disk with the profile and the installed Claude.
    ///
    /// - Parameters:
    ///   - bundleName: The `.app` folder's name found in the profile's clone
    ///     folder, or nil when there is none.
    ///   - record: The clone's record, when it reads.
    ///   - claudeVersion: The installed Claude's version, when known.
    public static func status(
        for profile: Profile,
        bundleName: String?,
        record: CloneRecord?,
        claudeVersion: String?
    ) -> CloneStatus {
        guard usesClone(profile) else { return .notNeeded }
        guard let bundleName else { return .missing }
        guard let record else { return .needsRenewal([.unknownOrigin]) }
        var reasons: [CloneRenewalReason] = []
        if let claudeVersion, record.claudeVersion != claudeVersion {
            reasons.append(.claudeUpdated(from: record.claudeVersion, to: claudeVersion))
        }
        if bundleName != ProfilePaths.cloneBundleName(for: profile.name) {
            reasons.append(.renamed)
        }
        if record.color != profile.color || record.monogram != profile.monogram {
            reasons.append(.iconChanged)
        }
        return reasons.isEmpty ? .ready : .needsRenewal(reasons)
    }

    /// The main account always opens with Claude itself, whatever its mode
    /// says, so the account the user already had keeps working as before.
    public static func usesClone(_ profile: Profile) -> Bool {
        !profile.isDefault && (profile.mode == .signedClone || profile.mode == .separateIdentity)
    }
}
