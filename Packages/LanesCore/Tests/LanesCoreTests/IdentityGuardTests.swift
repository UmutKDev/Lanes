import Foundation
import XCTest
@testable import LanesCore

final class IdentityGuardTests: XCTestCase {
    func testDomainsAndAddresses() {
        var profile = Profile(name: "Müşteri", color: .blue)
        XCTAssertTrue(profile.expectsEmail("kim@nerede.com"), "No domain set: no check")
        profile.expectedEmailDomains = ["Musteri.com", " @ortak.io ", "ben@gmail.com"]
        XCTAssertTrue(profile.expectsEmail("Ali@MUSTERI.com"))
        XCTAssertTrue(profile.expectsEmail("ali@tr.musteri.com"), "Subdomain")
        XCTAssertFalse(profile.expectsEmail("ali@kotumusteri.com"), "Only a real subdomain")
        XCTAssertTrue(profile.expectsEmail("x@ortak.io"))
        XCTAssertTrue(profile.expectsEmail("ben@gmail.com"))
        XCTAssertFalse(profile.expectsEmail("sen@gmail.com"), "A whole address must match exactly")
        XCTAssertFalse(profile.expectsEmail("adres-yok"))
    }

    func testRoundTrip() throws {
        let profile = Profile(name: "İş", color: .blue, expectedEmailDomains: ["is.com"])
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.expectedEmailDomains, ["is.com"])
        let plain = try JSONEncoder().encode(Profile(name: "Boş", color: .gray))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("expectedEmailDomains"))
    }
}
