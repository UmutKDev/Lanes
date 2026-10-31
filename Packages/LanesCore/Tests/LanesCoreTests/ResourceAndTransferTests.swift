import XCTest
@testable import LanesCore

final class IdleQuitTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 100_000)

    func testQuitsOnlyAfterTheChosenTimeWhenIdle() {
        let lastActive = now.addingTimeInterval(-31 * 60)
        XCTAssertTrue(IdleQuitPolicy.shouldQuit(idleMinutes: 30, lastActive: lastActive, now: now, isFrontmost: false, cpuPercent: 0.5))
        XCTAssertFalse(IdleQuitPolicy.shouldQuit(idleMinutes: 60, lastActive: lastActive, now: now, isFrontmost: false, cpuPercent: 0.5))
    }

    func testNeverQuitsWhenOffFrontBusyOrUnmeasured() {
        let lastActive = now.addingTimeInterval(-5 * 3600)
        XCTAssertFalse(IdleQuitPolicy.shouldQuit(idleMinutes: nil, lastActive: lastActive, now: now, isFrontmost: false, cpuPercent: 0))
        XCTAssertFalse(IdleQuitPolicy.shouldQuit(idleMinutes: 30, lastActive: lastActive, now: now, isFrontmost: true, cpuPercent: 0))
        XCTAssertFalse(IdleQuitPolicy.shouldQuit(idleMinutes: 30, lastActive: lastActive, now: now, isFrontmost: false, cpuPercent: 12))
        XCTAssertFalse(IdleQuitPolicy.shouldQuit(idleMinutes: 30, lastActive: lastActive, now: now, isFrontmost: false, cpuPercent: nil))
    }

    func testIdleMinutesRoundTripAndAreOmittedWhenUnset() throws {
        var profile = Profile(name: "İş", color: .blue)
        let plain = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertFalse(plain.contains("idleQuitMinutes"))
        profile.idleQuitMinutes = 60
        let decoded = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.idleQuitMinutes, 60)
    }
}

final class ProcessTreeTests: XCTestCase {
    func testGroupsHelpersUnderTheirRoot() {
        // 100 and 200 are two Claudes; 101, 102 helpers of 100; 103 a
        // grandchild; 300 belongs to neither.
        let parents: [Int32: Int32] = [100: 1, 101: 100, 102: 100, 103: 102, 200: 1, 201: 200, 300: 1]
        let groups = ProcessTree.groups(roots: [100, 200], parents: parents)
        XCTAssertEqual(groups[100], [100, 101, 102, 103])
        XCTAssertEqual(groups[200], [200, 201])
    }

    func testSurvivesAParentLoop() {
        let groups = ProcessTree.groups(roots: [10], parents: [10: 1, 20: 30, 30: 20])
        XCTAssertEqual(groups[10], [10])
    }
}

final class LibraryTransferTests: XCTestCase {
    func testExportLeavesOutTheClaudeAppAccountAndWindowPlaces() throws {
        let claudeApp = Profile(name: "Claude uygulaması", color: .gray, isDefault: true)
        let work = Profile(name: "İş", color: .blue, mode: .signedClone)
        let scene = ProfileScene(name: "Sabah", profileIDs: [claudeApp.id, work.id], windowFrames: [work.id.rawValue: SceneWindowFrame(x: 0, y: 0, width: 10, height: 10)])
        let library = ProfileLibrary(profiles: [claudeApp, work], scenes: [scene])

        let export = LibraryExport(library: library)
        XCTAssertEqual(export.profiles.map(\.id), [work.id])
        XCTAssertEqual(export.scenes.first?.profileIDs, [work.id])
        XCTAssertEqual(export.scenes.first?.windowFrames, [:])

        let decoded = try LibraryExport.decode(try export.encoded())
        XCTAssertEqual(decoded.profiles.map(\.name), ["İş"])
    }

    func testMergeAddsOnlyWhatIsMissingAndTwiceChangesNothing() throws {
        let work = Profile(name: "İş", color: .blue)
        let client = Profile(name: "Müşteri", color: .green)
        let scene = ProfileScene(name: "Sabah", profileIDs: [work.id, client.id])
        let export = LibraryExport(library: ProfileLibrary(profiles: [work, client], scenes: [scene]))

        var renamed = work
        renamed.rename(to: "İş (bu Mac)")
        let target = ProfileLibrary(profiles: [renamed])
        let first = export.merge(into: target)
        XCTAssertEqual(first.addedProfiles, 1)
        XCTAssertEqual(first.addedScenes, 1)
        XCTAssertEqual(first.library.profile(withID: work.id)?.name, "İş (bu Mac)")

        let second = export.merge(into: first.library)
        XCTAssertEqual(second.addedProfiles, 0)
        XCTAssertEqual(second.addedScenes, 0)
        XCTAssertEqual(second.library, first.library)
    }

    func testRejectsOtherJSON() {
        XCTAssertThrowsError(try LibraryExport.decode(Data(#"{"kind":"x","version":1,"exportedAt":"2026-10-31T00:00:00Z","profiles":[],"scenes":[]}"#.utf8))) { error in
            XCTAssertEqual(error as? LibraryTransferError, .notAnExport)
        }
    }
}

final class IdleQuitDescriptionTests: XCTestCase {
    func testDescribesMinutesAndHours() {
        XCTAssertEqual(IdleQuitPolicy.describe(minutes: 30), "30 dakika")
        XCTAssertEqual(IdleQuitPolicy.describe(minutes: 120), "2 saat")
    }
}
