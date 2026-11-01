import AppKit
import LanesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let router: WindowRouter
    private var statusItemController: StatusItemController?
    private var tabStripController: TabStripController?
    private var isWaitingToTerminate = false

    override init() {
        // LanesCore's own text (durations, the diagnostics report, the
        // `lanes` script) follows the language the app runs in. Set before
        // AppModel reads anything from LanesCore.
        CoreLanguage.current = CoreLanguage.from(localization: Bundle.main.preferredLocalizations.first)
        let model = AppModel()
        self.model = model
        self.router = WindowRouter(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CodeSignature.readInBackground()
        Notifier.setUp()
        model.start()
        IntentBridge.model = model
        LanesFocusFilter.restore(into: model)
        let statusItemController = StatusItemController(model: model, router: router)
        self.statusItemController = statusItemController
        router.statusItemController = statusItemController
        // A copy running from the DMG or a translocated folder opens its
        // window so the warning on Overview is seen. Otherwise Lanes would
        // start in the menu bar alone and look like it never opened.
        let relaunched = Updater.takeRelaunchedAfterUpdate()
        // A new install starts with the Başlarken tour; its last step
        // opens the main window. Existing users updating never see it. The
        // mark stays until the tour is closed, so a translocated first
        // launch or a crash mid-tour shows it on the next launch.
        if model.isFirstLaunch {
            UserDefaults.standard.set(true, forKey: Preferences.Key.onboardingPending)
        }
        if Preferences.onboardingDue, !model.isTranslocated, !relaunched {
            router.showOnboarding()
        } else if model.isFirstLaunch || relaunched || model.isTranslocated {
            router.showMainWindow(.overview)
        }
        observeShortcuts()
        tabStripController = TabStripController(model: model, router: router)
        model.openStartupScenes()
        model.reopenLastAccountsIfWanted()
        Task { [model] in
            if await LegacyWebData.removeOnce() > 0 {
                model.notice = AppModel.Notice(kind: .info, message: String(localized: "Hesaplar artık Claude uygulamasında kendi simgeleriyle açılıyor. Bu hesaplara bir kez yeniden giriş yapman gerekir."))
            }
        }
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
            case .palette:
                return (shortcut, { router.togglePalette() })
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
        guard Date() >= TerminalFocus.ignoreReopenUntil else { return false }
        router.showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting with link routing on gives `claude://` back to Claude first,
    /// so links do not relaunch Lanes while it is closed. The next launch
    /// takes the default again.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isLinkRoutingOn, LinkHandlerRegistry.lanesIsHandler else { return .terminateNow }
        isWaitingToTerminate = true
        Task {
            await self.model.giveLinksBackToClaude()
            self.replyToTerminate()
        }
        // Quitting never hangs on the system call.
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self.replyToTerminate()
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flushFrontTime()
    }

    private func replyToTerminate() {
        guard isWaitingToTerminate else { return }
        isWaitingToTerminate = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    /// A Spotlight result for an account.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard let id = SpotlightIndex.profileID(from: userActivity), let profile = model.profile(withID: id) else { return false }
        model.open(profile)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // The app that asked macOS to open the link, for "Akıllı
        // Yönlendirme" source rules. Only its process ID is read.
        let senderPID = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        for url in urls {
            if url.scheme?.lowercased() == LanesCommand.scheme {
                perform(LanesCommand(url: url))
            } else {
                model.receive(url, senderPID: senderPID)
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
        for profile in model.library.activeProfiles {
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
        if model.closedActiveProfiles.count > 1 || model.quittableOpenCount > 0 {
            menu.addItem(.separator())
        }
        if model.closedActiveProfiles.count > 1 {
            let openAll = NSMenuItem(title: String(localized: "Kapalı Hesapların Tümünü Aç"), action: #selector(openAllFromMenu(_:)), keyEquivalent: "")
            openAll.target = self
            menu.addItem(openAll)
        }
        if model.quittableOpenCount > 0 {
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

    @objc private func openAllFromMenu(_ sender: NSMenuItem) {
        model.openAllClosedAccounts()
    }

    @objc private func quitAllFromMenu(_ sender: NSMenuItem) {
        model.quitAllLanesAccounts()
    }

    @objc private func addProfileFromMenu(_ sender: NSMenuItem) {
        router.showAddProfile()
    }
}
