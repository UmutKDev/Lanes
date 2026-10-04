import Foundation

/// Where Lanes keeps each profile's data on disk.
///
/// Everything lives under one root, `~/Library/Application Support/Lanes` by
/// default. A profile's folders are named after its stable ID, so renaming a
/// profile never moves anything. The default profile has no folders of its own:
/// it uses Claude's standard locations, so the account the user already signed
/// in to keeps working untouched.
public struct ProfilePaths: Sendable, Equatable {
    public let root: URL
    public let home: URL

    public init(root: URL, home: URL) {
        self.root = root
        self.home = home
    }

    /// The standard layout for the current user.
    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ProfilePaths {
        let root = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Lanes", isDirectory: true)
        return ProfilePaths(root: root, home: home)
    }

    /// The list of profiles and their settings.
    public var profilesFile: URL {
        root.appendingPathComponent("profiles.json", isDirectory: false)
    }

    /// Validation reports, logs and other files Lanes writes about itself.
    public var diagnosticsDirectory: URL {
        root.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public func profileDirectory(for id: ProfileID) -> URL {
        root
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(id.rawValue, isDirectory: true)
    }

    /// The folder passed to Claude Desktop as `--user-data-dir`.
    /// `nil` for the default profile, which uses Claude's own folder.
    public func desktopDataDirectory(for profile: Profile) -> URL? {
        guard !profile.isDefault else { return nil }
        return profileDirectory(for: profile.id).appendingPathComponent("Claude", isDirectory: true)
    }

    /// The folder passed to Claude Code as `CLAUDE_CONFIG_DIR`.
    /// `nil` for the default profile, which uses `~/.claude`.
    public func claudeCodeConfigDirectory(for profile: Profile) -> URL? {
        guard !profile.isDefault else { return nil }
        return profileDirectory(for: profile.id).appendingPathComponent("ClaudeCode", isDirectory: true)
    }

    /// Claude Desktop's own data folder, used by the default profile.
    public var claudeDesktopDefaultDataDirectory: URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
    }

    /// Claude Code's own config folder, used by the default profile.
    public var claudeCodeDefaultConfigDirectory: URL {
        home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// The Claude Code folder a profile actually uses, default or not.
    public func effectiveClaudeCodeConfigDirectory(for profile: Profile) -> URL {
        claudeCodeConfigDirectory(for: profile) ?? claudeCodeDefaultConfigDirectory
    }

    /// The Claude Desktop folder a profile actually uses, default or not.
    public func effectiveDesktopDataDirectory(for profile: Profile) -> URL {
        desktopDataDirectory(for: profile) ?? claudeDesktopDefaultDataDirectory
    }

    /// Where signed clones of Claude.app go. Kept in the user's own
    /// Applications folder so Spotlight and Launchpad find them.
    public var clonesDirectory: URL {
        home
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Lanes Profiles", isDirectory: true)
    }

    /// The clone bundle for a profile, named after the profile so it reads well
    /// in the Dock and in Cmd-Tab.
    public func cloneBundle(for profile: Profile) -> URL {
        clonesDirectory.appendingPathComponent("Claude – \(ProfilePaths.safeFileName(profile.name)).app", isDirectory: true)
    }

    /// Replaces characters macOS or Finder treat specially in file names.
    static func safeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let withoutLeadingDot = cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
        return withoutLeadingDot.isEmpty ? "Profil" : withoutLeadingDot
    }
}
