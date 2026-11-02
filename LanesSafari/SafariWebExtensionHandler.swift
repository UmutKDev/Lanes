import AppKit
import Foundation
import os
import SafariServices

/// Native half of the Lanes Safari extension. The extension's scripts call
/// `browser.runtime.sendNativeMessage` and each message lands here. It does
/// three things only:
///
/// - keeps saved claude.ai sessions in the login Keychain, so they never sit
///   in Safari's extension storage as plain files,
/// - reads the account list Lanes shares (names, colors, e-mails) from the
///   app group folder,
/// - opens `lanes://` addresses, so a web account can open its desktop twin.
///
/// It never reads Safari data, Claude content or Lanes's account folders.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let reply = NativeBridge.handle(message)
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}

enum NativeBridge {
    static let log = Logger(subsystem: "com.umutkdev.Lanes.Safari", category: "bridge")

    static func handle(_ message: [String: Any]) -> [String: Any] {
        let type = message["type"] as? String ?? ""
        switch type {
        case "hello":
            return [
                "ok": true,
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "keychain": true,
                "lanes": LanesAccounts.read() ?? NSNull(),
            ]
        case "lanesAccounts":
            return ["ok": true, "lanes": LanesAccounts.read() ?? NSNull()]
        case "vaultGet":
            guard let key = message["key"] as? String, SessionVault.isValid(key) else { return failure("bad key") }
            switch SessionVault.read(key) {
            case let .success(value): return ["ok": true, "value": value ?? NSNull()]
            case let .failure(error): return failure(error.message)
            }
        case "vaultSet":
            guard let key = message["key"] as? String, SessionVault.isValid(key),
                  let value = message["value"] as? String else { return failure("bad request") }
            if let error = SessionVault.write(key, value) { return failure(error.message) }
            return ["ok": true]
        case "vaultDelete":
            guard let key = message["key"] as? String, SessionVault.isValid(key) else { return failure("bad key") }
            if let error = SessionVault.delete(key) { return failure(error.message) }
            return ["ok": true]
        case "openLanes":
            // Only lanes://open and lanes://show, built here from plain values.
            var components = URLComponents()
            components.scheme = "lanes"
            if let account = message["account"] as? String, !account.isEmpty {
                components.host = "open"
                components.queryItems = [URLQueryItem(name: "account", value: account)]
            } else {
                components.host = "show"
                components.queryItems = [URLQueryItem(name: "page", value: "integrations")]
            }
            guard let url = components.url else { return failure("bad account") }
            let opened = NSWorkspace.shared.open(url)
            return opened ? ["ok": true] : failure("Lanes could not be opened")
        default:
            return failure("unknown message")
        }
    }

    private static func failure(_ text: String) -> [String: Any] {
        log.error("Request failed: \(text, privacy: .public)")
        return ["ok": false, "error": text]
    }
}

/// The account list Lanes writes to the shared app group folder whenever its
/// accounts change (see SafariExtensionBridge in Lanes). Passed to the
/// extension as it is; nil when Lanes has not written it.
enum LanesAccounts {
    static func read() -> Any? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "LanesAppGroup") as? String,
              !group.isEmpty,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let file = folder.appendingPathComponent("SafariAccounts.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object) else { return nil }
        return object
    }
}

/// Saved claude.ai sessions, one generic password per account. Values are the
/// cookie list the extension captured, as JSON text.
enum SessionVault {
    static let service = "com.umutkdev.Lanes.Safari.sessions"

    struct Failure: Error { let message: String }

    /// Keys the extension makes: "session." followed by an account id.
    static func isValid(_ key: String) -> Bool {
        key.hasPrefix("session.") && key.count <= 80
            && key.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }
    }

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func read(_ key: String) -> Result<String?, Failure> {
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return .success(nil) }
        guard status == errSecSuccess, let data = result as? Data else {
            return .failure(Failure(message: "Keychain read failed (\(status))"))
        }
        return .success(String(data: data, encoding: .utf8))
    }

    static func write(_ key: String, _ value: String) -> Failure? {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return nil }
        guard update == errSecItemNotFound else { return Failure(message: "Keychain update failed (\(update))") }
        var add = query(key)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Lanes Safari: claude.ai oturumu"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess ? nil : Failure(message: "Keychain add failed (\(status))")
    }

    static func delete(_ key: String) -> Failure? {
        let status = SecItemDelete(query(key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound ? nil : Failure(message: "Keychain delete failed (\(status))")
    }
}
