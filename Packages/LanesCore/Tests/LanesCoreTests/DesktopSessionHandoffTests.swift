import Foundation
@testable import LanesCore
import XCTest

final class DesktopSessionHandoffTests: XCTestCase {
    private let cli = "6b1f2a3c-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    private let prior = "0f0e0d0c-0b0a-4908-8706-050403020100"
    private let account = "11111111-2222-4333-8444-555555555555"
    private let org = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    private let otherOrg = "99999999-8888-4777-8666-555555555555"

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

    private func recordText(cliSessionID: String) -> String {
        #"{"sessionId":"local_x","cliSessionId":"\#(cliSessionID)","priorCliSessionIds":["\#(prior)"],"cwd":"/p","title":"t","isArchived":true,"isStarred":true,"createdAt":1,"lastActivityAt":2,"enabledMcpTools":{"a:b":true},"remoteMcpServersConfig":[{"uuid":"u"}],"alwaysAllowedReasons":["r"],"sessionPermissionUpdates":[1],"bridgeSessionIds":["cse_1"],"interruptedAwaitingPerson":null,"steeredByRemoteClient":null,"toolSurfaceSnapshot":{},"promptAppendSnapshot":{"append":""},"model":"m"}"#
    }

    func testFindsTheRecordByItsClaudeCodeSession() throws {
        let data = root.appendingPathComponent("Claude", isDirectory: true)
        let folder = data.appendingPathComponent("claude-code-sessions/\(account)/\(org)", isDirectory: true)
        try write(recordText(cliSessionID: prior), to: folder.appendingPathComponent("local_a.json"))
        try write(recordText(cliSessionID: cli.uppercased()), to: folder.appendingPathComponent("local_b.json"))
        try write(recordText(cliSessionID: cli), to: folder.appendingPathComponent("notes.json"))

        let found = DesktopSessionHandoff.findRecord(cliSessionID: cli, inDesktopData: data)
        XCTAssertEqual(found?.url.lastPathComponent, "local_b.json")
        XCTAssertNil(DesktopSessionHandoff.findRecord(cliSessionID: "12345678-1234-4234-8234-123456789012", inDesktopData: data))
        XCTAssertNil(DesktopSessionHandoff.findRecord(cliSessionID: cli, inDesktopData: root.appendingPathComponent("missing")))
    }

