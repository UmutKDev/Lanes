import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Decides from the window list whether macOS is drawing the menu bar on a
/// screen.
///
/// An account hidden from the Dock runs as an accessory app, which owns no
/// menu bar. On a Space where only such apps have windows, macOS 26 and 27
/// sometimes stop drawing the menu bar altogether, clock included, until
/// the user clicks at the top of the screen. The window list shows this: the
/// screen's "Menubar" window (layer 24) is missing, transparent or moved off
/// the top edge.
///
/// All rectangles use the window list's coordinates: origin at the top left
/// of the primary screen, y growing downwards.
public enum MenuBarCheck {
    /// One on-screen window, as `CGWindowListCopyWindowInfo` reports it.
    public struct Window: Equatable, Sendable {
        public var layer: Int
        public var bounds: CGRect
        public var alpha: Double

        public init(layer: Int, bounds: CGRect, alpha: Double) {
            self.layer = layer
            self.bounds = bounds
            self.alpha = alpha
        }
    }

    /// The level of the menu bar window, `CGWindowLevelForKey(.mainMenuWindow)`.
    public static let menuBarLayer = 24

    /// True when a visible menu bar window sits on the top edge of `screen`.
    public static func isShown(on screen: CGRect, windows: [Window]) -> Bool {
        windows.contains { window in
            window.layer == menuBarLayer
                && window.alpha > 0.05
                && window.bounds.height > 0
                && abs(window.bounds.minY - screen.minY) <= 2
                && window.bounds.intersects(screen)
        }
    }

    /// True when any menu bar window is on screen at all. Used once to make
    /// sure the window list looks the way `isShown` expects on this Mac;
    /// otherwise Lanes would take every screen for one without a menu bar.
    public static func anyMenuBar(in windows: [Window]) -> Bool {
        windows.contains { $0.layer == menuBarLayer && $0.alpha > 0.05 && $0.bounds.height > 0 }
    }

    /// A window that covers the whole screen, top edge included, is in
    /// full screen. There the menu bar is meant to be hidden.
    public static func coversScreen(_ window: CGRect, screen: CGRect) -> Bool {
        window.minX <= screen.minX + 1 && window.minY <= screen.minY + 1
            && window.maxX >= screen.maxX - 1 && window.maxY >= screen.maxY - 1
    }

    /// Turns a screen frame from AppKit (origin at the bottom left of the
    /// primary screen) into window list coordinates.
    public static func windowListRect(ofScreen frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
