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
    /// When the panel closed because the user clicked the icon, that same click
    /// must not reopen it.
    private var lastClosed = Date.distantPast
    /// On macOS 27 one click can reach Lanes twice, as a session and as the
    /// button action. The second must not close the panel the first opened.
    private var lastShown = Date.distantPast
    /// A right click starts a session too while its menu is tracking.
    private var isShowingContextMenu = false

    init(model: AppModel, router: WindowRouter) {
        self.model = model
        self.router = router
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Lanes")
            image?.isTemplate = true
            button.image = image
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
    }

    /// Shows how many accounts are open next to the icon, and keeps it current.
    private func observeRunningCount() {
        withObservationTracking {
            updateTitle()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeRunningCount()
            }
        }
    }

    private func updateTitle() {
        let count = model.runningCount
        let title = Preferences.showsRunningCountInMenuBar && count > 1 ? " \(count)" : ""
        statusItem.button?.title = title
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
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
        let root = CommandPanelView(onClose: { [weak self] in self?.closePanel() })
            .environment(model)
            .environment(router)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = CommandPanel(content: hosting)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }
        return panel
    }

    private func position(_ panel: CommandPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 360, height: 400)
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = buttonFrame.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: String(localized: "Lanes'i Aç"), action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: String(localized: "Ayarlar…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
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

    @objc private func openSettings() {
        router.showSettings()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
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

    /// Escape closes the panel.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
