import Foundation
import WebKit

/// Earlier builds could open an account as claude.ai inside Lanes, with
/// that account's sign-in in a WebKit store Lanes made for it. That mode is
/// gone and those accounts now open in Claude.app, so the stores only hold
/// sign-ins nothing uses. They are removed once. Lanes never made any other
/// WebKit store, so every identified store is one of these.
enum LegacyWebData {
    private static let doneKey = "legacyWebDataRemoved"

    @MainActor
    static func removeOnce() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        // Touching the default store sets WebKit up on the main thread
        // first; asking for identifiers before that can crash WebKit.
        _ = WKWebsiteDataStore.default()
        for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: identifier)
            } catch {
                Log.app.error("Could not remove an old account's website data: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        defaults.removeObject(forKey: "openWebAccounts")
        defaults.set(true, forKey: doneKey)
    }
}
