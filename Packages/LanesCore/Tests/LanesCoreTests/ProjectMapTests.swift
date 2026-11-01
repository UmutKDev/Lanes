import Foundation
import XCTest
@testable import LanesCore

final class ProjectMapTests: XCTestCase {
    private let work = ProfileID(rawValue: "work")
    private let home = ProfileID(rawValue: "home")
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ id: String, _ folder: String, _ minutes: Double) -> ClaudeCodeSessionList.Session {
        ClaudeCodeSessionList.Session(id: id, projectFolderName: folder, modifiedAt: start.addingTimeInterval(minutes * 60))
    }

    func testGroupsSessionsByProjectAndAccount() {
        let map = ProjectMap(lists: [
            (work, ClaudeCodeSessionList(sessions: [
                session("a", "-Users-u-lanes", 1),
                session("b", "-Users-u-lanes", 5),
                session("c", "-Users-u-site", 2),
            ])),
            (home, ClaudeCodeSessionList(sessions: [
                session("d", "-Users-u-lanes", 3),
            ])),
        ])
        XCTAssertEqual(map.projects.map(\.folderName), ["-Users-u-lanes", "-Users-u-site"])
        let lanes = map.projects[0]
        XCTAssertTrue(lanes.isShared)
        XCTAssertEqual(lanes.sessionCount, 3)
        XCTAssertEqual(lanes.uses.map(\.profileID), [work, home])
        XCTAssertEqual(lanes.uses[0].sessionCount, 2)
        XCTAssertEqual(lanes.uses[0].newestSessionID, "b")
        XCTAssertEqual(lanes.lastUsed, start.addingTimeInterval(300))
        XCTAssertFalse(map.projects[1].isShared)
    }

    func testMixedClassesAreFlaggedOnlyAcrossKinds() {
        let map = ProjectMap(lists: [
            (work, ClaudeCodeSessionList(sessions: [session("a", "-p", 1)])),
            (home, ClaudeCodeSessionList(sessions: [session("b", "-p", 2)])),
        ])
        let project = map.projects[0]
        XCTAssertTrue(project.mixesClasses { $0 == self.work ? .employer : .personal })
        XCTAssertFalse(project.mixesClasses { _ in .client })
    }

    func testAccountListedTwiceCountsOnce() {
        let list = ClaudeCodeSessionList(sessions: [session("a", "-p", 1)])
        let map = ProjectMap(lists: [(work, list), (work, list)])
        XCTAssertEqual(map.projects[0].uses.count, 1)
        XCTAssertFalse(map.projects[0].isShared)
    }

    func testPulseFollowsTheLastWrite() {
        XCTAssertEqual(ClaudeCodePulse.pulse(lastWrite: nil, now: start), .idle)
        XCTAssertEqual(ClaudeCodePulse.pulse(lastWrite: start.addingTimeInterval(-5), now: start), .working)
        XCTAssertEqual(ClaudeCodePulse.pulse(lastWrite: start.addingTimeInterval(5), now: start), .working)
        XCTAssertEqual(ClaudeCodePulse.pulse(lastWrite: start.addingTimeInterval(-120), now: start), .recent)
        XCTAssertEqual(ClaudeCodePulse.pulse(lastWrite: start.addingTimeInterval(-3600), now: start), .idle)
    }
}
