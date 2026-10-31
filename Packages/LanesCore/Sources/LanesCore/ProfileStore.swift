import Foundation

/// What `profiles.json` holds. The order of `profiles` is the order the user
/// sees, and the first nine get ⌘1 to ⌘9.
public struct ProfileLibrary: Codable, Equatable, Sendable {
    /// Raise this only for a change an older Lanes must not read at all, such
    /// as a field whose meaning changes. Adding a field or a new value for an
    /// existing field needs no new version: older builds keep what they cannot
    /// read and write it back unchanged. A new version ships with a migration
    /// and a new frozen file in the compatibility tests.
    public static let currentVersion = 1

    public var version: Int
    public var profiles: [Profile]
    /// Saved groups of accounts. Written only when there is one, so a list
    /// without scenes looks exactly as before. Older builds keep the field
    /// as one they cannot read.
    public var scenes: [ProfileScene] = []
    /// Top-level fields this build does not know, kept for the next save.
    private var keptFields: [String: JSONValue] = [:]

    public init(version: Int = ProfileLibrary.currentVersion, profiles: [Profile] = [], scenes: [ProfileScene] = []) {
        self.version = version
        self.profiles = profiles
        self.scenes = scenes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        // The first files had a version from the start, so a missing one can only mean 1.
        version = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("version")) ?? 1
        profiles = try container.decodeIfPresent([Profile].self, forKey: AnyCodingKey("profiles")) ?? []
        // Scenes that don't read are kept as they were, like unknown fields.
        if container.contains(AnyCodingKey("scenes")) {
            if let scenes = try? container.decode([ProfileScene].self, forKey: AnyCodingKey("scenes")) {
                self.scenes = scenes
            } else {
                keptFields["scenes"] = try container.decode(JSONValue.self, forKey: AnyCodingKey("scenes"))
            }
        }
        for key in container.allKeys where !["version", "profiles", "scenes"].contains(key.stringValue) {
            keptFields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        // Scenes made in this build replace ones it could not read.
        for (key, value) in keptFields where !(key == "scenes" && !scenes.isEmpty) {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(version, forKey: AnyCodingKey("version"))
        try container.encode(profiles, forKey: AnyCodingKey("profiles"))
        if !scenes.isEmpty {
            try container.encode(scenes, forKey: AnyCodingKey("scenes"))
        }
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
    case duplicateSceneID(SceneID)
    case unknownScene(SceneID)
}

/// Reads and writes `profiles.json`. Writes are atomic, so a crash halfway never
/// leaves a broken file behind. Before each save the list on disk, if it
/// reads, is copied to `profiles.backup.json`, so one good copy always
/// survives a file that later turns unreadable.
public struct ProfileStore: Sendable {
    public let fileURL: URL

    /// The last list that read correctly before the most recent save.
    public var backupURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("backup.json")
    }

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

    /// Saves the library. A file on disk that `load()` rejects is moved aside
    /// first, so a save never replaces the only copy of a list Lanes could not
    /// read. Returns where that copy went, or nil when nothing was moved.
    @discardableResult
    public func save(_ library: ProfileLibrary, now: Date = Date()) throws -> URL? {
        try ProfileStore.validate(library)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ProfileStore.encoder.encode(library)
        var setAside: URL?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                _ = try load()
                try Data(contentsOf: fileURL).write(to: backupURL, options: [.atomic])
            } catch {
                setAside = try setAsideUnreadableFile(now: now)
            }
        }
        try data.write(to: fileURL, options: [.atomic])
        return setAside
    }

    /// Renames the file to `profiles-unreadable-<date>-<time>.json` in the same
    /// folder, adding a counter if that name is taken.
    func setAsideUnreadableFile(now: Date) throws -> URL {
        try LanesCore.setAsideUnreadableFile(at: fileURL, now: now)
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
        var seenScenes = Set<SceneID>()
        for scene in library.scenes {
            guard seenScenes.insert(scene.id).inserted else {
                throw ProfileStoreError.duplicateSceneID(scene.id)
            }
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
        // A scene keeps its name and other accounts.
        for sceneIndex in scenes.indices {
            scenes[sceneIndex].profileIDs.removeAll { $0 == id }
        }
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

/// What Lanes starts with when it opens.
public struct ProfileStartup {
    public var library: ProfileLibrary
    /// Why the list could not be read. Lanes then starts with an empty list
    /// and leaves the file alone until the next save moves it aside.
    public var loadError: (any Error)?
    /// True when there was no list yet, or it was empty.
    public var isFirstLaunch: Bool
    /// True when the list could not be read and `library` comes from
    /// `profiles.backup.json`. `loadError` says why. The unreadable file
    /// stays until the next save moves it aside.
    public var restoredFromBackup = false
    /// True when Claude.app's own account was put at the top of the list.
    /// The library still needs saving.
    public var addedClaudeAppAccount = false
}

extension ProfileStore {
    /// Loads the list. An unreadable list never turns into a new one.
    ///
    /// Lanes's own accounts each run in their own clone and folder. The
    /// account in Claude.app itself is only shown, marked as Claude.app's,
    /// with almost no settings: pass its name when Claude's own folder
    /// exists, and it is put at the top if the list lacks it.
    public func startup(claudeAppAccountName: String? = nil) -> ProfileStartup {
        var startup: ProfileStartup
        do {
            startup = ProfileStartup(library: try load(), loadError: nil, isFirstLaunch: false)
        } catch {
            guard let backup = try? ProfileStore(fileURL: backupURL).load(), !backup.profiles.isEmpty else {
                return ProfileStartup(library: ProfileLibrary(), loadError: error, isFirstLaunch: false)
            }
            startup = ProfileStartup(library: backup, loadError: error, isFirstLaunch: false, restoredFromBackup: true)
        }
        if startup.library.profiles.isEmpty {
            startup.isFirstLaunch = startup.loadError == nil
        }
        if startup.loadError == nil || startup.restoredFromBackup,
           let name = claudeAppAccountName, startup.library.defaultProfile == nil {
            startup.library.profiles.insert(Profile(name: name, color: .gray, isDefault: true), at: 0)
            startup.addedClaudeAppAccount = true
        }
        return startup
    }
}
