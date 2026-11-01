import AppKit

/// Lanes normally lives only in the menu bar. While the main window is open it
/// also shows a Dock icon and a menu bar, like a regular app.
@MainActor
enum DockPresence {
    /// Returns true when Lanes just turned into a regular app.
    @discardableResult
    static func windowWillShow(force: Bool = false) -> Bool {
        guard force || Preferences.showsDockIconWithWindow else { return false }
        guard NSApp.activationPolicy() != .regular else { return false }
        NSApp.setActivationPolicy(.regular)
        return true
    }

    /// An app that turns regular while it is already active keeps the
    /// previous app's menus in the menu bar (seen on macOS 26 with build 70:
    /// Lanes in front, Finder's menus shown). Handing activation to the
    /// Dock and taking it back makes the menu bar catch up.
    @MainActor
    static func refreshMenuBar(for window: NSWindow) async {
        guard NSApp.isActive,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        NSApp.yieldActivation(to: dock)
        _ = dock.activate(from: NSRunningApplication.current, options: [])
        try? await Task.sleep(nanoseconds: 60_000_000)
        _ = NSRunningApplication.current.activate(from: dock, options: [])
        window.makeKeyAndOrderFront(nil)
        for _ in 0..<10 where !NSApp.isActive {
            try? await Task.sleep(nanoseconds: 30_000_000)
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Called while `closing` is still on screen. Another Lanes window, such
    /// as Sparkle's update window, keeps Lanes a regular app and comes
    /// forward. Going back to the menu bar alone would deactivate Lanes and
    /// leave that window behind Claude.
    static func windowDidClose(_ closing: NSWindow? = nil) {
        if let other = otherWindows(except: closing).first {
            other.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Back to the menu bar alone once no Lanes window is left, for windows
    /// that don't go through `windowDidClose`, like Sparkle's.
    static func otherWindowDidClose() {
        guard otherWindows(except: nil).isEmpty else { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Visible, titled windows: the main window and Sparkle's. The menu bar
    /// panel and the status item have no title bar.
    private static func otherWindows(except closing: NSWindow?) -> [NSWindow] {
        NSApp.windows.filter { window in
            window !== closing && window.isVisible && window.styleMask.contains(.titled)
        }
    }
}

/// Brings a window forward reliably.
///
/// An app that lives in the menu bar does not always become active when asked,
/// especially right after it switches to a regular app (FB12399363,
/// FB7743313). So it tries the polite way first and escalates only when the
/// window is still not in front. On macOS 27 plain `activate()` never worked
/// on its own in testing and `activate(from:)` always did, so that comes first.
@MainActor
enum WindowActivator {
    /// The step that finally brought the window forward.
    enum Method {
        case activate
        case activateFrom
        case orderFrontRegardless
        case ignoringOtherApps
        case gaveUp
    }

    struct Outcome {
        var method: Method
    }

    /// - Parameter alwaysInDock: Show Lanes in the Dock whatever the
    ///   setting says, as account windows do.
    static func bringForward(_ window: NSWindow, alwaysInDock: Bool = false) async -> Outcome {
        let previous = NSWorkspace.shared.frontmostApplication
        let becameRegular = DockPresence.windowWillShow(force: alwaysInDock)
        if becameRegular {
            // The Dock icon needs a moment before activation sticks.
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        let result = await activate(window, previous: previous)
        if becameRegular, result.method != .gaveUp {
            await DockPresence.refreshMenuBar(for: window)
        }
        return result
    }

    private static func activate(_ window: NSWindow, previous: NSRunningApplication?) async -> Outcome {
        if let previous, previous != NSRunningApplication.current {
            _ = NSRunningApplication.current.activate(from: previous, options: [])
            window.makeKeyAndOrderFront(nil)
            if await waitUntilInFront(window, timeout: 0.15) {
                return Outcome(method: .activateFrom)
            }
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if await waitUntilInFront(window, timeout: 0.15) {
            return Outcome(method: .activate)
        }

        window.orderFrontRegardless()
        window.makeKey()
        if await waitUntilInFront(window, timeout: 0.15) {
            return Outcome(method: .orderFrontRegardless)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if await waitUntilInFront(window, timeout: 0.3) {
            return Outcome(method: .ignoringOtherApps)
        }

        // Right after launch the switch to a regular app can take longer
        // than the steps above wait. Seen in the M2 clean-install test: the
        // window came up in front but Finder stayed the active app, so the
        // menu bar and Cmd-Q went to Finder. One more try once it settles.
        try? await Task.sleep(nanoseconds: 500_000_000)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if await waitUntilInFront(window, timeout: 1.0) {
            return Outcome(method: .ignoringOtherApps)
        }
        Log.app.error("Main window shown but Lanes did not become active")
        return Outcome(method: .gaveUp)
    }

    private static func isInFront(_ window: NSWindow) -> Bool {
        NSApp.isActive && window.isKeyWindow && window.isVisible
    }

    private static func waitUntilInFront(_ window: NSWindow, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isInFront(window) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return isInFront(window)
    }
}
