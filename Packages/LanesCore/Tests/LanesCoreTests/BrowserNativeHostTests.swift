import Foundation
import XCTest
@testable import LanesCore

final class BrowserNativeHostTests: XCTestCase {
    final class MemoryVault: BrowserSessionVault {
        var items: [String: String] = [:]
        func read(_ account: String) -> Result<String?, BrowserNativeHost.VaultError> { .success(items[account]) }
        func write(_ account: String, _ value: String) -> BrowserNativeHost.VaultError? { items[account] = value; return nil }
        func delete(_ account: String) -> BrowserNativeHost.VaultError? { items[account] = nil; return nil }
    }

    let ext = BrowserNativeHost.developmentExtensionID

    func run(_ message: [String: Any], vault: MemoryVault, opened: inout [URL]) -> [String: Any] {
        var urls: [URL] = []
        let reply = BrowserNativeHost.handle(message, extensionID: ext, vault: vault, accounts: { ["accounts": []] }, open: { urls.append($0); return true }, version: "1.1.0")
        opened += urls
        return reply
    }

    func testFramingRoundTripsAndWaitsForWholeMessages() throws {
        let json = Data(#"{"type":"hello"}"#.utf8)
        var buffer = BrowserNativeHost.frame(json) + BrowserNativeHost.frame(Data("{}".utf8))
        XCTAssertEqual(Array(buffer.prefix(4)), [16, 0, 0, 0])
        var partial = buffer.prefix(10)
        XCTAssertNil(try BrowserNativeHost.takeMessage(from: &partial))
        XCTAssertEqual(try BrowserNativeHost.takeMessage(from: &buffer), json)
        XCTAssertEqual(try BrowserNativeHost.takeMessage(from: &buffer), Data("{}".utf8))
        XCTAssertTrue(buffer.isEmpty)
        var huge = Data([0, 0, 0, 0x7f])
        XCTAssertThrowsError(try BrowserNativeHost.takeMessage(from: &huge))
    }

    func testOriginsAndKeysAreChecked() {
        XCTAssertEqual(BrowserNativeHost.extensionID(fromOrigin: "chrome-extension://\(ext)/"), ext)
        XCTAssertNil(BrowserNativeHost.extensionID(fromOrigin: "https://claude.ai/"))
        XCTAssertNil(BrowserNativeHost.extensionID(fromOrigin: "chrome-extension://zzz/"))
        XCTAssertTrue(BrowserNativeHost.isValidKey("session.a0f1"))
        XCTAssertFalse(BrowserNativeHost.isValidKey("other.a0f1"))
        XCTAssertFalse(BrowserNativeHost.isValidKey("session.a/../b"))
    }

    func testVaultRequestsAreScopedToTheExtension() {
        let vault = MemoryVault()
        var opened: [URL] = []
        XCTAssertEqual(run(["type": "vaultSet", "key": "session.a1", "value": "[1]"], vault: vault, opened: &opened)["ok"] as? Bool, true)
        XCTAssertEqual(vault.items, ["\(ext)/session.a1": "[1]"])
        XCTAssertEqual(run(["type": "vaultGet", "key": "session.a1"], vault: vault, opened: &opened)["value"] as? String, "[1]")
        XCTAssertTrue(run(["type": "vaultGet", "key": "session.none"], vault: vault, opened: &opened)["value"] is NSNull)
        XCTAssertEqual(run(["type": "vaultGet", "key": "../x"], vault: vault, opened: &opened)["ok"] as? Bool, false)
        XCTAssertEqual(run(["type": "vaultDelete", "key": "session.a1"], vault: vault, opened: &opened)["ok"] as? Bool, true)
        XCTAssertTrue(vault.items.isEmpty)
        XCTAssertEqual(run(["type": "nope"], vault: vault, opened: &opened)["ok"] as? Bool, false)
    }

    func testOpenLanesBuildsOnlyLanesAddresses() {
        var opened: [URL] = []
        _ = run(["type": "openLanes", "account": "İş & Ev"], vault: MemoryVault(), opened: &opened)
        _ = run(["type": "openLanes", "account": ""], vault: MemoryVault(), opened: &opened)
        XCTAssertEqual(opened.map(\.absoluteString), ["lanes://open?account=%C4%B0%C5%9F%20%26%20Ev", "lanes://show?page=integrations"])
    }

    func testHostManifestListsTheExtensionAndIsRecognized() throws {
        let exe = URL(fileURLWithPath: "/Applications/Lanes.app/Contents/MacOS/lanes-browser-host")
        let data = BrowserNativeHost.hostManifest(executable: exe)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["name"] as? String, "com.umutkdev.lanes")
        XCTAssertEqual(object["path"] as? String, exe.path)
        XCTAssertEqual(object["type"] as? String, "stdio")
        XCTAssertEqual(object["allowed_origins"] as? [String], ["chrome-extension://\(ext)/"])
        XCTAssertEqual(BrowserNativeHost.hostFileState(data, executable: exe), .current)
        XCTAssertEqual(BrowserNativeHost.hostFileState(data, executable: URL(fileURLWithPath: "/tmp/x")), .outdated)
        XCTAssertEqual(BrowserNativeHost.hostFileState(Data(#"{"name":"other"}"#.utf8), executable: exe), .foreign)
        XCTAssertEqual(BrowserNativeHost.hostFileState(nil, executable: exe), .missing)
        let edge = try XCTUnwrap(BrowserNativeHost.browsers.first { $0.id == "edge" })
        XCTAssertEqual(edge.hostFile(home: URL(fileURLWithPath: "/Users/u")).path,
                       "/Users/u/Library/Application Support/Microsoft Edge/NativeMessagingHosts/com.umutkdev.lanes.json")
    }

    func testAccountListSharesOnlyNamesColorsAndEmails() throws {
        var work = Profile(id: ProfileID(rawValue: "w"), name: "İş", color: .purple)
        work.email = "is@example.com"
        let archived = Profile(id: ProfileID(rawValue: "a"), name: "Eski", color: .red, isArchived: true)
        let data = BrowserNativeHost.accountList([work, archived])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let accounts = try XCTUnwrap(object["accounts"] as? [[String: String]])
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0]["email"], "is@example.com")
        XCTAssertEqual(accounts[0]["color"], "purple")
        XCTAssertEqual(Set(accounts[0].keys), ["id", "name", "monogram", "color", "email"])
    }

    func testExtensionIDMatchesTheManifestKey() throws {
        // The ID Chrome derives from the manifest key must be the one the host allows.
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LanesChrome/manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { throw XCTSkip("LanesChrome not next to the package") }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let key = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(manifest["key"] as? String)))
        XCTAssertEqual(chromeExtensionID(publicKey: key), BrowserNativeHost.developmentExtensionID)
    }
}

