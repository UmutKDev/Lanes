import Foundation
import XCTest
@testable import LanesCore

final class ClaudeFolderImportTests: XCTestCase {
    let paths = ProfilePaths.standard(home: URL(fileURLWithPath: "/Users/umut", isDirectory: true))
    let support = "/Users/umut/Library/Application Support"

    func refusal(_ path: String, library: ProfileLibrary = ProfileLibrary(), inUse: [String] = []) -> ClaudeFolderImport.Refusal? {
        ClaudeFolderImport.refusal(for: path, paths: paths, library: library, userDataDirectories: inUse)
    }

    // MARK: Detection

    func testClaudeFolderWithMarkersLooksLikeClaude() {
        let names: Set<String> = ["Local State", "claude-code-sessions", "claude-code", "claude-code-spare"]
        XCTAssertTrue(ClaudeFolderImport.looksLikeClaudeData(name: "Claude-2", exists: names.contains))
        XCTAssertTrue(ClaudeFolderImport.looksLikeClaudeData(name: "Work", exists: names.contains), "a marker is enough")
    }

    func testClaudeNamedFolderWithOnlyLocalStateLooksLikeClaude() {
        XCTAssertTrue(ClaudeFolderImport.looksLikeClaudeData(name: "Claude-3", exists: { $0 == "Local State" }))
        XCTAssertTrue(ClaudeFolderImport.looksLikeClaudeData(name: "claude work", exists: { $0 == "Local State" }))
    }

    func testOtherChromiumFoldersAreLeftOut() {
        XCTAssertFalse(ClaudeFolderImport.looksLikeClaudeData(name: "Google", exists: { $0 == "Local State" }))
        XCTAssertFalse(ClaudeFolderImport.looksLikeClaudeData(name: "Slack", exists: { $0 == "Local State" }))
    }

    func testFolderWithoutLocalStateIsLeftOut() {
        XCTAssertFalse(ClaudeFolderImport.looksLikeClaudeData(name: "Claude-2", exists: { $0 == "claude-code-sessions" }))
    }

    func testCandidatesFromTopLevelNames() {
        let present: Set<String> = [
            "\(support)/Claude/Local State",
            "\(support)/Claude-2/Local State", "\(support)/Claude-2/claude-code-sessions",
            "\(support)/Claude-3/Local State",
            "\(support)/Google/Local State",
            "\(support)/Lanes/Local State",
            "\(support)/.Claude-hidden/Local State",
            "\(support)/Claude-4/claude-code",
        ]
        let found = ClaudeFolderImport.candidates(
            in: support,
            names: ["Google", "Claude-3", "Claude", "Lanes", ".Claude-hidden", "Claude-2", "Claude-4"],
            paths: paths,
            library: ProfileLibrary(),
            userDataDirectories: ["\(support)/Claude-3"],
            exists: present.contains
        )
        XCTAssertEqual(found, [
            .init(name: "Claude-2", path: "\(support)/Claude-2", inUse: false),
            .init(name: "Claude-3", path: "\(support)/Claude-3", inUse: true),
        ])
    }

    // MARK: Refusals

    func testPlainClaudeFolderIsRefusedInAnySpelling() {
        XCTAssertEqual(refusal("\(support)/Claude"), .plainClaudeFolder)
        XCTAssertEqual(refusal("\(support)/claude"), .plainClaudeFolder)
        XCTAssertEqual(refusal("\(support)/Claude/"), .plainClaudeFolder)
        XCTAssertEqual(refusal("\(support)/./Claude"), .plainClaudeFolder)
        XCTAssertEqual(refusal("\(support)/Claude/Partitions"), .plainClaudeFolder)
    }

    func testClaudeCodeFolderIsRefused() {
        XCTAssertEqual(refusal("/Users/umut/.claude"), .claudeCodeFolder)
        XCTAssertEqual(refusal("/Users/umut/.claude/projects"), .claudeCodeFolder)
    }

