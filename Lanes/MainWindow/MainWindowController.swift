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
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Lanes"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.center()
        window.setFrameAutosaveName("LanesMainWindow")
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

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            DetailView(destination: navigation.selection)
                .navigationTitle(title)
        }
        .inspector(isPresented: $navigation.showsInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $navigation.isAddingProfile) {
            AddProfileSheet()
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    private var title: String {
        if case let .account(id) = navigation.selection, let profile = model.profile(withID: id) {
            return profile.name
        }
        return navigation.selection.title
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
            primaryAction
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                navigation.showsInspector.toggle()
            } label: {
                Label("Denetçi", systemImage: "sidebar.trailing")
            }
            .help("Denetçiyi göster veya gizle")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    /// One prominent action per page: open the account on its page,
    /// otherwise add an account.
    @ViewBuilder
    private var primaryAction: some View {
        if case let .account(id) = navigation.selection, let profile = model.profile(withID: id) {
            Button {
                model.open(profile)
            } label: {
                Label(model.isRunning(profile) ? "Öne Getir" : "Aç", systemImage: "arrow.up.forward.app")
            }
            .help(model.isRunning(profile) ? "Bu hesabın Claude penceresini öne getir" : "Bu hesapla Claude'u aç")
        } else {
            Button {
                navigation.isAddingProfile = true
            } label: {
                Label("Hesap Ekle", systemImage: "plus")
            }
            .help("Yeni bir Claude hesabı ekle")
        }
    }
}

private struct DetailView: View {
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    let destination: Destination

    var body: some View {
        // A hidden page left in the history, or one the setting just hid,
        // shows the overview instead.
        switch destination.isVisible(showingDeveloperPages: showsDeveloperPages) ? destination : .overview {
        case .overview:
            OverviewPage()
        case let .account(id):
            AccountPage(profileID: id)
                .id(id)
        case .settings:
            SettingsPage()
        case .privacy:
            PrivacyPage()
        case .validation:
            ValidationPage()
        default:
            PlannedPage(destination: destination)
        }
    }
}
