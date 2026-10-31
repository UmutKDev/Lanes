import Foundation

/// Where the active account's Claude window goes in tab mode: right under
/// Lanes's tab strip, as wide as the strip.
///
/// AppKit measures from the bottom-left of the main screen, the
/// Accessibility API from its top-left, so every frame is converted with the
/// main screen's height.
public enum TabGeometry {
    /// The Claude window's frame in Accessibility coordinates for a strip
    /// at `strip` (AppKit coordinates) and a window `contentHeight` tall.
    public static func claudeFrame(strip: CGRect, contentHeight: CGFloat, mainScreenHeight: CGFloat) -> CGRect {
        let top = mainScreenHeight - strip.minY
        return CGRect(x: strip.minX, y: top, width: strip.width, height: max(contentHeight, minimumContentHeight))
    }

    /// The strip's frame (AppKit coordinates) that sits right above a Claude
    /// window at `claude` (Accessibility coordinates). Used when the user
    /// moves or resizes the Claude window itself.
    public static func stripFrame(above claude: CGRect, stripHeight: CGFloat, mainScreenHeight: CGFloat) -> CGRect {
        let stripBottom = mainScreenHeight - claude.minY
        return CGRect(x: claude.minX, y: stripBottom, width: claude.width, height: stripHeight)
    }

    /// Below this a Claude window is no use.
    public static let minimumContentHeight: CGFloat = 300

    /// Close enough to count as already in place, so moving a window does
    /// not trigger another move back and forth.
    public static func isClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
