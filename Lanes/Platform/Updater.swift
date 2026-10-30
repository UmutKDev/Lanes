import Foundation
import Observation
import Sparkle

/// Lanes's own updates, through Sparkle. Runs only in builds that carry a
/// feed URL and a public key, which `make release` builds do; Debug builds
/// leave both empty and never check.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    /// False in builds without a feed or key. The settings say so instead of
    /// offering a check that can't run.
    let isAvailable: Bool

    init(bundle: Bundle = .main) {
        let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isAvailable = !feed.isEmpty && !key.isEmpty
        controller = isAvailable
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
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
}
