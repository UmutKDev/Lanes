import Foundation
@testable import LanesCore
import XCTest

final class ClaudeCodeAccountTests: XCTestCase {
    func testReadsOnlyTheAccountFields() {
        let json = """
        {"numStartups": 4, "oauthAccount": {"accountUuid": "x", "emailAddress": " ada@example.com ",
         "displayName": "Ada", "organizationName": "Ada's Org", "organizationUuid": "y"}, "projects": {}}
        """
        XCTAssertEqual(
            ClaudeCodeAccount.parse(Data(json.utf8)),
            ClaudeCodeAccount(email: "ada@example.com", displayName: "Ada", organizationName: "Ada's Org")
        )
    }

    func testMissingOrEmptyFields() {
        XCTAssertNil(ClaudeCodeAccount.parse(Data(#"{"numStartups": 1}"#.utf8)))
        XCTAssertNil(ClaudeCodeAccount.parse(Data(#"{"oauthAccount": {"emailAddress": ""}}"#.utf8)))
        XCTAssertNil(ClaudeCodeAccount.parse(Data(#"{"oauthAccount": {"emailAddress": "nope"}}"#.utf8)))
        XCTAssertNil(ClaudeCodeAccount.parse(Data("not json".utf8)))
        XCTAssertEqual(
            ClaudeCodeAccount.parse(Data(#"{"oauthAccount": {"emailAddress": "a@b.c", "displayName": " "}}"#.utf8)),
            ClaudeCodeAccount(email: "a@b.c")
        )
    }

    func testAccountFileLocation() {
        let paths = ProfilePaths(root: URL(fileURLWithPath: "/r"), home: URL(fileURLWithPath: "/h"))
        let profile = Profile(id: ProfileID(rawValue: "p1"), name: "İş", color: .blue)
        XCTAssertEqual(paths.claudeCodeAccountFile(for: profile).path, "/r/Profiles/p1/ClaudeCode/.claude.json")
    }

    func testReadsFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(#"{"oauthAccount": {"emailAddress": "d@e.f"}}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ClaudeCodeAccount.read(from: url)?.email, "d@e.f")
        XCTAssertNil(ClaudeCodeAccount.read(from: url.appendingPathExtension("missing")))
    }
}
