import Foundation
import XCTest
@testable import LanesCore

final class ProfileIdentityTests: XCTestCase {
    func testOptionalFieldsAreWrittenOnlyWhenSet() throws {
        let plain = Profile(id: ProfileID(rawValue: "p"), name: "İş", color: .blue)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        XCTAssertFalse(json.contains("email"))
        XCTAssertFalse(json.contains("allowedFolders"))

        var detailed = plain
        detailed.email = "is@example.com"
        detailed.note = "Müşteri işleri"
        detailed.allowedFolders = ["/Users/umut/Projeler/Müşteri"]
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(detailed))
        XCTAssertEqual(decoded.email, "is@example.com")
        XCTAssertEqual(decoded.note, "Müşteri işleri")
        XCTAssertEqual(decoded.allowedFolders, ["/Users/umut/Projeler/Müşteri"])
    }

    func testAllowedFolders() {
        var profile = Profile(name: "Müşteri", color: .pink)
        XCTAssertTrue(profile.allowsFolder("/anywhere"), "no list means anywhere")
        profile.allowedFolders = ["/Users/umut/Müşteri/"]
        XCTAssertTrue(profile.allowsFolder("/Users/umut/Müşteri"))
        XCTAssertTrue(profile.allowsFolder("/Users/umut/Müşteri/app/src"))
        XCTAssertFalse(profile.allowsFolder("/Users/umut/Müşteri-2"))
        XCTAssertFalse(profile.allowsFolder("/Users/umut"))
    }
}
