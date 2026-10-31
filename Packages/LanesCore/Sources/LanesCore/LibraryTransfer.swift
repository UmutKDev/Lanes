import Foundation

/// The account list as a file the user can keep or take to another Mac:
/// names, colours, modes, notes and scenes. It holds no sign-in data and
/// no Claude folders, so accounts imported on a new Mac start signed out.
public struct LibraryExport: Codable, Equatable, Sendable {
    public static let kind = "lanes-accounts"

    public var kind: String
    public var version: Int
    public var exportedAt: Date
    public var profiles: [Profile]
    public var scenes: [ProfileScene]

    /// The Claude app's own account is left out: it belongs to Claude.
    public init(library: ProfileLibrary, exportedAt: Date = Date()) {
        kind = LibraryExport.kind
        version = 1
        self.exportedAt = exportedAt
        profiles = library.profiles.filter { !$0.isDefault }
        let exported = Set(profiles.map(\.id))
        scenes = library.scenes.map { scene in
            var scene = scene
            scene.profileIDs = scene.profileIDs.filter(exported.contains)
            // Window places belong to this Mac's screens.
            scene.windowFrames = [:]
            return scene
        }
    }

    public static func decode(_ data: Data) throws -> LibraryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(LibraryExport.self, from: data)
        guard export.kind == LibraryExport.kind else { throw LibraryTransferError.notAnExport }
        return export
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public struct MergeResult: Equatable, Sendable {
        public var library: ProfileLibrary
        public var addedProfiles: Int
        public var addedScenes: Int
        public var skipped: Int
    }

    /// Adds the accounts and scenes the library doesn't have yet, matched
    /// by ID, so importing the same file twice changes nothing. Existing
    /// accounts are never changed.
    public func merge(into library: ProfileLibrary) -> MergeResult {
        var library = library
        var addedProfiles = 0
        var addedScenes = 0
        var skipped = 0
        for profile in profiles where !profile.isDefault {
            if library.profile(withID: profile.id) == nil, (try? library.add(profile)) != nil {
                addedProfiles += 1
            } else {
                skipped += 1
            }
        }
        for scene in scenes {
            var scene = scene
            scene.profileIDs = scene.profileIDs.filter { library.profile(withID: $0) != nil }
            scene.windowFrames = [:]
            if library.scene(withID: scene.id) == nil, (try? library.addScene(scene)) != nil {
                addedScenes += 1
            } else {
                skipped += 1
            }
        }
        return MergeResult(library: library, addedProfiles: addedProfiles, addedScenes: addedScenes, skipped: skipped)
    }
}

public enum LibraryTransferError: LocalizedError, Equatable {
    case notAnExport

    public var errorDescription: String? {
        switch self {
        case .notAnExport: return "Bu dosya bir Lanes hesap listesi değil."
        }
    }
}
