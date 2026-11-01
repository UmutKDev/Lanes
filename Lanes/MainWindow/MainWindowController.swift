import AppKit
import SwiftUI

/// The main window: an AppKit window so Lanes controls exactly when it comes
/// forward, with SwiftUI inside. The toolbar and title come from SwiftUI.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    init(model: AppModel, router: WindowRouter) {
        let root = MainWindowView()
            .environment(model)
            .environment(router)
            .environment(router.navigation)
        let hosting = NSHostingController(rootView: root)
        hosting.sceneBridgingOptions = [.toolbars, .title]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Lanes"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        // SwiftUI writes the page title and subtitle into the window title,
        // which made the Dock menu list "İkinci Hesap (Açık · Kişisel · …)"
        // above the account's own entry. The Dock menu has its own account
        // and page items, so the window stays out of the window lists.
        window.isExcludedFromWindowsMenu = true
        // The minimum size comes from the SwiftUI root's frame; this only
        // mirrors the same tokens so AppKit never sizes the window below it.
        window.contentMinSize = NSSize(width: DS.Metrics.windowMinWidth, height: DS.Metrics.windowMinHeight)
        // Setting the content view controller sizes the window to the hosting
        // view, so give it the first-launch size before restoring the saved
        // frame. A saved frame wins; only a first launch is centred.
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.setFrameAutosaveName("LanesMainWindow")
        if !window.setFrameUsingName("LanesMainWindow") {
            window.center()
        }
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func windowWillClose(_ notification: Notification) {
        DockPresence.windowDidClose(window)
    }
}

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Whether the window is wide enough for sidebar, page and inspector.
    @State private var fitsThreeColumns = true
    /// True while the sidebar is hidden only to make room for the inspector,
    /// so Lanes brings it back itself and never undoes the user's own choice.
    /// Not cleared from columnVisibility changes: the split view writes its
    /// own visibility values while it animates, which used to clear it and
    /// left the sidebar hidden after the window grew.
    @State private var sidebarHiddenForInspector = false
    /// The first-launch Kurulum check runs once per launch: the hosting view
    /// outlives a closed window, so this survives closing and reopening it.
    @State private var checkedSetupOnce = false

    var body: some View {
        @Bindable var navigation = navigation
        // One value for the detail, the title and the inspector, so a hidden
        // page left in the history never shows one page under another's title.
        let shown = navigation.selection.displayed(showingDeveloperPages: showsDeveloperPages)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: DS.Metrics.sidebarMin,
                    ideal: DS.Metrics.sidebarIdeal,
                    max: DS.Metrics.sidebarMax
                )
        } detail: {
            DetailView(destination: shown)
                .navigationSplitViewColumnWidth(min: DS.Metrics.detailMinWidth, ideal: 640)
                .navigationTitle(title(for: shown))
        }
        .inspector(isPresented: inspectorBinding(allowed: shown.allowsInspector)) {
            InspectorView()
                .inspectorColumnWidth(
                    min: DS.Metrics.inspectorMin,
                    ideal: DS.Metrics.inspectorIdeal,
                    max: DS.Metrics.inspectorMax
                )
        }
        .toolbar {
            toolbarContent(inspectorAllowed: shown.allowsInspector)
        }
        .sheet(isPresented: $navigation.isAddingProfile) {
            AddProfileSheet()
        }
        .frame(minWidth: DS.Metrics.windowMinWidth, minHeight: DS.Metrics.windowMinHeight)
        // Acts only when the fit changes, so a sidebar the user reopens by
        // hand is not hidden again on every pixel of a resize.
        .onGeometryChange(for: Bool.self) { $0.size.width >= threeColumnWidth } action: { fits in
            fitsThreeColumns = fits
            fitColumns(inspectorShown: shown.allowsInspector && navigation.showsInspector)
        }
        .onChange(of: shown.allowsInspector && navigation.showsInspector) { _, isShown in
            fitColumns(inspectorShown: isShown)
        }
        .task {
            await openSetupOnFirstLaunchIfNeeded()
        }
    }

    /// Opens Kurulum once when Claude or Claude Code is missing and the page
    /// has never been shown. Only from the untouched start page: a window
    /// opened on a specific page, or one the user already moved around in,
    /// stays where it is.
    private func openSetupOnFirstLaunchIfNeeded() async {
        guard !checkedSetupOnce, !UserDefaults.standard.bool(forKey: Preferences.Key.setupShown) else { return }
        checkedSetupOnce = true
        // Waits for the first Claude Code lookup, which may ask a login shell.
        await model.setup.refresh()
        guard model.claude == nil || model.setup.claudeCommand == nil else {
            // Nothing is missing now, so a later change (Claude Code removed,
            // say) shows the sidebar badge instead of moving the window.
            UserDefaults.standard.set(true, forKey: Preferences.Key.setupShown)
            return
        }
        guard navigation.selection == .overview, !navigation.canGoBack else { return }
        navigation.navigate(to: .setup)
    }

    /// Below this width the sidebar, a page and the inspector do not fit
    /// side by side: the split view squeezes the sidebar to a sliver and
    /// pushes the inspector past the window edge.
    private var threeColumnWidth: CGFloat {
        DS.Metrics.sidebarIdeal + DS.Metrics.threeColumnDetailWidth + DS.Metrics.inspectorIdeal
    }

    /// Hides the sidebar while the inspector needs its room and brings it
    /// back when the inspector closes or the window grows wide enough.
    private func fitColumns(inspectorShown: Bool) {
        if inspectorShown && !fitsThreeColumns {
            if columnVisibility != .detailOnly {
                withAnimation(DS.Motion.standard) { columnVisibility = .detailOnly }
                sidebarHiddenForInspector = true
            }
        } else if sidebarHiddenForInspector {
            withAnimation(DS.Motion.standard) { columnVisibility = .all }
            sidebarHiddenForInspector = false
        }
    }

    private func title(for destination: Destination) -> String {
        if case let .account(id) = destination, let profile = model.profile(withID: id) {
            return profile.name
        }
        return destination.title
    }

    /// The inspector stays closed on pages with their own list column. The
    /// user's choice is kept for the other pages.
    private func inspectorBinding(allowed: Bool) -> Binding<Bool> {
        Binding(
            get: { allowed && navigation.showsInspector },
            set: { newValue in
                if allowed {
                    navigation.showsInspector = newValue
                }
            }
        )
    }

    /// The shell's own items only: history and the inspector toggle. Each
    /// page adds its actions in its own `.toolbar`, so they come and go with
    /// the page instead of one item changing its label and width.
    @ToolbarContentBuilder
    private func toolbarContent(inspectorAllowed: Bool) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                navigation.goBack()
            } label: {
                Label("Geri", systemImage: "chevron.backward")
            }
            .disabled(!navigation.canGoBack)
            .keyboardShortcut("[", modifiers: .command)

            Button {
                navigation.goForward()
            } label: {
                Label("İleri", systemImage: "chevron.forward")
            }
            .disabled(!navigation.canGoForward)
            .keyboardShortcut("]", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                navigation.showsInspector.toggle()
            } label: {
                Label("Denetçi", systemImage: "sidebar.trailing")
            }
            .help("Denetçiyi göster veya gizle")
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!inspectorAllowed)
        }
    }
}

