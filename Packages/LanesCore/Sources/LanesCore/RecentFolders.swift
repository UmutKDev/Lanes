import Foundation

/// The folders an account last opened Claude Code in, newest first.
public struct RecentFolders: Codable, Equatable, Sendable {
    public static let limit = 5

    public private(set) var paths: [String]

    public init(paths: [String] = []) {
        self.paths = Array(paths.prefix(RecentFolders.limit))
    }

    /// Puts the folder first. A trailing slash or a second visit doesn't
    /// add a second row.
    public mutating func use(_ path: String) {
        let normalized = RecentFolders.normalize(path)
        guard !normalized.isEmpty else { return }
        paths.removeAll { RecentFolders.normalize($0) == normalized }
        paths.insert(normalized, at: 0)
        if paths.count > RecentFolders.limit {
            paths.removeLast(paths.count - RecentFolders.limit)
        }
    }

    public mutating func forget(_ path: String) {
        let normalized = RecentFolders.normalize(path)
        paths.removeAll { RecentFolders.normalize($0) == normalized }
    }

    static func normalize(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

/// Folders under Lanes's Profiles folder that belong to no account, such as
/// those of removed accounts. Only names are compared, nothing is opened.
public enum OrphanProfileFolders {
    public static func find(folderNames: [String], library: ProfileLibrary) -> [String] {
        let known = Set(library.profiles.map(\.id.rawValue))
        return folderNames
            .filter { !$0.hasPrefix(".") && !known.contains($0) }
            .sorted()
    }
}
