import AppKit
import LanesCore
import Observation
import SwiftUI

/// Tab mode: a thin strip with one tab per account. The active account's
/// Claude window sits right under the strip at the same width, the other
/// accounts' Claudes are hidden. They keep running, so switching back is
/// instant and nothing is lost.
///
/// macOS lets no app put another app's window inside its own, so this is
/// the closest it gets: the strip and the window move as one. Moving and
/// resizing Claude's window needs the Accessibility permission.
@MainActor
@Observable
final class TabStripController: NSObject, NSWindowDelegate {
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let router: WindowRouter
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var windowObserver: AccessibilityWindowObserver?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    /// Set while Lanes moves a window itself, so the move it causes on the
    /// other side is not taken for the user's.
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var observedPID: pid_t?

    private(set) var activeProfileID: ProfileID?
    /// True while an account is opening from a tab.
    private(set) var openingProfileID: ProfileID?

    static let stripHeight: CGFloat = 40

    init(model: AppModel, router: WindowRouter) {
        self.model = model
        self.router = router
        super.init()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySetting()
            }
        }
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
        applySetting()
    }

    var isOn: Bool {
        panel != nil
    }

    /// Shows or removes the strip to match the setting.
    private func applySetting() {
        let wanted = Preferences.tabModeEnabled
        if wanted, panel == nil {
            showStrip()
        } else if !wanted, panel != nil {
            removeStrip()
        }
    }

    // MARK: The strip

    private func showStrip() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: Self.stripHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenNone, .managed]
        panel.minSize = NSSize(width: 480, height: Self.stripHeight)
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: Self.stripHeight)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: TabStripView(controller: self)
            .environment(model)
            .environment(router))
        panel.delegate = self
        if !panel.setFrameUsingName("LanesTabStrip") {
            panel.setFrame(defaultStripFrame(), display: false)
        }
        panel.setFrameAutosaveName("LanesTabStrip")
        self.panel = panel
        panel.orderFrontRegardless()
        Log.app.info("Tab mode on")
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let instance = model.instances.first(where: { $0.pid == front && $0.profileID != nil }) {
            activeProfileID = instance.profileID
            snapActiveWindow()
        }
    }

    private func removeStrip() {
        windowObserver?.stop()
        windowObserver = nil
        observedPID = nil
        panel?.orderOut(nil)
        panel = nil
        activeProfileID = nil
        Log.app.info("Tab mode off")
    }

    /// The top of the main screen's usable area, nearly full width.
    private func defaultStripFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(visible.width - 80, 1400)
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.maxY - Self.stripHeight - 20,
            width: width,
            height: Self.stripHeight
        )
    }

    /// How tall the Claude window under the strip is. Kept across launches.
    private var contentHeight: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Preferences.Key.tabContentHeight)
            if stored > 0 { return stored }
            let visible = NSScreen.main?.visibleFrame.height ?? 900
            return visible - Self.stripHeight - 60
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: Preferences.Key.tabContentHeight)
        }
    }

    private var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    func windowDidMove(_ notification: Notification) {
        snapActiveWindow()
    }

    func windowDidResize(_ notification: Notification) {
        snapActiveWindow()
    }

    // MARK: Switching

    func select(_ profile: Profile) {
        activeProfileID = profile.id
        Task { await show(profile) }
    }

    private func show(_ profile: Profile) async {
        let wasRunning = model.isRunning(profile)
        if !wasRunning {
            openingProfileID = profile.id
        }
        await model.openAndWait(profile)
        // An account inside Lanes is a native tab of Lanes's own window;
        // there is no Claude window to move.
        if model.runsInsideLanes(profile) {
            openingProfileID = nil
            hideOtherAccounts(except: profile)
            return
        }
        // A Claude that just started needs a moment for its window.
        var window: AccessibilityWindow?
        for _ in 0..<(wasRunning ? 3 : 40) {
            if let pid = model.instance(for: profile)?.pid, let found = AccessibilityWindow.main(of: pid) {
                window = found
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            model.refreshInstances()
        }
        openingProfileID = nil
        guard activeProfileID == profile.id else { return }
        if window == nil {
            Log.instances.error("Tab mode: no window found for the account")
        }
        hideOtherAccounts(except: profile)
        snapActiveWindow()
    }

    /// Hides, never quits, the other accounts' Claudes.
    private func hideOtherAccounts(except profile: Profile) {
        for instance in model.instances where instance.profileID != nil && instance.profileID != profile.id {
            NSRunningApplication(processIdentifier: instance.pid)?.hide()
        }
    }

    /// Puts the active account's window under the strip and watches it.
    private func snapActiveWindow() {
        guard !isApplying, let panel, AccessibilityPermission.isGranted,
              let id = activeProfileID, let profile = model.profile(withID: id),
              let pid = model.instance(for: profile)?.pid,
              let window = AccessibilityWindow.main(of: pid),
              !window.isFullScreen, !window.isMinimized else { return }
        let target = TabGeometry.claudeFrame(strip: panel.frame, contentHeight: contentHeight, mainScreenHeight: mainScreenHeight)
        if let current = window.frame, TabGeometry.isClose(current, target) {
            observe(window, pid: pid)
            return
        }
        isApplying = true
        window.setFrame(target)
        observe(window, pid: pid)
        // The move reaches the observer a moment later.
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            isApplying = false
        }
    }

    private func observe(_ window: AccessibilityWindow, pid: pid_t) {
        guard observedPID != pid || windowObserver == nil else { return }
        windowObserver?.stop()
        observedPID = pid
        windowObserver = AccessibilityWindowObserver(pid: pid, window: window) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.claudeWindowChanged()
                }
            }
        }
    }

    /// The user moved or resized Claude's window: the strip follows.
    private func claudeWindowChanged() {
        guard !isApplying, let panel, let pid = observedPID,
              let window = AccessibilityWindow.main(of: pid), let frame = window.frame,
              !window.isFullScreen else { return }
        let strip = TabGeometry.stripFrame(above: frame, stripHeight: Self.stripHeight, mainScreenHeight: mainScreenHeight)
        contentHeight = frame.height
        guard !TabGeometry.isClose(strip, panel.frame) else { return }
        isApplying = true
        panel.setFrame(strip, display: true)
        isApplying = false
    }

    /// The strip shows only while an account's Claude or Lanes is in front.
    /// Switching to an account some other way makes its tab active.
    private func frontApplicationChanged(to pid: pid_t?) {
        guard let panel else { return }
        if pid == ProcessInfo.processInfo.processIdentifier { return }
        if let pid, let instance = model.instances.first(where: { $0.pid == pid }), let id = instance.profileID {
            panel.orderFrontRegardless()
            if activeProfileID != id {
                activeProfileID = id
                snapActiveWindow()
            }
        } else if openingProfileID == nil {
            panel.orderOut(nil)
        }
    }
}

