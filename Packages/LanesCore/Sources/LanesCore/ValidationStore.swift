import Foundation

/// What the results file holds: one entry per check that has something
/// recorded.
public struct ValidationRecords: Equatable, Sendable {
    public var results: [ValidationCheckID: ValidationResult]
    /// Entries this build could not read, such as a check a newer Lanes added.
    /// Saving writes them back unchanged.
    var keptEntries: [JSONValue]
    /// Each result as it was read, with its JSON. A result this build has not
    /// changed is written back exactly as read, so fields a newer Lanes added
    /// to it survive.
    var loadedEntries: [ValidationCheckID: LoadedEntry]

    struct LoadedEntry: Equatable, Sendable {
        var result: ValidationResult
        var json: JSONValue
    }

    public init(results: [ValidationCheckID: ValidationResult] = [:]) {
        self.results = results
        self.keptEntries = []
        self.loadedEntries = [:]
    }

    /// Two records are equal when they would save the same results and kept
    /// entries; how they were read does not matter.
    public static func == (lhs: ValidationRecords, rhs: ValidationRecords) -> Bool {
        lhs.results == rhs.results && lhs.keptEntries == rhs.keptEntries
    }
}

/// Reads and writes the Faz 0 and Faz 0.5 results. Like `ProfileStore`, it
/// never replaces a file it could not read: the save moves that file aside
/// first.
public struct ValidationStore: Sendable {
    public let fileURL: URL
    /// Read only while `fileURL` does not exist yet, and never written.
    /// Builds from before Faz 0.5 keep writing this file, and they would drop
    /// every result if it held a check they do not know.
    public let legacyFileURL: URL?

    public init(fileURL: URL, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    public init(paths: ProfilePaths) {
        self.init(
            fileURL: paths.diagnosticsDirectory.appendingPathComponent("validation-results.json", isDirectory: false),
            legacyFileURL: paths.diagnosticsDirectory.appendingPathComponent("faz0-results.json", isDirectory: false)
        )
    }

    /// The file `load()` reads: the results file, or the older file while
    /// there is no results file yet. Nil when neither exists.
    public var sourceURL: URL? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        if let legacyFileURL, FileManager.default.fileExists(atPath: legacyFileURL.path) {
            return legacyFileURL
        }
        return nil
    }

    /// Loads the results, or returns none when there is no file yet. Throws
    /// when the file is not a list of entries at all.
    public func load() throws -> ValidationRecords {
        guard let sourceURL else { return ValidationRecords() }
        return try ValidationStore.read(sourceURL)
    }

    /// Saves the results in check order, followed by the entries this build
    /// could not read. Returns where an unreadable file was moved, or nil.
    ///
    /// - Parameter setAsideExisting: Move the file on disk aside without
    ///   reading it again. Pass true when it could not be read at launch:
    ///   if the user has repaired it since, it still holds results the
    ///   records in memory do not.
    @discardableResult
    public func save(_ records: ValidationRecords, setAsideExisting: Bool = false, now: Date = Date()) throws -> URL? {
        // A kept entry for a check this build has given an outcome is older
        // than that outcome, so the new result replaces it. A note or log
        // lines alone leave it in place. It comes after the result, so the
        // newer Lanes that wrote it still reads its own entry.
        let decided = Set(records.results.values.filter { $0.outcome != .notRun }.map(\.checkID.rawValue))
        let kept = records.keptEntries.filter { entry in
            guard case let .object(fields) = entry, case let .string(checkID)? = fields["checkID"] else { return true }
            return !decided.contains(checkID)
        }
        let results: [Entry] = ValidationCheckID.allCases.compactMap { id in
            guard let result = records.results[id] else { return nil }
            if let loaded = records.loadedEntries[id], loaded.result == result {
                return .kept(loaded.json)
            }
            return .result(result)
        }
        let data = try ValidationStore.encoder.encode(results + kept.map(Entry.kept))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var setAside: URL?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if setAsideExisting {
                setAside = try setAsideUnreadableFile(at: fileURL, now: now)
            } else {
                do {
                    _ = try ValidationStore.read(fileURL)
                } catch {
                    setAside = try setAsideUnreadableFile(at: fileURL, now: now)
                }
            }
        }
        try data.write(to: fileURL, options: [.atomic])
        return setAside
    }

    private static func read(_ url: URL) throws -> ValidationRecords {
        let data = try Data(contentsOf: url)
        let entries = try decoder.decode([JSONValue].self, from: data)
        var records = ValidationRecords()
        for json in entries {
            // Decoding the value again keeps one rule for dates and keys.
            if let result = try? decoder.decode(ValidationResult.self, from: encoder.encode(json)) {
                // A check listed twice keeps its last entry, as before.
                records.results[result.checkID] = result
                records.loadedEntries[result.checkID] = ValidationRecords.LoadedEntry(result: result, json: json)
            } else {
                records.keptEntries.append(json)
            }
        }
        return records
    }

    /// One entry of the list: a result this build wrote, or a value it keeps
    /// as it was.
    enum Entry: Encodable {
        case result(ValidationResult)
        case kept(JSONValue)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .result(result): try container.encode(result)
            case let .kept(value): try container.encode(value)
            }
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
