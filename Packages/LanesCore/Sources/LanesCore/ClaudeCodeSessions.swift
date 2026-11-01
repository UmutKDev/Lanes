import Foundation

/// The shape of a Claude Code `projects/` folder, read from file names and
/// dates only. Lanes never opens the session files: they hold the
/// conversations.
public struct ClaudeCodeSessionFolder: Equatable, Sendable {
    public struct Project: Equatable, Sendable {
        /// Claude Code names the folder after the project's path.
        public var folderName: String
        public var sessionCount: Int
    }

    public struct Session: Equatable, Sendable {
        public var projectFolderName: String
        /// The file name without `.jsonl`, which is what `claude --resume` takes.
        public var id: String
        public var modifiedAt: Date
    }

    public var projects: [Project]
    public var newestSession: Session?

    public var sessionCount: Int { projects.reduce(0) { $0 + $1.sessionCount } }

    /// Reads the folder. A missing folder reads as empty.
    public static func read(_ projectsDirectory: URL) -> ClaudeCodeSessionFolder {
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var projects: [Project] = []
        var newest: Session?
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            let sessions = files.filter { $0.pathExtension == "jsonl" }
            projects.append(Project(folderName: folder.lastPathComponent, sessionCount: sessions.count))
            for file in sessions {
                guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                if newest.map({ date > $0.modifiedAt }) ?? true {
                    newest = Session(projectFolderName: folder.lastPathComponent, id: file.deletingPathExtension().lastPathComponent, modifiedAt: date)
                }
            }
        }
        return ClaudeCodeSessionFolder(projects: projects, newestSession: newest)
    }

    /// Lines for the check's log.
    public var evidenceLines: [String] {
        var lines = [L("\(projects.count) proje klasörü, \(sessionCount) oturum dosyası.", "\(projects.count) project folders, \(sessionCount) session files.")]
        lines.append(contentsOf: projects.map { L("\($0.folderName): \($0.sessionCount) oturum", "\($0.folderName): \($0.sessionCount) sessions") })
        if let newestSession {
            lines.append(L("En yeni oturum: \(newestSession.id) (\(newestSession.projectFolderName))", "Newest session: \(newestSession.id) (\(newestSession.projectFolderName))"))
        }
        return lines
    }
}
