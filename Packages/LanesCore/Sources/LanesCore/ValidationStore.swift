import Foundation

/// What `faz0-results.json` holds: one entry per check that has something
/// recorded.
public struct ValidationRecords: Equatable, Sendable {
    public var results: [ValidationCheckID: ValidationResult]
    /// Entries this build could not read, such as a check a newer Lanes added.
    /// Saving writes them back unchanged.
    var keptEntries: [JSONValue]

    public init(results: [ValidationCheckID: ValidationResult] = [:]) {
        self.results = results
        self.keptEntries = []
    }
}

/// Reads and writes the Faz 0 results. Like `ProfileStore`, it never replaces
/// a file it could not read: the next save moves that file aside first.
public struct ValidationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(paths: ProfilePaths) {
        self.init(fileURL: paths.diagnosticsDirectory.appendingPathComponent("faz0-results.json", isDirectory: false))
    }

    /// Loads the results, or returns none when the file doesn't exist yet.
    /// Throws when the file is not a list of entries at all.
    public func load() throws -> ValidationRecords {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ValidationRecords()
        }
        let data = try Data(contentsOf: fileURL)
        let entries = try ValidationStore.decoder.decode([Entry].self, from: data)
        var records = ValidationRecords()
        for entry in entries {
            switch entry {
            case let .result(result):
                // A check listed twice keeps its last entry, as before.
                records.results[result.checkID] = result
            case let .kept(value):
                records.keptEntries.append(value)
            }
        }
        return records
    }

    /// Saves the results in check order, followed by the entries this build
    /// could not read. Returns where an unreadable file was moved, or nil.
    @discardableResult
    public func save(_ records: ValidationRecords, now: Date = Date()) throws -> URL? {
        // A kept entry for a check this build has just recorded is older
        // than the new result, so the new result replaces it.
        let recorded = Set(records.results.keys.map(\.rawValue))
        let kept = records.keptEntries.filter { entry in
            guard case let .object(fields) = entry, case let .string(checkID)? = fields["checkID"] else { return true }
            return !recorded.contains(checkID)
        }
        let list = ValidationCheckID.allCases.compactMap { records.results[$0] }.map(Entry.result) + kept.map(Entry.kept)
        let data = try ValidationStore.encoder.encode(list)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var setAside: URL?
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                _ = try load()
            } catch {
                setAside = try setAsideUnreadableFile(at: fileURL, now: now)
            }
        }
        try data.write(to: fileURL, options: [.atomic])
        return setAside
    }

    /// One entry of the list: a result this build reads, or a value it keeps.
    enum Entry: Codable {
        case result(ValidationResult)
        case kept(JSONValue)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let result = try? container.decode(ValidationResult.self) {
                self = .result(result)
            } else {
                self = .kept(try container.decode(JSONValue.self))
            }
        }

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
