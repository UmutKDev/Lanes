import Foundation
@testable import LanesCore
import XCTest

final class DesktopAccountTests: XCTestCase {
    private let uuid = "1F0E7A52-3C4B-4D6E-8F90-A1B2C3D4E5F6"

    private func config(_ accountUuid: String) -> String {
        """
        {"locale": "tr-TR", "lastKnownAccountUuid": "\(accountUuid)",
         "oauth:tokenCache": "FAKE-SECRET-1", "oauth:tokenCacheV2": {"token": "FAKE-SECRET-2"},
         "darkMode": "system"}
        """
    }

    func testReadsOnlyTheAccountNumber() {
        XCTAssertEqual(DesktopAccount.parseAccountUuid(Data(config(uuid).utf8)), uuid.lowercased())
    }

    func testRejectsMissingOrInvalidValues() {
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data(config("not-a-uuid").utf8)))
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data(config("").utf8)))
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data(#"{"oauth:tokenCache": "FAKE"}"#.utf8)))
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data(#"{"lastKnownAccountUuid": 42}"#.utf8)))
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data(#"["\#(uuid)"]"#.utf8)))
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data("not json".utf8)))
    }

    func testNestedAccountNumberIsIgnored() {
        XCTAssertNil(DesktopAccount.parseAccountUuid(Data(#"{"other": {"lastKnownAccountUuid": "\#(uuid)"}}"#.utf8)))
    }

    func testReadsFromDiskAndSkipsLargeFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(config(uuid).utf8).write(to: url)
        XCTAssertEqual(DesktopAccount.readAccountUuid(from: url), uuid.lowercased())
        XCTAssertNil(DesktopAccount.readAccountUuid(from: folder.appendingPathComponent("missing.json")))

        let big = folder.appendingPathComponent("big.json")
        let padding = String(repeating: " ", count: DesktopAccount.maximumFileSize)
        try Data((config(uuid) + padding).utf8).write(to: big)
        XCTAssertNil(DesktopAccount.readAccountUuid(from: big))
    }

    func testConfigFileLocation() {
        let paths = ProfilePaths(root: URL(fileURLWithPath: "/r"), home: URL(fileURLWithPath: "/h"))
        let profile = Profile(id: ProfileID(rawValue: "p1"), name: "İş", color: .blue)
        XCTAssertEqual(paths.desktopConfigFile(for: profile).path, "/r/Profiles/p1/Claude/config.json")
        let main = Profile(id: ProfileID(rawValue: "m"), name: "Ana", color: .blue, isDefault: true)
        XCTAssertEqual(paths.desktopConfigFile(for: main).path, "/h/Library/Application Support/Claude/config.json")
    }

    func testAccountMatch() {
        let a = uuid.lowercased()
        XCTAssertEqual(AccountMatch(claudeCodeUuid: a, desktopUuid: a), .same)
        XCTAssertEqual(AccountMatch(claudeCodeUuid: a, desktopUuid: "00000000-0000-0000-0000-000000000000"), .different)
        XCTAssertEqual(AccountMatch(claudeCodeUuid: nil, desktopUuid: a), .unknown)
        XCTAssertEqual(AccountMatch(claudeCodeUuid: a, desktopUuid: nil), .unknown)
    }

    func testClaudeCodeAccountNumber() {
        let json = #"{"oauthAccount": {"accountUuid": "\#(uuid)", "emailAddress": "a@b.c"}}"#
        XCTAssertEqual(ClaudeCodeAccount.parse(Data(json.utf8))?.accountUuid, uuid.lowercased())
        let bad = #"{"oauthAccount": {"accountUuid": "x", "emailAddress": "a@b.c"}}"#
        XCTAssertNil(ClaudeCodeAccount.parse(Data(bad.utf8))?.accountUuid)
    }
}
