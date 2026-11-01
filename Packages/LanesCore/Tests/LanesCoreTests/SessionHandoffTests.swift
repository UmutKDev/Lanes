import XCTest
@testable import LanesCore

final class SessionHandoffTests: XCTestCase {
    let from = URL(fileURLWithPath: "/a/ClaudeCode/projects", isDirectory: true)
    let to = URL(fileURLWithPath: "/b/ClaudeCode/projects", isDirectory: true)

    func testCopiesToTheSamePlaceInTheOtherAccount() throws {
        let handoff = try XCTUnwrap(SessionHandoff(sessionID: "41d7ec9b", projectFolderName: "-Users-admin-app", fromProjects: from, toProjects: to))
        XCTAssertEqual(handoff.sourceFile.path, "/a/ClaudeCode/projects/-Users-admin-app/41d7ec9b.jsonl")
        XCTAssertEqual(handoff.sourceFolder.path, "/a/ClaudeCode/projects/-Users-admin-app/41d7ec9b")
        XCTAssertEqual(handoff.destinationFile.path, "/b/ClaudeCode/projects/-Users-admin-app/41d7ec9b.jsonl")
        XCTAssertEqual(handoff.destinationFolder.path, "/b/ClaudeCode/projects/-Users-admin-app/41d7ec9b")
        XCTAssertEqual(SessionHandoff.resumeArguments(sessionID: "41d7ec9b"), ["--resume", "41d7ec9b", "--fork-session"])
    }

    func testRefusesNamesThatLeaveProjects() {
        XCTAssertNil(SessionHandoff(sessionID: "../x", projectFolderName: "-Users-a", fromProjects: from, toProjects: to))
        XCTAssertNil(SessionHandoff(sessionID: "x", projectFolderName: "..", fromProjects: from, toProjects: to))
        XCTAssertNil(SessionHandoff(sessionID: "", projectFolderName: "-Users-a", fromProjects: from, toProjects: to))
        XCTAssertNil(SessionHandoff(sessionID: ".hidden", projectFolderName: "-Users-a", fromProjects: from, toProjects: to))
    }

    func testRefusesTheSameAccountFolder() {
        XCTAssertNil(SessionHandoff(sessionID: "x", projectFolderName: "-Users-a", fromProjects: from, toProjects: from))
    }

    func testSharedFoldersAreTheSameFolder() {
        let shared = URL(fileURLWithPath: "/Users/u/.claude/projects", isDirectory: true)
        XCTAssertTrue(SessionHandoff.isSameFolder(shared, URL(fileURLWithPath: "/Users/u/.claude/projects/")))
        XCTAssertTrue(SessionHandoff.isSameFolder(shared, URL(fileURLWithPath: "/Users/U/.Claude/projects")))
        XCTAssertFalse(SessionHandoff.isSameFolder(from, to))
    }
}
