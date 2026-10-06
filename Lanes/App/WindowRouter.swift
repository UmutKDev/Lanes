import AppKit
import LanesCore
import Observation

/// Opens the main window and the panel, from anywhere: the panel, the Dock,
/// the menu bar and keyboard shortcuts all come through here.
@MainActor
@Observable
final class WindowRouter {
    @ObservationIgnored let model: AppModel
    @ObservationIgnored let navigation = NavigationModel()
    @ObservationIgnored weak var statusItemController: StatusItemController?
    @ObservationIgnored private var mainWindowController: MainWindowController?

    init(model: AppModel) {
        self.model = model
    }

    var mainWindow: NSWindow? {
        mainWindowController?.window
    }

    @discardableResult
    func showMainWindow(_ destination: Destination? = nil) -> Task<WindowActivator.Outcome?, Never> {
        if let destination {
            navigation.navigate(to: destination)
        }
        statusItemController?.closePanel()
        let controller = mainWindowController ?? MainWindowController(model: model, router: self)
        mainWindowController = controller
        return Task { @MainActor in
            guard let window = controller.window else { return nil }
            return await WindowActivator.bringForward(window)
        }
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane {
            navigation.selectSettingsPane(pane)
        }
        showMainWindow(.settings)
    }

    func showAddProfile() {
        showMainWindow()
        navigation.isAddingProfile = true
    }

    func showAccount(_ profile: Profile) {
        showMainWindow(.account(profile.id))
    }

    func togglePanel() {
        statusItemController?.togglePanel()
    }

    /// Faz 0 check 9: closes the main window, hands focus to Finder, opens the
    /// panel and reopens the window from it, the way a user would.
    func runActivationTrials(count: Int) async {
        let validation = model.validation
        validation.isRunningActivationTrials = true
        defer { validation.isRunningActivationTrials = false }

        var trials: [ActivationTrials.Trial] = []
        for _ in 0..<count {
            mainWindow?.close()
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                NSApp.yieldActivation(to: finder)
                _ = finder.activate(options: [])
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            statusItemController?.showPanel()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let outcome = await showMainWindow(.validation).value {
                trials.append(ActivationTrials.Trial(
                    becameKey: outcome.becameKey,
                    appBecameActive: outcome.appBecameActive && outcome.showsDockIcon == Preferences.showsDockIconWithWindow,
                    duration: outcome.duration,
                    method: outcome.method.rawValue
                ))
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        let summary = ActivationTrials(trials: trials)
        validation.appendEvidence(summary.evidenceLines + (trials.isEmpty ? [] : panelSessionNote), for: .mainWindowActivation)
        validation.setOutcome(summary.suggestedOutcome, for: .mainWindowActivation)
    }

    /// On macOS 27 the trials open the panel from code, which starts no menu
    /// bar session, so the report says which path they did not measure.
    private var panelSessionNote: [String] {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            return ["Panel koddan açıldı, macOS 27'nin menü çubuğu oturumu yoktu. Simgeye tıklanınca açılan ve pencere öne gelmeden önce oturumu kapatan yol ölçülmedi."]
        }
        #endif
        return []
    }
}
