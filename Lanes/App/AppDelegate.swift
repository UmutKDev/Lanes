import AppKit
import LanesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let router: WindowRouter
    private var statusItemController: StatusItemController?

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
        let statusItemController = StatusItemController(model: model, router: router)
        self.statusItemController = statusItemController
        router.statusItemController = statusItemController
        if model.isFirstLaunch || Updater.takeRelaunchedAfterUpdate() {
            router.showMainWindow(.overview)
        }
    }

    /// Clicking Lanes in Finder or Launchpad while it runs opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        router.showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(model.receive)
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

    @objc private func addProfileFromMenu(_ sender: NSMenuItem) {
        router.showAddProfile()
    }
}
