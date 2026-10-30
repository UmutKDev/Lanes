import Foundation

/// UserDefaults keys. Views read them with `@AppStorage` using the same keys.
enum Preferences {
    enum Key {
        static let showsDockIconWithWindow = "showsDockIconWithWindow"
        static let showsRunningCountInMenuBar = "showsRunningCountInMenuBar"
        static let linkRoutingEnabled = "linkRoutingEnabled"
        static let lastSettingsPane = "lastSettingsPane"
        static let showsDeveloperPages = "showsDeveloperPages"
        static let relaunchedAfterUpdate = "relaunchedAfterUpdate"
    }

    static var showsDockIconWithWindow: Bool {
        UserDefaults.standard.object(forKey: Key.showsDockIconWithWindow) as? Bool ?? true
    }

    static var showsRunningCountInMenuBar: Bool {
        UserDefaults.standard.object(forKey: Key.showsRunningCountInMenuBar) as? Bool ?? true
    }

    /// Debug builds show the Faz 0 checks and the pages that are not built
    /// yet; builds for testers hide them until the setting is turned on.
    static let developerPagesDefault: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    static var showsDeveloperPages: Bool {
        UserDefaults.standard.object(forKey: Key.showsDeveloperPages) as? Bool ?? developerPagesDefault
    }

    /// Off until Faz 0 shows that links can be delivered to the right window.
    static var linkRoutingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.linkRoutingEnabled)
    }
}
