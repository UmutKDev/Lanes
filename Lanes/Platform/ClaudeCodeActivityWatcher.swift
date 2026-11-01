import CoreServices
import Foundation
import LanesCore

/// Watches every account's Claude Code `projects/` folder with FSEvents and
/// reports which session file changed and when. Only paths and times are
/// used; no file is opened.
@MainActor
final class ClaudeCodeActivityWatcher {
    struct Write: Equatable {
        var date: Date
        /// The project folder the changed session belongs to.
        var projectFolderName: String
    }

    /// Called on the main thread with the account whose session changed.
    var onWrite: ((ProfileID, Write) -> Void)?

    private var stream: FSEventStreamRef?
    private var roots: [(id: ProfileID, path: String)] = []

    /// Watches these folders, replacing the previous set. Folders that do
    /// not exist yet are skipped; the caller passes them again later.
    func watch(_ folders: [ProfileID: URL]) {
        let existing = folders.compactMap { id, url -> (id: ProfileID, path: String)? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return (id, url.resolvingSymlinksInPath().standardizedFileURL.path)
        }
        .sorted { $0.path < $1.path }
        guard existing.map(\.path) != roots.map(\.path) || existing.map(\.id) != roots.map(\.id) else { return }
        stop()
        roots = existing
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let changed = Array(list.prefix(count))
            MainActor.assumeIsolated {
                watcher.handle(changed)
            }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(_ paths: [String]) {
        let now = Date()
        var latest: [ProfileID: Write] = [:]
        for path in paths where path.hasSuffix(".jsonl") {
            guard let root = roots.first(where: { path.hasPrefix($0.path + "/") }) else { continue }
            // projects/<folder>/<session>.jsonl; deeper files (subagent
            // logs) still name their project by the first part.
            let relative = path.dropFirst(root.path.count + 1).split(separator: "/")
            guard relative.count >= 2 else { continue }
            latest[root.id] = Write(date: now, projectFolderName: String(relative[0]))
        }
        for (id, write) in latest {
            onWrite?(id, write)
        }
    }
}
