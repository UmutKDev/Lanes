import Foundation
import XCTest
@testable import LanesCore

final class ClaudeCodeSessionsTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LanesCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func file(_ path: String, modified: TimeInterval) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: modified)], ofItemAtPath: url.path)
    }

    func testReadsNamesCountsAndTheNewestSession() throws {
        try file("-Users-ali-Lanes/aaaa.jsonl", modified: 1_790_000_000)
        try file("-Users-ali-Lanes/bbbb.jsonl", modified: 1_790_000_500)
        try file("-Users-ali-Lanes/notes.txt", modified: 1_790_009_000)
        try file("-Users-ali-Other/cccc.jsonl", modified: 1_790_000_100)
        try file("stray.jsonl", modified: 1_790_009_000)

        let folder = ClaudeCodeSessionFolder.read(directory)

        XCTAssertEqual(folder.projects, [
            .init(folderName: "-Users-ali-Lanes", sessionCount: 2),
            .init(folderName: "-Users-ali-Other", sessionCount: 1),
        ])
        XCTAssertEqual(folder.sessionCount, 3)
        XCTAssertEqual(folder.newestSession?.id, "bbbb")
        XCTAssertEqual(folder.newestSession?.projectFolderName, "-Users-ali-Lanes")
        XCTAssertEqual(folder.evidenceLines, [
            "2 proje klasörü, 3 oturum dosyası.",
            "-Users-ali-Lanes: 2 oturum",
            "-Users-ali-Other: 1 oturum",
            "En yeni oturum: bbbb (-Users-ali-Lanes)",
        ])
    }

    func testMissingFolderIsEmpty() {
        let folder = ClaudeCodeSessionFolder.read(directory.appendingPathComponent("projects"))
        XCTAssertEqual(folder, ClaudeCodeSessionFolder(projects: [], newestSession: nil))
        XCTAssertEqual(folder.evidenceLines, ["0 proje klasörü, 0 oturum dosyası."])
    }
}
