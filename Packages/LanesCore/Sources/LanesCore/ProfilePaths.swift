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

    /// Where Lanes keeps clones of Claude.app, one folder per profile named
    /// after its ID. Inside Lanes's own folder rather than ~/Applications, so
    /// Spotlight and Launchpad don't offer a clone that would open without
    /// its account's folder (Faz 0.5.2).
    public var clonesDirectory: URL {
        root.appendingPathComponent("Clones", isDirectory: true)
    }

    /// Where the Faz 0 builds put clones. Still recognised as clones, so an
    /// old one is never mistaken for Claude itself.
    public var legacyClonesDirectory: URL {
        home
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Lanes Profiles", isDirectory: true)
    }

    /// The folder holding one profile's clone and its record. Named by ID, so
    /// renaming the profile never leaves a clone behind and two profiles
    /// with the same name never share one.
    public func cloneFolder(for id: ProfileID) -> URL {
        clonesDirectory.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    /// The clone bundle for a profile. The bundle itself is named after the
    /// profile so it reads well in the Dock and in Cmd-Tab.
    public func cloneBundle(for profile: Profile) -> URL {
        cloneFolder(for: profile.id).appendingPathComponent(ProfilePaths.cloneBundleName(for: profile.name), isDirectory: true)
    }

    public static func cloneBundleName(for name: String) -> String {
        "Claude – \(safeFileName(name)).app"
    }

    /// What Lanes wrote down when it made a profile's clone.
    public func cloneRecordFile(for id: ProfileID) -> URL {
        cloneFolder(for: id).appendingPathComponent("clone.json", isDirectory: false)
    }

    /// True for a path inside either clones folder.
    public func isClonePath(_ path: String) -> Bool {
        let normalized = InstanceMatcher.normalize(path)
        return [clonesDirectory, legacyClonesDirectory].contains { folder in
            normalized.hasPrefix(InstanceMatcher.normalize(folder.path) + "/")
        }
    }

    /// The profile a clone bundle belongs to, read from its folder's name.
    /// Nil for a bundle outside the clones folder, such as a Faz 0 clone.
    public func profileID(forCloneBundle path: String) -> ProfileID? {
        let base = InstanceMatcher.normalize(clonesDirectory.path) + "/"
        let normalized = InstanceMatcher.normalize(path)
        guard normalized.hasPrefix(base) else { return nil }
        let parts = normalized.dropFirst(base.count).split(separator: "/")
        guard parts.count == 2, parts[1].hasSuffix(".app") else { return nil }
        return ProfileID(rawValue: String(parts[0]))
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
