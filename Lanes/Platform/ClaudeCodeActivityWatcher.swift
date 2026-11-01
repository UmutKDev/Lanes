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
    /// Watched folders and the accounts using each; two accounts can share
    /// one Claude Code folder.
    private var roots: [String: [ProfileID]] = [:]

    /// Watches these folders, replacing the previous set. Folders that do
    /// not exist yet are skipped; the caller passes them again later.
    func watch(_ folders: [ProfileID: URL]) {
        var existing: [String: [ProfileID]] = [:]
        for (id, url) in folders {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            existing[Self.canonicalPath(url.path), default: []].append(id)
        }
        for key in existing.keys {
            existing[key]?.sort { $0.rawValue < $1.rawValue }
        }
        guard existing != roots else { return }
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
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            // Removals (Claude Code clearing old sessions at start) and
            // renames are not work, so only writes and new files count.
            let removed = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
            let written = FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemCreated)
            var changed: [String] = []
            for index in 0..<min(count, list.count) {
                let flag = flags[index]
                if flag & removed == 0, flag & written != 0 {
                    changed.append(list[index])
                }
            }
            MainActor.assumeIsolated {
                watcher.handle(changed)
            }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            Array(existing.keys) as CFArray,
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

    /// The real path, keeping /private, which FSEvents reports and
    /// URL.resolvingSymlinksInPath would drop.
    static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func handle(_ paths: [String]) {
        let now = Date()
        var latest: [ProfileID: Write] = [:]
        for path in paths where path.hasSuffix(".jsonl") {
            guard let root = roots.keys.first(where: { path.hasPrefix($0 + "/") }), let ids = roots[root] else { continue }
            // projects/<folder>/<session>.jsonl; deeper files (subagent
            // logs) still name their project by the first part.
            let relative = path.dropFirst(root.count + 1).split(separator: "/")
            guard relative.count >= 2 else { continue }
            for id in ids {
                latest[id] = Write(date: now, projectFolderName: String(relative[0]))
            }
        }
        for (id, write) in latest {
            onWrite?(id, write)
        }
    }
}
