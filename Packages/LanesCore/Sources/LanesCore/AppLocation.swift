import Foundation

/// Where Lanes itself is running from.
public enum AppLocation {
    /// macOS runs a quarantined download from a random read-only copy (App
    /// Translocation). From there Sparkle can't replace Lanes and each launch
    /// looks like a new app.
    public static func isTranslocated(bundlePath: String) -> Bool {
        bundlePath.split(separator: "/").contains("AppTranslocation")
    }

    /// True when Lanes can't stay where it runs: a translocated copy, or a
    /// read-only volume such as the mounted DMG itself, which macOS does not
    /// translocate (seen on macOS 26.6 in the M2 first-install test). Lanes
    /// stops working once that DMG is ejected, and Sparkle can't update it.
    public static func isTemporary(bundlePath: String, volumeIsReadOnly: Bool) -> Bool {
        volumeIsReadOnly || isTranslocated(bundlePath: bundlePath)
    }
}
