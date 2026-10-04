import AppKit
import LanesCore

/// Starts Claude Desktop for a profile and brings running instances forward.
@MainActor
enum InstanceLauncher {
    @discardableResult
    static func launch(_ plan: LaunchPlan) async throws -> NSRunningApplication {
        for directory in plan.directoriesToCreate {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = plan.arguments
        configuration.environment = LaunchEnvironment.merged(
            base: ProcessInfo.processInfo.environment,
            additions: plan.environment
        )
        configuration.createsNewApplicationInstance = plan.createsNewInstance
        configuration.activates = true
        return try await NSWorkspace.shared.openApplication(at: plan.applicationURL, configuration: configuration)
    }

    /// Brings one specific instance forward. When it has no window on screen,
    /// a reopen event asks Claude to show one, like clicking its Dock icon.
    static func activate(pid: pid_t) async {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        NSApp.yieldActivation(to: app)
        _ = app.activate(options: [.activateAllWindows])
        if !hasWindowOnScreen(pid: pid) {
            try? await AppleEvents.sendReopen(to: pid)
        }
    }

    /// Uses the window list, which needs no permission for owner and layer.
    static func hasWindowOnScreen(pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue
            return owner == pid && layer == 0
        }
    }

    static func terminate(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}
