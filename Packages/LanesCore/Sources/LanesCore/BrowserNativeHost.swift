import Foundation

/// The native messaging host behind the Lanes extension for Chrome and Edge
/// (LanesChrome). Chrome-based browsers start `lanes-browser-host` from
/// Lanes.app whenever the extension calls `runtime.sendNativeMessage`, and
/// find it through a small JSON file Lanes puts in each browser's
/// `NativeMessagingHosts` folder.
///
/// The host does what the Safari extension's native part does, nothing more:
/// keeps saved claude.ai sessions in the login Keychain, hands over the
/// account list Lanes shares (names, colors, e-mails) and opens `lanes://`
/// addresses. It never reads browser data, Claude content or account folders.
public enum BrowserNativeHost {
    /// The host's name. Chrome allows only lowercase letters, digits, `_`
    /// and dots here.
    public static let name = "com.umutkdev.lanes"
    /// The helper's file name inside Lanes.app/Contents/MacOS.
    public static let executableName = "lanes-browser-host"
    /// The account list Lanes writes to its own folder for the host.
    public static let accountsFileName = "BrowserAccounts.json"
    /// Keychain service of the saved sessions.
    public static let keychainService = "com.umutkdev.Lanes.Browser.sessions"

    /// The extension's ID when loaded unpacked from Lanes.app or the repo:
    /// fixed by the `key` in LanesChrome/manifest.json.
    public static let developmentExtensionID = "gfddmgggahfmohadmaohjddpkhfnfaeg"
    /// IDs the Chrome Web Store and Edge Add-ons give the extension. Each
    /// store picks its own, so they are added here once the listings exist.
    public static let storeExtensionIDs: [String] = [
        "oibhpcchenilokfnhhdlfbconbieibgd", // Edge Add-ons
    ]

    public static var allowedExtensionIDs: [String] {
        [developmentExtensionID] + storeExtensionIDs
    }

    // MARK: Browsers

    /// A Chrome-based browser and its folder under Application Support.
    public struct Browser: Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let supportFolder: String

        /// `~/Library/Application Support/<browser>`: the host file only goes
        /// in when this exists, so Lanes never creates folders for browsers
        /// the user doesn't have.
        public func dataFolder(home: URL) -> URL {
            home.appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(supportFolder, isDirectory: true)
        }

        public func hostFile(home: URL) -> URL {
            dataFolder(home: home)
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
                .appendingPathComponent(BrowserNativeHost.name + ".json", isDirectory: false)
        }
    }

    public static let browsers: [Browser] = [
        Browser(id: "chrome", displayName: "Google Chrome", supportFolder: "Google/Chrome"),
        Browser(id: "chrome-beta", displayName: "Google Chrome Beta", supportFolder: "Google/Chrome Beta"),
        Browser(id: "chrome-dev", displayName: "Google Chrome Dev", supportFolder: "Google/Chrome Dev"),
        Browser(id: "chrome-canary", displayName: "Google Chrome Canary", supportFolder: "Google/Chrome Canary"),
        Browser(id: "chromium", displayName: "Chromium", supportFolder: "Chromium"),
        Browser(id: "edge", displayName: "Microsoft Edge", supportFolder: "Microsoft Edge"),
        Browser(id: "edge-beta", displayName: "Microsoft Edge Beta", supportFolder: "Microsoft Edge Beta"),
        Browser(id: "edge-dev", displayName: "Microsoft Edge Dev", supportFolder: "Microsoft Edge Dev"),
        Browser(id: "edge-canary", displayName: "Microsoft Edge Canary", supportFolder: "Microsoft Edge Canary"),
        Browser(id: "brave", displayName: "Brave", supportFolder: "BraveSoftware/Brave-Browser"),
        Browser(id: "vivaldi", displayName: "Vivaldi", supportFolder: "Vivaldi"),
        Browser(id: "arc", displayName: "Arc", supportFolder: "Arc/User Data"),
    ]

    /// The host file's contents. Sorted keys, so an unchanged file is not
    /// written again on every launch.
    public static func hostManifest(executable: URL) -> Data {
        let manifest: [String: Any] = [
            "name": name,
            "description": "Lanes: claude.ai sessions in the Keychain",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": allowedExtensionIDs.map { "chrome-extension://\($0)/" },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return data + Data("\n".utf8)
    }

    /// Whether a host file was written by Lanes (so Lanes may replace or
    /// remove it) and points at `executable`.
    public static func hostFileState(_ data: Data?, executable: URL) -> HostFileState {
        guard let data else { return .missing }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["name"] as? String == name else { return .foreign }
        return data == hostManifest(executable: executable) ? .current : .outdated
    }

    public enum HostFileState: Equatable, Sendable {
        case missing, current, outdated, foreign
    }

    // MARK: Account list

    /// What the extension gets as `lanes`: names, colors, monograms and
    /// e-mails of active accounts. The same shape the Safari extension reads.
    public static func accountList(_ profiles: [Profile], updatedAt: Date = Date()) -> Data {
        let accounts = profiles.filter { !$0.isArchived }.map { profile -> [String: String] in
            var entry = [
                "id": profile.id.rawValue,
                "name": profile.name,
                "monogram": profile.monogram,
                "color": profile.color.rawValue,
            ]
            if let email = profile.email, !email.isEmpty { entry["email"] = email }
            return entry
        }
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "version": 1,
            "updatedAt": formatter.string(from: updatedAt),
            "accounts": accounts,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: Messages

    /// Chrome's framing: a 32-bit length in native byte order (little endian
    /// on every Mac), then UTF-8 JSON.
    public static func frame(_ json: Data) -> Data {
        var length = UInt32(json.count).littleEndian
        return withUnsafeBytes(of: &length) { Data($0) } + json
    }

    /// Takes the first whole message off `buffer`. Nil while it is still
    /// incomplete. Messages over 4 MB are refused: the extension never sends
    /// anything near that, so it can only be garbage.
    public static func takeMessage(from buffer: inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let bytes = [UInt8](buffer.prefix(4))
        let length = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        guard length <= 4 * 1024 * 1024 else { throw FramingError.tooLarge }
        guard buffer.count >= 4 + length else { return nil }
        let start = buffer.startIndex
        let message = buffer.subdata(in: (start + 4)..<(start + 4 + length))
        buffer = buffer.subdata(in: (start + 4 + length)..<buffer.endIndex)
        return message
    }

    public enum FramingError: Error { case tooLarge }

    /// The extension ID from the origin Chrome passes as the first argument
    /// (`chrome-extension://<id>/`).
    public static func extensionID(fromOrigin origin: String) -> String? {
        let prefix = "chrome-extension://"
        guard origin.hasPrefix(prefix) else { return nil }
        let id = origin.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard id.count == 32, id.allSatisfy({ ("a"..."p").contains($0) }) else { return nil }
        return id
    }

    /// Keys the extension makes: "session." followed by an account id.
    public static func isValidKey(_ key: String) -> Bool {
        key.hasPrefix("session.") && key.count <= 80
            && key.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }
    }

    /// Keychain account of a saved session. Each extension install (Chrome,
    /// Edge, a store copy) has its own ID, so their sessions stay apart.
    public static func vaultAccount(extensionID: String, key: String) -> String {
        extensionID + "/" + key
    }

    /// `lanes://open?account=<name>` for a matched account, otherwise the
    /// Integrations page.
    public static func lanesURL(account: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "lanes"
        if let account, !account.isEmpty {
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "account", value: account)]
        } else {
            components.host = "show"
            components.queryItems = [URLQueryItem(name: "page", value: "integrations")]
        }
        return components.url
    }
}

