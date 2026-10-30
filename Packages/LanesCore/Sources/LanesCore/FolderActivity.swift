import Foundation

/// When a folder last changed, judged from modification dates alone. Lanes
/// uses it to see that an account's Claude really writes to that account's
/// own folder. No file is opened or read.
public enum FolderActivity {
    /// The newest modification date of the folder itself and of the items
    /// directly inside it. Nil when the folder does not exist. Subfolders are
    /// not walked: Claude rewrites files at the top level within seconds of
    /// starting, and a deep walk of a large profile would be slow.
    public static func latestModification(of folder: URL, fileManager: FileManager = .default) -> Date? {
        let key = URLResourceKey.contentModificationDateKey
        guard let own = try? folder.resourceValues(forKeys: [key]).contentModificationDate else {
            return nil
        }
        let children = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [key])) ?? []
        return children.reduce(own) { latest, child in
            let date = (try? child.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            return max(latest, date)
        }
    }

    /// The newest modification date anywhere under the folder, hidden files
    /// left out. Faz 0 check 4 uses it on Claude Code's projects folder,
    /// which stays small.
    public static func newestModification(in directory: URL) -> Date? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var newest: Date?
        for case let url as URL in enumerator {
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if newest.map({ date > $0 }) ?? true {
                newest = date
            }
        }
        return newest
    }

    /// True when the folder changed at or after `start`. A second of slack
    /// covers file systems that round modification dates.
    public static func changed(_ folder: URL, since start: Date, fileManager: FileManager = .default) -> Bool {
        guard let latest = latestModification(of: folder, fileManager: fileManager) else { return false }
        return latest >= start.addingTimeInterval(-1)
    }
}
