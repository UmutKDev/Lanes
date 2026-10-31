import AppIntents
import LanesCore

/// Lets Shortcuts, Spotlight and Siri reach the running Lanes.
@MainActor
enum IntentBridge {
    static weak var model: AppModel?
}

struct LanesIntentError: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource

    static let notRunning = LanesIntentError(localizedStringResource: "Lanes henüz hazır değil. Biraz sonra yeniden dene.")
    static let accountGone = LanesIntentError(localizedStringResource: "Bu hesap artık Lanes'te yok.")
    static let sceneGone = LanesIntentError(localizedStringResource: "Bu sahne artık Lanes'te yok.")
}

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Claude hesabı"
    static let defaultQuery = AccountQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ profile: Profile) {
        id = profile.id.rawValue
        name = profile.name
    }
}

struct AccountQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        let profiles = IntentBridge.model?.library.profiles ?? []
        return profiles.filter { identifiers.contains($0.id.rawValue) }.map(AccountEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        (IntentBridge.model?.library.profiles ?? []).map(AccountEntity.init)
    }
}

struct SceneEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lanes sahnesi"
    static let defaultQuery = SceneQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ scene: ProfileScene) {
        id = scene.id.rawValue
        name = scene.name
    }
}

struct SceneQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SceneEntity] {
        let scenes = IntentBridge.model?.library.scenes ?? []
        return scenes.filter { identifiers.contains($0.id.rawValue) }.map(SceneEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SceneEntity] {
        (IntentBridge.model?.library.scenes ?? []).map(SceneEntity.init)
    }
}

struct OpenAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Claude Hesabını Aç"
    static let description = IntentDescription("Bir Claude hesabını Lanes ile açar ya da açıksa öne getirir.")

    @Parameter(title: "Hesap")
    var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = IntentBridge.model else { throw LanesIntentError.notRunning }
        guard let profile = model.profile(withID: ProfileID(rawValue: account.id)) else { throw LanesIntentError.accountGone }
        await model.openAndWait(profile)
        return .result()
    }
}

struct OpenSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Lanes Sahnesini Aç"
    static let description = IntentDescription("Bir sahnedeki bütün hesapları sırayla açar.")

    @Parameter(title: "Sahne")
    var scene: SceneEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = IntentBridge.model else { throw LanesIntentError.notRunning }
        guard let found = model.library.scene(withID: SceneID(rawValue: scene.id)) else { throw LanesIntentError.sceneGone }
        await model.openAndWait(found)
        return .result()
    }
}

struct LanesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAccountIntent(),
            phrases: ["\(.applicationName) ile Claude hesabı aç"],
            shortTitle: "Hesabı Aç",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: OpenSceneIntent(),
            phrases: ["\(.applicationName) sahnesini aç"],
            shortTitle: "Sahneyi Aç",
            systemImageName: "rectangle.3.group"
        )
    }
}
