import Foundation
import XCTest
@testable import LanesCore

final class ProfileTests: XCTestCase {
    func testMonogramUsesTurkishCasing() {
        XCTAssertEqual(Profile.defaultMonogram(for: "işler"), "İ")
        XCTAssertEqual(Profile.defaultMonogram(for: "  ırmak"), "I")
        XCTAssertEqual(Profile.defaultMonogram(for: "Kişisel"), "K")
        XCTAssertEqual(Profile.defaultMonogram(for: "   "), "?")
    }

    func testExplicitMonogramWins() {
        let profile = Profile(name: "Müşteri", monogram: "AC", color: .teal)
        XCTAssertEqual(profile.monogram, "AC")
    }
}

final class ProfilePathsTests: XCTestCase {
    let paths = ProfilePaths.standard(home: URL(fileURLWithPath: "/Users/umut", isDirectory: true))

    func testStandardLayout() {
        XCTAssertEqual(paths.root.path, "/Users/umut/Library/Application Support/Lanes")
        XCTAssertEqual(paths.profilesFile.path, "/Users/umut/Library/Application Support/Lanes/profiles.json")
        XCTAssertEqual(paths.clonesDirectory.path, "/Users/umut/Applications/Lanes Profiles")
    }

    func testDefaultProfileUsesClaudesOwnFolders() {
        let profile = Profile(name: "Kişisel", color: .blue, isDefault: true)
        XCTAssertNil(paths.desktopDataDirectory(for: profile))
        XCTAssertNil(paths.claudeCodeConfigDirectory(for: profile))
        XCTAssertEqual(paths.effectiveDesktopDataDirectory(for: profile).path, "/Users/umut/Library/Application Support/Claude")
        XCTAssertEqual(paths.effectiveClaudeCodeConfigDirectory(for: profile).path, "/Users/umut/.claude")
    }

    func testOtherProfilesGetFoldersNamedByID() {
        let profile = Profile(id: ProfileID(rawValue: "abc"), name: "İş", color: .orange)
        XCTAssertEqual(paths.desktopDataDirectory(for: profile)?.path, "/Users/umut/Library/Application Support/Lanes/Profiles/abc/Claude")
        XCTAssertEqual(paths.claudeCodeConfigDirectory(for: profile)?.path, "/Users/umut/Library/Application Support/Lanes/Profiles/abc/ClaudeCode")
    }

    func testCloneBundleNameIsSafe() {
        let profile = Profile(name: "Müşteri/A: B", color: .pink)
        XCTAssertEqual(paths.cloneBundle(for: profile).lastPathComponent, "Claude – Müşteri-A- B.app")
        XCTAssertEqual(ProfilePaths.safeFileName(".gizli"), "gizli")
        XCTAssertEqual(ProfilePaths.safeFileName("  "), "Profil")
    }
}

final class ProfileStoreTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LanesCoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileLoadsEmptyLibrary() throws {
        let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        XCTAssertEqual(try store.load(), ProfileLibrary())
    }

    func testRoundTrip() throws {
        let store = ProfileStore(fileURL: directory.appendingPathComponent("nested/profiles.json"))
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        var library = ProfileLibrary()
        try library.add(Profile(name: "Kişisel", color: .blue, isDefault: true, createdAt: created))
        try library.add(Profile(name: "İş", color: .orange, mode: .signedClone, accountClass: .employer, createdAt: created))
        try store.save(library)
        XCTAssertEqual(try store.load(), library)
    }

    func testRejectsSecondDefault() throws {
        var library = ProfileLibrary()
        try library.add(Profile(name: "A", color: .blue, isDefault: true))
        XCTAssertThrowsError(try library.add(Profile(name: "B", color: .red, isDefault: true))) { error in
            XCTAssertEqual(error as? ProfileStoreError, .moreThanOneDefault)
        }
    }

    func testRejectsDuplicateIDs() throws {
        let id = ProfileID(rawValue: "same")
        var library = ProfileLibrary()
        try library.add(Profile(id: id, name: "A", color: .blue))
        XCTAssertThrowsError(try library.add(Profile(id: id, name: "B", color: .red)))
    }

    func testRejectsNewerFileVersion() throws {
        let url = directory.appendingPathComponent("profiles.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version": 99, "profiles": []}"#.utf8).write(to: url)
        XCTAssertThrowsError(try ProfileStore(fileURL: url).load()) { error in
            XCTAssertEqual(error as? ProfileStoreError, .unsupportedVersion(99))
        }
    }

    func testSaveMovesUnreadableFileAside() throws {
        let url = directory.appendingPathComponent("profiles.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unreadable = Data(#"{"version": 99, "profiles": []}"#.utf8)
        try unreadable.write(to: url)
        let store = ProfileStore(fileURL: url)
        var library = ProfileLibrary()
        try library.add(Profile(name: "Yeni", color: .blue, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))

        let setAside = try XCTUnwrap(try store.save(library))

        XCTAssertEqual(try Data(contentsOf: setAside), unreadable)
        XCTAssertTrue(setAside.lastPathComponent.hasPrefix("profiles-unreadable-"))
        XCTAssertEqual(setAside.pathExtension, "json")
        XCTAssertEqual(setAside.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(try store.load(), library)
    }

    func testSaveKeepsEachUnreadableCopy() throws {
        let url = directory.appendingPathComponent("profiles.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProfileStore(fileURL: url)
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        try Data("first".utf8).write(to: url)
        let first = try XCTUnwrap(try store.save(ProfileLibrary(), now: now))
        try Data("second".utf8).write(to: url)
        let second = try XCTUnwrap(try store.save(ProfileLibrary(), now: now))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
    }

    func testSaveOverReadableFileMovesNothing() throws {
        let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        var library = ProfileLibrary()
        XCTAssertNil(try store.save(library))
        try library.add(Profile(name: "A", color: .blue))
        XCTAssertNil(try store.save(library))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["profiles.json"])
    }

    func testMoveAssignsShortcuts() throws {
        var library = ProfileLibrary()
        let a = Profile(name: "A", color: .blue)
        let b = Profile(name: "B", color: .red)
        let c = Profile(name: "C", color: .green)
        try library.add(a)
        try library.add(b)
        try library.add(c)
        try library.move(c.id, to: 0)
        XCTAssertEqual(library.profiles.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(library.shortcutNumber(for: c.id), 1)
        XCTAssertEqual(library.shortcutNumber(for: b.id), 3)
        try library.move(c.id, to: 99)
        XCTAssertEqual(library.profiles.map(\.name), ["A", "B", "C"])
    }

    func testOnlyFirstNineGetShortcuts() throws {
        var library = ProfileLibrary()
        for index in 0..<10 {
            try library.add(Profile(name: "P\(index)", color: .gray))
        }
        XCTAssertEqual(library.shortcutNumber(for: library.profiles[8].id), 9)
        XCTAssertNil(library.shortcutNumber(for: library.profiles[9].id))
    }
}
