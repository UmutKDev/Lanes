import AppIntents
import Foundation
import UniformTypeIdentifiers
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
    static let claudeAppAccount = LanesIntentError(localizedStringResource: "Claude uygulamasının kendi hesabı Lanes'ten yönetilmez.")
    static let notAFolder = LanesIntentError(localizedStringResource: "Seçilen öğe bir klasör değil.")

    @MainActor
    static func profile(for account: AccountEntity) throws -> (AppModel, Profile) {
        guard let model = IntentBridge.model else { throw notRunning }
        guard let profile = model.profile(withID: ProfileID(rawValue: account.id)) else { throw accountGone }
        return (model, profile)
    }
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

struct QuitAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Claude Hesabını Kapat"
    static let description = IntentDescription("Bir hesabın Claude'unu ⌘Q gibi kapatır. Kapalıysa bir şey yapmaz.")

    @Parameter(title: "Hesap")
    var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let (model, profile) = try LanesIntentError.profile(for: account)
        guard !profile.isDefault else { throw LanesIntentError.claudeAppAccount }
        model.quit(profile)
        return .result()
    }
}

struct StartClaudeCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Claude Code'u Başlat"
    static let description = IntentDescription("Terminalde bir hesabın Claude Code'unu açar: seçilen klasörde, yoksa hesabın varsayılan klasöründe.")

    @Parameter(title: "Hesap")
    var account: AccountEntity

    @Parameter(title: "Klasör", supportedContentTypes: [.folder])
    var folder: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult {
        let (model, profile) = try LanesIntentError.profile(for: account)
        if let folder {
            guard let url = folder.fileURL, url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                throw LanesIntentError.notAFolder
            }
            model.openClaudeCode(profile, in: url)
        } else {
            model.openClaudeCode(profile)
        }
        return .result()
    }
}

struct MarkLimitedIntent: AppIntent {
    static let title: LocalizedStringResource = "Hesabı Dinlenmeye Al"
    static let description = IntentDescription("Limite takılan bir hesabı belirtilen saat kadar dinlenmeye alır; bağlantılar bu sürede aynı türdeki başka bir hesaba gider. 0 saat dinlenmeyi bitirir.")

    @Parameter(title: "Hesap")
    var account: AccountEntity

    @Parameter(title: "Saat", default: 5, inclusiveRange: (0, 48))
    var hours: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        let (model, profile) = try LanesIntentError.profile(for: account)
        guard !profile.isDefault else { throw LanesIntentError.claudeAppAccount }
        model.setLimited(profile, until: hours > 0 ? LimitWatch.until(hours: hours, from: Date()) : nil)
        return .result()
    }
}

struct GetFrontAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Öndeki Claude Hesabı"
    static let description = IntentDescription("En son önde olan Lanes hesabının adını verir.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let model = IntentBridge.model else { throw LanesIntentError.notRunning }
        let name = model.lastFrontProfileID.flatMap { model.profile(withID: $0)?.name } ?? ""
        return .result(value: name)
    }
}

struct GetFrontTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugünkü Claude Süresi"
    static let description = IntentDescription("Bir hesabın bugün önde kaldığı süreyi dakika olarak verir (tahmini; boşta geçen süre sayılmaz).")

    @Parameter(title: "Hesap")
    var account: AccountEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let (model, profile) = try LanesIntentError.profile(for: account)
        let minutes = Int(model.frontSeconds(for: profile.id, days: 1) / 60)
        return .result(value: minutes)
    }
}

struct WorkingClaudeCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Claude Code Çalışan Hesaplar"
    static let description = IntentDescription("Claude Code'un şu an çalıştığı hesapların adlarını verir. Oturum dosyalarının değişme zamanından tahmin edilir.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let model = IntentBridge.model else { throw LanesIntentError.notRunning }
        let names = model.library.profiles
            .filter { model.claudeCodePulse[$0.id] == .working }
            .map(\.name)
        return .result(value: names)
    }
}

enum AccountClassChoice: String, AppEnum {
    case personal, employer, client

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Hesap türü"
    static let caseDisplayRepresentations: [AccountClassChoice: DisplayRepresentation] = [
        .personal: "Kişisel",
        .employer: "İşveren",
        .client: "Müşteri",
    ]

    var name: String {
        switch self {
        case .personal: return String(localized: "Kişisel")
        case .employer: return String(localized: "İşveren")
        case .client: return String(localized: "Müşteri")
        }
    }

    var accountClass: AccountClass {
        switch self {
        case .personal: return .personal
        case .employer: return .employer
        case .client: return .client
        }
    }
}

/// Lanes's Focus filter: while a Focus is on, links go to the chosen
/// account, the menu bar panel lists one kind of account, and a scene can
/// open when the Focus starts.
struct LanesFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Lanes"
    static let description = IntentDescription("Odak açıkken bağlantıların gideceği hesabı ve panelde görünen hesap türünü seçer, istersen bir sahne açar.")

    @Parameter(title: "Bağlantıların gideceği hesap")
    var linkAccount: AccountEntity?

    @Parameter(title: "Panelde yalnız bu tür")
    var accountClass: AccountClassChoice?

    @Parameter(title: "Odak açılınca açılacak sahne")
    var scene: SceneEntity?

    var displayRepresentation: DisplayRepresentation {
        var parts: [String] = []
        if let linkAccount { parts.append(String(localized: "Bağlantılar: \(linkAccount.name)")) }
        if let accountClass { parts.append(String(localized: "Panel: \(accountClass.name)")) }
        if let scene { parts.append(String(localized: "Sahne: \(scene.name)")) }
        return DisplayRepresentation(
            title: "Lanes",
            subtitle: parts.isEmpty ? nil : LocalizedStringResource(stringLiteral: parts.joined(separator: " · "))
        )
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = IntentBridge.model else { throw LanesIntentError.notRunning }
        model.applyFocus(
            linkProfileID: linkAccount.map { ProfileID(rawValue: $0.id) },
            accountClass: accountClass?.accountClass,
            scene: scene.map { SceneID(rawValue: $0.id) }
        )
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
        AppShortcut(
            intent: StartClaudeCodeIntent(),
            phrases: ["\(.applicationName) ile Claude Code başlat"],
            shortTitle: "Claude Code",
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: MarkLimitedIntent(),
            phrases: ["\(.applicationName) hesabı dinlenmeye al"],
            shortTitle: "Dinlenmeye Al",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: WorkingClaudeCodeIntent(),
            phrases: ["\(.applicationName) Claude Code kimde çalışıyor"],
            shortTitle: "Claude Code Durumu",
            systemImageName: "waveform"
        )
    }
}
