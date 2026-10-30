import Foundation

/// Where Lanes itself is running from.
public enum AppLocation {
    /// macOS runs an app opened straight from a DMG or a quarantined download
    /// from a random read-only copy (App Translocation). From there Sparkle
    /// can't replace Lanes and each launch looks like a new app, so the
    /// Automation permission may be asked again.
    public static func isTranslocated(bundlePath: String) -> Bool {
        bundlePath.split(separator: "/").contains("AppTranslocation")
    }
}
