import Foundation

/// The account Claude Code says it is signed in to, read from its own
/// `.claude.json`. Only four plain fields of `oauthAccount` are read: the
/// email address, the display name, the organization name and the account
/// number (`accountUuid`, used to tell whether Claude Code and the Claude
/// app are signed in to the same account). Tokens are not in that file
/// (Claude Code keeps them in the Keychain) and nothing else in it is looked at.
public struct ClaudeCodeAccount: Equatable, Sendable {
    public let email: String
    public let displayName: String?
    public let organizationName: String?
    /// The account number, lowercased; nil when missing or not a UUID.
    public let accountUuid: String?

    public init(email: String, displayName: String? = nil, organizationName: String? = nil, accountUuid: String? = nil) {
        self.email = email
        self.displayName = displayName
        self.organizationName = organizationName
        self.accountUuid = accountUuid
    }

    /// The account in a `.claude.json` file's contents, or nil when Claude
    /// Code is not signed in there or the file is not what we expect.
    public static func parse(_ data: Data) -> ClaudeCodeAccount? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = root["oauthAccount"] as? [String: Any],
            let email = clean(account["emailAddress"]),
            email.contains("@")
        else { return nil }
        return ClaudeCodeAccount(
            email: email,
            displayName: clean(account["displayName"]),
            organizationName: clean(account["organizationName"]),
            accountUuid: DesktopAccount.normalizedUuid(account["accountUuid"])
        )
    }

    /// Reads the account from a file. Files over 8 MB are skipped: the real
    /// one is far smaller, and Lanes never loads a large file to find a name.
    public static func read(from url: URL) -> ClaudeCodeAccount? {
        guard
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
            size <= 8 * 1024 * 1024,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return parse(data)
    }

    private static func clean(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}

extension ProfilePaths {
    /// Claude Code's `.claude.json` for a profile: inside the profile's
    /// `CLAUDE_CONFIG_DIR`, or `~/.claude.json` for the default profile.
    public func claudeCodeAccountFile(for profile: Profile) -> URL {
        if let directory = claudeCodeConfigDirectory(for: profile) {
            return directory.appendingPathComponent(".claude.json", isDirectory: false)
        }
        return home.appendingPathComponent(".claude.json", isDirectory: false)
    }
}
