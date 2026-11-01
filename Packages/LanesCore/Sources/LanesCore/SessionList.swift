import Foundation

/// Every Claude Code session of one account, from file names and dates
/// only. The session files hold the conversations, so Lanes never opens
/// them.
public struct ClaudeCodeSessionList: Equatable, Sendable {
    public struct Session: Equatable, Sendable, Identifiable {
        /// What `claude --resume` takes.
        public var id: String
        /// Claude Code's folder name for the project, the project's path
        /// with `/` turned into `-`.
        public var projectFolderName: String
        public var modifiedAt: Date

        public init(id: String, projectFolderName: String, modifiedAt: Date) {
            self.id = id
            self.projectFolderName = projectFolderName
            self.modifiedAt = modifiedAt
        }
    }

    /// Newest first.
    public var sessions: [Session]

    public init(sessions: [Session]) {
        self.sessions = sessions.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public static func read(_ projectsDirectory: URL) -> ClaudeCodeSessionList {
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var sessions: [Session] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                sessions.append(Session(id: file.deletingPathExtension().lastPathComponent, projectFolderName: folder.lastPathComponent, modifiedAt: date))
            }
        }
        return ClaudeCodeSessionList(sessions: sessions)
    }

    /// The project folder a session ran in. Claude Code turns every `/` (and
    /// `.`) of the path into `-`, so a name with hyphens has more than one
    /// reading. The first reading that exists on disk wins, trying the
    /// fewest splits first; nil when none exists.
    public static func projectPath(forFolderName name: String, exists: (String) -> Bool) -> String? {
        guard name.hasPrefix("-") else { return nil }
        let parts = name.dropFirst().split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= 24 else { return nil }
        var path = ""
        var index = 0
        // Walk the parts, joining with "-" while the joined name is not a
        // folder of its own, so "/Users/u/my-app" reads back.
        while index < parts.count {
            var component = parts[index]
            var next = index + 1
            var best: (String, Int)? = exists(path + "/" + component) ? (component, next) : nil
            while next < parts.count {
                component += "-" + parts[next]
                next += 1
                if exists(path + "/" + component) {
                    best = (component, next)
                }
            }
            guard let (found, end) = best else { return nil }
            path += "/" + found
            index = end
        }
        return path.isEmpty ? nil : path
    }

    /// Sessions touched per day over the last `days` days, oldest first,
    /// for the Usage page. Counts files, not their contents.
    public func activity(days: Int, now: Date, calendar: Calendar = .current) -> [(day: Date, sessions: Int)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let count = sessions.filter { $0.modifiedAt >= day && $0.modifiedAt < next }.count
            return (day, count)
        }
    }
}

/// Continuing one account's Claude Code session with another account.
///
/// Claude Code keeps a session as `projects/<folder>/<id>.jsonl`, with an
/// optional `<id>/` folder next to it. Its own `--resume` only finds
/// sessions in the account's own `projects/`, so Lanes copies those two
/// items to the same place in the other account and resumes there with
/// `--fork-session`. Lanes never opens the files; the copy is made by the
/// file system. The original stays as it was.
public struct SessionHandoff: Equatable, Sendable {
    public var sourceFile: URL
    public var sourceFolder: URL
    public var destinationFile: URL
    public var destinationFolder: URL

    /// Nil when a name could lead outside `projects/`.
    public init?(sessionID: String, projectFolderName: String, fromProjects source: URL, toProjects destination: URL) {
        guard Self.isPlainName(sessionID), Self.isPlainName(projectFolderName),
              source.standardizedFileURL != destination.standardizedFileURL else { return nil }
        let from = source.appendingPathComponent(projectFolderName, isDirectory: true)
        let to = destination.appendingPathComponent(projectFolderName, isDirectory: true)
        sourceFile = from.appendingPathComponent(sessionID + ".jsonl", isDirectory: false)
        sourceFolder = from.appendingPathComponent(sessionID, isDirectory: true)
        destinationFile = to.appendingPathComponent(sessionID + ".jsonl", isDirectory: false)
        destinationFolder = to.appendingPathComponent(sessionID, isDirectory: true)
    }

    /// The arguments that continue the copy as a new session, so the copy
    /// itself stays an exact copy and can be replaced by a newer one later.
    public static func resumeArguments(sessionID: String) -> [String] {
        ["--resume", sessionID, "--fork-session"]
    }

    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\0") && !name.hasPrefix(".")
    }
}