/// Where the host keeps sessions; the Keychain in the app, a dictionary in
/// tests.
public protocol BrowserSessionVault {
    func read(_ account: String) -> Result<String?, BrowserNativeHost.VaultError>
    func write(_ account: String, _ value: String) -> BrowserNativeHost.VaultError?
    func delete(_ account: String) -> BrowserNativeHost.VaultError?
}

extension BrowserNativeHost {
    public struct VaultError: Error, Equatable {
        public let message: String
        public init(_ message: String) { self.message = message }
    }

    /// One request from the extension, one reply. `accounts` reads the list
    /// Lanes shares, `open` opens a lanes:// address.
    public static func handle(
        _ message: [String: Any],
        extensionID: String,
        vault: BrowserSessionVault,
        accounts: () -> Any?,
        open: (URL) -> Bool,
        version: String
    ) -> [String: Any] {
        func failure(_ text: String) -> [String: Any] { ["ok": false, "error": text] }
        let type = message["type"] as? String ?? ""
        switch type {
        case "hello":
            return ["ok": true, "version": version, "keychain": true, "lanes": accounts() ?? NSNull()]
        case "lanesAccounts":
            return ["ok": true, "lanes": accounts() ?? NSNull()]
        case "vaultGet":
            guard let key = message["key"] as? String, isValidKey(key) else { return failure("bad key") }
            switch vault.read(vaultAccount(extensionID: extensionID, key: key)) {
            case let .success(value): return ["ok": true, "value": value ?? NSNull()]
            case let .failure(error): return failure(error.message)
            }
        case "vaultSet":
            guard let key = message["key"] as? String, isValidKey(key),
                  let value = message["value"] as? String, value.utf8.count <= 512 * 1024 else { return failure("bad request") }
            if let error = vault.write(vaultAccount(extensionID: extensionID, key: key), value) { return failure(error.message) }
            return ["ok": true]
        case "vaultDelete":
            guard let key = message["key"] as? String, isValidKey(key) else { return failure("bad key") }
            if let error = vault.delete(vaultAccount(extensionID: extensionID, key: key)) { return failure(error.message) }
            return ["ok": true]
        case "openLanes":
            guard let url = lanesURL(account: message["account"] as? String) else { return failure("bad account") }
            return open(url) ? ["ok": true] : failure("Lanes could not be opened")
        default:
            return failure("unknown message")
        }
    }
}
