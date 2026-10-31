import AppKit

/// Lanes normally lives only in the menu bar. While the main window is open it
/// also shows a Dock icon and a menu bar, like a regular app.
@MainActor
enum DockPresence {
    static func windowWillShow() {
        guard Preferences.showsDockIconWithWindow else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
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
/// window is still not in front. Faz 0 check 9 measures which step works: on
/// macOS 27 plain `activate()` never worked on its own and `activate(from:)`
/// always did, so that comes first.
@MainActor
enum WindowActivator {
    enum Method: String, Codable {
        case activate = "activate()"
        case activateFrom = "activate(from:)"
        case orderFrontRegardless = "orderFrontRegardless()"
        case ignoringOtherApps = "activate(ignoringOtherApps:)"
        case gaveUp = "sonuçsuz"
    }

    struct Outcome {
        var method: Method
        var duration: TimeInterval
        var becameKey: Bool
        var appBecameActive: Bool
        var showsDockIcon: Bool
    }

    static func bringForward(_ window: NSWindow) async -> Outcome {
        let start = Date()
        let previous = NSWorkspace.shared.frontmostApplication
        DockPresence.windowWillShow()

        if let previous, previous != NSRunningApplication.current {
            _ = NSRunningApplication.current.activate(from: previous, options: [])
            window.makeKeyAndOrderFront(nil)
            if await waitUntilInFront(window, timeout: 0.15) {
                return outcome(.activateFrom, window, start)
            }
        }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if await waitUntilInFront(window, timeout: 0.15) {
            return outcome(.activate, window, start)
        }

        window.orderFrontRegardless()
        window.makeKey()
        if await waitUntilInFront(window, timeout: 0.15) {
            return outcome(.orderFrontRegardless, window, start)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if await waitUntilInFront(window, timeout: 0.3) {
            return outcome(.ignoringOtherApps, window, start)
        }

        // Right after launch the switch to a regular app can take longer
        // than the steps above wait. Seen in the M2 clean-install test: the
        // window came up in front but Finder stayed the active app, so the
        // menu bar and Cmd-Q went to Finder. One more try once it settles.
        try? await Task.sleep(nanoseconds: 500_000_000)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if await waitUntilInFront(window, timeout: 1.0) {
            return outcome(.ignoringOtherApps, window, start)
        }
        Log.app.error("Main window shown but Lanes did not become active")
        return outcome(.gaveUp, window, start)
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

    private static func outcome(_ method: Method, _ window: NSWindow, _ start: Date) -> Outcome {
        Outcome(
            method: method,
            duration: Date().timeIntervalSince(start),
            becameKey: window.isKeyWindow,
            appBecameActive: NSApp.isActive,
            showsDockIcon: NSApp.activationPolicy() == .regular
        )
    }
}
