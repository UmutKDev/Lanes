import AppKit
import CryptoKit
import LanesCore
import Observation
import WebKit

/// Accounts that run inside Lanes: claude.ai in Lanes's own windows, one
/// native tab per account, each with its own website data. The main
/// account never comes here; it stays on Claude.app.
///
/// Lanes never reads what WebKit stores for these accounts. The sign-in
/// happens on claude.ai's own page.
@MainActor
@Observable
final class WebAccounts {
    static let home = URL(string: "https://claude.ai/")!
    static let tabbingIdentifier = "LanesAccounts"

    /// Accounts with a window open.
    private(set) var openIDs: Set<ProfileID> = []
    /// The account whose window is key, for the menu bar icon.
    private(set) var keyProfileID: ProfileID?
    @ObservationIgnored private var controllers: [ProfileID: WebAccountWindowController] = [:]

    func isOpen(_ id: ProfileID) -> Bool {
        openIDs.contains(id)
    }

    /// Shows the account's tab, opening it first if needed. Returns true
    /// when it ended up in front.
    @discardableResult
    func show(_ profile: Profile, url: URL? = nil) async -> Bool {
        let controller: WebAccountWindowController
        if let existing = controllers[profile.id] {
            controller = existing
            if let url { existing.load(url) }
        } else {
            controller = WebAccountWindowController(
                profile: profile,
                store: WKWebsiteDataStore(forIdentifier: Self.storeIdentifier(for: profile.id)),
                start: url ?? Self.home
            )
            controller.onClose = { [weak self] id in self?.didClose(id) }
            controller.onBecomeKey = { [weak self] id in self?.keyProfileID = id }
            controllers[profile.id] = controller
            openIDs.insert(profile.id)
            // Joins the other account windows as a tab, like a browser.
            if let window = controller.window,
               let host = controllers.values.compactMap(\.window).first(where: { $0 !== window && $0.isVisible }) {
                host.addTabbedWindow(window, ordered: .above)
            }
        }
        guard let window = controller.window else { return false }
        window.tab.title = profile.name
        // Account windows always show Lanes in the Dock and in Cmd-Tab,
        // like any app with a window, whatever the main window setting says.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        let outcome = await WindowActivator.bringForward(window)
        return outcome.method != .gaveUp
    }

    func close(_ id: ProfileID) {
        controllers[id]?.window?.performClose(nil)
    }

    /// Keeps the tab's title and badge in step with the profile.
    func update(_ profile: Profile) {
        controllers[profile.id]?.apply(profile)
    }

    /// Forgets the account's sign-in and everything claude.ai stored for it.
    func removeData(for id: ProfileID) async {
        controllers[id]?.window?.close()
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: Self.storeIdentifier(for: id))
        } catch {
            Log.app.error("Could not remove an account's website data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func didClose(_ id: ProfileID) {
        controllers[id] = nil
        openIDs.remove(id)
        if keyProfileID == id { keyProfileID = nil }
    }

    /// The website data store's identifier, stable for the profile. Profile
    /// IDs are UUIDs; any other ID is hashed into one.
    nonisolated static func storeIdentifier(for id: ProfileID) -> UUID {
        if let uuid = UUID(uuidString: id.rawValue) { return uuid }
        var bytes = Array(Insecure.MD5.hash(data: Data(id.rawValue.utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
