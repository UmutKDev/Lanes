import Foundation

/// What `profiles.json` holds. The order of `profiles` is the order the user
/// sees, and the first nine get ⌘1 to ⌘9.
public struct ProfileLibrary: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var profiles: [Profile]

    public init(version: Int = ProfileLibrary.currentVersion, profiles: [Profile] = []) {
        self.version = version
        self.profiles = profiles
    }

    public var defaultProfile: Profile? {
        profiles.first(where: \.isDefault)
    }

    public func profile(withID id: ProfileID) -> Profile? {
        profiles.first(where: { $0.id == id })
    }

    /// The keyboard shortcut number (1 to 9) for a profile, if it has one.
    public func shortcutNumber(for id: ProfileID) -> Int? {
        guard let index = profiles.firstIndex(where: { $0.id == id }), index < 9 else { return nil }
        return index + 1
    }
}

public enum ProfileStoreError: Error, Equatable {
    case duplicateID(ProfileID)
    case unknownProfile(ProfileID)
    case moreThanOneDefault
    case unsupportedVersion(Int)
}

/// Reads and writes `profiles.json`. Writes are atomic, so a crash halfway never
/// leaves a broken file behind.
public struct ProfileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(paths: ProfilePaths) {
        self.init(fileURL: paths.profilesFile)
    }

    /// Loads the library, or returns an empty one when the file doesn't exist yet.
    public func load() throws -> ProfileLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProfileLibrary()
        }
        let data = try Data(contentsOf: fileURL)
        let library = try ProfileStore.decoder.decode(ProfileLibrary.self, from: data)
        guard library.version <= ProfileLibrary.currentVersion else {
            throw ProfileStoreError.unsupportedVersion(library.version)
        }
        try ProfileStore.validate(library)
        return library
    }

    public func save(_ library: ProfileLibrary) throws {
        try ProfileStore.validate(library)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ProfileStore.encoder.encode(library)
        try data.write(to: fileURL, options: [.atomic])
    }

    static func validate(_ library: ProfileLibrary) throws {
        var seen = Set<ProfileID>()
        for profile in library.profiles {
            guard seen.insert(profile.id).inserted else {
                throw ProfileStoreError.duplicateID(profile.id)
            }
        }
        if library.profiles.filter(\.isDefault).count > 1 {
            throw ProfileStoreError.moreThanOneDefault
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension ProfileLibrary {
    public mutating func add(_ profile: Profile) throws {
        guard self.profile(withID: profile.id) == nil else {
            throw ProfileStoreError.duplicateID(profile.id)
        }
        if profile.isDefault, defaultProfile != nil {
            throw ProfileStoreError.moreThanOneDefault
        }
        profiles.append(profile)
    }

    public mutating func update(_ profile: Profile) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.unknownProfile(profile.id)
        }
        if profile.isDefault, let current = defaultProfile, current.id != profile.id {
            throw ProfileStoreError.moreThanOneDefault
        }
        profiles[index] = profile
    }

    public mutating func remove(_ id: ProfileID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.unknownProfile(id)
        }
        profiles.remove(at: index)
    }

    /// Moves a profile to a new position. Dragging rows in the sidebar calls
    /// this, and it is how ⌘1 to ⌘9 are assigned.
    public mutating func move(_ id: ProfileID, to newIndex: Int) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.unknownProfile(id)
        }
        let profile = profiles.remove(at: index)
        let clamped = min(max(newIndex, 0), profiles.count)
        profiles.insert(profile, at: clamped)
    }
}
