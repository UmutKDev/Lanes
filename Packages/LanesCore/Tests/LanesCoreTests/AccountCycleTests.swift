import XCTest
@testable import LanesCore

final class AccountCycleTests: XCTestCase {
    let a = ProfileID(rawValue: "a"), b = ProfileID(rawValue: "b"), c = ProfileID(rawValue: "c")

    func testSkipsClosedAccountsAndWraps() {
        let order = [a, b, c]
        XCTAssertEqual(AccountCycle.target(current: a, open: [a, c], order: order, forward: true), c)
        XCTAssertEqual(AccountCycle.target(current: c, open: [a, c], order: order, forward: true), a)
        XCTAssertEqual(AccountCycle.target(current: a, open: [a, c], order: order, forward: false), c)
    }

    func testStartsAtAnEndWithoutACurrentAccount() {
        XCTAssertEqual(AccountCycle.target(current: nil, open: [b, c], order: [a, b, c], forward: true), b)
        XCTAssertEqual(AccountCycle.target(current: a, open: [b, c], order: [a, b, c], forward: false), c)
        XCTAssertNil(AccountCycle.target(current: nil, open: [], order: [a], forward: true))
    }

    func testNewTargetsSurviveSavingAndPruning() {
        XCTAssertEqual(ShortcutTarget(key: ShortcutTarget.nextAccount.description), .nextAccount)
        XCTAssertEqual(ShortcutTarget(key: ShortcutTarget.previousAccount.description), .previousAccount)
        XCTAssertEqual(ShortcutTarget(key: ShortcutTarget.palette.description), .palette)
    }
}
