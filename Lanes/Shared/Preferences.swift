import Foundation

/// UserDefaults keys. Views read them with `@AppStorage` using the same keys.
enum Preferences {
    enum Key {
        static let showsDockIconWithWindow = "showsDockIconWithWindow"
        static let showsRunningCountInMenuBar = "showsRunningCountInMenuBar"
        static let linkRoutingEnabled = "linkRoutingEnabled"
        static let lastSettingsPane = "lastSettingsPane"
    }

    static var showsDockIconWithWindow: Bool {
        UserDefaults.standard.object(forKey: Key.showsDockIconWithWindow) as? Bool ?? true
    }

    static var showsRunningCountInMenuBar: Bool {
        UserDefaults.standard.object(forKey: Key.showsRunningCountInMenuBar) as? Bool ?? true
    }

    /// Off until Faz 0 shows that links can be delivered to the right window.
    static var linkRoutingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.linkRoutingEnabled)
    }
}
