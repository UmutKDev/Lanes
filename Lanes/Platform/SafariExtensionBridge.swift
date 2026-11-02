import Foundation
import LanesCore
import SafariServices

/// Lanes's side of the Safari extension (LanesSafari). Lanes shares its
/// account list through the app group folder, so the extension can give a
/// claude.ai account the same name and color as its desktop twin and open it
/// in Lanes. Only names, colors, monograms and e-mails are shared: never
/// account folders, sessions or Claude data.
enum SafariExtensionBridge {
    static let extensionIdentifier = "com.umutkdev.Lanes.Safari"
    static let fileName = "SafariAccounts.json"

    enum State: Equatable {
        case on
        case off
        /// Safari could not say: the extension is not registered yet (Lanes
        /// runs from a build folder) or Safari is too old.
        case unknown
    }

    private static var groupFolder: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LanesAppGroup") as? String,
              group.contains(".") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    /// Writes the list the extension reads. Archived accounts are left out.
    /// Failure only costs the name and color match, so it is logged, not shown.
    static func publish(_ profiles: [Profile]) {
        guard let folder = groupFolder else { return }
        let accounts = profiles.map { profile -> [String: String] in
            var entry = [
                "id": profile.id.rawValue,
                "name": profile.name,
                "monogram": profile.monogram,
                "color": profile.color.rawValue,
            ]
            if let email = profile.email, !email.isEmpty { entry["email"] = email }
            return entry
        }
        let payload: [String: Any] = [
            "version": 1,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "accounts": accounts,
        ]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
        } catch {
            Log.app.error("Safari account list not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func state() async -> State {
        await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionIdentifier) { state, error in
                if let state, error == nil {
                    continuation.resume(returning: state.isEnabled ? .on : .off)
                } else {
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    /// Opens Safari's Extensions settings with Lanes selected.
    static func openSafariSettings() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionIdentifier) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }
}
