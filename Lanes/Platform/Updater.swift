import AppKit
import Observation
import Sparkle

/// Lanes's own updates, through Sparkle. Runs only in builds that carry a
/// feed URL and a public key, which `make release` builds do; Debug builds
/// leave both empty and never check.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    // Sparkle holds its delegate weakly.
    @ObservationIgnored private let delegate: UpdaterDelegate
    @ObservationIgnored private let userDriverDelegate: UserDriverDelegate

    /// False in builds without a feed or key. The settings say so instead of
    /// offering a check that can't run.
    let isAvailable: Bool

    init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isAvailable = !feed.isEmpty && !key.isEmpty
        let delegate = UpdaterDelegate()
        self.delegate = delegate
        let userDriverDelegate = UserDriverDelegate()
        self.userDriverDelegate = userDriverDelegate
        controller = isAvailable
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: userDriverDelegate)
            : nil
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    /// Sparkle keeps this in Lanes's defaults. Mirrored here so SwiftUI
    /// redraws when it changes.
    private(set) var automaticallyChecks: Bool

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecks = enabled
    }

    var lastCheck: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    func checkNow() {
        controller?.checkForUpdates(nil)
    }

    /// True once, on the launch right after Sparkle installed an update.
    /// Lanes otherwise starts in the menu bar alone, and after "Yükle ve
    /// Yeniden Başlat" nothing would show that the update finished.
    static func takeRelaunchedAfterUpdate() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Preferences.Key.relaunchedAfterUpdate) else { return false }
        defaults.removeObject(forKey: Preferences.Key.relaunchedAfterUpdate)
        return true
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        UserDefaults.standard.set(true, forKey: Preferences.Key.relaunchedAfterUpdate)
    }
}

/// Lanes usually runs in the menu bar alone, so Sparkle's window would open
/// behind whatever app is in front. It shows like the main window does: with
/// a Dock icon and in front, and Lanes goes back to the menu bar after.
/// Sparkle calls it on the main thread.
private final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            DockPresence.windowWillShow()
            NSApp.activate()
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Sparkle's window is still on screen at this point.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                DockPresence.otherWindowDidClose()
            }
        }
    }
}
