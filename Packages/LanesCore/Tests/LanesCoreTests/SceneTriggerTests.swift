import Foundation
import XCTest
@testable import LanesCore

final class SceneTriggerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        // November 2026: the 2nd is a Monday.
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testDueOnceAfterItsTime() {
        let nine = SceneSchedule(minuteOfDay: 9 * 60)
        XCTAssertFalse(nine.isDue(now: date(2, 8, 59), lastOpened: nil, calendar: calendar))
        XCTAssertTrue(nine.isDue(now: date(2, 9, 0), lastOpened: nil, calendar: calendar))
        XCTAssertFalse(nine.isDue(now: date(2, 9, 5), lastOpened: date(2, 9, 0), calendar: calendar))
        XCTAssertTrue(nine.isDue(now: date(3, 9, 1), lastOpened: date(2, 9, 0), calendar: calendar))
    }

    func testTooLateWaitsForTheNextDay() {
        let nine = SceneSchedule(minuteOfDay: 9 * 60)
        XCTAssertTrue(nine.isDue(now: date(2, 10, 59), lastOpened: nil, calendar: calendar))
        XCTAssertFalse(nine.isDue(now: date(2, 11, 1), lastOpened: nil, calendar: calendar))
    }

    func testWeekdaysAreRespected() {
        // Monday (2) to Friday (6).
        let weekdays = SceneSchedule(minuteOfDay: 9 * 60, weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(weekdays.isDue(now: date(2, 9, 0), lastOpened: nil, calendar: calendar))
        // November 1 2026 is a Sunday.
        XCTAssertFalse(weekdays.isDue(now: date(1, 9, 0), lastOpened: nil, calendar: calendar))
    }

    func testOutOfRangeValuesAreClamped() {
        let schedule = SceneSchedule(minuteOfDay: 5000, weekdays: [0, 3, 9])
        XCTAssertEqual(schedule.minuteOfDay, 1439)
        XCTAssertEqual(schedule.weekdays, [3])
    }

    func testTriggersRoundTripAndOldScenesStayTheSame() throws {
        let plain = ProfileScene(name: "İş", profileIDs: [])
        let plainJSON = try String(decoding: JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(plainJSON.contains("schedule"))
        XCTAssertFalse(plainJSON.contains("display"))
        var scene = plain
        scene.schedule = SceneSchedule(minuteOfDay: 540, weekdays: [2])
        scene.display = SceneDisplay(identifier: "ABC", name: "LG")
        let decoded = try JSONDecoder().decode(ProfileScene.self, from: JSONEncoder().encode(scene))
        XCTAssertEqual(decoded.schedule, scene.schedule)
        XCTAssertEqual(decoded.display, scene.display)
    }
}
