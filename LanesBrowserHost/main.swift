import AppKit
import Foundation
import LanesCore
import Security

// lanes-browser-host: the native messaging host of the Lanes extension for
// Chrome and Edge. The browser starts it for each `sendNativeMessage` call
// with the calling extension's origin as the first argument, writes one
// framed JSON request to stdin and reads one framed reply from stdout. The
// logic is in LanesCore (BrowserNativeHost); this file only adds the
// Keychain, the account list file and NSWorkspace.

/// Saved sessions as generic passwords in the login Keychain, one per
/// extension install and account.
struct KeychainVault: BrowserSessionVault {
    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: BrowserNativeHost.keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    func read(_ account: String) -> Result<String?, BrowserNativeHost.VaultError> {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return .success(nil) }
        guard status == errSecSuccess, let data = result as? Data else {
            return .failure(.init("Keychain read failed (\(status))"))
        }
        return .success(String(data: data, encoding: .utf8))
    }

    func write(_ account: String, _ value: String) -> BrowserNativeHost.VaultError? {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return nil }
        guard update == errSecItemNotFound else { return .init("Keychain update failed (\(update))") }
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Lanes (Chrome/Edge): claude.ai oturumu"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess ? nil : .init("Keychain add failed (\(status))")
    }

    func delete(_ account: String) -> BrowserNativeHost.VaultError? {
        let status = SecItemDelete(query(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound ? nil : .init("Keychain delete failed (\(status))")
    }
}

func sharedAccounts() -> Any? {
    let file = ProfilePaths.standard().root.appendingPathComponent(BrowserNativeHost.accountsFileName, isDirectory: false)
    guard let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data),
          JSONSerialization.isValidJSONObject(object) else { return nil }
    return object
}

func send(_ reply: [String: Any]) {
    guard let json = try? JSONSerialization.data(withJSONObject: reply) else { return }
    FileHandle.standardOutput.write(BrowserNativeHost.frame(json))
}

let arguments = CommandLine.arguments
guard arguments.count > 1, let extensionID = BrowserNativeHost.extensionID(fromOrigin: arguments[1]) else {
    FileHandle.standardError.write(Data("lanes-browser-host is started by Chrome or Edge for the Lanes extension.\n".utf8))
    exit(64)
}

let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
let vault = KeychainVault()
var buffer = Data()
while true {
    let chunk = FileHandle.standardInput.availableData
    if chunk.isEmpty { break } // the browser closed the pipe
    buffer.append(chunk)
    do {
        while let request = try BrowserNativeHost.takeMessage(from: &buffer) {
            let message = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any] ?? [:]
            send(BrowserNativeHost.handle(
                message,
                extensionID: extensionID,
                vault: vault,
                accounts: sharedAccounts,
                open: { NSWorkspace.shared.open($0) },
                version: version
            ))
        }
    } catch {
        send(["ok": false, "error": "message too large"])
        exit(65)
    }
}
