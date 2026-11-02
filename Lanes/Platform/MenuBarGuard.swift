import AppKit
import ApplicationServices
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
/// After a hidden account comes to the front or the Space changes, Lanes
/// checks the window list. When the menu bar is gone from the account's
/// screen, Finder takes the front for a moment and hands it back. Finder is
/// a regular app with a desktop on every Space, so it takes over the menu
/// bar and macOS draws it again. The account keeps the keyboard; only the
/// menu bar shows Finder's menus, as it would after a click at the top.
@MainActor
final class MenuBarGuard {
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
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
                    self?.scheduleCheck()
                }
            })
        }
        menuBarSeen = MenuBarCheck.anyMenuBar(in: Self.windows().map(\.window))
    }

    private func scheduleCheck() {
        pending?.cancel()
        pending = Task { [weak self] in
            // The menu bar settles a moment after the switch.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    private func check() async {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy != .regular,
              model.instances.contains(where: { $0.pid == front.processIdentifier }) else { return }
        let windows = Self.windows()
        if MenuBarCheck.anyMenuBar(in: windows.map(\.window)) {
            menuBarSeen = true
        }
        guard menuBarSeen,
              let screen = Self.screen(of: front.processIdentifier, in: windows),
              !MenuBarCheck.isShown(on: screen, windows: windows.map(\.window)) else { return }
        // A window over the whole screen is in full screen, where the menu
        // bar is meant to hide.
        if windows.contains(where: { $0.pid == front.processIdentifier && $0.window.layer == 0 && MenuBarCheck.coversScreen($0.window.bounds, screen: screen) }) {
            return
        }
        // Never more than three times a minute, in case the menu bar is
        // hidden for a reason Lanes doesn't know.
        let now = Date()
        recentRepairs = recentRepairs.filter { now.timeIntervalSince($0) < 60 }
        guard recentRepairs.count < 3 else { return }
        recentRepairs.append(now)
        let repaired = await handMenuBarToFinder(returningTo: front, screen: screen)
        Log.app.info("Menu bar was missing over a Dock-hidden account; repaired: \(repaired, privacy: .public)")
    }

    private func handMenuBarToFinder(returningTo app: NSRunningApplication, screen: CGRect) async -> Bool {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return false }
        if AccessibilityPermission.isGranted {
            // Works from the background, which plain activation doesn't.
            setFrontmost(finder.processIdentifier)
            try? await Task.sleep(nanoseconds: 120_000_000)
            setFrontmost(app.processIdentifier)
        } else {
            _ = finder.activate()
            try? await Task.sleep(nanoseconds: 120_000_000)
            _ = app.activate()
        }
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                // The account must end up in front again whatever happened.
                if AccessibilityPermission.isGranted {
                    setFrontmost(app.processIdentifier)
                } else {
                    _ = app.activate()
                }
                continue
            }
            if MenuBarCheck.isShown(on: screen, windows: Self.windows().map(\.window)) { return true }
        }
        return false
    }

    private func setFrontmost(_ pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
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
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { MenuBarCheck.windowListRect(ofScreen: $0.frame, primaryHeight: primaryHeight) }
        return screens.max { lhs, rhs in
            area(lhs.intersection(window.window.bounds)) < area(rhs.intersection(window.window.bounds))
        }.flatMap { area($0.intersection(window.window.bounds)) > 0 ? $0 : nil }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
