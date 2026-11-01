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
    case setup
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
        case .setup: return String(localized: "Kurulum")
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
        case .setup: return "checklist"
        case .health: return "stethoscope"
        case .maintenance: return "externaldrive"
        case .privacy: return "hand.raised"
        case .integrations: return "puzzlepiece.extension"
        // Not "checklist": Kurulum uses it in the same sidebar section.
        case .validation: return "testtube.2"
        case .settings: return "gearshape"
        }
    }

    /// Pages a `lanes://show?page=` address can name.
    init?(pageName: String) {
        switch pageName.lowercased() {
        case "overview": self = .overview
        case "sessions": self = .sessions
        case "usage": self = .usage
        case "accountmap", "map": self = .accountMap
        case "links": self = .links
        case "toolbox": self = .toolbox
        case "scenes": self = .scenes
        case "setup": self = .setup
        case "health": self = .health
        case "maintenance": self = .maintenance
        case "privacy": self = .privacy
        case "integrations": self = .integrations
        case "settings": self = .settings
        default: return nil
        }
    }

    /// Whether the sidebar lists the page. Only the Faz 0 checks need the
    /// developer pages setting.
    func isVisible(showingDeveloperPages: Bool) -> Bool {
        switch self {
        case .validation: return showingDeveloperPages
        default: return true
        }
    }

    /// The page the window actually shows for this selection. A hidden page
    /// left in the history, or one the setting just hid, shows the overview.
    /// The title, the sidebar highlight and the detail all use this value.
    func displayed(showingDeveloperPages: Bool) -> Destination {
        isVisible(showingDeveloperPages: showingDeveloperPages) ? self : .overview
    }

    /// Pages with their own list column (Settings panes, Validation checks)
    /// need the width the inspector would take, so it stays closed there.
    var allowsInspector: Bool {
        switch self {
        case .settings, .validation: return false
        default: return true
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case menuBarAndDock
    case tabs
    case shortcuts
    case notifications
    case updates
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "Genel")
        case .menuBarAndDock: return String(localized: "Menü Çubuğu ve Dock")
        case .tabs: return String(localized: "Sekmeler")
        case .shortcuts: return String(localized: "Kısayollar")
        case .notifications: return String(localized: "Bildirimler")
        case .updates: return String(localized: "Güncellemeler")
        case .advanced: return String(localized: "Gelişmiş")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuBarAndDock: return "menubar.dock.rectangle"
        case .tabs: return "rectangle.topthird.inset.filled"
        case .shortcuts: return "command"
        case .notifications: return "bell.badge"
        case .updates: return "arrow.triangle.2.circlepath"
        case .advanced: return "slider.horizontal.3"
        }
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
        case .desktop: return String(localized: "Uygulama")
        case .claudeCode: return String(localized: "Claude Code")
        case .security: return String(localized: "Güvenlik")
        case .storage: return String(localized: "Depolama")
        }
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
        // "windowBadges" was merged into Menü Çubuğu ve Dock.
        settingsPane = stored == "windowBadges" ? .menuBarAndDock : stored.flatMap(SettingsPane.init(rawValue:)) ?? .general
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
