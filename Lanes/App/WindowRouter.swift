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
        // Before the panel closes: check 9's icon-click run counts only
        // windows opened from a panel that a click on the icon opened.
        let trialRunID = takeArmedIconClickRun()
        statusItemController?.closePanel()
        let controller = mainWindowController ?? MainWindowController(model: model, router: self)
        mainWindowController = controller
        return Task { @MainActor in
            guard let window = controller.window else { return nil }
            let outcome = await WindowActivator.bringForward(window)
            if let trialRunID {
                self.recordIconClickTrial(outcome, runID: trialRunID)
            }
            return outcome
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

    /// Check 9 measured the way a user works: the user clicks the menu bar
    /// icon and the panel's window button, and Lanes records each try. Between
    /// tries it closes the window and hands focus to Finder.
    func startIconClickTrials(count: Int) {
        statusItemController?.setMeasuringIconClicks(true)
        let run = ValidationModel.IconClickRun(target: count)
        model.validation.iconClickRun = run
        Task { await prepareForNextIconClick(runID: run.id) }
    }

    func stopIconClickTrials() {
        model.validation.iconClickRun = nil
        statusItemController?.setMeasuringIconClicks(false)
    }

    /// Closes the window, hands focus to Finder and only then accepts the
    /// next try. Each step stops if the run was stopped or replaced.
    private func prepareForNextIconClick(runID: UUID) async {
        // Long enough to see that the window came forward.
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard model.validation.iconClickRun?.id == runID else { return }
        mainWindow?.close()
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard model.validation.iconClickRun?.id == runID else { return }
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            NSApp.yieldActivation(to: finder)
            _ = finder.activate(options: [])
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard model.validation.iconClickRun?.id == runID else { return }
        // A panel opened before this point is not part of the next try.
        _ = statusItemController?.takePanelLatency()
        model.validation.iconClickRun?.isArmed = true
    }

    /// The run a window opened now counts for, if one is waiting for a try
    /// and the panel was opened by a click on the icon. Taking it disarms the
    /// run, so a second click before the window is up does not count twice.
    private func takeArmedIconClickRun() -> UUID? {
        guard let run = model.validation.iconClickRun, run.isArmed,
              statusItemController?.isPanelVisible == true,
              statusItemController?.hasPanelOpeningFromIconClick == true
        else { return nil }
        model.validation.iconClickRun?.isArmed = false
        return run.id
    }

    private func recordIconClickTrial(_ outcome: WindowActivator.Outcome, runID: UUID) {
        guard var run = model.validation.iconClickRun, run.id == runID else { return }
        let latency = statusItemController?.takePanelLatency()
        run.trials.append(ActivationTrials.Trial(
            becameKey: outcome.becameKey,
            appBecameActive: outcome.appBecameActive && outcome.showsDockIcon == Preferences.showsDockIconWithWindow,
            duration: outcome.duration,
            method: outcome.method.rawValue,
            panelLatency: latency?.seconds,
            panelLatencySource: latency?.source
        ))
        guard run.trials.count >= run.target else {
            model.validation.iconClickRun = run
            Task { await prepareForNextIconClick(runID: runID) }
            return
        }
        model.validation.iconClickRun = nil
        statusItemController?.setMeasuringIconClicks(false)
        let summary = ActivationTrials(trials: run.trials)
        let validation = model.validation
        validation.appendEvidence(["Panel menü çubuğundaki simgeye tıklanarak açıldı."] + summary.evidenceLines, for: .mainWindowActivation)
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
