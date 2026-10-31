import Foundation
import XCTest
@testable import LanesCore

final class CloneRecordTests: XCTestCase {
    let profile = Profile(id: ProfileID(rawValue: "c"), name: "İş", color: .purple, mode: .signedClone)

    func testStandardAndMainAccountNeedNoClone() {
        let standard = Profile(name: "Standart", color: .blue)
        XCTAssertEqual(CloneCheck.status(for: standard, bundleName: nil, record: nil, claudeVersion: "1"), .notNeeded)
        let main = Profile(name: "Ana", color: .blue, mode: .signedClone, isDefault: true)
        XCTAssertEqual(CloneCheck.status(for: main, bundleName: nil, record: nil, claudeVersion: "1"), .notNeeded)
    }

    func testMissingAndReady() {
        XCTAssertEqual(CloneCheck.status(for: profile, bundleName: nil, record: nil, claudeVersion: "1"), .missing)
        let record = CloneRecord(profile: profile, claudeVersion: "1")
        XCTAssertEqual(CloneCheck.status(for: profile, bundleName: "Claude – İş.app", record: record, claudeVersion: "1"), .ready)
        XCTAssertEqual(CloneCheck.status(for: profile, bundleName: "Claude – İş.app", record: record, claudeVersion: nil), .ready,
                       "an unknown Claude version is no reason to renew")
    }

    func testRenewalReasons() {
        let record = CloneRecord(claudeVersion: "1", name: "Eski", color: .red, monogram: "E")
        XCTAssertEqual(
            CloneCheck.status(for: profile, bundleName: "Claude – Eski.app", record: record, claudeVersion: "2"),
            .needsRenewal([.claudeUpdated(from: "1", to: "2"), .renamed, .iconChanged])
        )
        XCTAssertEqual(CloneCheck.status(for: profile, bundleName: "Claude – İş.app", record: nil, claudeVersion: "2"), .needsRenewal([.unknownOrigin]))
        XCTAssertTrue(CloneStatus.missing.needsWork)
        XCTAssertFalse(CloneStatus.ready.needsWork)
    }

    func testDockSettingChangeRenewsTheClone() throws {
        let shown = CloneRecord(profile: profile, claudeVersion: "1")
        XCTAssertNil(shown.hiddenFromDock, "a clone in the Dock writes no flag, like older records")
        var hidden = profile
        hidden.hidesFromDock = true
        XCTAssertEqual(CloneCheck.status(for: hidden, bundleName: "Claude – İş.app", record: shown, claudeVersion: "1"), .needsRenewal([.dockSettingChanged]))
        let hiddenRecord = CloneRecord(profile: hidden, claudeVersion: "1")
        XCTAssertEqual(hiddenRecord.hiddenFromDock, true)
        XCTAssertEqual(CloneCheck.status(for: hidden, bundleName: "Claude – İş.app", record: hiddenRecord, claudeVersion: "1"), .ready)
        XCTAssertEqual(CloneCheck.status(for: profile, bundleName: "Claude – İş.app", record: hiddenRecord, claudeVersion: "1"), .needsRenewal([.dockSettingChanged]))
    }

    func testHidesFromDockIsWrittenOnlyWhenSet() throws {
        let plain = String(data: try JSONEncoder().encode(profile), encoding: .utf8) ?? ""
        XCTAssertFalse(plain.contains("hidesFromDock"))
        var hidden = profile
        hidden.hidesFromDock = true
        let decoded = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(hidden))
        XCTAssertTrue(decoded.hidesFromDock)
    }

    func testRecordRoundTrips() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clone.json")
        let record = CloneRecord(profile: profile, claudeVersion: "1.2", madeAt: Date(timeIntervalSince1970: 1_800_000_000))
        try record.write(to: url)
        XCTAssertEqual(CloneRecord.read(from: url), record)
        XCTAssertNil(CloneRecord.read(from: folder.appendingPathComponent("yok.json")))
    }
}

final class InsideLanesModeTests: XCTestCase {
    func testInsideLanesNeedsNoCloneAndNoClaudeApp() throws {
        let profile = Profile(name: "Web", color: .teal, mode: .insideLanes)
        XCTAssertFalse(CloneCheck.usesClone(profile))
        XCTAssertFalse(profile.mode.usesClaudeApp)
        XCTAssertTrue(ProfileMode.standard.usesClaudeApp)
        XCTAssertEqual(ProfileMode.insideLanes.rawValue, "lanes")
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: data).mode, .insideLanes)
    }
}
