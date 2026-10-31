import XCTest
@testable import LanesCore

final class ShortcutTests: XCTestCase {
    private let optionCommandL = KeyShortcut(keyCode: 37, modifiers: [.option, .command], key: "L")

    func testShiftAloneIsNotEnough() {
        XCTAssertFalse(KeyShortcut(keyCode: 37, modifiers: [.shift], key: "L").isAllowed)
        XCTAssertFalse(KeyShortcut(keyCode: 37, modifiers: [], key: "L").isAllowed)
        XCTAssertTrue(optionCommandL.isAllowed)
    }

    func testFunctionKeyWorksAlone() {
        XCTAssertTrue(KeyShortcut(keyCode: 96, modifiers: [], key: "F5").isAllowed)
    }

    func testDescriptionUsesMenuOrder() {
        let shortcut = KeyShortcut(keyCode: 37, modifiers: [.command, .shift, .option, .control], key: "L")
        XCTAssertEqual(shortcut.description, "⌃⌥⇧⌘L")
    }

    func testSameKeysOnTwoTargetsIsRefused() throws {
        var bindings = ShortcutBindings()
        let work = ProfileID(rawValue: "work")
        try bindings.set(optionCommandL, for: .panel)
        XCTAssertThrowsError(try bindings.set(optionCommandL, for: .profile(work))) { error in
            XCTAssertEqual(error as? ShortcutBindings.SetError, .inUse(by: .panel))
        }
        // Recording the same keys again for the same target is fine.
        XCTAssertNoThrow(try bindings.set(optionCommandL, for: .panel))
    }

    func testClashIgnoresTheKeyLabel() throws {
        var bindings = ShortcutBindings()
        try bindings.set(optionCommandL, for: .panel)
        let sameKeysOtherLabel = KeyShortcut(keyCode: 37, modifiers: [.option, .command], key: "l")
        XCTAssertEqual(bindings.conflict(for: sameKeysOtherLabel, except: .profile(ProfileID(rawValue: "x"))), .panel)
    }

    func testNilClears() throws {
        var bindings = ShortcutBindings()
        try bindings.set(optionCommandL, for: .panel)
        try bindings.set(nil, for: .panel)
        XCTAssertNil(bindings.shortcut(for: .panel))
    }

    func testRoundTripAndPrune() throws {
        var bindings = ShortcutBindings()
        let kept = ProfileID(rawValue: "kept")
        let gone = ProfileID(rawValue: "gone")
        let scene = SceneID(rawValue: "s1")
        try bindings.set(optionCommandL, for: .panel)
        try bindings.set(KeyShortcut(keyCode: 18, modifiers: [.control, .option], key: "1"), for: .profile(kept))
        try bindings.set(KeyShortcut(keyCode: 19, modifiers: [.control, .option], key: "2"), for: .profile(gone))
        try bindings.set(KeyShortcut(keyCode: 20, modifiers: [.control, .option], key: "3"), for: .scene(scene))

        let data = try JSONEncoder().encode(bindings)
        var decoded = try JSONDecoder().decode(ShortcutBindings.self, from: data)
        XCTAssertEqual(decoded, bindings)

        XCTAssertTrue(decoded.prune(profiles: [kept], scenes: []))
        XCTAssertEqual(decoded.all.map(\.target), [.panel, .profile(kept)])
        XCTAssertFalse(decoded.prune(profiles: [kept], scenes: []))
    }

    func testUnreadableBindingsStartEmpty() throws {
        let decoded = try JSONDecoder().decode(ShortcutBindings.self, from: Data("[1, 2]".utf8))
        XCTAssertEqual(decoded, ShortcutBindings())
    }

    func testTargetKeysRoundTrip() {
        for target in [ShortcutTarget.panel, .profile(ProfileID(rawValue: "a")), .scene(SceneID(rawValue: "b"))] {
            XCTAssertEqual(ShortcutTarget(key: target.description), target)
        }
        XCTAssertNil(ShortcutTarget(key: "window:1"))
    }
}

