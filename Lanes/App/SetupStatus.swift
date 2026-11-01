import AppKit
import Observation
import UserNotifications

/// What Kurulum checks, shared by the page and the sidebar badge. Lanes
/// refreshes it when it comes forward and while the page is open; nothing
/// here installs or asks for anything on its own.
@MainActor
@Observable
final class SetupStatus {
    /// The `claude` command, once looked for. Nil when it is missing.
    private(set) var claudeCommand: String?
    private(set) var claudeCommandVersion: String?
    private(set) var hasLookedForClaudeCommand = false
    /// Nil until the first check finished.
    private(set) var automation: AppleEvents.Permission?
    private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    private(set) var notifications: UNAuthorizationStatus?

    let installer = ClaudeCodeInstaller()

    /// The refresh in flight, so the window's first-launch check and an
    /// activation at the same moment share one login-shell lookup.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Everything on the page.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task {
            await refreshPermissions()
            await refreshClaudeCommand()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// The cheap checks, which the open page repeats every few seconds so a
    /// switch turned on in System Settings shows up without a click.
    func refreshPermissions() async {
        accessibilityGranted = AccessibilityPermission.isGranted
        automation = await AppleEvents.reopenPermission(bundleIdentifier: ClaudeInstallation.bundleIdentifier)
        notifications = await Notifier.authorizationStatus()
    }

    /// Looks for `claude` again and reads its version when the path changed.
    func refreshClaudeCommand() async {
        let found = await ClaudeCommandLocator.find()
        if let found {
            if found != claudeCommand || claudeCommandVersion == nil {
                claudeCommandVersion = await ClaudeCommandLocator.version(at: found)
            }
        } else {
            claudeCommandVersion = nil
        }
        claudeCommand = found
        hasLookedForClaudeCommand = true
    }

    /// Shows macOS's Automation prompt for Claude. Only from the button.
    func requestAutomation() async {
        automation = await AppleEvents.requestPermission(bundleIdentifier: ClaudeInstallation.bundleIdentifier)
    }

    func requestNotifications() async {
        _ = await Notifier.requestPermission()
        notifications = await Notifier.authorizationStatus()
    }

    /// Runs the official installer, only from the "Kur" button.
    func installClaudeCode() async {
        await installer.install { [self] in
            await refreshClaudeCommand()
            return claudeCommand != nil
        }
    }

    /// What the sidebar badge counts: Claude, Claude Code, Automation and
    /// Accessibility. Automation counts once macOS says it is not granted,
    /// including "not asked yet"; with no Claude open it cannot be read, and
    /// an unread state is not counted as missing.
    func unfinishedCount(claudeInstalled: Bool) -> Int {
        var count = 0
        if !claudeInstalled { count += 1 }
        if hasLookedForClaudeCommand, claudeCommand == nil { count += 1 }
        switch automation {
        case .denied?, .notAskedYet?: count += 1
        case .granted?, .claudeNotRunning?, .unknown?, nil: break
        }
        if !accessibilityGranted { count += 1 }
        return count
    }
}

extension AppModel {
    /// The number on Kurulum's sidebar row.
    var unfinishedSetupCount: Int {
        setup.unfinishedCount(claudeInstalled: claude != nil)
    }
}
