import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import LanesCore

final class SingleWindowGeometryTests: XCTestCase {
    func testClaudeCoversEverythingRightOfTheSidebar() {
        // Main screen 1000 high, Lanes window 1200x800 with its bottom at
        // y = 100 (AppKit), so its top is 100 from the top of the screen.
        let window = CGRect(x: 50, y: 100, width: 1200, height: 800)
        let frame = SingleWindowGeometry.claudeFrame(window: window, sidebarWidth: 220, mainScreenHeight: 1000)
        XCTAssertEqual(frame, CGRect(x: 270, y: 100, width: 980, height: 800))
    }

    func testRoundTrip() {
        let window = CGRect(x: 30, y: 60, width: 1300, height: 840)
        let claude = SingleWindowGeometry.claudeFrame(window: window, sidebarWidth: 210, mainScreenHeight: 1117)
        XCTAssertEqual(SingleWindowGeometry.windowFrame(around: claude, sidebarWidth: 210, mainScreenHeight: 1117), window)
    }

    func testTinyWindowStillGivesClaudeRoom() {
        let frame = SingleWindowGeometry.claudeFrame(window: CGRect(x: 0, y: 0, width: 300, height: 100), sidebarWidth: 220, mainScreenHeight: 1000)
        XCTAssertEqual(frame.width, SingleWindowGeometry.minimumStageWidth)
        XCTAssertEqual(frame.height, SingleWindowGeometry.minimumStageHeight)
    }
}
