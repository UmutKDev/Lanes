import Foundation

/// Stable identifier of a profile. Folder names on disk use it, so renaming a
/// profile never moves its data.
public struct ProfileID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> ProfileID {
        ProfileID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

/// The colours a profile can take. They map to system colours in the app, so
/// they adapt to light, dark and increased-contrast appearances.
public enum ProfileColor: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, mint, teal, cyan, indigo, brown, gray
}

/// How a profile's Claude Desktop instance is started.
public enum ProfileMode: String, Codable, CaseIterable, Sendable {
    /// The original Claude.app, started with the profile's own `--user-data-dir`.
    case standard
    /// An APFS clone of Claude.app with a Finder icon. Anthropic's signature stays intact.
    case signedClone
    /// A clone with its own bundle identifier, re-signed locally. Experimental.
    case separateIdentity
}

/// What kind of account a profile holds. Used for warnings and defaults, never
/// to rank accounts.
public enum AccountClass: String, Codable, CaseIterable, Sendable {
    case personal
    case employer
    case client
}

public struct Profile: Identifiable, Hashable, Codable, Sendable {
    public var id: ProfileID
    public var name: String
    public var monogram: String
    public var color: ProfileColor
    public var mode: ProfileMode
    public var accountClass: AccountClass
    /// The default profile uses Claude's own data folder and `~/.claude`, so the
    /// account the user already signed in to keeps working untouched.
    public var isDefault: Bool
    public var createdAt: Date

    public init(
        id: ProfileID = .make(),
        name: String,
        monogram: String? = nil,
        color: ProfileColor,
        mode: ProfileMode = .standard,
        accountClass: AccountClass = .personal,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.monogram = monogram ?? Profile.defaultMonogram(for: name)
        self.color = color
        self.mode = mode
        self.accountClass = accountClass
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    /// First letter of the name, upper-cased with Turkish rules ("işler" → "İ").
    public static func defaultMonogram(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased(with: Locale(identifier: "tr_TR"))
    }
}
