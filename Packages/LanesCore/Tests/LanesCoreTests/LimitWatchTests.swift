import Foundation
import XCTest
@testable import LanesCore

final class LimitWatchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func library(_ profiles: [Profile]) -> ProfileLibrary {
        ProfileLibrary(profiles: profiles)
    }

    func testRestingAccountHandsOverToTheNextOfTheSameKind() {
        var a = Profile(name: "A", color: .blue, accountClass: .employer)
        a.limitedUntil = now.addingTimeInterval(3600)
        let personal = Profile(name: "P", color: .green, accountClass: .personal)
        let b = Profile(name: "B", color: .orange, accountClass: .employer)
        let lib = library([a, personal, b])
        XCTAssertEqual(LimitWatch.standIn(for: a, in: lib, now: now)?.id, b.id)
        XCTAssertEqual(LimitWatch.effective(a, in: lib, now: now).id, b.id)
    }

    func testNoStandInWhenNotRestingOrNoneFits() {
        var a = Profile(name: "A", color: .blue, accountClass: .employer)
        let personal = Profile(name: "P", color: .green, accountClass: .personal)
        XCTAssertNil(LimitWatch.standIn(for: a, in: library([a, personal]), now: now))
        a.limitedUntil = now.addingTimeInterval(60)
        XCTAssertNil(LimitWatch.standIn(for: a, in: library([a, personal]), now: now))
        XCTAssertEqual(LimitWatch.effective(a, in: library([a, personal]), now: now).id, a.id)
    }

    func testSkipsRestingArchivedAndClaudeAppAccountsAndWraps() {
        var a = Profile(name: "A", color: .blue)
        a.limitedUntil = now.addingTimeInterval(60)
        var tired = Profile(name: "T", color: .red)
        tired.limitedUntil = now.addingTimeInterval(60)
        let archived = Profile(name: "R", color: .gray, isArchived: true)
        let claudeApp = Profile(name: "Claude", color: .gray, isDefault: true)
        let first = Profile(name: "F", color: .teal)
        let lib = library([first, a, tired, archived, claudeApp])
        XCTAssertEqual(LimitWatch.standIn(for: a, in: lib, now: now)?.id, first.id)
    }

    func testRestEndsAtItsTime() {
        var a = Profile(name: "A", color: .blue)
        a.limitedUntil = now
        XCTAssertFalse(a.isResting(at: now))
        XCTAssertTrue(a.isResting(at: now.addingTimeInterval(-1)))
    }

    func testPresetRoundsUpToTheMinute() {
        let start = Date(timeIntervalSinceReferenceDate: 600 + 10)
        XCTAssertEqual(LimitWatch.until(hours: 1, from: start).timeIntervalSinceReferenceDate, 600 + 3600 + 60)
    }

    func testLimitedUntilRoundTrips() throws {
        var a = Profile(name: "A", color: .blue)
        a.limitedUntil = now
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(decoded.limitedUntil, now)
    }
}
