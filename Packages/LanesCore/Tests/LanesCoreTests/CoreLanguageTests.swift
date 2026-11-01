import Foundation
import XCTest
@testable import LanesCore

/// LanesCore text in English. Each test sets the language and puts Turkish
/// back, which the other tests expect.
final class CoreLanguageTests: XCTestCase {
    override func tearDown() {
        CoreLanguage.current = .turkish
        super.tearDown()
    }

    func testLanguageFromLocalization() {
        XCTAssertEqual(CoreLanguage.from(localization: "en"), .english)
        XCTAssertEqual(CoreLanguage.from(localization: "en-GB"), .english)
        XCTAssertEqual(CoreLanguage.from(localization: "tr"), .turkish)
        XCTAssertEqual(CoreLanguage.from(localization: nil), .turkish)
    }

    func testDurationsInEnglish() {
        CoreLanguage.current = .english
        XCTAssertEqual(Timesheet.duration(20), "—")
        XCTAssertEqual(Timesheet.duration(12 * 60), "12 min")
        XCTAssertEqual(Timesheet.duration(65 * 60), "1 h 05 min")
        XCTAssertEqual(Timesheet.duration(120 * 60), "2 h")
        XCTAssertEqual(FrontTimeLog.describe(seconds: 20), "Less than 1 min")
        XCTAssertEqual(FrontTimeLog.describe(seconds: 85 * 60), "1 h 25 min")
    }

    func testDurationsStayTurkishByDefault() {
        XCTAssertEqual(Timesheet.duration(65 * 60), "1 sa 05 dk")
    }

    func testEnglishScriptSpeaksEnglish() {
        let script = LanesCLI.script(language: .english)
        XCTAssertTrue(script.contains("lanes use ACCOUNT                   Link this folder to an account (.lanes)"))
        XCTAssertTrue(script.contains("Unknown command: $command. For help: lanes help"))
        XCTAssertFalse(script.contains("Hesap"))
        XCTAssertFalse(script.contains("\\#("))
        XCTAssertTrue(script.contains("--settings \"$HOOKS\""))
        // `lanes help` prints lines 6 to 11: the usage, in both languages.
        for language in CoreLanguage.allCases {
            let lines = LanesCLI.script(language: language).split(separator: "\n", omittingEmptySubsequences: false)
            XCTAssertTrue(lines[5].hasPrefix("#   lanes claude "), "\(language)")
            XCTAssertTrue(lines[10].hasPrefix("#   lanes open "), "\(language)")
            XCTAssertEqual(lines[11], "", "\(language)")
        }
    }

    func testScriptFollowsTheCurrentLanguage() {
        CoreLanguage.current = .english
        XCTAssertEqual(LanesCLI.script(), LanesCLI.script(language: .english))
        XCTAssertTrue(LanesCLI.isCurrent(LanesCLI.script()))
    }

    func testScriptInAnotherLanguageIsNotCurrent() {
        let english = LanesCLI.script(language: .english)
        let turkish = LanesCLI.script(language: .turkish)
        XCTAssertTrue(LanesCLI.isCurrent(english, language: .english))
        XCTAssertFalse(LanesCLI.isCurrent(english, language: .turkish))
        XCTAssertFalse(LanesCLI.isCurrent(turkish, language: .english))
        XCTAssertTrue(LanesCLI.isOurs(english))
    }

    func testOlderScriptIsOursButNotCurrent() {
        let older = "#!/bin/sh\n# lanes-cli-version \(LanesCLI.version)\n# Lanes komut satırı aracı.\n"
        XCTAssertTrue(LanesCLI.isOurs(older))
        XCTAssertFalse(LanesCLI.isCurrent(older, language: .turkish))
        XCTAssertFalse(LanesCLI.isCurrent(older, language: .english))
    }

    func testErrorAndCSVInEnglish() {
        CoreLanguage.current = .english
        XCTAssertEqual(LibraryTransferError.notAnExport.errorDescription, "This file isn’t a Lanes account list.")
        XCTAssertTrue(LanesCLI.map(library: ProfileLibrary(profiles: []), paths: .standard(home: URL(fileURLWithPath: "/Users/u", isDirectory: true))).hasPrefix("# Lanes account map."))
    }
}