    func testPicksTheSignedInAccountsNewestOrganization() throws {
        let data = root.appendingPathComponent("Claude", isDirectory: true)
        let sessions = data.appendingPathComponent("claude-code-sessions", isDirectory: true)
        let old = sessions.appendingPathComponent("\(account)/\(otherOrg)", isDirectory: true)
        let new = sessions.appendingPathComponent("\(account)/\(org)", isDirectory: true)
        try write("{}", to: old.appendingPathComponent("local_1.json"))
        try write("{}", to: new.appendingPathComponent("local_2.json"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: old.appendingPathComponent("local_1.json").path)
        try FileManager.default.createDirectory(at: sessions.appendingPathComponent("not-a-uuid"), withIntermediateDirectories: true)

        XCTAssertEqual(DesktopSessionHandoff.recordsFolder(inDesktopData: data, accountUuid: account.uppercased())?.lastPathComponent, org)
        XCTAssertEqual(DesktopSessionHandoff.recordsFolder(inDesktopData: data, accountUuid: nil)?.lastPathComponent, org, "One account folder: it is used")
        XCTAssertNil(DesktopSessionHandoff.recordsFolder(inDesktopData: data, accountUuid: otherOrg))
        XCTAssertNil(DesktopSessionHandoff.recordsFolder(inDesktopData: root.appendingPathComponent("missing"), accountUuid: account))
    }

    func testTransplantLeavesOutTheSourceAccountsKeys() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(recordText(cliSessionID: cli).utf8)) as? [String: Any])
        let id = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let copy = DesktopSessionHandoff.transplant(object, localID: id, now: now)

        XCTAssertEqual(copy["sessionId"] as? String, "local_aaaaaaaa-0000-4000-8000-000000000001")
        XCTAssertEqual(copy["cliSessionId"] as? String, cli)
        XCTAssertEqual(copy["title"] as? String, "t")
        XCTAssertEqual(copy["model"] as? String, "m")
        XCTAssertEqual(copy["isArchived"] as? Bool, false)
        XCTAssertNil(copy["isStarred"])
        XCTAssertEqual((copy["lastActivityAt"] as? NSNumber)?.int64Value, 1_800_000_000_000)
        XCTAssertEqual((copy["createdAt"] as? NSNumber)?.intValue, 1)
        for key in ["enabledMcpTools", "bridgeSessionIds", "toolSurfaceSnapshot"] {
            XCTAssertNil(copy[key], key)
        }
        for key in ["remoteMcpServersConfig", "alwaysAllowedReasons", "sessionPermissionUpdates"] {
            XCTAssertEqual((copy[key] as? [Any])?.count, 0, key)
        }
        XCTAssertTrue(copy["interruptedAwaitingPerson"] is NSNull)
        XCTAssertNotNil(copy["promptAppendSnapshot"])
        XCTAssertEqual(DesktopSessionHandoff.fileName(localID: id), "local_aaaaaaaa-0000-4000-8000-000000000001.json")
    }

    func testWritesWholeRecordsAndNeverOverwrites() throws {
        let folder = root.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID()
        let url = try DesktopSessionHandoff.write(["sessionId": "local_1", "n": NSNumber(value: 2)], localID: id, into: folder)
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(back["sessionId"] as? String, "local_1")
        XCTAssertThrowsError(try DesktopSessionHandoff.write([:], localID: id, into: folder))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".lanes-partial") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testCopiesTheEarlierPartsOfTheConversation() throws {
        let data = root.appendingPathComponent("Claude", isDirectory: true)
        let folder = data.appendingPathComponent("claude-code-sessions/\(account)/\(org)", isDirectory: true)
        try write(recordText(cliSessionID: cli), to: folder.appendingPathComponent("local_a.json"))
        let source = root.appendingPathComponent("A/projects", isDirectory: true)
        let target = root.appendingPathComponent("B/projects", isDirectory: true)
        try write("", to: source.appendingPathComponent("-p/\(cli).jsonl"))
        try write("", to: source.appendingPathComponent("-p/\(prior).jsonl"))
        try write("", to: source.appendingPathComponent("-p/12345678-1234-4234-8234-123456789012.jsonl"))

        let record = try XCTUnwrap(DesktopSessionHandoff.findRecord(cliSessionID: cli, inDesktopData: data))
        let ids = DesktopSessionHandoff.relatedSessionIDs(record: record, mainSessionID: cli.uppercased())
        XCTAssertTrue(ids.contains(prior))
        XCTAssertFalse(ids.contains(cli))
        let items = SharedSessionCopy.plan(sessionIDs: ids, sharedProjects: source, targetProjects: target)
        XCTAssertEqual(items.map(\.handoff.destinationFile.lastPathComponent), ["\(prior).jsonl"])
    }

    func testReadsCodeTabTitles() throws {
        let data = root.appendingPathComponent("Claude", isDirectory: true)
        let folder = data.appendingPathComponent("claude-code-sessions/\(account)/\(org)", isDirectory: true)
        try write(#"{"cliSessionId":"\#(cli.uppercased())","title":" Haftalık rapor ","isArchived":false}"#, to: folder.appendingPathComponent("local_a.json"))
        try write(#"{"cliSessionId":"\#(prior)","title":"Eski","isArchived":true}"#, to: folder.appendingPathComponent("local_b.json"))
        try write(#"{"cliSessionId":"12345678-1234-4234-8234-123456789012","title":""}"#, to: folder.appendingPathComponent("local_c.json"))
        XCTAssertEqual(DesktopSessionHandoff.titles(inDesktopData: data), [cli: "Haftalık rapor"])
        XCTAssertTrue(DesktopSessionHandoff.titles(inDesktopData: root.appendingPathComponent("missing")).isEmpty)
    }
}
