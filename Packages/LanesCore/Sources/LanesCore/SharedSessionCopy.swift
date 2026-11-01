import Foundation

/// Copies an account's own Claude Code sessions out of `~/.claude` when it
/// stops sharing that folder and gets one of its own.
///
/// The Claude app keeps a small record for every Code session it started,
/// under `claude-code-sessions` in its data folder. The conversation itself
/// is Claude Code's file, `projects/<folder>/<session>.jsonl`, in whichever
/// config folder Claude Code used. Once the account switches folders, the
/// app still lists the session but cannot find its file. Copying the files
/// named by the app's records keeps them working.
///
/// Only session numbers are taken from the app's records: they are matched
/// as text, nothing else in them is kept. `~/.claude` is only read, and a
/// file already in the new folder is never replaced.
public enum SharedSessionCopy {
    /// The app's Code session records, inside its data folder.
    public static let recordsFolderName = "claude-code-sessions"
    /// Records larger than this are skipped.
    public static let maxRecordSize = 1 << 20
    /// At most this many records are read.
    public static let maxRecordCount = 5000

    /// Every session number found in the app's Code session records,
    /// lowercased. Empty when the folder is missing.
    public static func sessionIDs(inDesktopData dataDirectory: URL) -> Set<String> {
        let records = dataDirectory.appendingPathComponent(recordsFolderName, isDirectory: true)
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: records,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var ids = Set<String>()
        var read = 0
        for case let url as URL in walker {
            guard read < maxRecordCount else { break }
            guard url.pathExtension.lowercased() == "json",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= maxRecordSize,
                  let data = try? Data(contentsOf: url) else { continue }
            read += 1
            ids.formUnion(uuids(in: data))
        }
        return ids
    }

    /// The UUID-shaped strings in a record, lowercased.
    static func uuids(in data: Data) -> Set<String> {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var found = Set<String>()
        let hex = Set("0123456789abcdefABCDEF")
        let characters = Array(text)
        let length = 36
        var index = 0
        while index + length <= characters.count {
            let slice = characters[index..<(index + length)]
            if isUUID(slice, hex: hex),
               index == 0 || !hex.contains(characters[index - 1]) && characters[index - 1] != "-",
               index + length == characters.count || !hex.contains(characters[index + length]) && characters[index + length] != "-" {
                found.insert(String(slice).lowercased())
                index += length
            } else {
                index += 1
            }
        }
        return found
    }

    private static func isUUID(_ slice: ArraySlice<Character>, hex: Set<Character>) -> Bool {
        for (offset, character) in slice.enumerated() {
            if [8, 13, 18, 23].contains(offset) {
                guard character == "-" else { return false }
            } else {
                guard hex.contains(character) else { return false }
            }
        }
        return true
    }

    /// One session to copy: its file and, when present, its folder of
    /// side files (subagents, tool results).
    public struct Item: Equatable, Sendable {
        public var handoff: SessionHandoff
        public var hasFolder: Bool
    }

    /// The sessions in `sharedProjects` whose number is in `sessionIDs` and
    /// that `targetProjects` does not have yet.
    public static func plan(sessionIDs: Set<String>, sharedProjects: URL, targetProjects: URL) -> [Item] {
        guard !sessionIDs.isEmpty,
              !SessionHandoff.isSameFolder(sharedProjects, targetProjects) else { return [] }
        let manager = FileManager.default
        guard let projectFolders = try? manager.contentsOfDirectory(
            at: sharedProjects,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var items: [Item] = []
        for folder in projectFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let files = try? manager.contentsOfDirectory(
                      at: folder,
                      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                      options: [.skipsHiddenFiles]
                  ) else { continue }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "jsonl" {
                let id = file.deletingPathExtension().lastPathComponent
                guard sessionIDs.contains(id.lowercased()),
                      let fileValues = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      fileValues.isRegularFile == true, fileValues.isSymbolicLink != true,
                      let handoff = SessionHandoff(sessionID: id, projectFolderName: folder.lastPathComponent, fromProjects: sharedProjects, toProjects: targetProjects),
                      !exists(handoff.destinationFile), !exists(handoff.destinationFolder) else { continue }
                items.append(Item(handoff: handoff, hasFolder: isPlainFolder(handoff.sourceFolder)))
            }
        }
        return items
    }

    /// Copies the planned sessions. Returns how many were copied; a session
    /// that fails is skipped and the rest still go.
    @discardableResult
    public static func copy(_ items: [Item]) -> (copied: Int, failed: Int) {
        let manager = FileManager.default
        var copied = 0
        var failed = 0
        for item in items {
            let handoff = item.handoff
            // Checked again: something may have appeared since planning.
            guard !exists(handoff.destinationFile), !exists(handoff.destinationFolder) else { continue }
            // Copied under hidden names first and renamed only when whole,
            // so a failed copy never leaves a half session that a later run
            // would take as done.
            let parent = handoff.destinationFile.deletingLastPathComponent()
            let partialFile = parent.appendingPathComponent("." + handoff.destinationFile.lastPathComponent + ".lanes-partial", isDirectory: false)
            let partialFolder = parent.appendingPathComponent("." + handoff.destinationFolder.lastPathComponent + ".lanes-partial", isDirectory: true)
            let copiesFolder = item.hasFolder && isPlainFolder(handoff.sourceFolder)
            do {
                try manager.createDirectory(at: parent, withIntermediateDirectories: true)
                try? manager.removeItem(at: partialFile)
                try? manager.removeItem(at: partialFolder)
                try manager.copyItem(at: handoff.sourceFile, to: partialFile)
                if copiesFolder {
                    try manager.copyItem(at: handoff.sourceFolder, to: partialFolder)
                    try manager.moveItem(at: partialFolder, to: handoff.destinationFolder)
                }
                try manager.moveItem(at: partialFile, to: handoff.destinationFile)
                copied += 1
            } catch {
                try? manager.removeItem(at: partialFile)
                try? manager.removeItem(at: partialFolder)
                // A side folder moved in without its session file would make
                // later runs skip the session.
                if copiesFolder, !exists(handoff.destinationFile) {
                    try? manager.removeItem(at: handoff.destinationFolder)
                }
                failed += 1
            }
        }
        return (copied, failed)
    }

    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func isPlainFolder(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }
}
