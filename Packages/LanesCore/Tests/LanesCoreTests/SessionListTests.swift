import Foundation
import XCTest
@testable import LanesCore

final class SessionListTests: XCTestCase {
    func testReadsNamesAndDatesNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("-Users-u-app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let old = project.appendingPathComponent("aaa.jsonl")
        let new = project.appendingPathComponent("bbb.jsonl")
        try Data().write(to: old)
        try Data().write(to: new)
        try Data().write(to: project.appendingPathComponent("notes.txt"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: new.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let list = ClaudeCodeSessionList.read(root)
        XCTAssertEqual(list.sessions.map(\.id), ["bbb", "aaa"])
        XCTAssertEqual(list.sessions.first?.projectFolderName, "-Users-u-app")
    }

    func testMissingFolderReadsEmpty() {
        XCTAssertEqual(ClaudeCodeSessionList.read(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).sessions, [])
    }

    func testProjectPathPrefersExistingFolders() {
        let existing: Set<String> = ["/Users", "/Users/u", "/Users/u/my-app"]
        XCTAssertEqual(ClaudeCodeSessionList.projectPath(forFolderName: "-Users-u-my-app", exists: existing.contains), "/Users/u/my-app")
    }

    func testProjectPathPlainSplit() {
        let existing: Set<String> = ["/Users", "/Users/u", "/Users/u/my", "/Users/u/my/app"]
        XCTAssertEqual(ClaudeCodeSessionList.projectPath(forFolderName: "-Users-u-my-app", exists: existing.contains), "/Users/u/my/app")
    }

    func testProjectPathMissingIsNil() {
        XCTAssertNil(ClaudeCodeSessionList.projectPath(forFolderName: "-Users-gone", exists: { _ in false }))
        XCTAssertNil(ClaudeCodeSessionList.projectPath(forFolderName: "relative", exists: { _ in true }))
    }

    func testActivityCountsPerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 10 * 86_400 + 3_600)
        let list = ClaudeCodeSessionList(sessions: [
            .init(id: "a", projectFolderName: "p", modifiedAt: now),
            .init(id: "b", projectFolderName: "p", modifiedAt: now.addingTimeInterval(-60)),
            .init(id: "c", projectFolderName: "p", modifiedAt: now.addingTimeInterval(-86_400)),
            .init(id: "d", projectFolderName: "p", modifiedAt: now.addingTimeInterval(-30 * 86_400)),
        ])
        let activity = list.activity(days: 3, now: now, calendar: calendar)
        XCTAssertEqual(activity.map(\.sessions), [0, 1, 2])
    }

    func testProjectPathReadsDots() {
        let existing: Set<String> = [
            "/Users", "/Users/admin", "/Users/admin/wt2", "/Users/admin/wt2.worktrees",
            "/Users/admin/wt2.worktrees/lanes-ana-hesap-1101-1319", "/Users/admin/.config", "/Users/admin/.config/app",
        ]
        XCTAssertEqual(
            ClaudeCodeSessionList.projectPath(forFolderName: "-Users-admin-wt2-worktrees-lanes-ana-hesap-1101-1319", exists: existing.contains),
            "/Users/admin/wt2.worktrees/lanes-ana-hesap-1101-1319"
        )
        XCTAssertEqual(ClaudeCodeSessionList.projectPath(forFolderName: "-Users-admin-wt2", exists: existing.contains), "/Users/admin/wt2")
        XCTAssertEqual(ClaudeCodeSessionList.projectPath(forFolderName: "-Users-admin--config-app", exists: existing.contains), "/Users/admin/.config/app")
    }
}
