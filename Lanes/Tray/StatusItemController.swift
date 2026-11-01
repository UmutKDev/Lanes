import AppKit
import LanesCore
import Observation
import SwiftUI

/// The menu bar icon and the panel that drops down from it.
///
/// A left click opens the panel. A right click opens a short menu with the
/// main window, settings and Quit, as menu bar apps usually do.
///
/// On macOS 27 the menu bar shows the icon as pressed only while an expanded
/// interface session is open, and AppKit uses that session for keyboard
/// focus. A left click starts one; Lanes shows the panel for it and ends it
/// when the panel closes.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let router: WindowRouter
    private let statusItem: NSStatusItem
    private var panel: CommandPanel?
    /// Shared with the panel's SwiftUI view: list height cap and openings.
    private let panelState: CommandPanelState
    /// When the panel closed because the user clicked the icon, that same click
    /// must not reopen it.
    private var lastClosed = Date.distantPast
    /// On macOS 27 one click can reach Lanes twice, as a session and as the
    /// button action. The second must not close the panel the first opened.
    private var lastShown = Date.distantPast
    /// A right click starts a session too while its menu is tracking.
    private var isShowingContextMenu = false
    private var defaultsObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    /// The app in front other than Lanes. Matched against the accounts on
    /// each scan, so a Claude that just opened shows once Lanes has seen it.
    private var frontPID: pid_t?
    private var shownIconKey: String?

    init(model: AppModel, router: WindowRouter) {
        self.model = model
        self.router = router
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panelState = CommandPanelState()
        super.init()

        if let button = statusItem.button {
            button.image = StatusItemController.lanesIcon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Lanes"
        }
        statusItem.autosaveName = "LanesStatusItem"
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            statusItem.expandedInterfaceDelegate = self
        }
        #endif
        observeRunningCount()
        observeCountSetting()
        observeFrontApplication()
    }

    /// The app icon's three tilted panes, as a template image for the menu
    /// bar: the back two fainter, the front one solid.
    private static let lanesIcon: NSImage? = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let scale = rect.width / 16
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 8, y: 8)
            context.rotate(by: -14 * .pi / 180)
            context.translateBy(x: -8, y: -8)
            let panes: [(CGFloat, CGFloat, CGFloat)] = [(4.5, 2, 0.55), (3.5, 5.5, 0.8), (2.5, 9, 1)]
            for (x, y, alpha) in panes {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 9, height: 5), xRadius: 1.5, yRadius: 1.5).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lanes"
        return image
    }()

    /// Window indicators v1: the icon takes the colour and letter of the
    /// account whose Claude is in front. Only the frontmost app's process
    /// number is compared with the accounts Lanes already tracks.
    private func observeFrontApplication() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.frontApplicationChanged(to: pid)
            }
        }
        frontApplicationChanged(to: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    private func frontApplicationChanged(to pid: pid_t?) {
        // Lanes itself coming forward keeps the account that was in front.
        if pid == ProcessInfo.processInfo.processIdentifier { return }
        frontPID = pid
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        var profile: Profile?
        if Preferences.showsFrontAccountInMenuBar, let frontPID {
            let id = model.instances.first(where: { $0.pid == frontPID })?.profileID
            profile = id.flatMap(model.profile(withID:))
        }
        let key = profile.map { "\($0.id.rawValue)|\($0.color.rawValue)|\($0.monogram)" } ?? "lanes"
        guard key != shownIconKey else { return }
        shownIconKey = key
        if let profile {
            button.image = StatusItemController.monogramIcon(for: profile)
            button.toolTip = String(localized: "Lanes · önde: \(profile.name)")
        } else {
            button.image = StatusItemController.lanesIcon
            button.toolTip = "Lanes"
        }
    }

    /// A small filled circle in the account's colour with its letter.
    private static func monogramIcon(for profile: Profile) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            profile.color.nsColor.setFill()
            circle.fill()
            let font = NSFont.systemFont(ofSize: 10, weight: .bold)
            let foreground: NSColor = profile.color.isLightSwatch ? NSColor.black.withAlphaComponent(0.78) : NSColor.white
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
            let text = NSAttributedString(string: profile.monogram, attributes: attributes)
            let textSize = text.size()
            // Centre the capital letter, not the whole line box: the
            // baseline sits half a cap height below the middle, and the
            // drawing origin sits one descender below the baseline.
            let baseline = rect.midY - font.capHeight / 2
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: baseline + font.descender))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = profile.name
        return image
    }

    /// Shows how many accounts are open next to the icon, and keeps it current.
    private func observeRunningCount() {
        withObservationTracking {
            updateTitle()
            updateIcon()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeRunningCount()
            }
        }
    }

    /// The count setting lives in UserDefaults, which Observation does not
    /// track, so turning it on or off in Settings would otherwise show only
    /// when the next account opens or closes.
    private func observeCountSetting() {
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateTitle()
                self?.updateIcon()
            }
        }
    }

    private func updateTitle() {
        let count = model.runningCount
        let title = Preferences.showsRunningCountInMenuBar && count > 1 ? " \(count)" : ""
        // Every UserDefaults change lands here, so an unchanged title is left
        // alone.
        if statusItem.button?.title != title {
            statusItem.button?.title = title
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    func togglePanel() {
        if panel?.isVisible == true {
            guard Date().timeIntervalSince(lastShown) > 0.25 else { return }
            closePanel()
        } else if Date().timeIntervalSince(lastClosed) > 0.25 {
            showPanel()
        }
    }

    func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.refreshInstances()
        panelState.maxListHeight = maxListHeight()
        panelState.presentation += 1
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        lastShown = Date()
        statusItem.button?.highlight(true)
    }

    func closePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        lastClosed = Date()
        statusItem.button?.highlight(false)
        cancelExpandedSession()
    }

    /// Ends the macOS 27 session, if one is open. Its end callback calls
    /// `closePanel()` again, which returns early because the panel is hidden.
    private func cancelExpandedSession() {
        guard !isShowingContextMenu else { return }
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            statusItem.expandedInterfaceSession?.cancel()
        }
        #endif
    }

    private func makePanel() -> CommandPanel {
        let root = CommandPanelView(state: panelState, onClose: { [weak self] in self?.closePanel() })
            .environment(model)
            .environment(router)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = CommandPanel(content: hosting)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }
        return panel
    }

    /// Room the panel's pinned parts take (header, search, footer,
    /// dividers), left out of the list's height cap.
    private static let panelChromeHeight: CGFloat = 150

    /// The screen the status item is on.
    private var statusItemScreen: NSScreen? {
        statusItem.button?.window?.screen ?? NSScreen.main
    }

    /// How tall the accounts and scenes list may get before it scrolls.
    private func maxListHeight() -> CGFloat {
        let visibleHeight = statusItemScreen?.visibleFrame.height ?? 800
        return max(visibleHeight * DS.Panel.maxHeightFraction - Self.panelChromeHeight, DS.Monogram.panel * 3)
    }

    /// Puts the panel under the icon. The top edge stays anchored there
    /// afterwards: CommandPanel keeps it when the SwiftUI content changes
    /// height (a notice, a search, a wrapping line).
    private func position(_ panel: CommandPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.anchoredTop = buttonFrame.minY - 6
        panel.minimumBottom = visible.minY + 8
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let width = max(size.width, DS.Panel.width)
        var x = buttonFrame.midX - width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        let y = buttonFrame.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: String(localized: "Lanes'i Aç"), action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let palette = NSMenuItem(title: String(localized: "Komut Paleti…"), action: #selector(openPalette), keyEquivalent: "")
        palette.target = self
        menu.addItem(palette)
        let settings = NSMenuItem(title: String(localized: "Ayarlar…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let tour = NSMenuItem(title: String(localized: "Başlarken Turu…"), action: #selector(openOnboarding), keyEquivalent: "")
        tour.target = self
        menu.addItem(tour)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Lanes'ten Çık"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        if let button = statusItem.button {
            // Cancelling the session while the menu tracks would dismiss the
            // menu, so it is ended only after the menu closes.
            isShowingContextMenu = true
            _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            isShowingContextMenu = false
            cancelExpandedSession()
        }
    }

    @objc private func openMainWindow() {
        router.showMainWindow()
    }

    @objc private func openPalette() {
        router.togglePalette()
    }

    @objc private func openOnboarding() {
        router.showOnboarding()
    }

    @objc private func openSettings() {
        router.showSettings()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    /// The panel follows its SwiftUI content's height. Keep the top edge
    /// under the icon (in case AppKit resized without going through
    /// `setFrame(_:display:)`) and redraw the shadow for the new shape.
    func windowDidResize(_ notification: Notification) {
        guard let panel, (notification.object as? NSWindow) === panel else { return }
        let anchored = panel.anchoredFrame(for: panel.frame)
        if anchored.origin != panel.frame.origin {
            panel.setFrameOrigin(anchored.origin)
        }
        panel.invalidateShadow()
    }
}

#if compiler(>=6.4)
@available(macOS 27, *)
extension StatusItemController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ item: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        guard !isShowingContextMenu else { return }
        if panel?.isVisible == true {
            // Opened a moment ago by this click's button action: keep it open
            // and let the session show the pressed icon. Otherwise the click
            // closes the panel.
            if Date().timeIntervalSince(lastShown) <= 0.25 { return }
            session.cancel()
            closePanel()
            return
        }
        guard Date().timeIntervalSince(lastClosed) > 0.25 else {
            session.cancel()
            return
        }
        showPanel()
    }

    func statusItemDidEndExpandedInterfaceSession(_ item: NSStatusItem, animated: Bool) {
        closePanel()
    }
}
#endif

/// A borderless panel that takes keyboard focus without activating Lanes, so
/// the app the user was in stays in front behind it.
final class CommandPanel: NSPanel {
    init(content: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: DS.Panel.width, height: DS.Panel.width),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        contentViewController = content
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Screen y of the panel's top edge, set each time it is positioned.
    /// The content view controller resizes the window as the SwiftUI height
    /// changes, and AppKit keeps the bottom edge; this keeps the top instead.
    var anchoredTop: CGFloat?
    /// Lowest screen y the bottom edge may reach.
    var minimumBottom: CGFloat?

    /// `rect` moved so its top sits at `anchoredTop`, and never below
    /// `minimumBottom`.
    func anchoredFrame(for rect: NSRect) -> NSRect {
        var frame = rect
        if let anchoredTop {
            frame.origin.y = anchoredTop - frame.height
        }
        if let minimumBottom {
            frame.origin.y = max(frame.origin.y, minimumBottom)
        }
        return frame
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(anchoredFrame(for: frameRect), display: flag)
    }

    /// Escape closes the panel.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
