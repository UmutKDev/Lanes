import AppKit
import LanesCore
import Observation
import SwiftUI

/// Single-window mode: one Lanes window with the accounts listed on the
/// left. The active account's Claude window covers the rest of it, so the
/// two read as one window, and they move and resize together. The other
/// accounts' Claudes are hidden but keep running, so switching is instant.
///
/// macOS lets no app put another app's window inside its own, and Claude
/// offers no way to draw into someone else's window. So the right side of
/// the Lanes window is see-through, and Claude's own window sits exactly
/// over it. Moving and resizing Claude's window needs the Accessibility
/// permission; its contents and title are never read.
@MainActor
@Observable
final class SingleWindowController: NSObject, NSWindowDelegate {
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let router: WindowRouter
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var windowObserver: AccessibilityWindowObserver?
    @ObservationIgnored private var observedPID: pid_t?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var timer: Timer?
    /// Set while Lanes moves a window itself, so the move it causes on the
    /// other side is not taken for the user's.
    @ObservationIgnored private var isApplying = false
    /// Set while Lanes hides the accounts because its window closed or went
    /// to the Dock, so that hiding does not count as the user's.
    @ObservationIgnored private var isClosing = false
    /// Accounts whose windows Lanes minimized because macOS would not hide
    /// them (clones kept out of the Dock can't be hidden like other apps).
    @ObservationIgnored private var minimizedPIDs: Set<pid_t> = []

    private(set) var activeProfileID: ProfileID?
    /// True while an account is opening from the list.
    private(set) var openingProfileID: ProfileID?
    /// True while the active account's Claude window sits over the right
    /// side. Otherwise that side shows a placeholder, not the desktop.
    private(set) var isStageCovered = false

    static let sidebarWidth: CGFloat = 232
    private static let cornerRadius: CGFloat = 16

