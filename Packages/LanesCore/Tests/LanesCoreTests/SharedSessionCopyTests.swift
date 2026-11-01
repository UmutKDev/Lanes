import Foundation
@testable import LanesCore
import XCTest

final class SharedSessionCopyTests: XCTestCase {
    private let mine = "6b1f2a3c-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let mineUpper = "AABBCCDD-1122-4334-8556-778899AABBCC"
    private let other = "0f0e0d0c-0b0a-4908-8706-050403020100"

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testFindsSessionNumbersInRecords() {
        let text = #"{"sessionId":"local_\#(mine)","cliSessionId":"\#(mineUpper)","cwd":"/x","n":"\#(mine)x"}"#
        XCTAssertEqual(SharedSessionCopy.uuids(in: Data(text.utf8)), [mine, mineUpper.lowercased()])
        XCTAssertEqual(SharedSessionCopy.uuids(in: Data("\(mine)".utf8)), [mine])
        XCTAssertTrue(SharedSessionCopy.uuids(in: Data("a\(mine)".utf8)).isEmpty)
        XCTAssertTrue(SharedSessionCopy.uuids(in: Data("\(mine)-1".utf8)).isEmpty)
        XCTAssertTrue(SharedSessionCopy.uuids(in: Data("not-a-uuid".utf8)).isEmpty)
        XCTAssertTrue(SharedSessionCopy.uuids(in: Data([0xff, 0xfe])).isEmpty)
    }

    func testReadsOnlyJSONRecordsUnderTheRecordsFolder() throws {
        let data = root.appendingPathComponent("Claude", isDirectory: true)
        let records = data.appendingPathComponent("claude-code-sessions/org/acct", isDirectory: true)
        try write(#"{"cliSessionId":"\#(mine)"}"#, to: records.appendingPathComponent("local_1.json"))
        try write(#"{"cliSessionId":"\#(other)"}"#, to: records.appendingPathComponent("notes.txt"))
        try write(#"{"cliSessionId":"\#(other)"}"#, to: data.appendingPathComponent("config.json"))
        XCTAssertEqual(SharedSessionCopy.sessionIDs(inDesktopData: data), [mine])
        XCTAssertTrue(SharedSessionCopy.sessionIDs(inDesktopData: root.appendingPathComponent("missing")).isEmpty)
    }

    func testCopiesOnlyTheAccountsSessionsAndNeverOverwrites() throws {
        let shared = root.appendingPathComponent("shared/projects", isDirectory: true)
        let target = root.appendingPathComponent("own/projects", isDirectory: true)
        let project = "-Users-u-Code-app"
        try write("mine", to: shared.appendingPathComponent("\(project)/\(mine).jsonl"))
        try write("side", to: shared.appendingPathComponent("\(project)/\(mine)/subagents/a.jsonl"))
        try write("upper", to: shared.appendingPathComponent("\(project)/\(mineUpper).jsonl"))
        try write("theirs", to: shared.appendingPathComponent("\(project)/\(other).jsonl"))
        try write("already", to: target.appendingPathComponent("\(project)/\(mineUpper).jsonl"))

        let ids: Set<String> = [mine, mineUpper.lowercased()]
        let items = SharedSessionCopy.plan(sessionIDs: ids, sharedProjects: shared, targetProjects: target)
        XCTAssertEqual(items.map(\.handoff.destinationFile.lastPathComponent), ["\(mine).jsonl"])
        XCTAssertEqual(items.first?.hasFolder, true)

        let result = SharedSessionCopy.copy(items)
        XCTAssertEqual(result.copied, 1)
        XCTAssertEqual(result.failed, 0)
        let copied = target.appendingPathComponent(project)
        XCTAssertEqual(try String(contentsOf: copied.appendingPathComponent("\(mine).jsonl"), encoding: .utf8), "mine")
        XCTAssertEqual(try String(contentsOf: copied.appendingPathComponent("\(mine)/subagents/a.jsonl"), encoding: .utf8), "side")
        XCTAssertEqual(try String(contentsOf: copied.appendingPathComponent("\(mineUpper).jsonl"), encoding: .utf8), "already")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.appendingPathComponent("\(other).jsonl").path))
        // The source stays.
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.appendingPathComponent("\(project)/\(mine).jsonl").path))
        // No partial copies are left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: copied.path).filter { $0.hasSuffix(".lanes-partial") }
        XCTAssertTrue(leftovers.isEmpty)
        // A second run finds nothing left to copy.
        XCTAssertTrue(SharedSessionCopy.plan(sessionIDs: ids, sharedProjects: shared, targetProjects: target).isEmpty)
    }

    func testSkipsSymlinksAndSameFolder() throws {
        let shared = root.appendingPathComponent("shared/projects", isDirectory: true)
        let target = root.appendingPathComponent("own/projects", isDirectory: true)
        let outside = root.appendingPathComponent("outside.jsonl")
        try write("secret", to: outside)
        try FileManager.default.createDirectory(at: shared.appendingPathComponent("p"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: shared.appendingPathComponent("p/\(mine).jsonl"), withDestinationURL: outside)
        XCTAssertTrue(SharedSessionCopy.plan(sessionIDs: [mine], sharedProjects: shared, targetProjects: target).isEmpty)

        try write("x", to: shared.appendingPathComponent("q/\(other).jsonl"))
        XCTAssertTrue(SharedSessionCopy.plan(sessionIDs: [other], sharedProjects: shared, targetProjects: shared).isEmpty)
        XCTAssertTrue(SharedSessionCopy.plan(sessionIDs: [], sharedProjects: shared, targetProjects: target).isEmpty)
    }

    func testFailedCopyLeavesNothingBehind() throws {
        let shared = root.appendingPathComponent("shared/projects", isDirectory: true)
        let target = root.appendingPathComponent("own/projects", isDirectory: true)
        try write("mine", to: shared.appendingPathComponent("p/\(mine).jsonl"))
        let items = SharedSessionCopy.plan(sessionIDs: [mine], sharedProjects: shared, targetProjects: target)
        XCTAssertEqual(items.count, 1)
        // The source disappears between planning and copying.
        try FileManager.default.removeItem(at: shared.appendingPathComponent("p/\(mine).jsonl"))
        let result = SharedSessionCopy.copy(items)
        XCTAssertEqual(result.copied, 0)
        XCTAssertEqual(result.failed, 1)
        let folder = target.appendingPathComponent("p")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
    }
}
