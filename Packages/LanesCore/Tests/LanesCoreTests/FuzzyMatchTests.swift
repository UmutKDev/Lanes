import XCTest
@testable import LanesCore

final class FuzzyMatchTests: XCTestCase {
    func testMatchesInOrderOnly() {
        XCTAssertNotNil(FuzzyMatch.score("isc", in: "İş Claude"))
        XCTAssertNil(FuzzyMatch.score("csi", in: "İş Claude"))
        XCTAssertEqual(FuzzyMatch.score("  ", in: "anything"), 0)
    }

    func testTurkishLettersFold() {
        XCTAssertNotNil(FuzzyMatch.score("ikinci", in: "İkinci Hesap"))
        XCTAssertNotNil(FuzzyMatch.score("musteri", in: "Müşteri A"))
    }

    func testPrefixBeatsContainsBeatsScattered() throws {
        let prefix = try XCTUnwrap(FuzzyMatch.score("oturum", in: "Oturumlar"))
        let contains = try XCTUnwrap(FuzzyMatch.score("oturum", in: "Son Oturumlar"))
        let scattered = try XCTUnwrap(FuzzyMatch.score("otr", in: "Ofis Tarayıcı Rehberi"))
        XCTAssertGreaterThan(prefix, contains)
        XCTAssertGreaterThan(contains, scattered)
    }

    func testWordStartsBeatMiddleLetters() throws {
        let starts = try XCTUnwrap(FuzzyMatch.score("ih", in: "İkinci Hesap"))
        let middle = try XCTUnwrap(FuzzyMatch.score("ih", in: "Mihrap"))
        XCTAssertGreaterThan(starts, middle)
    }
}
