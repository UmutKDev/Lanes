import AppKit
import LanesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let router: WindowRouter
    private var statusItemController: StatusItemController?
    private var tabStripController: TabStripController?

    override init() {
        let model = AppModel()
        self.model = model
        self.router = WindowRouter(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CodeSignature.readInBackground()
        model.start()
        IntentBridge.model = model
        let statusItemController = StatusItemController(model: model, router: router)
        self.statusItemController = statusItemController
        router.statusItemController = statusItemController
        // A copy running from the DMG or a translocated folder opens its
        // window so the warning on Overview is seen. Otherwise Lanes would
        // start in the menu bar alone and look like it never opened.
        if model.isFirstLaunch || Updater.takeRelaunchedAfterUpdate() || model.isTranslocated {
            router.showMainWindow(.overview)
        }
        observeShortcuts()
        tabStripController = TabStripController(model: model, router: router)
        model.openStartupScenes()
        model.reopenLastAccountsIfWanted()
        Task { await model.webAccounts.restore(from: model.library.profiles) }
    }

    /// Registers the shortcuts again whenever they, the accounts or the
    /// scenes change.
    private func observeShortcuts() {
        let items = withObservationTracking {
            shortcutActions()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeShortcuts()
            }
        }
        // Outside the tracking: registering updates what Settings shows.
        HotKeyCenter.shared.register(items)
    }

    private func shortcutActions() -> [(KeyShortcut, @MainActor () -> Void)] {
        let model = model
        let router = router
        let items: [(KeyShortcut, @MainActor () -> Void)] = model.shortcuts.all.compactMap { target, shortcut in
            switch target {
            case .panel:
                return (shortcut, { router.togglePanel() })
            case .nextAccount:
                return (shortcut, { model.cycleOpenAccounts(forward: true) })
            case .previousAccount:
                return (shortcut, { model.cycleOpenAccounts(forward: false) })
            case let .profile(id):
                guard model.profile(withID: id) != nil else { return nil }
                return (shortcut, {
                    if let profile = model.profile(withID: id) { model.open(profile) }
                })
            case let .scene(id):
                guard model.library.scene(withID: id) != nil else { return nil }
                return (shortcut, {
                    if let scene = model.library.scene(withID: id) { model.open(scene) }
                })
            }
        }
        return items
    }

    /// Clicking Lanes in Finder or Launchpad while it runs opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        router.showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Spotlight result for an account.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard let id = SpotlightIndex.profileID(from: userActivity), let profile = model.profile(withID: id) else { return false }
        model.open(profile)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme?.lowercased() == LanesCommand.scheme {
                perform(LanesCommand(url: url))
            } else {
                model.receive(url)
            }
        }
    }

    /// Runs a `lanes://` address. Unknown ones only open the window, so a
    /// typo is visible instead of silently ignored.
    private func perform(_ command: LanesCommand?) {
        switch command {
        case let .openAccount(query)?:
            if let profile = model.library.profile(matching: query) {
                model.open(profile)
            } else {
                model.notice = AppModel.Notice(kind: .warning, message: String(localized: "\"\(query)\" adında bir hesap yok."))
                router.showMainWindow(.integrations)
            }
        case let .openScene(query)?:
            if let scene = model.library.scene(matching: query) {
                model.open(scene)
            } else {
                model.notice = AppModel.Notice(kind: .warning, message: String(localized: "\"\(query)\" adında bir sahne yok."))
                router.showMainWindow(.scenes)
            }
        case let .show(page)?:
            router.showMainWindow(page.flatMap(Destination.init(pageName:)))
        case .panel?:
            router.togglePanel()
        case nil:
            router.showMainWindow(.integrations)
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for profile in model.library.profiles {
            let title = model.isRunning(profile)
                ? String(localized: "\(profile.name) (açık)")
                : profile.name
            let item = NSMenuItem(title: title, action: #selector(openProfileFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.rawValue
            menu.addItem(item)
        }
        if !model.library.scenes.isEmpty {
            menu.addItem(.separator())
            for scene in model.library.scenes {
                let item = NSMenuItem(title: String(localized: "Sahne: \(scene.name)"), action: #selector(openSceneFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = scene.id.rawValue
                menu.addItem(item)
            }
        }
        if model.quittableOpenCount > 0 {
            menu.addItem(.separator())
            let quitAll = NSMenuItem(title: String(localized: "Lanes Hesaplarının Tümünü Kapat"), action: #selector(quitAllFromMenu(_:)), keyEquivalent: "")
            quitAll.target = self
            menu.addItem(quitAll)
        }
        menu.addItem(.separator())
        let add = NSMenuItem(title: String(localized: "Hesap Ekle…"), action: #selector(addProfileFromMenu(_:)), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        return menu
    }

    @objc private func openProfileFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let profile = model.profile(withID: ProfileID(rawValue: raw)) else { return }
        model.open(profile)
    }

    @objc private func openSceneFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scene = model.library.scene(withID: SceneID(rawValue: raw)) else { return }
        model.open(scene)
    }

    @objc private func quitAllFromMenu(_ sender: NSMenuItem) {
        model.quitAllLanesAccounts()
    }

    @objc private func addProfileFromMenu(_ sender: NSMenuItem) {
        router.showAddProfile()
    }
}