    func testLanesFoldersAreRefused() {
        XCTAssertEqual(refusal("\(support)/Lanes"), .insideLanes)
        XCTAssertEqual(refusal("\(support)/Lanes/Profiles/x/Claude"), .insideLanes)
    }

    func testFoldersHoldingProtectedOnesAreRefused() {
        XCTAssertEqual(refusal(support), .containsProtectedFolder)
        XCTAssertEqual(refusal("/Users/umut/Library"), .containsProtectedFolder)
        XCTAssertEqual(refusal("/Users/umut"), .containsProtectedFolder)
        XCTAssertEqual(refusal("/"), .containsProtectedFolder)
    }

    func testAnAccountsFolderIsRefused() {
        let work = Profile(id: ProfileID(rawValue: "w"), name: "İş", color: .blue)
        XCTAssertEqual(refusal("\(support)/Lanes/Profiles/w/Claude", library: ProfileLibrary(profiles: [work])), .usedByAccount(work.id))
    }

    func testImportableFolderHasNoRefusal() {
        XCTAssertNil(refusal("\(support)/Claude-2"))
        XCTAssertNil(refusal("/Users/umut/Documents/Claude-Old"))
    }

    func testFolderInUseIsRefused() {
        XCTAssertEqual(refusal("\(support)/Claude-2", inUse: ["\(support)/Claude-2"]), .inUse)
        XCTAssertNil(refusal("\(support)/Claude-2", inUse: ["\(support)/Claude-20"]))
    }

    func testIsInUse() {
        let path = "\(support)/Claude-2"
        XCTAssertTrue(ClaudeFolderImport.isInUse(path: path, userDataDirectories: [path]))
        XCTAssertTrue(ClaudeFolderImport.isInUse(path: path, userDataDirectories: [path + "/"]))
        XCTAssertTrue(ClaudeFolderImport.isInUse(path: path, userDataDirectories: ["\(support)/claude-2"]))
        XCTAssertTrue(ClaudeFolderImport.isInUse(path: path, userDataDirectories: [support]), "a folder above it")
        XCTAssertTrue(ClaudeFolderImport.isInUse(path: path, userDataDirectories: [path + "/Sub"]), "a folder inside it")
        XCTAssertFalse(ClaudeFolderImport.isInUse(path: path, userDataDirectories: ["\(support)/Claude-20"]))
        XCTAssertFalse(ClaudeFolderImport.isInUse(path: path, userDataDirectories: []))
        let instance = RunningInstance(pid: 1, applicationBundlePath: "/Applications/Claude.app", userDataDirectory: path, profileID: nil)
        XCTAssertTrue(ClaudeFolderImport.isInUse(path: path, instances: [instance]))
    }

    // MARK: Names

    func testSuggestedName() {
        XCTAssertEqual(ClaudeFolderImport.suggestedName(folderName: "Claude-2", launcherName: "Claude Work.app"), "Claude Work")
        XCTAssertEqual(ClaudeFolderImport.suggestedName(folderName: "Claude-2", launcherName: nil), "Claude-2", "a bare number is no name")
        XCTAssertEqual(ClaudeFolderImport.suggestedName(folderName: "Claude-Work", launcherName: nil), "Work")
        XCTAssertEqual(ClaudeFolderImport.suggestedName(folderName: "Claude İş", launcherName: nil), "İş")
        XCTAssertEqual(ClaudeFolderImport.suggestedName(folderName: "Claude", launcherName: nil), "Claude")
        XCTAssertEqual(ClaudeFolderImport.suggestedName(folderName: "Eski", launcherName: " .app"), "Eski")
    }

    func testRefusalsHaveShortMessages() {
        let all: [ClaudeFolderImport.Refusal] = [.plainClaudeFolder, .claudeCodeFolder, .insideLanes, .containsProtectedFolder, .usedByAccount(ProfileID(rawValue: "x")), .inUse, .notAFolder, .symbolicLink, .otherVolume]
        for refusal in all {
            XCTAssertFalse(refusal.message.isEmpty)
            XCTAssertLessThanOrEqual(refusal.message.count, 60)
        }
    }
}
