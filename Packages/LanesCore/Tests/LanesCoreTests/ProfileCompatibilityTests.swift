import Foundation
import XCTest
@testable import LanesCore

/// `profiles.json` has to stay readable across Lanes versions, in both
/// directions within a file version: a newer build reads what an older one
/// wrote, and an older build keeps what a newer one added.
final class ProfileCompatibilityTests: XCTestCase {
    /// A version 1 file exactly as Lanes 0.1.0 writes it. Never edit this
    /// string: a change that needs a different file needs a new version and a
    /// new frozen file next to this one.
    static let versionOneFile = """
    {
      "profiles" : [
        {
          "accountClass" : "personal",
          "color" : "orange",
          "createdAt" : "2026-10-04T22:10:00Z",
          "id" : "0f3c9a52-1d2e-4b7a-9c11-000000000001",
          "isDefault" : true,
          "mode" : "standard",
          "monogram" : "A",
          "name" : "Ana hesap"
        },
        {
          "accountClass" : "employer",
          "color" : "blue",
          "createdAt" : "2026-10-04T22:12:30Z",
          "id" : "0f3c9a52-1d2e-4b7a-9c11-000000000002",
          "isDefault" : false,
          "mode" : "signedClone",
          "monogram" : "İ",
          "name" : "İş"
        }
      ],
      "version" : 1
    }
    """

    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LanesCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func store(with contents: String) throws -> ProfileStore {
        let url = directory.appendingPathComponent("profiles.json")
        try Data(contents.utf8).write(to: url)
        return ProfileStore(fileURL: url)
    }

