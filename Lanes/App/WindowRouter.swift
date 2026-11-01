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
    @ObservationIgnored private var paletteController: PaletteController?
    @ObservationIgnored private var onboardingController: OnboardingWindowController?

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

    /// The Başlarken tour, in its own window.
    func showOnboarding() {
        statusItemController?.closePanel()
        // A closed tour starts again from its first step.
        let open = onboardingController?.window?.isVisible == true ? onboardingController : nil
        let controller = open ?? OnboardingWindowController(model: model, router: self)
        onboardingController = controller
        guard let window = controller.window else { return }
        Task { @MainActor in
            _ = await WindowActivator.bringForward(window, alwaysInDock: true)
        }
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

    /// Opens or closes the Komut Paleti.
    func togglePalette() {
        statusItemController?.closePanel()
        let controller = paletteController ?? PaletteController(model: model, router: self)
        paletteController = controller
        controller.toggle()
    }
}
