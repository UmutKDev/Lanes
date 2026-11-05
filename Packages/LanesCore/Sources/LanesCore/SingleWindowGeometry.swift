import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where the active account's Claude window goes in single-window mode:
/// the Lanes window has the account list on the left, and Claude's window
/// covers the rest of it, so the two read as one window.
///
/// The Lanes window's frame is in AppKit coordinates (bottom-left of the
/// main screen), Claude's in Accessibility coordinates (top-left), so every
/// frame is converted with the main screen's height.
public enum SingleWindowGeometry {
    /// Claude's frame (Accessibility coordinates) for a Lanes window at
    /// `window` (AppKit coordinates) whose account list is `sidebarWidth`
    /// wide.
    public static func claudeFrame(window: CGRect, sidebarWidth: CGFloat, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: window.minX + sidebarWidth,
            y: mainScreenHeight - window.maxY,
            width: max(window.width - sidebarWidth, minimumStageWidth),
            height: max(window.height, minimumStageHeight)
        )
    }

    /// The Lanes window's frame (AppKit coordinates) around a Claude window
    /// at `claude` (Accessibility coordinates). Used when the user moves or
    /// resizes Claude's window itself.
    public static func windowFrame(around claude: CGRect, sidebarWidth: CGFloat, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: claude.minX - sidebarWidth,
            y: mainScreenHeight - claude.maxY,
            width: claude.width + sidebarWidth,
            height: claude.height
        )
    }

    /// Below these a Claude window is no use.
    public static let minimumStageWidth: CGFloat = 480
    public static let minimumStageHeight: CGFloat = 360
}