    func jsonObject(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    func testReadsTheFrozenVersionOneFile() throws {
        let library = try store(with: Self.versionOneFile).load()

        XCTAssertEqual(library.version, 1)
        XCTAssertEqual(library.profiles.count, 2)
        let main = library.profiles[0]
        XCTAssertEqual(main.id, ProfileID(rawValue: "0f3c9a52-1d2e-4b7a-9c11-000000000001"))
        XCTAssertEqual(main.name, "Ana hesap")
        XCTAssertEqual(main.monogram, "A")
        XCTAssertEqual(main.color, .orange)
        XCTAssertEqual(main.mode, .standard)
        XCTAssertEqual(main.accountClass, .personal)
        XCTAssertTrue(main.isDefault)
        XCTAssertEqual(main.createdAt, ISO8601DateFormatter().date(from: "2026-10-04T22:10:00Z"))
        let work = library.profiles[1]
        XCTAssertEqual(work.name, "İş")
        XCTAssertEqual(work.monogram, "İ")
        XCTAssertEqual(work.mode, .signedClone)
        XCTAssertEqual(work.accountClass, .employer)
        XCTAssertFalse(work.isDefault)
    }

    func testWritesTheSameFieldsItRead() throws {
        let library = try store(with: Self.versionOneFile).load()
        let written = try ProfileStore.encoder.encode(library)
        XCTAssertEqual(try jsonObject(written), try jsonObject(Data(Self.versionOneFile.utf8)))
    }

    func testMissingFieldsGetDefaults() throws {
        let library = try store(with: #"{"profiles": [{"id": "a"}]}"#).load()

        XCTAssertEqual(library.version, 1)
        let profile = try XCTUnwrap(library.profiles.first)
        XCTAssertEqual(profile.id, ProfileID(rawValue: "a"))
        XCTAssertEqual(profile.name, "Adsız hesap")
        XCTAssertEqual(profile.monogram, "A")
        XCTAssertEqual(profile.color, .gray)
        XCTAssertEqual(profile.mode, .standard)
        XCTAssertEqual(profile.accountClass, .personal)
        XCTAssertFalse(profile.isDefault)
        XCTAssertEqual(profile.createdAt, Date(timeIntervalSince1970: 0))
    }

    func testEmptyFileObjectIsAnEmptyList() throws {
        XCTAssertEqual(try store(with: "{}").load(), ProfileLibrary())
    }

    func testProfileWithoutIDIsRejected() throws {
        XCTAssertThrowsError(try store(with: #"{"version": 1, "profiles": [{"name": "A"}]}"#).load())
    }

    func testNewerFileIsReadAndItsAdditionsAreKept() throws {
        let newer = """
        {
          "version": 1,
          "rules": [{"kind": "new", "profile": "b"}],
          "profiles": [
            {
              "id": "b",
              "name": "Müşteri",
              "monogram": "M",
              "color": "magenta",
              "mode": "sandbox",
              "accountClass": "partner",
              "isDefault": "yes",
              "createdAt": 1790000000,
              "labels": {"email": "m@example.com", "plan": null, "seats": 3, "pinned": true}
            }
          ]
        }
        """
        let store = try store(with: newer)
        let library = try store.load()

        let profile = try XCTUnwrap(library.profiles.first)
        XCTAssertEqual(profile.name, "Müşteri")
        XCTAssertEqual(profile.color, .gray)
        XCTAssertEqual(profile.mode, .standard)
        XCTAssertEqual(profile.accountClass, .personal)
        XCTAssertFalse(profile.isDefault)
        XCTAssertEqual(profile.createdAt, Date(timeIntervalSince1970: 0))

        XCTAssertNil(try store.save(library))
        let saved = try jsonObject(Data(contentsOf: store.fileURL))
        XCTAssertEqual(saved, try jsonObject(Data(newer.utf8)))
    }

    func testKeptNumbersAreWrittenBackExactly() throws {
        let numbers = ["9007199254740993", "9223372036854775807", "-9223372036854775808", "18446744073709551615", "0.1", "1.5"]
        let list = numbers.joined(separator: ", ")
        let newer = #"{"version": 1, "counters": [\#(list)], "profiles": [{"id": "d", "name": "D", "counters": [\#(list)]}]}"#
        let store = try store(with: newer)

        XCTAssertNil(try store.save(store.load()))

        let saved = try String(contentsOf: store.fileURL, encoding: .utf8)
        for number in numbers {
            XCTAssertEqual(saved.components(separatedBy: number).count - 1, 2, "\(number) was not written back as it was read")
        }
    }

    func testRenamingLeavesAnUnreadableMonogramAsItWas() throws {
        var library = try store(with: #"{"profiles": [{"id": "e", "name": "Ali", "monogram": {"emoji": "x"}}]}"#).load()
        var profile = try XCTUnwrap(library.profiles.first)
        XCTAssertEqual(profile.monogram, "A")

        profile.rename(to: "Burak")
        try library.update(profile)

        XCTAssertEqual(profile.name, "Burak")
        XCTAssertEqual(profile.monogram, "B")
        let saved = try jsonObject(ProfileStore.encoder.encode(library))
        let savedProfile = try XCTUnwrap((saved["profiles"] as? [NSDictionary])?.first)
        XCTAssertEqual(savedProfile["name"] as? String, "Burak")
        XCTAssertEqual(savedProfile["monogram"] as? NSDictionary, ["emoji": "x"])
    }

    func testRenamingMovesOnlyAMonogramThatFollowedTheName() {
        var following = Profile(name: "Ali", color: .blue)
        following.rename(to: "işler")
        XCTAssertEqual(following.monogram, "İ")

        var chosen = Profile(name: "Ali", monogram: "Q", color: .blue)
        chosen.rename(to: "Burak")
        XCTAssertEqual(chosen.monogram, "Q")
    }

    func testChangingAKeptFieldWritesTheNewValue() throws {
        let store = try store(with: #"{"version": 1, "profiles": [{"id": "c", "name": "C", "color": "magenta", "mode": "sandbox"}]}"#)
        var library = try store.load()
        var profile = try XCTUnwrap(library.profiles.first)
        profile.color = .teal
        try library.update(profile)

        try store.save(library)
        let saved = try jsonObject(Data(contentsOf: store.fileURL))
        let savedProfile = try XCTUnwrap((saved["profiles"] as? [NSDictionary])?.first)
        XCTAssertEqual(savedProfile["color"] as? String, "teal")
        XCTAssertEqual(savedProfile["mode"] as? String, "sandbox")
        XCTAssertEqual(try store.load().profiles.first?.color, .teal)
    }

    func testSharedClaudeCodeFlagRoundTrips() throws {
        let store = try store(with: #"{"version": 1, "profiles": [{"id": "s", "name": "S", "usesSharedClaudeCode": true}]}"#)
        let library = try store.load()
        XCTAssertTrue(try XCTUnwrap(library.profiles.first).usesSharedClaudeCode)
        XCTAssertNil(try store.save(library))
        let saved = try jsonObject(Data(contentsOf: store.fileURL))
        let profile = try XCTUnwrap((saved["profiles"] as? [NSDictionary])?.first)
        XCTAssertEqual(profile["usesSharedClaudeCode"] as? Bool, true)
    }

    func testSharedClaudeCodeFlagIsFalseAndUnwrittenWhenAbsent() throws {
        let library = try store(with: Self.versionOneFile).load()
        XCTAssertFalse(library.profiles.contains(where: \.usesSharedClaudeCode))
        let written = try String(decoding: ProfileStore.encoder.encode(library), as: UTF8.self)
        XCTAssertFalse(written.contains("usesSharedClaudeCode"))
    }

    func testSharedClaudeCodeFlagOfAnotherTypeIsKeptNextToUnknownFields() throws {
        let newer = #"{"version": 1, "profiles": [{"id": "s", "name": "S", "usesSharedClaudeCode": "yes", "future": {"a": 1}}]}"#
        let store = try store(with: newer)
        let library = try store.load()
        XCTAssertFalse(try XCTUnwrap(library.profiles.first).usesSharedClaudeCode)
        XCTAssertNil(try store.save(library))
        let saved = try jsonObject(Data(contentsOf: store.fileURL))
        let profile = try XCTUnwrap((saved["profiles"] as? [NSDictionary])?.first)
        XCTAssertEqual(profile["usesSharedClaudeCode"] as? String, "yes")
        XCTAssertEqual(profile["future"] as? NSDictionary, ["a": 1])

        var changed = try XCTUnwrap(library.profiles.first)
        changed.usesSharedClaudeCode = true
        let rewritten = try jsonObject(ProfileStore.encoder.encode(changed))
        XCTAssertEqual(rewritten["usesSharedClaudeCode"] as? Bool, true)
    }
}

final class ProfileStartupTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LanesCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    var fileURL: URL {
        directory.appendingPathComponent("profiles.json")
    }

    func testFirstLaunchStartsEmpty() throws {
        let startup = ProfileStore(fileURL: fileURL).startup()

        XCTAssertTrue(startup.isFirstLaunch)
        XCTAssertNil(startup.loadError)
        XCTAssertTrue(startup.library.profiles.isEmpty, "Claude's own account is not Lanes's")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testEmptyListCountsAsFirstLaunch() throws {
        try ProfileStore(fileURL: fileURL).save(ProfileLibrary())
        let startup = ProfileStore(fileURL: fileURL).startup()
        XCTAssertTrue(startup.isFirstLaunch)
        XCTAssertTrue(startup.library.profiles.isEmpty)
    }

    func testReadableListIsUsedAsItIs() throws {
        var library = ProfileLibrary()
        try library.add(Profile(name: "Kişisel", color: .blue, mode: .signedClone, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try library.add(Profile(name: "İş", color: .orange, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try ProfileStore(fileURL: fileURL).save(library)

        let startup = ProfileStore(fileURL: fileURL).startup()

        XCTAssertFalse(startup.isFirstLaunch)
        XCTAssertNil(startup.loadError)
        XCTAssertFalse(startup.addedClaudeAppAccount)
        XCTAssertEqual(startup.library, library)
    }

    func testUnreadableListIsNeverReplacedByANewOne() throws {
        try Data(#"{"version": 99, "profiles": []}"#.utf8).write(to: fileURL)

        let startup = ProfileStore(fileURL: fileURL).startup()

        XCTAssertFalse(startup.isFirstLaunch)
        XCTAssertEqual(startup.loadError as? ProfileStoreError, .unsupportedVersion(99))
        XCTAssertTrue(startup.library.profiles.isEmpty)
        XCTAssertFalse(startup.restoredFromBackup)
    }

    func testSaveKeepsThePreviousReadableListAsBackup() throws {
        let store = ProfileStore(fileURL: fileURL)
        var first = ProfileLibrary()
        try first.add(Profile(name: "Ana hesap", color: .orange, isDefault: true, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try store.save(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.backupURL.path))

        var second = first
        try second.add(Profile(name: "İş", color: .blue, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try store.save(second)

        XCTAssertEqual(store.backupURL.lastPathComponent, "profiles.backup.json")
        XCTAssertEqual(try ProfileStore(fileURL: store.backupURL).load(), first)
        XCTAssertEqual(try store.load(), second)
    }

    func testUnreadableFileIsNeverCopiedToBackup() throws {
        let store = ProfileStore(fileURL: fileURL)
        var library = ProfileLibrary()
        try library.add(Profile(name: "Ana hesap", color: .orange, isDefault: true, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try store.save(library)
        try store.save(library)
        try Data("bozuk".utf8).write(to: fileURL)

        try store.save(library)

        XCTAssertEqual(try ProfileStore(fileURL: store.backupURL).load(), library)
    }

    func testUnreadableListIsRestoredFromBackup() throws {
        let store = ProfileStore(fileURL: fileURL)
        var library = ProfileLibrary()
        try library.add(Profile(name: "Kişisel", color: .orange, mode: .signedClone, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try library.add(Profile(name: "İş", color: .blue, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try store.save(library)
        try store.save(library)
        try Data("bozuk".utf8).write(to: fileURL)

        let startup = store.startup()

        XCTAssertTrue(startup.restoredFromBackup)
        XCTAssertNotNil(startup.loadError)
        XCTAssertFalse(startup.isFirstLaunch)
        XCTAssertEqual(startup.library, library)
        // The unreadable file waits for the next save to move it aside.
        XCTAssertEqual(try Data(contentsOf: fileURL), Data("bozuk".utf8))
    }

    func testClaudeAppAccountIsKeptAndAddedOnlyWhenItsFolderExists() throws {
        var library = ProfileLibrary()
        try library.add(Profile(name: "İş", color: .blue, mode: .signedClone, createdAt: Date(timeIntervalSince1970: 1_790_000_000)))
        try ProfileStore(fileURL: fileURL).save(library)

        let without = ProfileStore(fileURL: fileURL).startup()
        XCTAssertFalse(without.addedClaudeAppAccount)
        XCTAssertNil(without.library.defaultProfile)

        let with = ProfileStore(fileURL: fileURL).startup(claudeAppAccountName: "Claude uygulaması")
        XCTAssertTrue(with.addedClaudeAppAccount)
        XCTAssertFalse(with.isFirstLaunch)
        XCTAssertEqual(with.library.profiles.map(\.name), ["Claude uygulaması", "İş"])
        XCTAssertEqual(with.library.defaultProfile?.mode, .standard)
    }

    func testFirstLaunchWithClaudeShowsItsAccount() throws {
        let startup = ProfileStore(fileURL: fileURL).startup(claudeAppAccountName: "Claude uygulaması")
        XCTAssertTrue(startup.isFirstLaunch)
        XCTAssertEqual(startup.library.profiles.map(\.isDefault), [true])
    }

    func testUnreadableListGetsNoClaudeAppAccount() throws {
        try Data(#"{"version": 99, "profiles": []}"#.utf8).write(to: fileURL)
        let startup = ProfileStore(fileURL: fileURL).startup(claudeAppAccountName: "Claude uygulaması")
        XCTAssertTrue(startup.library.profiles.isEmpty)
    }
}
