import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest
@testable import LanesCore

final class TabGeometryTests: XCTestCase {
    func testClaudeSitsRightUnderTheStrip() {
        // Main screen 1000 high, strip 40 high with its bottom at y = 900
        // (AppKit), so its top is 60 from the top of the screen.
        let strip = CGRect(x: 100, y: 900, width: 1200, height: 40)
        let frame = TabGeometry.claudeFrame(strip: strip, contentHeight: 800, mainScreenHeight: 1000)
        XCTAssertEqual(frame, CGRect(x: 100, y: 100, width: 1200, height: 800))
    }

    func testRoundTrip() {
        let strip = CGRect(x: 50, y: 700, width: 900, height: 38)
        let claude = TabGeometry.claudeFrame(strip: strip, contentHeight: 600, mainScreenHeight: 1117)
        XCTAssertEqual(TabGeometry.stripFrame(above: claude, stripHeight: 38, mainScreenHeight: 1117), strip)
    }

    func testTinyHeightIsRaised() {
        let frame = TabGeometry.claudeFrame(strip: CGRect(x: 0, y: 0, width: 800, height: 40), contentHeight: 10, mainScreenHeight: 1000)
        XCTAssertEqual(frame.height, TabGeometry.minimumContentHeight)
    }

    func testIsClose() {
        XCTAssertTrue(TabGeometry.isClose(CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 1, y: 1.5, width: 11, height: 9)))
        XCTAssertFalse(TabGeometry.isClose(CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 5, y: 0, width: 10, height: 10)))
    }
}
