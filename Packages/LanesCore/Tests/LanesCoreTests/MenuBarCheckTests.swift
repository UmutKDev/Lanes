import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import LanesCore
import XCTest

final class MenuBarCheckTests: XCTestCase {
    // Umut's setup on 2026-11-02: built-in screen as primary, an HP above it.
    let builtIn = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let hpAppKit = CGRect(x: -68, y: 1169, width: 1920, height: 1080)

    var hp: CGRect {
        MenuBarCheck.windowListRect(ofScreen: hpAppKit, primaryHeight: 1169)
    }

    func testScreenConversionMatchesWindowList() {
        XCTAssertEqual(hp, CGRect(x: -68, y: -1080, width: 1920, height: 1080))
        XCTAssertEqual(MenuBarCheck.windowListRect(ofScreen: builtIn, primaryHeight: 1169), builtIn)
    }

    func testMenuBarsOnBothScreens() {
        let windows = [
            MenuBarCheck.Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1800, height: 39), alpha: 1),
            MenuBarCheck.Window(layer: 24, bounds: CGRect(x: -68, y: -1080, width: 1920, height: 30), alpha: 1),
            MenuBarCheck.Window(layer: 0, bounds: CGRect(x: 0, y: 39, width: 1800, height: 1000), alpha: 1),
        ]
        XCTAssertTrue(MenuBarCheck.isShown(on: builtIn, windows: windows))
        XCTAssertTrue(MenuBarCheck.isShown(on: hp, windows: windows))
        XCTAssertTrue(MenuBarCheck.anyMenuBar(in: windows))
    }

    func testMissingTransparentOrMovedMenuBar() {
        let other = MenuBarCheck.Window(layer: 24, bounds: CGRect(x: -68, y: -1080, width: 1920, height: 30), alpha: 1)
        XCTAssertFalse(MenuBarCheck.isShown(on: builtIn, windows: [other]))
        let transparent = MenuBarCheck.Window(layer: 24, bounds: CGRect(x: 0, y: 0, width: 1800, height: 39), alpha: 0)
        XCTAssertFalse(MenuBarCheck.isShown(on: builtIn, windows: [transparent, other]))
        let movedUp = MenuBarCheck.Window(layer: 24, bounds: CGRect(x: 0, y: -39, width: 1800, height: 39), alpha: 1)
        XCTAssertFalse(MenuBarCheck.isShown(on: builtIn, windows: [movedUp, other]))
        XCTAssertFalse(MenuBarCheck.anyMenuBar(in: [transparent]))
    }

    func testFullScreenWindow() {
        XCTAssertTrue(MenuBarCheck.coversScreen(builtIn, screen: builtIn))
        XCTAssertFalse(MenuBarCheck.coversScreen(CGRect(x: 0, y: 39, width: 1800, height: 1130), screen: builtIn))
    }
}
