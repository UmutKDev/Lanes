import Foundation
@testable import LanesCore
import XCTest

final class SessionMoveLogTests: XCTestCase {
    private func move(_ created: [String] = [], date: TimeInterval = 0) -> SessionMove {
        SessionMove(date: Date(timeIntervalSince1970: date), sourceID: ProfileID(rawValue: "a"), targetID: ProfileID(rawValue: "b"), project: "app", title: "Rapor", addedToCodeTab: true, created: created)
    }

    func testUndoOnlyTouchesTheTargetAccountsFolders() {
        let root = URL(fileURLWithPath: "/L/Profiles/b", isDirectory: true)
        let entry = move([
            "/L/Profiles/b/ClaudeCode/projects/-p/1.jsonl",
            "/L/Profiles/b/Claude/claude-code-sessions/x/y/local_1.json",
            "/L/Profiles/a/ClaudeCode/projects/-p/1.jsonl",
            "/L/Profiles/b/../a/secret",
            "/L/Profiles/b",
            "/L/Profiles/bb/x",
        ])
        XCTAssertEqual(entry.removablePaths(allowedRoots: [root]), [
            "/L/Profiles/b/ClaudeCode/projects/-p/1.jsonl",
            "/L/Profiles/b/Claude/claude-code-sessions/x/y/local_1.json",
        ])
        XCTAssertTrue(entry.removablePaths(allowedRoots: []).isEmpty)
    }

    func testKeepsTheNewestMovesAndRoundTrips() {
        var moves: [SessionMove] = []
        for index in 0..<(SessionMoveLog.limit + 5) {
            moves = SessionMoveLog.adding(move(date: TimeInterval(index)), to: moves)
        }
        XCTAssertEqual(moves.count, SessionMoveLog.limit)
        XCTAssertEqual(moves.first?.date, Date(timeIntervalSince1970: TimeInterval(SessionMoveLog.limit + 4)))
        XCTAssertEqual(SessionMoveLog.decode(SessionMoveLog.encode(moves)), moves)
        XCTAssertTrue(SessionMoveLog.decode(Data("bozuk".utf8)).isEmpty)
        XCTAssertTrue(SessionMoveLog.decode(nil).isEmpty)
    }
}