/// The strip's content: one tab per account, then add and settings.
struct TabStripView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let controller: TabStripController

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.library.profiles) { profile in
                TabButton(profile: profile, isActive: controller.activeProfileID == profile.id, isOpening: controller.openingProfileID == profile.id) {
                    controller.select(profile)
                }
            }
            Button {
                router.showAddProfile()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Hesap Ekle")
            Spacer(minLength: 8)
            Button {
                router.showSettings(.tabs)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Sekme ayarları")
        }
        .padding(.horizontal, 8)
        .frame(height: TabStripController.stripHeight)
        .background(.bar)
    }
}

private struct TabButton: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let profile: Profile
    let isActive: Bool
    let isOpening: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                MonogramView(profile: profile, size: 18, isRunning: model.isRunning(profile))
                Text(profile.name)
                    .lineLimit(1)
                    .font(.callout.weight(isActive ? .semibold : .regular))
                if isOpening {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: 220)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? profile.color.swatch.opacity(0.22) : (isHovered ? Color.primary.opacity(0.07) : .clear))
            )
            .overlay(alignment: .bottom) {
                if isActive {
                    Capsule()
                        .fill(profile.color.swatch)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(model.isRunning(profile) ? "\(profile.name) sekmesine geç" : "\(profile.name) hesabını aç")
        .contextMenu {
            if model.isRunning(profile) {
                Button("Claude'dan Çık") {
                    model.quit(profile)
                }
            }
            Button("Claude Code'u Terminalde Aç") {
                model.openClaudeCode(profile)
            }
            Divider()
            Button("Hesap Ayarları…") {
                router.showAccount(profile)
            }
        }
    }
}
