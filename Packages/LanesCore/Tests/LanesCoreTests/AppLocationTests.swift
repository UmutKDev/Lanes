import XCTest
@testable import LanesCore

final class AppLocationTests: XCTestCase {
    func testTranslocatedPathIsRecognized() {
        XCTAssertTrue(AppLocation.isTranslocated(bundlePath: "/private/var/folders/xy/abc/T/AppTranslocation/5B1C-77E0/d/Lanes.app"))
    }

    func testApplicationsFolderIsNotTranslocated() {
        XCTAssertFalse(AppLocation.isTranslocated(bundlePath: "/Applications/Lanes.app"))
    }

    func testOnlyAWholePathComponentCounts() {
        XCTAssertFalse(AppLocation.isTranslocated(bundlePath: "/Users/umut/AppTranslocationNotes/Lanes.app"))
    }

    func testReadOnlyVolumeIsTemporary() {
        XCTAssertTrue(AppLocation.isTemporary(bundlePath: "/Volumes/Lanes/Lanes.app", volumeIsReadOnly: true))
    }

    func testTranslocatedCopyIsTemporary() {
        XCTAssertTrue(AppLocation.isTemporary(bundlePath: "/private/var/folders/xy/abc/T/AppTranslocation/5B1C-77E0/d/Lanes.app", volumeIsReadOnly: true))
    }

    func testApplicationsFolderIsNotTemporary() {
        XCTAssertFalse(AppLocation.isTemporary(bundlePath: "/Applications/Lanes.app", volumeIsReadOnly: false))
    }
}
