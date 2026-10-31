import Foundation
import XCTest
@testable import LanesCore

final class ToolboxTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testShareAndUnshare() throws {
        let toolbox = Toolbox(directory: root.appendingPathComponent("Toolbox"))
        let account = root.appendingPathComponent("ClaudeCode")
        XCTAssertEqual(toolbox.state(of: .commands, inAccountFolder: account), .absent)
        try toolbox.share(.commands, inAccountFolder: account)
        try toolbox.share(.claudeMD, inAccountFolder: account)
        XCTAssertEqual(toolbox.state(of: .commands, inAccountFolder: account), .shared)
        XCTAssertEqual(toolbox.state(of: .claudeMD, inAccountFolder: account), .shared)
        XCTAssertNoThrow(try toolbox.share(.commands, inAccountFolder: account), "sharing twice is fine")

        try toolbox.unshare(.commands, inAccountFolder: account)
        XCTAssertEqual(toolbox.state(of: .commands, inAccountFolder: account), .absent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: toolbox.url(of: .commands).path), "the Toolbox copy stays")
    }

    func testAccountsOwnItemsAreLeftAlone() throws {
        let toolbox = Toolbox(directory: root.appendingPathComponent("Toolbox"))
        let account = root.appendingPathComponent("ClaudeCode")
        try FileManager.default.createDirectory(at: account.appendingPathComponent("agents"), withIntermediateDirectories: true)
        XCTAssertEqual(toolbox.state(of: .agents, inAccountFolder: account), .own)
        XCTAssertThrowsError(try toolbox.share(.agents, inAccountFolder: account))
        XCTAssertThrowsError(try toolbox.unshare(.agents, inAccountFolder: account))
        XCTAssertTrue(FileManager.default.fileExists(atPath: account.appendingPathComponent("agents").path))
    }

    func testMCPConfig() throws {
        let toolbox = Toolbox(directory: root.appendingPathComponent("Toolbox"))
        XCTAssertEqual(toolbox.mcpArguments(), [], "no file, nothing added")
        try FileManager.default.createDirectory(at: toolbox.directory, withIntermediateDirectories: true)
        try Data(MCPConfig.template.utf8).write(to: toolbox.mcpConfigFile)
        XCTAssertEqual(toolbox.mcpArguments(), [], "an empty list adds nothing")
        try Data(#"{"mcpServers":{"b":{"command":"x"},"a":{"command":"y"}}}"#.utf8).write(to: toolbox.mcpConfigFile)
        XCTAssertEqual(try MCPConfig.serverNames(in: Data(contentsOf: toolbox.mcpConfigFile)), ["a", "b"])
        XCTAssertEqual(toolbox.mcpArguments(), ["--mcp-config", toolbox.mcpConfigFile.path])
        XCTAssertThrowsError(try MCPConfig.serverNames(in: Data("[]".utf8)))
        XCTAssertThrowsError(try MCPConfig.serverNames(in: Data(#"{"servers":{}}"#.utf8)))
    }
}
