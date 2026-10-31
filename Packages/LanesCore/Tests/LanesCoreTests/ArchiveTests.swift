import XCTest
@testable import LanesCore

final class ArchiveTests: XCTestCase {
    private func library() -> ProfileLibrary {
        ProfileLibrary(profiles: [
            Profile(id: ProfileID(rawValue: "main"), name: "Ana", color: .blue, isDefault: true),
            Profile(id: ProfileID(rawValue: "a"), name: "A", color: .green),
            Profile(id: ProfileID(rawValue: "b"), name: "B", color: .red),
            Profile(id: ProfileID(rawValue: "c"), name: "C", color: .teal),
        ])
    }

    func testArchivedAccountsLeaveShortcutNumbers() throws {
        var lib = library()
        try lib.setArchived(ProfileID(rawValue: "a"), true)
        XCTAssertEqual(lib.activeProfiles.map(\.name), ["Ana", "B", "C"])
        XCTAssertEqual(lib.archivedProfiles.map(\.name), ["A"])
        XCTAssertNil(lib.shortcutNumber(for: ProfileID(rawValue: "a")))
        XCTAssertEqual(lib.shortcutNumber(for: ProfileID(rawValue: "b")), 2)
        try lib.setArchived(ProfileID(rawValue: "a"), false)
        XCTAssertEqual(lib.shortcutNumber(for: ProfileID(rawValue: "a")), 2)
    }

    func testDefaultAccountCannotBeArchived() throws {
        var lib = library()
        try lib.setArchived(ProfileID(rawValue: "main"), true)
        XCTAssertFalse(lib.profiles[0].isArchived)
        XCTAssertThrowsError(try lib.setArchived(ProfileID(rawValue: "x"), true))
    }

    func testReorderActiveKeepsArchivedAtTheEnd() throws {
        var lib = library()
        try lib.setArchived(ProfileID(rawValue: "a"), true)
        lib.reorderActive([ProfileID(rawValue: "c"), ProfileID(rawValue: "main")])
        XCTAssertEqual(lib.profiles.map(\.name), ["C", "Ana", "B", "A"])
    }

    func testArchiveFlagRoundTripsAndStaysOutWhenFalse() throws {
        var profile = Profile(name: "A", color: .green)
        let plain = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        XCTAssertFalse(plain.contains("isArchived"))
        profile.isArchived = true
        let decoded = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(profile))
        XCTAssertTrue(decoded.isArchived)
    }
}
