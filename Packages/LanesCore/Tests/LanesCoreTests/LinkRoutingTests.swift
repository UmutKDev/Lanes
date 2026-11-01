import Foundation
import XCTest
@testable import LanesCore

final class LinkRoutingTests: XCTestCase {
    private let library = ProfileLibrary(profiles: [
        Profile(id: ProfileID(rawValue: "main"), name: "Ana hesap", color: .orange, isDefault: true),
        Profile(id: ProfileID(rawValue: "work"), name: "İş", color: .blue),
    ])
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    /// 2026-11-02 is a Monday (weekday 2).
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTimeWindow() {
        let workHours = LinkTimeWindow(startMinute: 9 * 60, endMinute: 18 * 60, weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(workHours.contains(date(2, 9), calendar: calendar))
        XCTAssertFalse(workHours.contains(date(2, 18), calendar: calendar))
        XCTAssertFalse(workHours.contains(date(1, 10), calendar: calendar), "Sunday")
        let night = LinkTimeWindow(startMinute: 22 * 60, endMinute: 2 * 60, weekdays: [6])
        XCTAssertTrue(night.contains(date(6, 23), calendar: calendar), "Friday evening")
        XCTAssertTrue(night.contains(date(7, 1), calendar: calendar), "Saturday 01:00 belongs to Friday")
        XCTAssertFalse(night.contains(date(8, 1), calendar: calendar), "Sunday 01:00 belongs to Saturday")
        XCTAssertTrue(LinkTimeWindow(startMinute: 0, endMinute: 0).contains(date(4, 13), calendar: calendar))
    }

    func testRuleBeatsKindAndExplainsItself() {
        let rule = LinkRule(name: "Mesai", sourceApps: [LinkSourceApp(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")],
                            window: LinkTimeWindow(startMinute: 9 * 60, endMinute: 18 * 60), target: .profile(ProfileID(rawValue: "work")))
        let rules = LinkRules(byKind: [.newChat: .profile(ProfileID(rawValue: "main"))], rules: [rule])
        let fromSlack = rules.decide(route: .newChat(prompt: nil), sourceApp: "com.tinyspeck.slackmacgap", now: date(2, 10), calendar: calendar, frontmost: nil, library: library)
        XCTAssertEqual(fromSlack.profile?.name, "İş")
        XCTAssertEqual(fromSlack.reason, .rule(name: "Mesai"))
        let fromMail = rules.decide(route: .newChat(prompt: nil), sourceApp: "com.apple.mail", now: date(2, 10), calendar: calendar, frontmost: nil, library: library)
        XCTAssertEqual(fromMail.profile?.name, "Ana hesap")
        XCTAssertEqual(fromMail.reason, .kind(.newChat))
        let evening = rules.decide(route: .newChat(prompt: nil), sourceApp: "com.tinyspeck.slackmacgap", now: date(2, 20), calendar: calendar, frontmost: nil, library: library)
        XCTAssertEqual(evening.reason, .kind(.newChat))
    }

    func testDisabledOrGoneRuleIsSkipped() {
        var off = LinkRule(name: "Kapalı", target: .profile(ProfileID(rawValue: "work")))
        off.isEnabled = false
        let gone = LinkRule(name: "Silinen", target: .profile(ProfileID(rawValue: "gone")))
        var rules = LinkRules(rules: [off, gone])
        let decision = rules.decide(route: .newCodeSession, sourceApp: nil, now: date(2, 10), calendar: calendar, frontmost: ProfileID(rawValue: "work"), library: library)
        XCTAssertEqual(decision.profile?.name, "İş")
        XCTAssertEqual(decision.reason, .frontmost)
        XCTAssertEqual(rules.decide(route: .newCodeSession, sourceApp: nil, now: date(2, 10), calendar: calendar, frontmost: nil, library: library).reason, .defaultAccount)
        rules.prune(profiles: [ProfileID(rawValue: "main"), ProfileID(rawValue: "work")])
        XCTAssertEqual(rules.rules.map(\.name), ["Kapalı"])
    }

    func testRulesRoundTripAndOldFilesStillRead() throws {
        let rules = LinkRules(rules: [LinkRule(name: "Kod", kinds: [.code], window: LinkTimeWindow(startMinute: 60, endMinute: 120, weekdays: [2]), target: .frontmost)])
        XCTAssertEqual(try JSONDecoder().decode(LinkRules.self, from: JSONEncoder().encode(rules)), rules)
        let old = #"{"fallback": {"frontmost": {}}, "byKind": {}}"#
        XCTAssertEqual(try JSONDecoder().decode(LinkRules.self, from: Data(old.utf8)).rules, [])
        let future = #"{"name": "Yeni", "kinds": ["future"], "target": {"frontmost": {}}}"#
        let rule = try JSONDecoder().decode(LinkRule.self, from: Data(future.utf8))
        XCTAssertFalse(rule.matches(kind: .newChat, sourceApp: nil, at: date(2, 10), calendar: calendar), "A rule whose kinds are all unknown never matches")
        let again = try JSONDecoder().decode(LinkRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(again.unknownKinds, ["future"], "Unknown kinds survive a save")
        // A rule this Lanes cannot read drops only itself.
        let mixed = #"{"fallback": {"frontmost": {}}, "byKind": {}, "rules": [{"name": "Bozuk", "target": {"future": {}}}, {"name": "İyi", "target": {"frontmost": {}}}]}"#
        XCTAssertEqual(try JSONDecoder().decode(LinkRules.self, from: Data(mixed.utf8)).rules.map(\.name), ["İyi"])
    }

    func testMatchedFrontmostRuleKeepsItsReasonWithoutAFrontAccount() {
        let rules = LinkRules(rules: [LinkRule(name: "Her şey", target: .frontmost)])
        let decision = rules.decide(route: .newChat(prompt: nil), sourceApp: nil, now: date(2, 10), calendar: calendar, frontmost: nil, library: library)
        XCTAssertEqual(decision.profile?.name, "Ana hesap")
        XCTAssertEqual(decision.reason, .rule(name: "Her şey"))
    }

    func testKindRuleForGoneAccountFallsBackToFront() {
        let rules = LinkRules(fallback: .profile(ProfileID(rawValue: "main")), byKind: [.code: .profile(ProfileID(rawValue: "gone"))])
        let decision = rules.decide(route: .newCodeSession, sourceApp: nil, now: date(2, 10), calendar: calendar, frontmost: ProfileID(rawValue: "work"), library: library)
        XCTAssertEqual(decision.profile?.name, "İş")
        XCTAssertEqual(decision.reason, .frontmost)
    }

    func testLogKeepsThirtyDays() throws {
        let now = date(30, 12)
        var log = LinkLog()
        log.add(LinkLogEntry(kind: "Yeni sohbet", receivedAt: now.addingTimeInterval(-31 * 24 * 3600), outcome: "eski"), now: now)
        log.add(LinkLogEntry(kind: "Yeni sohbet", receivedAt: now.addingTimeInterval(-60), outcome: "yeni", reason: "Kural: Mesai", source: "Slack"), now: now)
        XCTAssertEqual(log.entries.map(\.outcome), ["yeni"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("linklog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try log.save(to: url)
        XCTAssertEqual(LinkLog.load(from: url, now: now).entries.first?.reason, "Kural: Mesai")
    }
}
