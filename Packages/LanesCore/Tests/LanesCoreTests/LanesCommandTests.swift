import Foundation
import XCTest
@testable import LanesCore

final class LanesCommandTests: XCTestCase {
    func command(_ text: String) -> LanesCommand? {
        LanesCommand(url: URL(string: text)!)
    }

    func testParsesCommands() {
        XCTAssertEqual(command("lanes://open?account=%C4%B0%C5%9F"), .openAccount("İş"))
        XCTAssertEqual(command("LANES://open?Account=2"), .openAccount("2"))
        XCTAssertEqual(command("lanes:open?account=abc"), .openAccount("abc"))
        XCTAssertEqual(command("lanes://scene?name=Sabah"), .openScene("Sabah"))
        XCTAssertEqual(command("lanes://show"), .show(page: nil))
        XCTAssertEqual(command("lanes://show?page=health"), .show(page: "health"))
        XCTAssertEqual(command("lanes://panel"), .panel)
    }

    func testRejectsUnknownAndIncomplete() {
        XCTAssertNil(command("lanes://open"))
        XCTAssertNil(command("lanes://open?account=%20"))
        XCTAssertNil(command("lanes://quit?account=1"), "nothing a web page could misuse")
        XCTAssertNil(command("claude://open?account=1"))
    }

    func testURLRoundTrips() {
        for item in [LanesCommand.openAccount("Müşteri A"), .openScene("Sabah işi"), .show(page: "health"), .show(page: nil), .panel] {
            XCTAssertEqual(LanesCommand(url: item.url), item)
        }
    }

    func testFindsAccountsAndScenes() throws {
        var library = ProfileLibrary()
        let main = Profile(id: ProfileID(rawValue: "m"), name: "Ana hesap", color: .orange, isDefault: true)
        let work = Profile(id: ProfileID(rawValue: "w"), name: "İş", color: .blue)
        try library.add(main)
        try library.add(work)
        library.scenes = [ProfileScene(id: SceneID(rawValue: "s"), name: "Sabah", profileIDs: [work.id])]

        XCTAssertEqual(library.profile(matching: "w")?.id, work.id)
        XCTAssertEqual(library.profile(matching: "iş")?.id, work.id, "Turkish lower case: İ becomes i")
        XCTAssertEqual(library.profile(matching: " ANA HESAP ")?.id, main.id)
        XCTAssertEqual(library.profile(matching: "2")?.id, work.id)
        XCTAssertNil(library.profile(matching: "3"))
        XCTAssertNil(library.profile(matching: "Yok"))
        XCTAssertEqual(library.scene(matching: "sabah")?.id.rawValue, "s")
        XCTAssertEqual(library.scene(matching: "s")?.name, "Sabah")
        XCTAssertNil(library.scene(matching: "Akşam"))
    }

    func testNumbersSkipArchivedAccounts() throws {
        var library = ProfileLibrary()
        let first = Profile(id: ProfileID(rawValue: "a"), name: "A", color: .orange)
        let second = Profile(id: ProfileID(rawValue: "b"), name: "B", color: .blue)
        let third = Profile(id: ProfileID(rawValue: "c"), name: "C", color: .green)
        try library.add(first)
        try library.add(second)
        try library.add(third)
        try library.setArchived(second.id, true)

        XCTAssertEqual(library.profile(matching: "2")?.id, third.id, "Like ⌘2, the second account in the sidebar")
        XCTAssertNil(library.profile(matching: "3"))
        XCTAssertEqual(library.profile(matching: "b")?.id, second.id, "An archived account is still found by its ID")
    }
}
