import AppKit
import LanesCore

/// Brings the menu bar back when an account hidden from the Dock leaves the
/// screen without one.
///
/// A hidden account runs as an accessory app (`LSUIElement`), and so does
/// Lanes itself. Neither owns a menu bar. On a Space where only they have
/// windows, macOS sometimes stops drawing the menu bar, clock included,
/// until the user clicks at the top of the screen (seen on macOS 27.0.1,
/// 2026-11-02).
///
/// While a hidden account is in front, Lanes checks the window list once a
/// second. The menu bar often goes only a few seconds after a switch from a
/// full-screen app, with no event to tell. When it has been gone from the
/// account's screen for over a second, Lanes asks Finder and then the
/// account to come forward. In a test on Umut's Mac (2026-11-02) this brought
/// the menu bar back within a second, without the Accessibility permission.
@MainActor
final class MenuBarGuard {
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []
    private var watch: Task<Void, Never>?
    private var watchedPID: pid_t?
    /// The window list showed a menu bar at least once, so its layout is
    /// what `MenuBarCheck` expects.
    private var menuBarSeen = false
    private var recentRepairs: [Date] = []

    init(model: AppModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateWatch()
                }
            })
        }
        menuBarSeen = MenuBarCheck.anyMenuBar(in: Self.windows().map(\.window))
        updateWatch()
    }

    /// The front app when it is an account hidden from the Dock.
    private func hiddenAccountInFront() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy != .regular,
              model.instances.contains(where: { $0.pid == front.processIdentifier }) else { return nil }
        return front
    }

    private func updateWatch() {
        guard let front = hiddenAccountInFront() else {
            watch?.cancel()
            watch = nil
            watchedPID = nil
            return
        }
        guard watchedPID != front.processIdentifier || watch == nil else { return }
        watch?.cancel()
        watchedPID = front.processIdentifier
        watch = Task { [weak self] in
            var missingChecks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, let app = self.hiddenAccountInFront() else { return }
                if self.isMenuBarMissing(over: app) {
                    missingChecks += 1
                } else {
                    missingChecks = 0
                }
                if missingChecks >= 2 {
                    missingChecks = 0
                    await self.repair(app)
                }
            }
        }
    }

    private func isMenuBarMissing(over app: NSRunningApplication) -> Bool {
        let windows = Self.windows()
        let listed = windows.map(\.window)
        if MenuBarCheck.anyMenuBar(in: listed) {
            menuBarSeen = true
        }
        guard menuBarSeen,
              let screen = Self.screen(of: app.processIdentifier, in: windows),
              !MenuBarCheck.isShown(on: screen, windows: listed) else { return false }
        // A window over the whole screen is in full screen, where the menu
        // bar is meant to hide.
        let pid = app.processIdentifier
        return !windows.contains { $0.pid == pid && $0.window.layer == 0 && MenuBarCheck.coversScreen($0.window.bounds, screen: screen) }
    }

    private func repair(_ app: NSRunningApplication) async {
        // Never more than three times a minute, in case the menu bar is
        // hidden for a reason Lanes doesn't know.
        let now = Date()
        recentRepairs = recentRepairs.filter { now.timeIntervalSince($0) < 60 }
        guard recentRepairs.count < 3,
              let screen = Self.screen(of: app.processIdentifier, in: Self.windows()) else { return }
        recentRepairs.append(now)
        let repaired = await handMenuBarToFinder(returningTo: app, screen: screen)
        Log.app.notice("Menu bar was missing over a Dock-hidden account; repaired: \(repaired, privacy: .public)")
    }

    /// The steps the test on Umut's Mac used. Finder's activation is only a
    /// request and did not visibly take the front; asking the account to
    /// come forward right after is what made macOS draw the menu bar again.
    private func handMenuBarToFinder(returningTo app: NSRunningApplication, screen: CGRect) async -> Bool {
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            _ = finder.activate()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        _ = app.activate()
        for _ in 0..<16 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                // The account must end up in front again whatever happened.
                _ = app.activate()
                continue
            }
            if MenuBarCheck.isShown(on: screen, windows: Self.windows().map(\.window)) { return true }
        }
        return false
    }

    // MARK: Window list

    private struct ListedWindow {
        var pid: pid_t
        var window: MenuBarCheck.Window
    }

    /// Owner, layer, bounds and alpha need no permission.
    private static func windows() -> [ListedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return ListedWindow(pid: pid, window: MenuBarCheck.Window(layer: layer, bounds: bounds, alpha: alpha))
        }
    }

    /// The screen, in window list coordinates, that holds most of the app's
    /// frontmost ordinary window.
    private static func screen(of pid: pid_t, in windows: [ListedWindow]) -> CGRect? {
        guard let window = windows.first(where: { $0.pid == pid && $0.window.layer == 0 && $0.window.bounds.width > 100 }) else { return nil }
        let bounds = window.window.bounds
        let primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0
        var best: CGRect?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let rect = MenuBarCheck.windowListRect(ofScreen: screen.frame, primaryHeight: primaryHeight)
            let overlap = area(rect.intersection(bounds))
            if overlap > bestArea {
                best = rect
                bestArea = overlap
            }
        }
        return best
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
