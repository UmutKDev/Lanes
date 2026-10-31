import LanesCore
import Observation
import SwiftUI

/// Every page the main window can show.
enum Destination: Hashable {
    case overview
    case sessions
    case usage
    case account(ProfileID)
    case accountMap
    case links
    case toolbox
    case scenes
    case health
    case maintenance
    case privacy
    case integrations
    case validation
    case settings

    var title: String {
        switch self {
        case .overview: return String(localized: "Genel Bakış")
        case .sessions: return String(localized: "Oturumlar")
        case .usage: return String(localized: "Kullanım")
        case .account: return String(localized: "Hesap")
        case .accountMap: return String(localized: "Hesap Haritası")
        case .links: return String(localized: "Bağlantılar")
        case .toolbox: return String(localized: "Araç Kutusu")
        case .scenes: return String(localized: "Sahneler")
        case .health: return String(localized: "Sağlık")
        case .maintenance: return String(localized: "Bakım")
        case .privacy: return String(localized: "Gizlilik")
        case .integrations: return String(localized: "Entegrasyonlar")
        case .validation: return String(localized: "Faz 0 Doğrulama")
        case .settings: return String(localized: "Ayarlar")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .sessions: return "bubble.left.and.text.bubble.right"
        case .usage: return "gauge.with.dots.needle.33percent"
        case .account: return "person.crop.circle"
        case .accountMap: return "point.3.connected.trianglepath.dotted"
        case .links: return "link"
        case .toolbox: return "wrench.and.screwdriver"
        case .scenes: return "rectangle.3.group"
        case .health: return "stethoscope"
        case .maintenance: return "externaldrive"
        case .privacy: return "hand.raised"
        case .integrations: return "puzzlepiece.extension"
        case .validation: return "checklist"
        case .settings: return "gearshape"
        }
    }

    /// Whether the sidebar lists the page. Pages that are not built yet and
    /// the Faz 0 checks only show with the developer pages setting.
    func isVisible(showingDeveloperPages: Bool) -> Bool {
        switch self {
        case .overview, .account, .scenes, .health, .privacy, .settings: return true
        default: return showingDeveloperPages
        }
    }

    /// One sentence for pages that are not built yet.
    var plannedSummary: String {
        switch self {
        case .sessions: return String(localized: "Tüm hesapların Claude Code oturumları tek listede. Bir oturumu başka bir hesapla sürdürmek de buradan olacak.")
        case .usage: return String(localized: "Her hesabın kendi kullanım sınırı ve sıfırlanma saati. Hesaplar birbirleriyle toplanmaz ya da sıralanmaz.")
        case .accountMap: return String(localized: "Hangi klasörün, hangi bağlantının hangi hesapla açılacağını belirleyen kurallar.")
        case .links: return String(localized: "Lanes'in yönlendirdiği claude:// bağlantılarının geçmişi.")
        case .toolbox: return String(localized: "Hesaplar arasında paylaşılabilen MCP sunucuları, komutlar ve ayarlar.")
        case .scenes: return String(localized: "Birden çok hesabı tek tıkla, belirli pencere düzeniyle açan kayıtlı düzenler.")
        case .health: return String(localized: "Claude sürümü, klonların imza durumu ve bağlantı varsayılanı tek bakışta.")
        case .maintenance: return String(localized: "Profil klasörlerinin boyutu, önbellek temizliği ve yedekleme.")
        case .integrations: return String(localized: "Kısayollar, Raycast ve Alfred ile bağlantılar.")
        default: return ""
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case menuBarAndDock
    case tabs
    case windowBadges
    case shortcuts
    case notifications
    case updates
    case license
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "Genel")
        case .menuBarAndDock: return String(localized: "Menü Çubuğu ve Dock")
        case .tabs: return String(localized: "Sekmeler")
        case .windowBadges: return String(localized: "Pencere Göstergeleri")
        case .shortcuts: return String(localized: "Kısayollar")
        case .notifications: return String(localized: "Bildirimler")
        case .updates: return String(localized: "Güncellemeler")
        case .license: return String(localized: "Lisans")
        case .advanced: return String(localized: "Gelişmiş")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuBarAndDock: return "menubar.dock.rectangle"
        case .tabs: return "rectangle.topthird.inset.filled"
        case .windowBadges: return "macwindow.badge.plus"
        case .shortcuts: return "command"
        case .notifications: return "bell.badge"
        case .updates: return "arrow.triangle.2.circlepath"
        case .license: return "checkmark.seal"
        case .advanced: return "slider.horizontal.3"
        }
    }

    /// Panes that are not built yet only show with the developer pages setting.
    var isBuilt: Bool {
        switch self {
        case .general, .menuBarAndDock, .tabs, .windowBadges, .shortcuts, .updates, .advanced: return true
        case .notifications, .license: return false
        }
    }

    static func visible(showingDeveloperPages: Bool) -> [SettingsPane] {
        allCases.filter { $0.isBuilt || showingDeveloperPages }
    }
}

enum AccountTab: String, CaseIterable, Identifiable {
    case general
    case identity
    case desktop
    case claudeCode
    case security
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "Genel")
        case .identity: return String(localized: "Kimlik")
        case .desktop: return String(localized: "Desktop")
        case .claudeCode: return String(localized: "Claude Code")
        case .security: return String(localized: "Güvenlik")
        case .storage: return String(localized: "Depolama")
        }
    }

    /// Tabs that are not built yet only show with the developer pages setting.
    var isBuilt: Bool {
        switch self {
        case .general, .desktop, .claudeCode: return true
        case .identity, .security, .storage: return false
        }
    }

    static func visible(showingDeveloperPages: Bool) -> [AccountTab] {
        allCases.filter { $0.isBuilt || showingDeveloperPages }
    }
}

/// Where the main window is, with back and forward history.
@MainActor
@Observable
final class NavigationModel {
    private(set) var selection: Destination = .overview
    private var backStack: [Destination] = []
    private var forwardStack: [Destination] = []

    var showsInspector = false
    var isAddingProfile = false
    var accountTab: AccountTab = .general
    private(set) var settingsPane: SettingsPane

    init() {
        let stored = UserDefaults.standard.string(forKey: Preferences.Key.lastSettingsPane)
        settingsPane = stored.flatMap(SettingsPane.init(rawValue:)) ?? .general
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func navigate(to destination: Destination) {
        guard destination != selection else { return }
        backStack.append(selection)
        forwardStack.removeAll()
        selection = destination
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(selection)
        selection = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(selection)
        selection = next
    }

    func selectSettingsPane(_ pane: SettingsPane) {
        settingsPane = pane
        UserDefaults.standard.set(pane.rawValue, forKey: Preferences.Key.lastSettingsPane)
    }

    /// Drops a deleted account from the history.
    func forget(_ id: ProfileID) {
        let gone = Destination.account(id)
        backStack.removeAll { $0 == gone }
        forwardStack.removeAll { $0 == gone }
        if selection == gone {
            selection = .overview
        }
    }
}
