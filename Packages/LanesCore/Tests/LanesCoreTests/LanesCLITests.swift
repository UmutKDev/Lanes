import Foundation
import XCTest
@testable import LanesCore

final class LanesCLITests: XCTestCase {
    private let paths = ProfilePaths.standard(home: URL(fileURLWithPath: "/Users/umut", isDirectory: true))

    func testMapListsActiveAccountsWithTheirFolders() {
        var work = Profile(id: ProfileID(rawValue: "w"), name: "İş\tHesabı", color: .blue)
        work.linkedFolders = ["/Users/umut/İş/"]
        work.allowedFolders = ["/Users/umut/İş"]
        let claudeApp = Profile(id: ProfileID(rawValue: "d"), name: "Claude", color: .gray, isDefault: true)
        let archived = Profile(id: ProfileID(rawValue: "a"), name: "Eski", color: .red, isArchived: true)
        let map = LanesCLI.map(library: ProfileLibrary(profiles: [work, archived, claudeApp]), paths: paths)
        let lines = map.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[1], "A\tw\t1\tİş Hesabı\t/Users/umut/Library/Application Support/Lanes/Profiles/w/ClaudeCode")
        XCTAssertEqual(lines[2], "L\tw\t/Users/umut/İş")
        XCTAssertEqual(lines[3], "P\tw\t/Users/umut/İş")
        XCTAssertEqual(lines[4], "A\td\t2\tClaude\t-")
        XCTAssertFalse(map.contains("Eski"))
    }

    func testScriptIsRecognisedAndVersioned() {
        let script = LanesCLI.script
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(LanesCLI.isOurs(script))
        XCTAssertTrue(LanesCLI.isCurrent(script))
        XCTAssertFalse(LanesCLI.isOurs("#!/bin/sh\necho someone else's lanes\n"))
        XCTAssertFalse(script.contains("\\#("))
        XCTAssertTrue(script.contains("cli-accounts.tsv"))
    }
}
