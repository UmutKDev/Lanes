import Foundation
import XCTest
@testable import LanesCore

final class TimesheetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private let work = ProfileID(rawValue: "work")

    func testWeekStartsOnMonday() {
        // 2026-11-01 is a Sunday, 2026-11-02 a Monday.
        XCTAssertEqual(Timesheet.weekStart(containing: date(1, 15), calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!)
        XCTAssertEqual(Timesheet.weekStart(containing: date(2, 0), calendar: calendar), date(2, 0))
        XCTAssertEqual(Timesheet.weekStart(containing: date(8, 23), calendar: calendar), date(2, 0))
    }

    func testWritesJoinIntoWork() {
        var log = ProjectTimeLog()
        XCTAssertTrue(log.recordWrite(work, folderName: "-p", at: date(2, 10, 3), previous: (date(2, 10, 0), "-p"), calendar: calendar))
        XCTAssertFalse(log.recordWrite(work, folderName: "-p", at: date(2, 10, 30), previous: (date(2, 10, 3), "-p"), calendar: calendar), "A long pause is not work")
        XCTAssertFalse(log.recordWrite(work, folderName: "-q", at: date(2, 10, 31), previous: (date(2, 10, 30), "-p"), calendar: calendar), "Another project starts fresh")
        XCTAssertEqual(log.projects(for: work, on: date(2, 12), calendar: calendar)["-p"], 180)
        // Split at midnight.
        log.recordWrite(work, folderName: "-p", at: date(3, 0, 2), previous: (date(2, 23, 59), "-p"), calendar: calendar)
        XCTAssertEqual(log.projects(for: work, on: date(2, 12), calendar: calendar)["-p"], 240)
        XCTAssertEqual(log.projects(for: work, on: date(3, 12), calendar: calendar)["-p"], 120)
    }

    func testWeekAndCSV() {
        var front = FrontTimeLog()
        front.record(work, from: date(2, 9), to: date(2, 11), calendar: calendar)
        var projects = ProjectTimeLog()
        projects.recordWrite(work, folderName: "-app", at: date(3, 10, 4), previous: (date(3, 10, 0), "-app"), calendar: calendar)
        let sheet = Timesheet(
            weekStart: date(2, 0),
            accounts: [(work, "İş, A.Ş."), (ProfileID(rawValue: "idle"), "Boş")],
            front: front, projects: projects, today: date(9, 12), calendar: calendar,
            projectName: { $0 == "-app" ? "=app" : $0 }
        )
        XCTAssertEqual(sheet.usedAccounts.map(\.name), ["İş, A.Ş."])
        XCTAssertEqual(sheet.usedAccounts.first?.frontTotal, 7200)
        XCTAssertEqual(sheet.usedAccounts.first?.code, [0, 240, 0, 0, 0, 0, 0])
        let lines = sheet.csv(calendar: calendar).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "Hesap,Proje,Tür,2026-11-02,2026-11-03,2026-11-04,2026-11-05,2026-11-06,2026-11-07,2026-11-08,Toplam (dk)")
        XCTAssertEqual(lines[1], "\"İş, A.Ş.\",,Claude önde,120,0,0,0,0,0,0,120")
        XCTAssertEqual(lines[2], "\"İş, A.Ş.\",'=app,Claude Code,0,4,0,0,0,0,0,4")
        XCTAssertEqual(sheet.summary, "İş, A.Ş.: 2 sa, Claude Code 4 dk")
    }

    func testDuration() {
        XCTAssertEqual(Timesheet.duration(20), "—")
        XCTAssertEqual(Timesheet.duration(12 * 60), "12 dk")
        XCTAssertEqual(Timesheet.duration(65 * 60), "1 sa 05 dk")
        XCTAssertEqual(Timesheet.duration(120 * 60), "2 sa")
    }
}
