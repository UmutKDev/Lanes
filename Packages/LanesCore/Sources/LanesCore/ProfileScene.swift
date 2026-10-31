import Foundation

public struct SceneID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> SceneID {
        SceneID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }
}

/// A saved group of accounts that open together, such as "İş" with the work
/// and client accounts. Called a scene in the app.
public struct ProfileScene: Identifiable, Hashable, Codable, Sendable {
    public var id: SceneID
    public var name: String
    /// In the order they open.
    public var profileIDs: [ProfileID]
    /// Opens the scene each time Lanes starts, which with "Oturum açıldığında
    /// Lanes'i başlat" means at login.
    public var opensWhenLanesStarts: Bool

    public init(id: SceneID = .make(), name: String, profileIDs: [ProfileID], opensWhenLanesStarts: Bool = false) {
        self.id = id
        self.name = name
        self.profileIDs = profileIDs
        self.opensWhenLanesStarts = opensWhenLanesStarts
    }

    enum CodingKeys: String, CodingKey {
        case id, name, profileIDs, opensWhenLanesStarts
    }

    /// Only the ID is required, like a profile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SceneID.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Adsız sahne"
        profileIDs = (try? container.decode([ProfileID].self, forKey: .profileIDs)) ?? []
        opensWhenLanesStarts = (try? container.decode(Bool.self, forKey: .opensWhenLanesStarts)) ?? false
    }

    /// The scene's accounts that still exist, in the scene's order.
    public func profiles(in library: ProfileLibrary) -> [Profile] {
        profileIDs.compactMap(library.profile(withID:))
    }
}

extension ProfileLibrary {
    public func scene(withID id: SceneID) -> ProfileScene? {
        scenes.first { $0.id == id }
    }

    public mutating func addScene(_ scene: ProfileScene) throws {
        guard self.scene(withID: scene.id) == nil else {
            throw ProfileStoreError.duplicateSceneID(scene.id)
        }
        scenes.append(scene)
    }

    public mutating func updateScene(_ scene: ProfileScene) throws {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else {
            throw ProfileStoreError.unknownScene(scene.id)
        }
        scenes[index] = scene
    }

    public mutating func removeScene(_ id: SceneID) {
        scenes.removeAll { $0.id == id }
    }
}
