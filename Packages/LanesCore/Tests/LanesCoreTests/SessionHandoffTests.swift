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

    func testEarlierPartIsAPrefixOfTheNewerFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func file(_ name: String, _ text: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            return url
        }
        let old = try file("old", "a\nb\n")
        let new = try file("new", "a\nb\nc\n")
        let other = try file("other", "a\nx\nc\n")
        let empty = try file("empty", "")
        XCTAssertTrue(SessionHandoff.isEarlierPart(old, of: new))
        XCTAssertTrue(SessionHandoff.isEarlierPart(new, of: new))
        XCTAssertTrue(SessionHandoff.isEarlierPart(empty, of: new))
        XCTAssertFalse(SessionHandoff.isEarlierPart(new, of: old), "Longer than the source")
        XCTAssertFalse(SessionHandoff.isEarlierPart(other, of: new), "Went on differently")
        XCTAssertFalse(SessionHandoff.isEarlierPart(root.appendingPathComponent("missing"), of: new))
    }
}
