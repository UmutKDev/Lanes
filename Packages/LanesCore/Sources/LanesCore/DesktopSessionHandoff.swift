import Foundation

/// Continuing a session of the Claude app's Code tab in another account's
/// Code tab.
///
/// The app keeps one record per Code session in
/// `claude-code-sessions/<account>/<org>/local_<uuid>.json` inside its data
/// folder. The record's `cliSessionId` names Claude Code's own session file,
/// `projects/<folder>/<uuid>.jsonl`, in the account's Claude Code folder. The
/// Code tab lists the records it finds in its own account's folder, so a
/// session copied with `SessionHandoff` alone does not show up there.
///
/// Lanes copies the session files and writes a new record for the target
/// account, made from the source record with everything tied to the source
/// account (its connectors, tool grants, remote control and bridge links)
/// left out. The record is handled as data only: nothing in it is shown,
/// logged or sent anywhere.
public enum DesktopSessionHandoff {
    /// Records larger than this are skipped.
    public static let maxRecordSize = 16 << 20
    /// At most this many records are searched.
    public static let maxRecordCount = 5000

    static let recordPrefix = "local_"

    /// Keys tied to the source account, or to a run of the source app, that
    /// the new record leaves out. The app fills in what it needs again.
    static let droppedKeys: Set<String> = [
        "enabledMcpTools",
        "bridgeSessionIds",
        "remoteControlSpawn",
        "envScopeId",
        "startedFromEnvironmentId",
        "toolSurfaceSnapshot",
        "scheduledTaskId",
        "forkedFromSessionId",
        "spawnedFrom",
        "publishedArtifacts",
        "sideSessionNotes",
        "error",
        "errorAt",
    ]

    /// Keys reset to an empty list: connectors and permission grants belong
    /// to the source account.
    static let emptiedKeys: [String] = [
        "remoteMcpServersConfig",
        "alwaysAllowedReasons",
        "sessionPermissionUpdates",
    ]

    /// Keys every record has, set to null: they describe the source app's
    /// last run, not the conversation.
    static let nulledKeys: [String] = [
        "interruptedAwaitingPerson",
        "steeredByRemoteClient",
    ]

    /// One record found on disk.
    public struct Record {
        public var url: URL
        public var data: Data
        public var object: [String: Any]
    }

    /// The record whose `cliSessionId` is `sessionID`, from the app's data
    /// folder. Nil when the session was not started in the Code tab.
    public static func findRecord(cliSessionID sessionID: String, inDesktopData dataDirectory: URL) -> Record? {
        let records = dataDirectory.appendingPathComponent(SharedSessionCopy.recordsFolderName, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: records,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let wanted = sessionID.lowercased()
        // The session number is looked for as plain text first, so only the
        // one matching record is parsed.
        let needle = Data(wanted.utf8)
        let needleUpper = Data(sessionID.uppercased().utf8)
        var read = 0
        for case let url as URL in walker {
            guard read < maxRecordCount else { break }
            guard url.lastPathComponent.hasPrefix(recordPrefix), url.pathExtension.lowercased() == "json",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= maxRecordSize,
                  let data = try? Data(contentsOf: url) else { continue }
            read += 1
            guard data.range(of: needle) != nil || data.range(of: needleUpper) != nil,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["cliSessionId"] as? String)?.lowercased() == wanted else { continue }
            return Record(url: url, data: data, object: object)
        }
        return nil
    }

    /// The folder the target app keeps its Code session records in:
    /// `claude-code-sessions/<account>/<org>`. The account folder is the
    /// one named after the app's signed-in account; of its organization
    /// folders, the one with the newest record. Nil when the target app has
    /// not used the Code tab yet, so there is no folder to write into.
    public static func recordsFolder(inDesktopData dataDirectory: URL, accountUuid: String?) -> URL? {
        let manager = FileManager.default
        let root = dataDirectory.appendingPathComponent(SharedSessionCopy.recordsFolderName, isDirectory: true)
        func plainFolders(in url: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? [])
                .filter {
                    let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    return values?.isDirectory == true && values?.isSymbolicLink != true && UUID(uuidString: $0.lastPathComponent) != nil
                }
        }
        let accounts = plainFolders(in: root)
        let account: URL?
        if let accountUuid {
            account = accounts.first { $0.lastPathComponent.lowercased() == accountUuid.lowercased() }
        } else {
            account = accounts.count == 1 ? accounts.first : nil
        }
        guard let account else { return nil }
        let orgs = plainFolders(in: account)
        guard orgs.count > 1 else { return orgs.first }
        return orgs.max { newestRecordDate(in: $0) < newestRecordDate(in: $1) }
    }

    private static func newestRecordDate(in folder: URL) -> Date {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(recordPrefix) && $0.pathExtension == "json" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max() ?? .distantPast
    }

    /// The new record for the target account: the source record under a new
    /// `local_<uuid>` number, not archived, marked as just active,
    /// with the source account's own keys left out.
    public static func transplant(_ record: [String: Any], localID: UUID, now: Date) -> [String: Any] {
        var copy = record
        for key in droppedKeys {
            copy.removeValue(forKey: key)
        }
        for key in emptiedKeys where copy[key] != nil {
            copy[key] = [Any]()
        }
        for key in nulledKeys where copy[key] != nil {
            copy[key] = NSNull()
        }
        copy["sessionId"] = recordPrefix + localID.uuidString.lowercased()
        copy["isArchived"] = false
        copy["isStarred"] = nil
        copy["lastActivityAt"] = NSNumber(value: Int64((now.timeIntervalSince1970 * 1000).rounded()))
        return copy
    }

    /// The file name for a record number.
    public static func fileName(localID: UUID) -> String {
        recordPrefix + localID.uuidString.lowercased() + ".json"
    }

    /// Writes the record into `folder`, never over an existing file.
    /// Written under a hidden name first and renamed when whole, so the app
    /// never sees half a record.
    public static func write(_ record: [String: Any], localID: UUID, into folder: URL) throws -> URL {
        let manager = FileManager.default
        let destination = folder.appendingPathComponent(fileName(localID: localID), isDirectory: false)
        guard (try? manager.attributesOfItem(atPath: destination.path)) == nil else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
        }
        let data = try JSONSerialization.data(withJSONObject: record, options: [])
        let partial = folder.appendingPathComponent("." + destination.lastPathComponent + ".lanes-partial", isDirectory: false)
        try? manager.removeItem(at: partial)
        try data.write(to: partial)
        do {
            try manager.moveItem(at: partial, to: destination)
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
        return destination
    }

    /// The other Claude Code sessions a record names (earlier parts of the
    /// same conversation, rewinds), as lowercased UUIDs, for
    /// `SharedSessionCopy.plan`, which copies only those that exist as
    /// session files. The main session is left out.
    public static func relatedSessionIDs(record: Record, mainSessionID: String) -> Set<String> {
        SharedSessionCopy.uuids(in: record.data).subtracting([mainSessionID.lowercased()])
    }
}