final class SceneTests: XCTestCase {
    private func library() -> ProfileLibrary {
        ProfileLibrary(profiles: [
            Profile(id: ProfileID(rawValue: "main"), name: "Ana hesap", color: .orange, isDefault: true),
            Profile(id: ProfileID(rawValue: "work"), name: "İş", color: .blue),
            Profile(id: ProfileID(rawValue: "client"), name: "Müşteri", color: .green),
        ])
    }

    func testListWithoutScenesHasNoScenesField() throws {
        let data = try ProfileStore.encoder.encode(library())
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("scenes"))
    }

    func testScenesRoundTrip() throws {
        var library = library()
        let scene = ProfileScene(name: "İş", profileIDs: [ProfileID(rawValue: "work"), ProfileID(rawValue: "client")], opensWhenLanesStarts: true)
        try library.addScene(scene)
        let data = try ProfileStore.encoder.encode(library)
        let decoded = try ProfileStore.decoder.decode(ProfileLibrary.self, from: data)
        XCTAssertEqual(decoded.scenes, [scene])
        XCTAssertEqual(decoded.scene(withID: scene.id)?.profiles(in: decoded).map(\.name), ["İş", "Müşteri"])
    }

    func testRemovingAnAccountTakesItOutOfScenes() throws {
        var library = library()
        let scene = ProfileScene(name: "İş", profileIDs: [ProfileID(rawValue: "work"), ProfileID(rawValue: "client")])
        try library.addScene(scene)
        try library.remove(ProfileID(rawValue: "work"))
        XCTAssertEqual(library.scenes.first?.profileIDs, [ProfileID(rawValue: "client")])
    }

    func testDuplicateSceneIsRefused() throws {
        var library = library()
        let scene = ProfileScene(name: "İş", profileIDs: [])
        try library.addScene(scene)
        XCTAssertThrowsError(try library.addScene(scene))
    }

    func testUnreadableScenesAreKeptAsTheyWere() throws {
        let json = """
        {"version": 1, "profiles": [{"id": "main", "name": "Ana hesap", "isDefault": true}], "scenes": "from a newer Lanes"}
        """
        let decoded = try ProfileStore.decoder.decode(ProfileLibrary.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.scenes.isEmpty)
        let text = String(decoding: try ProfileStore.encoder.encode(decoded), as: UTF8.self)
        XCTAssertTrue(text.contains("from a newer Lanes"))
    }

    func testSceneWithMissingFieldsReads() throws {
        let json = #"[{"id": "s1"}]"#
        let scenes = try JSONDecoder().decode([ProfileScene].self, from: Data(json.utf8))
        XCTAssertEqual(scenes.first?.name, "Adsız sahne")
        XCTAssertEqual(scenes.first?.profileIDs, [])
        XCTAssertEqual(scenes.first?.opensWhenLanesStarts, false)
    }
}

final class RecentFoldersTests: XCTestCase {
    func testNewestFirstWithoutDuplicates() {
        var recent = RecentFolders()
        recent.use("/Users/u/a")
        recent.use("/Users/u/b/")
        recent.use("/Users/u/a/")
        XCTAssertEqual(recent.paths, ["/Users/u/a", "/Users/u/b"])
    }

    func testKeepsFive() {
        var recent = RecentFolders()
        for index in 1...7 {
            recent.use("/p/\(index)")
        }
        XCTAssertEqual(recent.paths, ["/p/7", "/p/6", "/p/5", "/p/4", "/p/3"])
    }

    func testForget() {
        var recent = RecentFolders(paths: ["/a", "/b"])
        recent.forget("/a/")
        XCTAssertEqual(recent.paths, ["/b"])
    }

    func testRootStaysRoot() {
        var recent = RecentFolders()
        recent.use("/")
        XCTAssertEqual(recent.paths, ["/"])
    }
}

final class OrphanFolderTests: XCTestCase {
    func testOnlyUnknownFoldersCount() {
        let library = ProfileLibrary(profiles: [Profile(id: ProfileID(rawValue: "work"), name: "İş", color: .blue)])
        XCTAssertEqual(
            OrphanProfileFolders.find(folderNames: ["work", "old", ".DS_Store", "another"], library: library),
            ["another", "old"]
        )
    }
}
