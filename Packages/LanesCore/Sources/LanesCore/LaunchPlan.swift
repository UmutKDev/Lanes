import Foundation

/// Everything needed to start Claude Desktop for one profile. The app turns it
/// into an `NSWorkspace.OpenConfiguration`; keeping it here makes the rules
/// testable without AppKit.
public struct LaunchPlan: Equatable, Sendable {
    /// The app bundle to open: Claude.app itself, or the profile's clone.
    public var applicationURL: URL
    public var arguments: [String]
    /// Variables added to the launched app's environment.
    public var environment: [String: String]
    /// True when macOS must start a separate instance instead of activating a
    /// running one. Always true today: when any profile's Claude is running,
    /// opening Claude.app without it would bring that other account forward.
    /// A profile that is already running is activated, never relaunched.
    public var createsNewInstance: Bool
    /// The folder `--user-data-dir` points to, created before launch.
    public var dataDirectory: URL?
    /// The folder `CLAUDE_CONFIG_DIR` points to, created before launch.
    public var claudeCodeConfigDirectory: URL?
    /// True when the profile should open its clone but none was given, so
    /// Claude itself opens instead. The app says so instead of hiding it.
    public var fallsBackToClaude = false

    public init(
        applicationURL: URL,
        arguments: [String],
        environment: [String: String],
        createsNewInstance: Bool,
        dataDirectory: URL?,
        claudeCodeConfigDirectory: URL?
    ) {
        self.applicationURL = applicationURL
        self.arguments = arguments
        self.environment = environment
        self.createsNewInstance = createsNewInstance
        self.dataDirectory = dataDirectory
        self.claudeCodeConfigDirectory = claudeCodeConfigDirectory
    }

    /// The folders that must exist before launch.
    public var directoriesToCreate: [URL] {
        [dataDirectory, claudeCodeConfigDirectory].compactMap { $0 }
    }
}

public enum LaunchPlanner {
    public static let userDataDirectoryFlag = "--user-data-dir"
    public static let claudeConfigDirectoryVariable = "CLAUDE_CONFIG_DIR"

    /// Builds the launch plan for a profile. A profile inside Lanes gets
    /// the same plan as Standart, for when the user opens it in Claude once.
    ///
    /// - Parameters:
    ///   - claudeApp: The installed Claude.app.
    ///   - cloneApp: The profile's clone, when one exists on disk. Ignored for
    ///     profiles in standard mode.
    public static func plan(
        for profile: Profile,
        claudeApp: URL,
        cloneApp: URL?,
        paths: ProfilePaths
    ) -> LaunchPlan {
        let usesClone = CloneCheck.usesClone(profile)
        let application = usesClone ? (cloneApp ?? claudeApp) : claudeApp

        guard !profile.isDefault else {
            return LaunchPlan(
                applicationURL: application,
                arguments: [],
                environment: [:],
                createsNewInstance: true,
                dataDirectory: nil,
                claudeCodeConfigDirectory: nil
            )
        }

        let dataDirectory = paths.effectiveDesktopDataDirectory(for: profile)
        // nil for an account sharing `~/.claude`: no variable, and Lanes
        // never creates or touches that folder.
        let configDirectory = paths.claudeCodeConfigDirectory(for: profile)
        var plan = LaunchPlan(
            applicationURL: application,
            arguments: ["\(userDataDirectoryFlag)=\(dataDirectory.path)"],
            environment: configDirectory.map { [claudeConfigDirectoryVariable: $0.path] } ?? [:],
            createsNewInstance: true,
            dataDirectory: dataDirectory,
            claudeCodeConfigDirectory: configDirectory
        )
        plan.fallsBackToClaude = usesClone && cloneApp == nil
        return plan
    }

    /// What to do when the user opens a profile: bring its running window
    /// forward, or start it.
    public static func action(
        for profile: Profile,
        running: [RunningInstance],
        claudeApp: URL,
        cloneApp: URL?,
        paths: ProfilePaths
    ) -> LaunchAction {
        if let instance = running.first(where: { $0.profileID == profile.id }) {
            return .activate(pid: instance.pid)
        }
        return .launch(plan(for: profile, claudeApp: claudeApp, cloneApp: cloneApp, paths: paths))
    }
}

/// Builds the full environment for a launched instance.
///
/// It is not documented whether `NSWorkspace.OpenConfiguration.environment`
/// adds to or replaces the inherited environment, so Lanes always passes the
/// whole thing: its own environment, minus variables that only describe Lanes
/// itself, plus the profile's additions.
public enum LaunchEnvironment {
    static let droppedPrefixes = ["DYLD_", "__CF", "XPC_", "OS_ACTIVITY_", "MallocNano", "NSZombie"]
    static let droppedNames: Set<String> = ["CLAUDE_CONFIG_DIR"]

    public static func merged(base: [String: String], additions: [String: String]) -> [String: String] {
        var result = base.filter { key, _ in
            !droppedNames.contains(key) && !droppedPrefixes.contains(where: { key.hasPrefix($0) })
        }
        result.merge(additions) { _, new in new }
        return result
    }
}

public enum LaunchAction: Equatable, Sendable {
    case activate(pid: Int32)
    case launch(LaunchPlan)
}

/// Builds the shell commands that run Claude Code with a profile's account, for
/// the "open in Terminal" action and for copying to the clipboard.
public enum ClaudeCodeCommand {
    /// Where Claude Code's installers put the `claude` command: the official
    /// installer (`~/.local/bin`), the older local install, then Homebrew.
    /// `~` stands for the home folder.
    public static let wellKnownDirectories = [
        "~/.local/bin",
        "~/.claude/local",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// A line for a zsh script that puts those folders on PATH. The official
    /// installer adds `~/.local/bin` only in `~/.zshrc`, which a script run
    /// by Terminal never reads, so `claude` was "command not found" there.
    public static var pathExport: String {
        let folders = wellKnownDirectories.map { $0.hasPrefix("~/") ? "$HOME/" + $0.dropFirst(2) : $0 }
        return "export PATH=\"" + folders.joined(separator: ":") + ":$PATH\""
    }

    /// The `claude` paths to try, with `~` expanded against `home`.
    public static func candidatePaths(home: String) -> [String] {
        wellKnownDirectories.map { folder in
            let expanded = folder.hasPrefix("~/") ? home + "/" + folder.dropFirst(2) : folder
            return expanded + "/claude"
        }
    }

    /// `CLAUDE_CONFIG_DIR='…' claude`, or plain `claude` for the default profile.
    public static func command(for profile: Profile, paths: ProfilePaths, arguments: [String] = []) -> String {
        var parts: [String] = []
        if let directory = paths.claudeCodeConfigDirectory(for: profile) {
            parts.append("\(LaunchPlanner.claudeConfigDirectoryVariable)=\(shellQuoted(directory.path))")
        }
        parts.append("claude")
        parts.append(contentsOf: arguments.map(shellQuoted))
        return parts.joined(separator: " ")
    }

    /// Quotes a value for POSIX shells. Plain words stay unquoted so the
    /// command reads naturally.
    public static func shellQuoted(_ value: String) -> String {
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,")
        if !value.isEmpty, value.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
