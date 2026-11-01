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
        static let shortcuts = "shortcuts"
        static let recentClaudeCodeFolders = "recentClaudeCodeFolders"
        static let showsFrontAccountInMenuBar = "showsFrontAccountInMenuBar"
        static let tabModeEnabled = "tabModeEnabled"
        static let linkRules = "linkRules"
        static let tabContentHeight = "tabContentHeight"
        static let focusModeEnabled = "focusModeEnabled"
        static let reopensLastAccounts = "reopensLastAccounts"
        static let lastOpenAccounts = "lastOpenAccounts"
        static let panelSortsByRecent = "panelSortsByRecent"
        static let lastUsedAccounts = "lastUsedAccounts"
        static let memoryAlertGigabytes = "memoryAlertGigabytes"
        /// Set once the Kurulum page has been shown, so the first launch
        /// opens it at most once.
        static let setupShown = "setupShown"
        static let onboardingCompleted = "onboardingCompleted"
        /// Set on a new install until the Başlarken tour is closed, so a
        /// tour cut short by a crash, a quit or a translocated first launch
        /// comes back on the next launch.
        static let onboardingPending = "onboardingPending"
        static let doneNoticesEnabled = "doneNoticesEnabled"
        static let accountFrameEnabled = "accountFrameEnabled"
        static let clipboardGuardEnabled = "clipboardGuardEnabled"
        static let doneNoticeKinds = "doneNoticeKinds"
        static let doneNoticesWhileTerminalInFront = "doneNoticesWhileTerminalInFront"
    }

    /// Whether this launch should open the Başlarken tour: a new install
    /// whose tour has not been closed yet.
    static var onboardingDue: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: Key.onboardingPending) && !defaults.bool(forKey: Key.onboardingCompleted)
    }

    static func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Key.onboardingCompleted)
        UserDefaults.standard.removeObject(forKey: Key.onboardingPending)
    }

    /// Accounts as tabs under one strip. Off until the user turns it on,
    /// because it needs the Accessibility permission.
    static var tabModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.tabModeEnabled)
    }

    /// The menu bar icon takes the colour and letter of the account whose
    /// Claude is in front.
    static var showsFrontAccountInMenuBar: Bool {
        UserDefaults.standard.object(forKey: Key.showsFrontAccountInMenuBar) as? Bool ?? true
    }

    /// When an account's Claude comes forward, the other accounts' Claude
    /// windows are hidden (Cmd-H), so only one account is on screen.
    static var focusModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.focusModeEnabled)
    }

    /// A border in the account's colour around the Claude window in front.
    static var accountFrameEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.accountFrameEnabled)
    }

    /// A warning when something copied in one account is about to be
    /// pasted into another.
    static var clipboardGuardEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.clipboardGuardEnabled)
    }

    /// Lanes reopens the accounts that were open when it last ran, for
    /// example after a restart.
    static var reopensLastAccounts: Bool {
        UserDefaults.standard.bool(forKey: Key.reopensLastAccounts)
    }

    static var showsDockIconWithWindow: Bool {
        UserDefaults.standard.object(forKey: Key.showsDockIconWithWindow) as? Bool ?? true
    }

    static var showsRunningCountInMenuBar: Bool {
        UserDefaults.standard.object(forKey: Key.showsRunningCountInMenuBar) as? Bool ?? true
    }

    /// Debug builds show the Faz 0 checks; builds for testers hide them until
    /// the setting is turned on.
    static let developerPagesDefault: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Off until Faz 0 shows that links can be delivered to the right window.
    static var linkRoutingEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.linkRoutingEnabled)
    }
}
