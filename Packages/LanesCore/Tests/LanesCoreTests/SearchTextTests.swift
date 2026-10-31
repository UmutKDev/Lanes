import XCTest
@testable import LanesCore

final class SearchTextTests: XCTestCase {
    func testTurkishDottedAndDotlessI() {
        XCTAssertTrue(SearchText.matches("ikinci", in: ["İkinci Hesap"]))
        XCTAssertTrue(SearchText.matches("IKINCI", in: ["İkinci Hesap"]))
        XCTAssertTrue(SearchText.matches("isik", in: ["Işık"]))
        XCTAssertTrue(SearchText.matches("ışık", in: ["ISIK"]))
    }

    func testAccentsAndCaseIgnored() {
        XCTAssertTrue(SearchText.matches("musteri", in: ["", "Müşteri işleri"]))
        XCTAssertTrue(SearchText.matches("ÇALIŞMA", in: ["çalışma"]))
        XCTAssertFalse(SearchText.matches("zzz", in: ["İkinci Hesap"]))
    }

    func testEmptyQueryMatches() {
        XCTAssertTrue(SearchText.matches("  ", in: ["x"]))
    }
}
