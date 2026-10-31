import Foundation
import XCTest
@testable import LanesCore

final class SceneLayoutTests: XCTestCase {
    func testFramesAreWrittenOnlyWhenSaved() throws {
        let plain = ProfileScene(name: "İş", profileIDs: [ProfileID(rawValue: "a")])
        let json = String(data: try JSONEncoder().encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("windowFrames"))
        XCTAssertEqual(try JSONDecoder().decode(ProfileScene.self, from: Data(json.utf8)), plain)
    }

    func testFramesRoundTripAndPrune() throws {
        var scene = ProfileScene(
            name: "İş",
            profileIDs: [ProfileID(rawValue: "a"), ProfileID(rawValue: "b")],
            windowFrames: [
                "a": SceneWindowFrame(x: 0, y: 25, width: 800, height: 600),
                "gone": SceneWindowFrame(x: 1, y: 2, width: 3, height: 4),
            ]
        )
        let decoded = try JSONDecoder().decode(ProfileScene.self, from: try JSONEncoder().encode(scene))
        XCTAssertEqual(decoded.windowFrame(for: ProfileID(rawValue: "a")), SceneWindowFrame(x: 0, y: 25, width: 800, height: 600))
        scene.pruneWindowFrames()
        XCTAssertEqual(Array(scene.windowFrames.keys), ["a"])
    }

    func testOlderSceneWithoutFramesReads() throws {
        let json = #"{"id":"s","name":"Eski","profileIDs":["a"],"opensWhenLanesStarts":true}"#
        let scene = try JSONDecoder().decode(ProfileScene.self, from: Data(json.utf8))
        XCTAssertTrue(scene.windowFrames.isEmpty)
        XCTAssertTrue(scene.opensWhenLanesStarts)
    }
}