/// Chrome's ID: the first 16 bytes of SHA-256 of the public key, each hex
/// digit mapped to a...p. SHA-256 is written out here because Linux has no
/// CryptoKit and the test must run there too.
private func chromeExtensionID(publicKey: Data) -> String {
    let digest = sha256([UInt8](publicKey))
    let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    return String(hex.map { Character(UnicodeScalar(UInt8(97) + UInt8($0.hexDigitValue!))) })
}

private func sha256(_ message: [UInt8]) -> [UInt8] {
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var data = message
    let bitLength = UInt64(message.count) * 8
    data.append(0x80)
    while data.count % 64 != 56 { data.append(0) }
    for i in (0..<8).reversed() { data.append(UInt8((bitLength >> (UInt64(i) * 8)) & 0xff)) }
    func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    for chunk in stride(from: 0, to: data.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(data[chunk + i * 4 + $1]) }
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            let ch = (e & f) ^ (~e & g)
            let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
        }
        h = [h[0] &+ a, h[1] &+ b, h[2] &+ c, h[3] &+ d, h[4] &+ e, h[5] &+ f, h[6] &+ g, h[7] &+ hh]
    }
    return h.flatMap { v in (0..<4).reversed().map { UInt8((v >> (UInt32($0) * 8)) & 0xff) } }
}