    init(model: AppModel, router: WindowRouter) {
        self.model = model
        self.router = router
        super.init()
        let defaults = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // Posted synchronously, even from inside AppKit while the window
            // is being made (text measuring registers defaults), which ran
            // turnOn() twice and crashed. Apply the setting a turn later.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applySetting() }
            }
        }
        observers.append((NotificationCenter.default, defaults))
        let workspace = NSWorkspace.shared.notificationCenter
        let activation = workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.frontApplicationChanged(to: pid) }
        }
        observers.append((workspace, activation))
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshStage() }
            }
            observers.append((workspace, token))
        }
        applySetting()
    }

    var isOn: Bool {
        Preferences.tabModeEnabled && Preferences.tabLayout == .singleWindow
    }

    /// Opens or closes the mode to match the setting.
    private func applySetting() {
        if isOn, window == nil {
            turnOn()
        } else if !isOn, window != nil {
            turnOff()
        }
    }

    // MARK: The window

    private func turnOn() {
        let window = makeWindow()
        self.window = window
        Log.app.info("Single-window mode on")
        startTimer()
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let instance = model.instances.first(where: { $0.pid == front && $0.profileID != nil }) {
            activeProfileID = instance.profileID
        } else {
            activeProfileID = model.library.activeProfiles.first(where: { model.isRunning($0) })?.id
        }
        // Showing the window also puts the active account's Claude in it.
        showWindow()
    }

    private func turnOff() {
        stopTimer()
        windowObserver?.stop()
        windowObserver = nil
        observedPID = nil
        activeProfileID = nil
        isStageCovered = false
        let closing = window
        window = nil
        closing?.delegate = nil
        closing?.orderOut(nil)
        DockPresence.windowDidClose(closing)
        // The mode hid the other accounts; without its window there would be
        // no way back to them, so they all come back.
        for instance in model.instances where instance.profileID != nil {
            bringBack(pid: instance.pid)
        }
        Log.app.info("Single-window mode off")
    }

    /// Brings the Lanes window forward, with a Dock icon, as the one place
    /// the accounts live.
    func showWindow() {
        guard isOn else { return }
        let window = self.window ?? makeWindow()
        self.window = window
        startTimer()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        Task {
            _ = await WindowActivator.bringForward(window, alwaysInDock: true)
            if let id = activeProfileID, let profile = model.profile(withID: id) {
                select(profile)
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Lanes"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // The right side is see-through, so Claude's window shows there
        // even while Lanes is in front, and clicks there reach Claude.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Claude's window can't follow Lanes into a full-screen Space.
        window.collectionBehavior = [.managed, .fullScreenNone]
        window.minSize = NSSize(
            width: Self.sidebarWidth + SingleWindowGeometry.minimumStageWidth,
            height: SingleWindowGeometry.minimumStageHeight
        )
        let hostingView = NSHostingView(rootView: SingleWindowView(controller: self)
            .environment(model)
            .environment(router))
        // The window's size is Lanes's own (and Claude's); SwiftUI must not
        // drive it, or AppKit loops on constraints and throws.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.delegate = self
        if !window.setFrameUsingName("LanesSingleWindow") {
            window.setFrame(defaultFrame(), display: false)
        }
        window.setFrameAutosaveName("LanesSingleWindow")
        return window
    }

    private func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(visible.width - 80, 1440)
        let height = min(visible.height - 60, 960)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    private var mainScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        snapActiveWindow()
    }

    func windowDidResize(_ notification: Notification) {
        snapActiveWindow()
    }

    /// Closing the window puts every account away with it. They keep
    /// running and come back with the window.
    func windowWillClose(_ notification: Notification) {
        stopTimer()
        hideAccounts(except: nil)
        DockPresence.windowDidClose(window)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        stopTimer()
        hideAccounts(except: nil)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        startTimer()
        if let id = activeProfileID, let profile = model.profile(withID: id) {
            select(profile)
        }
    }

    // MARK: Switching

    func select(_ profile: Profile) {
        activeProfileID = profile.id
        Task { await show(profile) }
    }

    private func show(_ profile: Profile) async {
        let runningPID = model.instance(for: profile)?.pid
        if let runningPID {
            // Shown in place first, so bringing it forward later does not
            // switch to the Space where it was left.
            bringBack(pid: runningPID)
            hideAccounts(except: profile)
            try? await Task.sleep(nanoseconds: 120_000_000)
            await bringToCurrentSpace(pid: runningPID)
            snapActiveWindow()
        } else {
            openingProfileID = profile.id
        }
        await model.openAndWait(profile)
        // A Claude that just started needs a moment for its window.
        var found = false
        for _ in 0..<(runningPID == nil ? 40 : 3) {
            if let pid = model.instance(for: profile)?.pid, AccessibilityWindow.main(of: pid) != nil {
                found = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            model.refreshInstances()
        }
        openingProfileID = nil
        guard activeProfileID == profile.id else { return }
        if !found {
            Log.instances.error("Single-window mode: no window found for the account")
        }
        hideAccounts(except: profile)
        snapActiveWindow()
        keepWindowUnderClaude()
        refreshStage()
    }

    /// Hides, never quits, the accounts' Claudes. `nil` hides them all.
    private func hideAccounts(except profile: Profile?) {
        for instance in model.instances where instance.profileID != nil && instance.profileID != profile?.id {
            putAway(pid: instance.pid)
        }
    }

    /// Hides an account's Claude. A clone kept out of the Dock runs as an
    /// accessory app, which macOS does not hide on request, so its windows
    /// go to the Dock instead.
    private func putAway(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.activationPolicy == .regular, app.hide() { return }
        if AccessibilityWindow.setHidden(true, pid: pid), app.isHidden { return }
        guard AccessibilityPermission.isGranted else { return }
        var minimized = false
        for window in AccessibilityWindow.all(of: pid) where !window.isMinimized && !window.isFullScreen {
            minimized = window.setMinimized(true) || minimized
        }
        if minimized {
            minimizedPIDs.insert(pid)
        }
    }

    /// Undoes `putAway`. Synchronous where it can be, so it also works
    /// while Lanes quits.
    private func bringBack(pid: pid_t) {
        if !AccessibilityWindow.setHidden(false, pid: pid) {
            NSRunningApplication(processIdentifier: pid)?.unhide()
        }
        guard minimizedPIDs.remove(pid) != nil else { return }
        for window in AccessibilityWindow.all(of: pid) where window.isMinimized {
            window.setMinimized(false)
        }
    }

    /// A Claude window left on another desktop would pull the user there.
    /// A window that comes back from the Dock opens on the current desktop,
    /// so such a window is minimized and brought straight back.
    private func bringToCurrentSpace(pid: pid_t) async {
        guard AccessibilityPermission.isGranted,
              !ClaudeWindowList.hasWindowOnScreen(pid: pid),
              let window = AccessibilityWindow.main(of: pid),
              !window.isFullScreen else { return }
        if !window.isMinimized {
            window.setMinimized(true)
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        window.setMinimized(false)
        try? await Task.sleep(nanoseconds: 350_000_000)
        Log.app.info("Single-window mode: brought an account's window to this desktop: \(ClaudeWindowList.hasWindowOnScreen(pid: pid) ? "yes" : "no", privacy: .public)")
    }

    // MARK: Keeping the two windows together

    private var activePID: pid_t? {
        guard let id = activeProfileID, let profile = model.profile(withID: id) else { return nil }
        return model.instance(for: profile)?.pid
    }

    /// Puts the active account's Claude window over the right side of the
    /// Lanes window and watches it.
    private func snapActiveWindow() {
        guard !isApplying, let window, window.isVisible, !window.isMiniaturized,
              AccessibilityPermission.isGranted,
              let pid = activePID,
              let claude = AccessibilityWindow.main(of: pid),
              !claude.isFullScreen, !claude.isMinimized else { return }
        let target = SingleWindowGeometry.claudeFrame(window: window.frame, sidebarWidth: Self.sidebarWidth, mainScreenHeight: mainScreenHeight)
        observe(claude, pid: pid)
        if let current = claude.frame, TabGeometry.isClose(current, target) { return }
        isApplying = true
        claude.setFrame(target)
        // The move reaches the observer a moment later.
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            isApplying = false
        }
    }

    private func observe(_ claude: AccessibilityWindow, pid: pid_t) {
        guard observedPID != pid || windowObserver == nil else { return }
        windowObserver?.stop()
        observedPID = pid
        windowObserver = AccessibilityWindowObserver(pid: pid, window: claude) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.claudeWindowChanged() }
            }
        }
    }

    /// The user moved or resized Claude's window: the Lanes window follows.
    private func claudeWindowChanged() {
        guard !isApplying, let window, let pid = observedPID, pid == activePID,
              let claude = AccessibilityWindow.main(of: pid), let frame = claude.frame,
              !claude.isFullScreen, !claude.isMinimized else { return }
        let target = SingleWindowGeometry.windowFrame(around: frame, sidebarWidth: Self.sidebarWidth, mainScreenHeight: mainScreenHeight)
        guard !TabGeometry.isClose(target, window.frame) else { return }
        isApplying = true
        window.setFrame(target, display: true)
        isApplying = false
    }

    /// Keeps the Lanes window right behind Claude's, so the list stays in
    /// sight next to it. Never activates anything.
    private func keepWindowUnderClaude() {
        guard let window, window.isVisible, !window.isMiniaturized,
              let pid = activePID, let number = ClaudeWindowList.frontWindowNumber(of: pid) else { return }
        window.order(.below, relativeTo: number)
    }

    /// Another way of switching (the menu bar panel, a shortcut, a click)
    /// brought an account forward: it becomes the active one here too.
    private func frontApplicationChanged(to pid: pid_t?) {
        guard isOn, let pid, pid != ProcessInfo.processInfo.processIdentifier,
              let instance = model.instances.first(where: { $0.pid == pid }),
              let id = instance.profileID, let profile = model.profile(withID: id) else { return }
        guard let window else { return }
        // Set first: bringing the window back from the Dock selects the
        // active account, which must already be this one.
        let switched = activeProfileID != id
        activeProfileID = id
        if minimizedPIDs.contains(pid) {
            bringBack(pid: pid)
        }
        if !window.isVisible || window.isMiniaturized {
            // The window was closed; the account brings it back, behind
            // Claude and without taking the focus.
            if window.isMiniaturized { window.deminiaturize(nil) }
            DockPresence.windowWillShow(force: true)
            window.orderFront(nil)
            startTimer()
        }
        if switched {
            hideAccounts(except: profile)
        }
        snapActiveWindow()
        keepWindowUnderClaude()
        refreshStage()
    }

    // MARK: The right side

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Once a second: puts back a Claude window that drifted (a missed
    /// move, a new window), and updates what the right side shows.
    private func tick() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        snapActiveWindow()
        refreshStage()
    }

    /// Whether Claude's window really covers the right side. When it
    /// doesn't (the account is closed, hidden or minimized), a placeholder
    /// shows there instead of the desktop.
    private func refreshStage() {
        guard let pid = activePID,
              let app = NSRunningApplication(processIdentifier: pid), !app.isHidden,
              let claude = AccessibilityWindow.main(of: pid), !claude.isMinimized, !claude.isFullScreen,
              ClaudeWindowList.hasWindowOnScreen(pid: pid) else {
            setStageCovered(false)
            return
        }
        setStageCovered(true)
    }

    private func setStageCovered(_ covered: Bool) {
        guard isStageCovered != covered else { return }
        isStageCovered = covered
        window?.invalidateShadow()
    }

    /// Lanes is quitting: hidden accounts would have no way back, so they
    /// all come back.
    func restoreAccounts() {
        guard window != nil else { return }
        for instance in model.instances where instance.profileID != nil {
            bringBack(pid: instance.pid)
        }
    }
}

