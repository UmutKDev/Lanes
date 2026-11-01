import Foundation
import XCTest
@testable import LanesCore

final class LaunchPlanTests: XCTestCase {
    let paths = ProfilePaths.standard(home: URL(fileURLWithPath: "/Users/umut", isDirectory: true))
    let claudeApp = URL(fileURLWithPath: "/Applications/Claude.app", isDirectory: true)
    let cloneApp = URL(fileURLWithPath: "/Users/umut/Applications/Lanes Profiles/Claude – İş.app", isDirectory: true)

    func testDefaultProfileLaunchesClaudeUntouched() {
        let profile = Profile(name: "Kişisel", color: .blue, isDefault: true)
        let plan = LaunchPlanner.plan(for: profile, claudeApp: claudeApp, cloneApp: nil, paths: paths)
        XCTAssertEqual(plan.applicationURL, claudeApp)
        XCTAssertEqual(plan.arguments, [])
        XCTAssertEqual(plan.environment, [:])
        XCTAssertTrue(plan.createsNewInstance, "otherwise a running profile would be brought forward instead")
        XCTAssertEqual(plan.directoriesToCreate, [])
    }

    func testOtherProfileGetsOwnDataAndConfigFolders() {
        let profile = Profile(id: ProfileID(rawValue: "p1"), name: "İş", color: .orange)
        let plan = LaunchPlanner.plan(for: profile, claudeApp: claudeApp, cloneApp: cloneApp, paths: paths)
        let root = "/Users/umut/Library/Application Support/Lanes/Profiles/p1"
        XCTAssertEqual(plan.applicationURL, claudeApp, "standard mode ignores the clone")
        XCTAssertEqual(plan.arguments, ["--user-data-dir=\(root)/Claude"])
        XCTAssertEqual(plan.environment, ["CLAUDE_CONFIG_DIR": "\(root)/ClaudeCode"])
        XCTAssertTrue(plan.createsNewInstance)
        XCTAssertEqual(plan.directoriesToCreate.map(\.path), ["\(root)/Claude", "\(root)/ClaudeCode"])
    }

    func testCloneModeUsesCloneWhenPresent() {
        let profile = Profile(name: "İş", color: .orange, mode: .signedClone)
        XCTAssertEqual(LaunchPlanner.plan(for: profile, claudeApp: claudeApp, cloneApp: cloneApp, paths: paths).applicationURL, cloneApp)
        XCTAssertFalse(LaunchPlanner.plan(for: profile, claudeApp: claudeApp, cloneApp: cloneApp, paths: paths).fallsBackToClaude)
        let fallback = LaunchPlanner.plan(for: profile, claudeApp: claudeApp, cloneApp: nil, paths: paths)
        XCTAssertEqual(fallback.applicationURL, claudeApp)
        XCTAssertTrue(fallback.fallsBackToClaude, "a missing clone is reported, not hidden")
    }

    func testMainAccountNeverOpensAClone() {
        let profile = Profile(name: "Kişisel", color: .blue, mode: .signedClone, isDefault: true)
        let plan = LaunchPlanner.plan(for: profile, claudeApp: claudeApp, cloneApp: cloneApp, paths: paths)
        XCTAssertEqual(plan.applicationURL, claudeApp)
        XCTAssertFalse(plan.fallsBackToClaude)
    }

    func testRunningProfileIsActivatedNotRelaunched() {
        let profile = Profile(name: "İş", color: .orange)
        let other = RunningInstance(pid: 10, applicationBundlePath: claudeApp.path, userDataDirectory: nil, profileID: ProfileID(rawValue: "x"))
        let mine = RunningInstance(pid: 42, applicationBundlePath: claudeApp.path, userDataDirectory: "/d", profileID: profile.id)
        XCTAssertEqual(
            LaunchPlanner.action(for: profile, running: [other, mine], claudeApp: claudeApp, cloneApp: nil, paths: paths),
            .activate(pid: 42)
        )
        guard case .launch = LaunchPlanner.action(for: profile, running: [other], claudeApp: claudeApp, cloneApp: nil, paths: paths) else {
            return XCTFail("expected a launch")
        }
    }

    func testClaudeCommandLookupCoversTheOfficialInstaller() {
        XCTAssertEqual(
            ClaudeCodeCommand.pathExport,
            "export PATH=\"$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH\""
        )
        XCTAssertEqual(ClaudeCodeCommand.candidatePaths(home: "/Users/umut").first, "/Users/umut/.local/bin/claude")
        XCTAssertTrue(ClaudeCodeCommand.candidatePaths(home: "/Users/umut").contains("/opt/homebrew/bin/claude"))
    }

    func testClaudeCodeCommand() {
        let standard = Profile(name: "Kişisel", color: .blue, isDefault: true)
        XCTAssertEqual(ClaudeCodeCommand.command(for: standard, paths: paths), "claude")

        let work = Profile(id: ProfileID(rawValue: "p1"), name: "İş", color: .orange)
        XCTAssertEqual(
            ClaudeCodeCommand.command(for: work, paths: paths, arguments: ["--resume", "it's"]),
            "CLAUDE_CONFIG_DIR='/Users/umut/Library/Application Support/Lanes/Profiles/p1/ClaudeCode' claude --resume 'it'\\''s'"
        )
    }

    func testShellQuoting() {
        XCTAssertEqual(ClaudeCodeCommand.shellQuoted("plain-word_1.2"), "plain-word_1.2")
        XCTAssertEqual(ClaudeCodeCommand.shellQuoted(""), "''")
        XCTAssertEqual(ClaudeCodeCommand.shellQuoted("a b"), "'a b'")
        XCTAssertEqual(ClaudeCodeCommand.shellQuoted("$(rm -rf ~)"), "'$(rm -rf ~)'")
    }

    func testLaunchEnvironment() {
        let base = [
            "HOME": "/Users/umut",
            "PATH": "/usr/bin",
            "DYLD_INSERT_LIBRARIES": "x",
            "__CFBundleIdentifier": "com.umutkdev.Lanes",
            "XPC_SERVICE_NAME": "y",
            "CLAUDE_CONFIG_DIR": "/leaked/from/lanes",
        ]
        XCTAssertEqual(
            LaunchEnvironment.merged(base: base, additions: ["CLAUDE_CONFIG_DIR": "/p"]),
            ["HOME": "/Users/umut", "PATH": "/usr/bin", "CLAUDE_CONFIG_DIR": "/p"]
        )
        XCTAssertNil(LaunchEnvironment.merged(base: base, additions: [:])["CLAUDE_CONFIG_DIR"],
                     "the default profile must not inherit a config folder from Lanes's own environment")
    }
}
