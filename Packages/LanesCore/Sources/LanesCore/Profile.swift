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
    public var name: String { didSet { keptFields[Field.name.rawValue] = nil } }
    public var monogram: String { didSet { keptFields[Field.monogram.rawValue] = nil } }
    public var color: ProfileColor { didSet { keptFields[Field.color.rawValue] = nil } }
    public var mode: ProfileMode { didSet { keptFields[Field.mode.rawValue] = nil } }
    public var accountClass: AccountClass { didSet { keptFields[Field.accountClass.rawValue] = nil } }
    /// The default profile uses Claude's own data folder and `~/.claude`, so the
    /// account the user already signed in to keeps working untouched.
    public var isDefault: Bool { didSet { keptFields[Field.isDefault.rawValue] = nil } }
    public var createdAt: Date { didSet { keptFields[Field.createdAt.rawValue] = nil } }
    /// Fields this build could not read, as they were written. Saving puts
    /// them back, so an older Lanes never erases what a newer one stored.
    /// Setting a field drops its kept value.
    private var keptFields: [String: JSONValue] = [:]

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

extension Profile {
    enum Field: String, CaseIterable {
        case id, name, monogram, color, mode, accountClass, isDefault, createdAt
    }

    /// Reads a profile even when fields are missing or hold values this build
    /// does not know, such as a colour added later. Only the ID is required,
    /// because the profile's folders are named after it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var kept: [String: JSONValue] = [:]
        for key in container.allKeys where Field(rawValue: key.stringValue) == nil {
            kept[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        func read<T: Decodable>(_ type: T.Type, _ field: Field) throws -> T? {
            let key = AnyCodingKey(field.rawValue)
            guard container.contains(key) else { return nil }
            if let value = try? container.decode(type, forKey: key) {
                return value
            }
            kept[field.rawValue] = try container.decode(JSONValue.self, forKey: key)
            return nil
        }

        let name = try read(String.self, .name) ?? "Adsız hesap"
        id = try container.decode(ProfileID.self, forKey: AnyCodingKey(Field.id.rawValue))
        self.name = name
        monogram = try read(String.self, .monogram) ?? Profile.defaultMonogram(for: name)
        color = try read(ProfileColor.self, .color) ?? .gray
        mode = try read(ProfileMode.self, .mode) ?? .standard
        accountClass = try read(AccountClass.self, .accountClass) ?? .personal
        isDefault = try read(Bool.self, .isDefault) ?? false
        createdAt = try read(Date.self, .createdAt) ?? Date(timeIntervalSince1970: 0)
        keptFields = kept
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in keptFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        func write<T: Encodable>(_ value: T, _ field: Field) throws {
            guard keptFields[field.rawValue] == nil else { return }
            try container.encode(value, forKey: AnyCodingKey(field.rawValue))
        }
        try write(id, .id)
        try write(name, .name)
        try write(monogram, .monogram)
        try write(color, .color)
        try write(mode, .mode)
        try write(accountClass, .accountClass)
        try write(isDefault, .isDefault)
        try write(createdAt, .createdAt)
    }
}
