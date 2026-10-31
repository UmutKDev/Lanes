import AppKit
import LanesCore

/// The installed Claude Desktop app.
struct ClaudeInstallation: Equatable {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    let url: URL
    let version: String?

    /// Finds Claude.app, skipping Lanes's own clones: they share Claude's
    /// bundle identifier, and Launch Services may list them first.
    static func find(paths: ProfilePaths) -> ClaudeInstallation? {
        let clonesPath = InstanceMatcher.normalize(paths.clonesDirectory.path) + "/"
        let candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !InstanceMatcher.normalize($0.path).hasPrefix(clonesPath) }
        let preferred = candidates.first(where: { $0.path.hasPrefix("/Applications/") }) ?? candidates.first
        guard let url = preferred else { return nil }
        // Read from the file each time: Bundle caches its Info.plist, so it
        // would keep showing the version from before a Claude update.
        let plist = url.appendingPathComponent("Contents/Info.plist", isDirectory: false)
        let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String
        return ClaudeInstallation(url: url, version: version)
    }
}
