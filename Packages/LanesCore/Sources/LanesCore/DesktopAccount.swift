import Foundation

/// Which account the Claude app is signed in to, as far as Lanes needs to
/// know: only the account number (`lastKnownAccountUuid`) in the app's
/// `config.json`. The app keeps no email or name there.
///
/// The same file also holds the app's sign-in keys (`oauth:tokenCache`,
/// `oauth:tokenCacheV2`). Lanes never reads, keeps, logs or returns them:
/// only the one top-level account number is taken from the parsed file and
/// everything else is dropped right away.
public enum DesktopAccount {
    /// Files over this size are skipped; the real one is far smaller.
    static let maximumFileSize = 2 * 1024 * 1024

    /// The account number in a `config.json` file's contents, lowercased,
    /// or nil when it is missing or not a UUID. Never reads the
    /// `oauth:tokenCache` / `oauth:tokenCacheV2` keys.
    public static func parseAccountUuid(_ data: Data) -> String? {
        guard data.count <= maximumFileSize,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return normalizedUuid(root["lastKnownAccountUuid"])
    }

    /// Reads only the account number from the Claude app's `config.json`.
    /// Never reads the `oauth:tokenCache` / `oauth:tokenCacheV2` keys.
    public static func readAccountUuid(from configURL: URL) -> String? {
        guard
            let size = (try? configURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
            size <= maximumFileSize,
            let data = try? Data(contentsOf: configURL)
        else { return nil }
        return parseAccountUuid(data)
    }

    /// A UUID string, lowercased, or nil for anything else.
    static func normalizedUuid(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: text) else { return nil }
        return uuid.uuidString.lowercased()
    }
}

/// Whether Claude Code is signed in to the same account as the Claude app.
public enum AccountMatch: Equatable, Sendable {
    case same
    case different
    /// One of the two account numbers is missing.
    case unknown

    public init(claudeCodeUuid: String?, desktopUuid: String?) {
        guard let claudeCodeUuid, let desktopUuid else {
            self = .unknown
            return
        }
        self = claudeCodeUuid == desktopUuid ? .same : .different
    }
}

extension ProfilePaths {
    /// The Claude app's `config.json` for a profile: in the profile's own
    /// data folder, or Claude's own folder for the default profile.
    public func desktopConfigFile(for profile: Profile) -> URL {
        effectiveDesktopDataDirectory(for: profile).appendingPathComponent("config.json", isDirectory: false)
    }
}
