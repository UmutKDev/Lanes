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
    /// True only during check 9's icon-click run. Off, the measuring code
    /// below does nothing and no event monitor is installed.
    private var isMeasuringIconClicks = false
    private var mouseDownMonitors: [Any] = []
    /// Recent presses on the icon, on the system uptime clock that NSEvent
    /// timestamps use.
    private var iconMouseDowns: [TimeInterval] = []
    /// The panel opening being measured, on the same clock.
    private var panelOpening: PanelOpening?

    private struct PanelOpening {
        /// When Lanes was told about the click and began showing the panel.
        var shownAt: TimeInterval
        /// The left click AppKit handed the callback, when it was one.
        var eventTime: TimeInterval?
        /// When the panel took keyboard focus.
        var keyAt: TimeInterval?
    }

    /// Seconds from the click until the panel took focus, and what the
    /// start was: "mouseDown" (the press on the icon), "event" (the click
    /// event AppKit handed over) or "callback" (the moment Lanes was told,
    /// which leaves out the system's own delay).
    struct PanelLatency {
        var seconds: TimeInterval
        var source: String
    }

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
        if let run = model.validation.iconClickRun {
            // "…" while Lanes gets ready for the next try.
            statusItem.button?.title = run.isArmed ? " \(min(run.trials.count + 1, run.target))/\(run.target)" : " …"
            return
        }
        let count = model.runningCount
        let title = Preferences.showsRunningCountInMenuBar && count > 1 ? " \(count)" : ""
        statusItem.button?.title = title
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel(fromIconClick: true)
        }
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    /// True when the panel was opened by a click on the icon during an
    /// icon-click run and has taken focus.
    var hasPanelOpeningFromIconClick: Bool {
        panelOpening?.keyAt != nil
    }

    func togglePanel(fromIconClick: Bool = false) {
        if panel?.isVisible == true {
            guard Date().timeIntervalSince(lastShown) > 0.25 else { return }
            closePanel()
        } else if Date().timeIntervalSince(lastClosed) > 0.25 {
            showPanel(fromIconClick: fromIconClick)
        }
    }

    func showPanel(fromIconClick: Bool = false) {
        notePanelOpening(fromIconClick: fromIconClick)
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
        if model.validation.iconClickRun != nil {
            let stop = NSMenuItem(title: String(localized: "Ölçümü Durdur"), action: #selector(stopIconClickTrials), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
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

    @objc private func stopIconClickTrials() {
        router.stopIconClickTrials()
    }

    // MARK: Check 9 icon-click measuring

    /// Starts or stops watching presses on the icon. The monitors only
    /// observe: the local one passes every event on unchanged.
    func setMeasuringIconClicks(_ on: Bool) {
        guard on != isMeasuringIconClicks else { return }
        isMeasuringIconClicks = on
        iconMouseDowns = []
        panelOpening = nil
        if on {
            // Up to macOS 26 a press on Lanes's own icon is an event for
            // Lanes; on macOS 27 it has been seen reaching global monitors.
            // AppKit calls both handlers on the main thread. Only presses
            // inside the icon are kept, and only their time.
            let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.noteMouseDown(event)
                }
                return event
            }
            let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.noteMouseDown(event)
                }
            }
            if let local {
                mouseDownMonitors.append(local)
            }
            if let global {
                mouseDownMonitors.append(global)
            }
        } else {
            for monitor in mouseDownMonitors {
                NSEvent.removeMonitor(monitor)
            }
            mouseDownMonitors = []
        }
    }

    private func noteMouseDown(_ event: NSEvent) {
        guard event.timestamp > 0, let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // An event for another app has no window; its location is already
        // in screen coordinates.
        let point: NSPoint
        if let window = event.window {
            point = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            point = event.locationInWindow
        }
        guard buttonRect.insetBy(dx: -2, dy: -2).contains(point) else { return }
        iconMouseDowns.append(event.timestamp)
        if iconMouseDowns.count > 4 {
            iconMouseDowns.removeFirst()
        }
    }

    private func notePanelOpening(fromIconClick: Bool) {
        guard isMeasuringIconClicks, fromIconClick else {
            panelOpening = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        panelOpening = PanelOpening(shownAt: now, eventTime: freshClickEventTime(now: now))
    }

    /// The left click AppKit is handling, if it is one and is recent. On
    /// macOS 27 `NSApp.currentEvent` in status item callbacks is often an
    /// unrelated event (mouse moved, entered or exited), so anything else is
    /// ignored. Events made by other apps can carry a zero timestamp.
    private func freshClickEventTime(now: TimeInterval) -> TimeInterval? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            let age = now - event.timestamp
            return event.timestamp > 0 && age >= 0 && age < 1 ? event.timestamp : nil
        default:
            return nil
        }
    }

    /// The last icon-to-panel time, once: a second call returns nil. Read it
    /// after the main window opened, so a press that a global monitor
    /// delivered late is already counted.
    func takePanelLatency() -> PanelLatency? {
        defer { panelOpening = nil }
        guard let opening = panelOpening, let keyAt = opening.keyAt else { return nil }
        let start: TimeInterval
        let source: String
        if let press = iconMouseDowns.last(where: { $0 <= opening.shownAt && opening.shownAt - $0 < 1 }) {
            start = press
            source = "mouseDown"
        } else if let eventTime = opening.eventTime {
            start = eventTime
            source = "event"
        } else {
            start = opening.shownAt
            source = "callback"
        }
        let seconds = keyAt - start
        guard seconds >= 0 else { return nil }
        return PanelLatency(seconds: seconds, source: source)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, panelOpening != nil, panelOpening?.keyAt == nil else { return }
        panelOpening?.keyAt = ProcessInfo.processInfo.systemUptime
    }

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
        showPanel(fromIconClick: true)
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