/// Claude's windows in macOS's window list: only their owner, layer and
/// number are read, never titles or contents.
enum ClaudeWindowList {
    private static func normalWindows(of pid: pid_t) -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.filter { info in
            (info[kCGWindowLayer as String] as? Int) == 0
                && (info[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid
                && (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
        }
    }

    /// True when the app has a normal window on the current desktop.
    static func hasWindowOnScreen(pid: pid_t) -> Bool {
        !normalWindows(of: pid).isEmpty
    }

    /// The window-server number of the app's frontmost normal window.
    static func frontWindowNumber(of pid: pid_t) -> Int? {
        normalWindows(of: pid).first?[kCGWindowNumber as String] as? Int
    }
}

// MARK: - View

/// The Lanes window: the account list on the left, Claude's window (or a
/// placeholder) on the right.
struct SingleWindowView: View {
    let controller: SingleWindowController

    var body: some View {
        HStack(spacing: 0) {
            SingleWindowSidebar(controller: controller)
                .frame(width: SingleWindowController.sidebarWidth)
            SingleWindowStage(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

private struct SingleWindowSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let controller: SingleWindowController

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 16,
        bottomLeadingRadius: 16,
        bottomTrailingRadius: 0,
        topTrailingRadius: 0,
        style: .continuous
    )

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            // Room for the window's close, minimise and zoom buttons.
            Color.clear.frame(height: 36)
            Text("Hesaplar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s)
            ScrollView {
                VStack(spacing: DS.Space.xxs) {
                    ForEach(Array(model.library.activeProfiles.enumerated()), id: \.element.id) { index, profile in
                        SingleWindowAccountRow(
                            profile: profile,
                            index: index,
                            isActive: controller.activeProfileID == profile.id,
                            isOpening: controller.openingProfileID == profile.id
                        ) {
                            controller.select(profile)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.xs) {
                DSIconButton("Hesap Ekle", systemImage: "plus") {
                    router.showAddProfile()
                }
                Spacer()
                DSIconButton("Lanes'i Aç", systemImage: "macwindow") {
                    router.showMainWindow()
                }
                DSIconButton("Sekme ayarları", systemImage: "gearshape") {
                    router.showSettings(.tabs)
                }
            }
        }
        .padding(DS.Space.s)
        .padding(.bottom, DS.Space.xs)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: Self.shape)
    }
}

private struct SingleWindowAccountRow: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let profile: Profile
    let index: Int
    let isActive: Bool
    let isOpening: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let isRunning = model.isRunning(profile)
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                MonogramView(profile: profile, size: DS.Monogram.small, isRunning: isRunning)
                    .opacity(isOpening ? 0.35 : 1)
                    .overlay {
                        if isOpening {
                            ProgressView().controlSize(.mini)
                        }
                    }
                Text(profile.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if index < 9 {
                    Text(verbatim: "⌘\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered || isActive ? 1 : 0)
                }
            }
            .padding(.horizontal, DS.Space.s)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(profile.color.swatch.opacity(0.28)) : AnyShapeStyle(DS.Palette.hoverFill))
                    .opacity(isActive || isHovered ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(NumberShortcut(index: index))
        .onHover { isHovered = $0 }
        .animation(DS.Motion.hover, value: isHovered)
        .animation(DS.Motion.standard, value: isActive)
        .help(isRunning ? Text("\(profile.name) hesabına geç") : Text("\(profile.name) hesabını aç"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu {
            if isRunning {
                Button("Claude'dan Çık") {
                    model.quit(profile)
                }
            }
            Button("Claude Code'u Terminalde Aç") {
                model.openClaudeCode(profile)
            }
            Divider()
            Button("Hesap Sayfası") {
                router.showAccount(profile)
            }
        }
    }
}

/// ⌘1 to ⌘9 for the first nine accounts.
private struct NumberShortcut: ViewModifier {
    let index: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if index < 9, let key = "\(index + 1)".first {
            content.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            content
        }
    }
}

/// See-through while Claude's window covers it; a placeholder otherwise.
private struct SingleWindowStage: View {
    @Environment(AppModel.self) private var model
    let controller: SingleWindowController

    private static let shape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 16,
        topTrailingRadius: 16,
        style: .continuous
    )

    var body: some View {
        if controller.isStageCovered {
            Color.clear
        } else {
            VStack(spacing: DS.Space.m) {
                if controller.openingProfileID != nil {
                    ProgressView()
                    Text("Claude açılıyor…")
                        .foregroundStyle(.secondary)
                } else if !AccessibilityPermission.isGranted {
                    Image(systemName: "hand.raised")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Claude penceresini buraya yerleştirmek için Erişilebilirlik izni gerekiyor.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("İzin İste") {
                        AccessibilityPermission.request()
                    }
                } else {
                    Image(systemName: "rectangle.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Group {
                        if model.library.activeProfiles.isEmpty {
                            Text("Henüz hesap yok. Soldaki + ile ekleyebilirsin.")
                        } else {
                            Text("Soldan bir hesap seç.")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor), in: Self.shape)
        }
    }
}
