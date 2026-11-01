import XCTest
@testable import LanesCore

final class LauncherScriptTests: XCTestCase {
    let home = "/Users/umut"
    let folder = "/Users/umut/Library/Application Support/Claude-2"

    func points(_ script: String, at folder: String? = nil) -> Bool {
        LauncherScript.pointsAt(script: script, folder: folder ?? self.folder, home: home)
    }

    func testHomeVariableInsideEscapedQuotes() {
        let script = #"do shell script "open -n /Applications/Claude.app --args --user-data-dir=\"$HOME/Library/Application Support/Claude-2\"""#
        XCTAssertTrue(points(script))
    }

    func testTildeForm() {
        XCTAssertTrue(points(#"do shell script "open -n /Applications/Claude.app --args '--user-data-dir=~/Library/Application Support/Claude-2'""#))
    }

    func testBracedHomeForm() {
        XCTAssertTrue(points(#"do shell script "open -n -a Claude.app --args --user-data-dir=\"${HOME}/Library/Application Support/Claude-2\"""#))
    }

    func testAbsoluteForm() {
        XCTAssertTrue(points("do shell script \"open -n /Applications/Claude.app --args --user-data-dir='/Users/umut/Library/Application Support/Claude-2/'\""))
    }

    func testEscapedSpaces() {
        XCTAssertTrue(points(#"do shell script "open -n /Applications/Claude.app --args --user-data-dir=~/Library/Application\\ Support/Claude-2""#))
        XCTAssertTrue(points("open -n /Applications/Claude.app --args --user-data-dir=~/Library/Application\\ Support/Claude-2\n"))
    }

    func testOtherFolderWithTheSamePrefixDoesNotMatch() {
        let script = #"do shell script "open -n /Applications/Claude.app --args --user-data-dir=\"$HOME/Library/Application Support/Claude-20\"""#
        XCTAssertFalse(points(script))
        XCTAssertTrue(points(script, at: "/Users/umut/Library/Application Support/Claude-20"))
    }

    func testQuotedFolderWithASpaceAfterTheNameDoesNotMatch() {
        let single = "do shell script \"open -n /Applications/Claude.app --args --user-data-dir='/Users/umut/Library/Application Support/Claude-2 Backup'\""
        let double = #"do shell script "open -n /Applications/Claude.app --args --user-data-dir=\"$HOME/Library/Application Support/Claude-2 Backup\"""#
        let wholeArgument = #"do shell script "open -n /Applications/Claude.app --args '--user-data-dir=~/Library/Application Support/Claude-2 Backup'""#
        for script in [single, double, wholeArgument] {
            XCTAssertFalse(points(script))
            XCTAssertTrue(points(script, at: "/Users/umut/Library/Application Support/Claude-2 Backup"))
        }
    }

    func testScriptMustOpenClaude() {
        XCTAssertFalse(points(#"do shell script "open -n /Applications/Slack.app --args --user-data-dir=\"$HOME/Library/Application Support/Claude-2\"""#))
    }

    func testScriptMustSetTheDataFolder() {
        XCTAssertFalse(points(#"do shell script "open -n /Applications/Claude.app ~/Library/Application\ Support/Claude-2""#))
    }
}
