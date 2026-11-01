import Foundation
import XCTest
@testable import LanesCore

final class MCPStudioTests: XCTestCase {
    var root: URL!
    var toolbox: Toolbox!
    let first = ProfileID(rawValue: "first")
    let second = ProfileID(rawValue: "second")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        toolbox = Toolbox(directory: root.appendingPathComponent("Toolbox", isDirectory: true))
        try FileManager.default.createDirectory(at: toolbox.directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeServers(_ json: String) throws {
        try Data(json.utf8).write(to: toolbox.mcpConfigFile)
    }

    func testSettings() {
        var settings = MCPAccountSettings()
        XCTAssertTrue(settings.isEnabled("github", for: first), "on until turned off")
        settings.set("github", enabled: false, for: first)
        XCTAssertFalse(settings.isEnabled("github", for: first))
        XCTAssertTrue(settings.isEnabled("github", for: second))
        settings.set("github", enabled: false, for: first)
        XCTAssertEqual(settings.disabled["github"], ["first"], "no duplicates")
        settings.set("github", enabled: true, for: first)
        XCTAssertNil(settings.disabled["github"])

        settings.set("a", enabled: false, for: first)
        settings.set("a", enabled: false, for: second)
        settings.set("gone", enabled: false, for: first)
        settings.prune(servers: ["a"], profiles: [second])
        XCTAssertEqual(settings.disabled, ["a": ["second"]])
    }

    func testArgumentsPerAccount() throws {
        XCTAssertEqual(toolbox.mcpArguments(for: first), [], "no file")
        try writeServers(#"{"mcpServers":{"a":{"command":"x","env":{"K":"secret"}},"b":{"url":"https://example.com/mcp"}}}"#)
        XCTAssertEqual(toolbox.mcpArguments(for: first), ["--mcp-config", toolbox.mcpConfigFile.path], "all on: the shared file")

        var settings = MCPAccountSettings()
        settings.set("b", enabled: false, for: first)
        try settings.save(to: toolbox.mcpAccountsFile)
        let file = toolbox.accountMCPFile(for: first)
        XCTAssertEqual(toolbox.mcpArguments(for: first), ["--mcp-config", file.path])
        let servers = try MCPConfig.servers(in: Data(contentsOf: file))
        XCTAssertEqual(Array(servers.keys), ["a"])
        XCTAssertEqual(servers["a"], .object(["command": .string("x"), "env": .object(["K": .string("secret")])]), "kept as written")
        #if os(macOS)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        #endif
        XCTAssertEqual(toolbox.mcpArguments(for: second), ["--mcp-config", toolbox.mcpConfigFile.path], "other accounts unchanged")

        settings.set("a", enabled: false, for: first)
        try settings.save(to: toolbox.mcpAccountsFile)
        XCTAssertEqual(toolbox.mcpArguments(for: first), [], "none on: nothing")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the old copy goes")
    }

    func testRemote() {
        XCTAssertTrue(MCPConfig.isRemote(.object(["url": .string("https://x")])))
        XCTAssertFalse(MCPConfig.isRemote(.object(["command": .string("npx")])))
    }

    func testPackRoundTripBlanksSecrets() throws {
        try writeServers(#"{"mcpServers":{"a":{"command":"x","env":{"TOKEN":"secret"}},"b":{"type":"http","url":"https://e/mcp","headers":{"Authorization":"Bearer s"}}}}"#)
        try FileManager.default.createDirectory(at: toolbox.url(of: .commands), withIntermediateDirectories: true)
        try Data("Review the diff.".utf8).write(to: toolbox.url(of: .commands).appendingPathComponent("review.md"))
        try FileManager.default.createDirectory(at: toolbox.url(of: .skills).appendingPathComponent("lint"), withIntermediateDirectories: true)
        try Data("# Lint".utf8).write(to: toolbox.url(of: .skills).appendingPathComponent("lint/SKILL.md"))
        try Data([0, 1, 2, 0]).write(to: toolbox.url(of: .skills).appendingPathComponent("lint/blob.bin"))
        try Data("hidden".utf8).write(to: toolbox.url(of: .commands).appendingPathComponent(".secret"))
        try Data("Be brief.".utf8).write(to: toolbox.url(of: .claudeMD))

        let (pack, skipped) = try TeamPack.make(from: toolbox, exportedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(skipped, ["skills/lint/blob.bin"])
        XCTAssertEqual(pack.files, ["CLAUDE.md": "Be brief.", "commands/review.md": "Review the diff.", "skills/lint/SKILL.md": "# Lint"])
        XCTAssertEqual(pack.blanked, ["a: TOKEN", "b: Authorization"])
        let encoded = try pack.encoded()
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("Bearer"))
        XCTAssertEqual(try TeamPack.decode(encoded), pack)

        // Into another Mac's Toolbox that already has its own "a".
        let other = Toolbox(directory: root.appendingPathComponent("Other", isDirectory: true))
        try FileManager.default.createDirectory(at: other.directory, withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"a":{"command":"mine"}}}"#.utf8).write(to: other.mcpConfigFile)
        try FileManager.default.createDirectory(at: other.url(of: .commands), withIntermediateDirectories: true)
        try Data("my own".utf8).write(to: other.url(of: .commands).appendingPathComponent("review.md"))

        let result = try pack.install(into: other)
        XCTAssertEqual(result.addedServers, ["b"])
        XCTAssertEqual(result.skippedServers, ["a"])
        XCTAssertEqual(result.blanked, ["b: Authorization"])
        XCTAssertEqual(result.addedFiles, ["CLAUDE.md", "skills/lint/SKILL.md"])
        XCTAssertEqual(result.skippedFiles, ["commands/review.md"])
        let servers = try MCPConfig.servers(in: Data(contentsOf: other.mcpConfigFile))
        XCTAssertEqual(servers["a"], .object(["command": .string("mine")]), "own server untouched")
        XCTAssertEqual(try String(contentsOf: other.url(of: .commands).appendingPathComponent("review.md"), encoding: .utf8), "my own")

        let again = try pack.install(into: other)
        XCTAssertEqual(again.addedServers, [])
        XCTAssertEqual(again.addedFiles, [], "installing twice changes nothing")
    }

    func testPackPathsStayInside() {
        XCTAssertNotNil(TeamPack.destination(of: "commands/a.md", in: toolbox))
        XCTAssertNotNil(TeamPack.destination(of: "CLAUDE.md", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "commands/../../evil", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "../evil", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "/etc/passwd", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "settings.json", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "CLAUDE.md/x", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "commands", in: toolbox))
        XCTAssertNil(TeamPack.destination(of: "commands/.hidden", in: toolbox))
    }

    func testURLSecretsAreBlanked() {
        let (clean, names) = TeamPack.blank(.object(["url": .string("https://bob:pw@mcp.example.com/sse?token=abc&team=1#x")]))
        XCTAssertEqual(clean, .object(["url": .string("https://mcp.example.com/sse?token=&team=")]))
        XCTAssertEqual(names, ["url (kullanıcı:parola)", "url ?team", "url ?token"])
        let (plain, none) = TeamPack.blank(.object(["url": .string("https://mcp.example.com/mcp")]))
        XCTAssertEqual(plain, .object(["url": .string("https://mcp.example.com/mcp")]))
        XCTAssertEqual(none, [])
    }

    func testInstallSkipsUnwritableFiles() throws {
        let pack = TeamPack(kind: TeamPack.kind, version: 1, exportedAt: Date(), mcpServers: [:], files: ["commands/a/b.md": "x", "commands/c.md": "y"], blanked: [])
        try FileManager.default.createDirectory(at: toolbox.url(of: .commands), withIntermediateDirectories: true)
        try Data("file, not folder".utf8).write(to: toolbox.url(of: .commands).appendingPathComponent("a"))
        let result = try pack.install(into: toolbox)
        XCTAssertEqual(result.addedFiles, ["commands/c.md"])
        XCTAssertEqual(result.skippedFiles, ["commands/a/b.md"])
    }

    func testNotAPack() {
        XCTAssertThrowsError(try TeamPack.decode(Data(#"{"kind":"lanes-accounts"}"#.utf8)))
    }
}
