import Foundation

/// One session Lanes moved to another account, kept so the move can be
/// undone: the files Lanes created in the target account, by path.
public struct SessionMove: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var sourceID: ProfileID
    public var targetID: ProfileID
    /// The project's folder name, for the list.
    public var project: String
    /// The Code tab title, when the session had one. Kept only on this Mac,
    /// in Lanes's own settings.
    public var title: String?
    /// Whether a Code tab record was written, so undoing needs the target
    /// app restarted.
    public var addedToCodeTab: Bool
    /// Files and folders Lanes created in the target account.
    public var created: [String]

    public init(id: UUID = UUID(), date: Date, sourceID: ProfileID, targetID: ProfileID, project: String, title: String?, addedToCodeTab: Bool, created: [String]) {
        self.id = id
        self.date = date
        self.sourceID = sourceID
        self.targetID = targetID
        self.project = project
        self.title = title
        self.addedToCodeTab = addedToCodeTab
        self.created = created
    }

    /// The paths that may be removed on undo: only those inside one of
    /// `allowedRoots` (the target account's own folders), so a damaged
    /// settings file can never point undo anywhere else.
    public func removablePaths(allowedRoots: [URL]) -> [String] {
        let roots = allowedRoots.map { InstanceMatcher.normalize($0.standardizedFileURL.path) + "/" }
        return created.filter { path in
            let normalized = InstanceMatcher.normalize(URL(fileURLWithPath: path).standardizedFileURL.path)
            return !path.contains("/../") && roots.contains { normalized.hasPrefix($0) && normalized.count > $0.count }
        }
    }
}

/// The recent moves, newest first, at most `limit`.
public enum SessionMoveLog {
    public static let limit = 20

    public static func adding(_ move: SessionMove, to moves: [SessionMove]) -> [SessionMove] {
        Array(([move] + moves.filter { $0.id != move.id }).prefix(limit))
    }

    public static func decode(_ data: Data?) -> [SessionMove] {
        guard let data, let moves = try? JSONDecoder().decode([SessionMove].self, from: data) else { return [] }
        return moves
    }

    public static func encode(_ moves: [SessionMove]) -> Data? {
        try? JSONEncoder().encode(moves)
    }
}
