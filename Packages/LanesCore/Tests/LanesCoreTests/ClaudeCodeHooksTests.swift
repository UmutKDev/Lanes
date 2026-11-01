import XCTest
@testable import LanesCore

final class ClaudeCodeHooksTests: XCTestCase {
    func testEventParsesWhatTheHookWrites() {
        let text = "lanes-event 1\nad43461d-0000-4000-8000-000000000001\ndone\nttys003\nApple_Terminal\n/Users/umut/Projeler/lanes\n"
        let event = ClaudeCodeHooks.Event(contents: text)
        XCTAssertEqual(event, ClaudeCodeHooks.Event(
            profileID: ProfileID(rawValue: "ad43461d-0000-4000-8000-000000000001"),
            kind: .done,
            tty: "ttys003",
            terminalProgram: "Apple_Terminal",
            projectPath: "/Users/umut/Projeler/lanes"
        ))
    }

    func testEventRejectsForeignOrBrokenFiles() {
        XCTAssertNil(ClaudeCodeHooks.Event(contents: "lanes-event 2\nid\ndone\n\n\n/\n"), "unknown version")
        XCTAssertNil(ClaudeCodeHooks.Event(contents: "lanes-event 1\nid\nfinished\n\n\n/\n"), "unknown kind")
        XCTAssertNil(ClaudeCodeHooks.Event(contents: "lanes-event 1\n../x\ndone\n\n\n/\n"), "odd ID")
        XCTAssertNil(ClaudeCodeHooks.Event(contents: "lanes-event 1\nid\ndone\n"), "too short")
    }

    func testEventDropsUnsafeFieldsButKeepsTheEvent() throws {
        let text = "lanes-event 1\nabc\nwaiting\nttys1\" & do shell script \"x\nTerm\"inal\nrelative/path\n"
        let event = try XCTUnwrap(ClaudeCodeHooks.Event(contents: text))
        XCTAssertEqual(event.kind, .waiting)
        XCTAssertNil(event.tty, "only ttys and digits can reach the AppleScript")
        XCTAssertNil(event.terminalProgram)
        XCTAssertNil(event.projectPath)
    }

    func testTTYAcceptsDevicePaths() {
        XCTAssertEqual(ClaudeCodeHooks.Event.validTTY("/dev/ttys012"), "ttys012")
        XCTAssertEqual(ClaudeCodeHooks.Event.validTTY("ttys4"), "ttys4")
        XCTAssertNil(ClaudeCodeHooks.Event.validTTY("??"))
        XCTAssertNil(ClaudeCodeHooks.Event.validTTY("ttys"))
        XCTAssertNil(ClaudeCodeHooks.Event.validTTY("console"))
    }

    func testSettingsHoldOnlyTheChosenHooks() throws {
        let id = ProfileID(rawValue: "abc-1")
        let both = ClaudeCodeHooks.settings(scriptPath: "/Users/u/Library/Application Support/Lanes/ClaudeCodeHooks/lanes-hook", profileID: id, kinds: [.done, .waiting])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: both) as? [String: Any])
        XCTAssertEqual(Array(object.keys), ["hooks"], "nothing but hooks")
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["Stop", "Notification"])
        let stop = try XCTUnwrap((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(stop.first?["command"] as? String, "/bin/sh '/Users/u/Library/Application Support/Lanes/ClaudeCodeHooks/lanes-hook' abc-1 done")
        let notification = try XCTUnwrap((hooks["Notification"] as? [[String: Any]])?.first)
        XCTAssertEqual(notification["matcher"] as? String, "permission_prompt")

        let doneOnly = ClaudeCodeHooks.settings(scriptPath: "/x/lanes-hook", profileID: id, kinds: [.done])
        let doneHooks = try XCTUnwrap((JSONSerialization.jsonObject(with: doneOnly) as? [String: Any])?["hooks"] as? [String: Any])
        XCTAssertEqual(Array(doneHooks.keys), ["Stop"])
    }

    func testScriptWritesTheHeaderLanesReads() {
        XCTAssertTrue(ClaudeCodeHooks.script.contains("\"\(ClaudeCodeHooks.eventHeader)\""))
        XCTAssertTrue(ClaudeCodeHooks.script.contains("cat >/dev/null"), "input is thrown away unread")
        XCTAssertTrue(ClaudeCodeHooks.script.contains("/\(ClaudeCodeHooks.eventsFolderName)\""))
    }

    func testTerminalPrograms() {
        XCTAssertEqual(ClaudeCodeHooks.terminalBundleIdentifier(for: "Apple_Terminal"), "com.apple.Terminal")
        XCTAssertEqual(ClaudeCodeHooks.terminalBundleIdentifier(for: "iTerm.app"), "com.googlecode.iterm2")
        XCTAssertNil(ClaudeCodeHooks.terminalBundleIdentifier(for: nil))
    }
}