private struct DetailView: View {
    let destination: Destination

    var body: some View {
        // The overview shows the notice among its own banners. Other pages
        // show it too, so a warning appears where the button was pressed.
        // It floats over the page's bottom edge: anything that changes the
        // page's layout or safe area throws off the window's toolbar insets.
        // Pages keep their last rows clear of it with a bottom margin
        // (DSPage and dsForm reserve DS.Metrics.noticeClearance).
        page(destination)
            .overlay(alignment: .bottom) {
                PageNoticeBar(isHidden: destination == .overview)
            }
    }

    @ViewBuilder
    private func page(_ destination: Destination) -> some View {
        // MainWindowView passes the page actually shown: a hidden page left
        // in the history, or one the setting just hid, arrives as the overview.
        switch destination {
        case .overview:
            OverviewPage()
        case let .account(id):
            AccountPage(profileID: id)
                .id(id)
        case .settings:
            SettingsPage()
        case .privacy:
            PrivacyPage()
        case .scenes:
            ScenesPage()
        case .sessions:
            SessionsPage()
        case .accountMap:
            AccountMapPage()
        case .links:
            LinksPage()
        case .usage:
            UsagePage()
        case .setup:
            SetupPage()
        case .health:
            HealthPage()
        case .integrations:
            IntegrationsPage()
        case .maintenance:
            MaintenancePage()
        case .toolbox:
            ToolboxPage()
        case .validation:
            ValidationPage()
        }
    }
}

/// The app's latest notice, above any page but the overview: one floating
/// glass row that slides up from the bottom edge.
private struct PageNoticeBar: View {
    @Environment(AppModel.self) private var model
    let isHidden: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if !isHidden, let notice = model.notice {
                DSNoticeRow(notice: notice, isFloating: true) {
                    model.notice = nil
                }
                .frame(maxWidth: 560)
                .padding(DS.Space.l)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.notice, value: model.notice?.id)
    }
}
