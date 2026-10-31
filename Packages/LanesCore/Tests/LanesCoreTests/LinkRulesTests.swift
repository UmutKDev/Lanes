import Foundation
import XCTest
@testable import LanesCore

final class LinkRulesTests: XCTestCase {
    private let library = ProfileLibrary(profiles: [
        Profile(id: ProfileID(rawValue: "main"), name: "Ana hesap", color: .orange, isDefault: true),
        Profile(id: ProfileID(rawValue: "work"), name: "İş", color: .blue),
    ])

    func testFrontmostByDefault() {
        let rules = LinkRules()
        XCTAssertEqual(rules.profile(for: .newChat(prompt: nil), frontmost: ProfileID(rawValue: "work"), library: library)?.name, "İş")
        XCTAssertEqual(rules.profile(for: .newChat(prompt: nil), frontmost: nil, library: library)?.name, "Ana hesap")
    }

    func testKindRuleWins() {
        let rules = LinkRules(byKind: [.code: .profile(ProfileID(rawValue: "work"))])
        XCTAssertEqual(rules.profile(for: .newCodeSession, frontmost: ProfileID(rawValue: "main"), library: library)?.name, "İş")
        XCTAssertEqual(rules.profile(for: .codeNeedsInput, frontmost: nil, library: library)?.name, "İş")
        XCTAssertEqual(rules.profile(for: .resume(sessionID: nil), frontmost: nil, library: library)?.name, "Ana hesap")
    }

    func testRemovedAccountFallsBack() {
        var rules = LinkRules(fallback: .profile(ProfileID(rawValue: "gone")))
        XCTAssertEqual(rules.profile(for: .newChat(prompt: nil), frontmost: nil, library: library)?.name, "Ana hesap")
        rules.prune(profiles: [ProfileID(rawValue: "main")])
        XCTAssertEqual(rules.fallback, .frontmost)
    }

    func testRoundTripAndUnknownKindDropped() throws {
        let rules = LinkRules(fallback: .profile(ProfileID(rawValue: "main")), byKind: [.cowork: .frontmost])
        let decoded = try JSONDecoder().decode(LinkRules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
        let json = #"{"fallback": {"frontmost": {}}, "byKind": {"future": {"frontmost": {}}}}"#
        XCTAssertEqual(try JSONDecoder().decode(LinkRules.self, from: Data(json.utf8)).byKind, [:])
    }
}
