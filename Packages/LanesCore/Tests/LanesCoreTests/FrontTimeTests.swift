import XCTest
@testable import LanesCore

final class FrontTimeTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()
    let work = ProfileID(rawValue: "work")

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testSplitsAtMidnight() {
        var log = FrontTimeLog()
        log.record(work, from: date(30, 23, 30), to: date(31, 0, 45), calendar: calendar)
        XCTAssertEqual(log.days["2026-10-30"]?["work"], 30 * 60)
        XCTAssertEqual(log.days["2026-10-31"]?["work"], 45 * 60)
        XCTAssertEqual(log.seconds(for: work, days: 1, now: date(31, 12), calendar: calendar), 45 * 60)
        XCTAssertEqual(log.seconds(for: work, days: 7, now: date(31, 12), calendar: calendar), 75 * 60)
        XCTAssertEqual(log.seconds(for: work, on: date(30, 8), calendar: calendar), 30 * 60)
    }

    func testPruneDropsOldDaysAndRemovedAccounts() {
        var log = FrontTimeLog()
        log.record(work, from: date(1, 10), to: date(1, 11), calendar: calendar)
        log.record(work, from: date(31, 10), to: date(31, 11), calendar: calendar)
        log.record(ProfileID(rawValue: "gone"), from: date(31, 12), to: date(31, 13), calendar: calendar)
        log.prune(now: date(31, 14), keeping: [work], calendar: calendar)
        XCTAssertNil(log.days["2026-10-01"])
        XCTAssertEqual(log.days["2026-10-31"], ["work": 3600])
    }

    func testDescribe() {
        XCTAssertEqual(FrontTimeLog.describe(seconds: 0), "0 dk")
        XCTAssertEqual(FrontTimeLog.describe(seconds: 20), "1 dk'dan az")
        XCTAssertEqual(FrontTimeLog.describe(seconds: 12 * 60), "12 dk")
        XCTAssertEqual(FrontTimeLog.describe(seconds: 85 * 60), "1 sa 25 dk")
    }
}
