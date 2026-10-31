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
    ///
    /// Since macOS 14 activation is only a request, and Lanes is usually not
    /// the active app when the panel asks, so the system may refuse it.
    /// Returns whether the instance is in front shortly afterwards.
    @discardableResult
    static func activate(pid: pid_t) async -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        // Since macOS 14 only the active app can hand activation over. From
        // a global shortcut or the menu bar panel Lanes is in the background,
        // so it first asks to become active itself; the key press that got
        // here is what lets macOS agree.
        if !NSApp.isActive {
            NSApp.activate()
            for _ in 0..<5 where !NSApp.isActive {
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
        for attempt in 0..<3 {
            NSApp.yieldActivation(to: app)
            _ = app.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
            if attempt > 0 || !hasWindowOnScreen(pid: pid) {
                try? await AppleEvents.sendReopen(to: pid)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
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
