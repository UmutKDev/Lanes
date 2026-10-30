import Foundation
import XCTest
@testable import LanesCore

final class FolderActivityTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderActivityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func setDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testMissingFolderHasNoDate() {
        let missing = directory.appendingPathComponent("yok", isDirectory: true)
        XCTAssertNil(FolderActivity.latestModification(of: missing))
        XCTAssertFalse(FolderActivity.changed(missing, since: .distantPast))
    }

    func testNewestTopLevelItemCounts() throws {
        let old = Date(timeIntervalSince1970: 1_790_000_000)
        let new = old.addingTimeInterval(600)
        let file = directory.appendingPathComponent("Preferences")
        try Data("{}".utf8).write(to: file)
        try setDate(new, of: file)
        try setDate(old, of: directory)

        XCTAssertEqual(FolderActivity.latestModification(of: directory), new)
        XCTAssertTrue(FolderActivity.changed(directory, since: new))
        XCTAssertFalse(FolderActivity.changed(directory, since: new.addingTimeInterval(60)))
    }

    func testDeeperItemsAreNotWalked() throws {
        let old = Date(timeIntervalSince1970: 1_790_000_000)
        let sub = directory.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let deep = sub.appendingPathComponent("data")
        try Data("x".utf8).write(to: deep)
        try setDate(old.addingTimeInterval(600), of: deep)
        try setDate(old, of: sub)
        try setDate(old, of: directory)

        XCTAssertEqual(FolderActivity.latestModification(of: directory), old)
    }
}
