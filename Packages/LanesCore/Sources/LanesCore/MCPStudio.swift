import Foundation

/// "MCP Stüdyosu": which of the Toolbox's MCP servers each account's
/// Claude Code gets. A server is on for every account until it is turned
/// off for one, so new accounts and new servers work as before.
public struct MCPAccountSettings: Codable, Equatable, Sendable {
    /// Account IDs per server name that do not get that server.
    public private(set) var disabled: [String: [String]]

    public init(disabled: [String: [String]] = [:]) {
        self.disabled = disabled
    }

    public func isEnabled(_ server: String, for id: ProfileID) -> Bool {
        !(disabled[server]?.contains(id.rawValue) ?? false)
    }

    public mutating func set(_ server: String, enabled: Bool, for id: ProfileID) {
        var ids = disabled[server] ?? []
        ids.removeAll { $0 == id.rawValue }
        if !enabled { ids.append(id.rawValue) }
        ids.sort()
        disabled[server] = ids.isEmpty ? nil : ids
    }

    /// Forgets servers no longer in the list and accounts no longer in
    /// the library.
    public mutating func prune(servers: Set<String>, profiles: Set<ProfileID>) {
        let ids = Set(profiles.map(\.rawValue))
        var kept: [String: [String]] = [:]
        for (server, off) in disabled where servers.contains(server) {
            let remaining = off.filter(ids.contains)
            if !remaining.isEmpty { kept[server] = remaining }
        }
        disabled = kept
    }

    public static func load(from url: URL) -> MCPAccountSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(MCPAccountSettings.self, from: data) else { return MCPAccountSettings() }
        return settings
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension MCPConfig {
    /// The `mcpServers` object of a `--mcp-config` file, each server as
    /// written, so nothing in it changes on the way through.
    public static func servers(in data: Data) throws -> [String: JSONValue] {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), case let .object(object) = value else {
            throw Failure.notJSON
        }
        guard case let .object(servers)? = object["mcpServers"] else { throw Failure.noServerList }
        return servers
    }

    /// A `--mcp-config` file holding `servers`.
    public static func file(with servers: [String: JSONValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(["mcpServers": .object(servers)]))
    }

    /// "Komut" (a program on this Mac) or "Uzak" (an HTTP or SSE address),
    /// from the server's `command` or `url` field.
    public static func isRemote(_ server: JSONValue) -> Bool {
        guard case let .object(fields) = server else { return false }
        return fields["url"] != nil && fields["command"] == nil
    }
}

extension Toolbox {
    /// Which accounts get which shared MCP servers.
    public var mcpAccountsFile: URL {
        directory.appendingPathComponent("mcp-accounts.json", isDirectory: false)
    }

    /// Per-account copies of `mcp.json` holding only that account's servers.
    public var accountMCPDirectory: URL {
        directory.appendingPathComponent("MCP", isDirectory: true)
    }

    public func accountMCPFile(for id: ProfileID) -> URL {
        let name = id.rawValue.replacingOccurrences(of: "/", with: "_")
        return accountMCPDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    /// The arguments that add this account's shared MCP servers to a
    /// Claude Code started by Lanes. With every server on it is the
    /// shared file; with some off, a copy holding only the others,
    /// readable only by the user; with none on, nothing.
    public func mcpArguments(for id: ProfileID) -> [String] {
        guard let data = try? Data(contentsOf: mcpConfigFile),
              let servers = try? MCPConfig.servers(in: data), !servers.isEmpty else { return [] }
        let settings = MCPAccountSettings.load(from: mcpAccountsFile)
        let enabled = servers.filter { settings.isEnabled($0.key, for: id) }
        let file = accountMCPFile(for: id)
        if enabled.count == servers.count {
            try? FileManager.default.removeItem(at: file)
            return ["--mcp-config", mcpConfigFile.path]
        }
        guard !enabled.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return []
        }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: accountMCPDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Created empty and private first, so the keys in it are never
            // readable by others, not even for a moment.
            if !fileManager.fileExists(atPath: file.path) {
                _ = fileManager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: MCPConfig.file(with: enabled))
            return ["--mcp-config", file.path]
        } catch {
            // Better no shared servers than ones the user turned off.
            return []
        }
    }
}

/// "Ekip Paketi": the Toolbox in one file to hand to a teammate: the MCP
/// servers without their secrets, CLAUDE.md, commands, agents and skills.
/// No account, sign-in or Claude data is in it.
public struct TeamPack: Codable, Equatable, Sendable {
    public static let kind = "lanes-team-pack"
    public static let fileExtension = "lanespack"
    /// Text files only, each at most this large.
    public static let maximumFileSize = 512 * 1024
    public static let maximumTotalSize = 8 * 1024 * 1024

    public var kind: String
    public var version: Int
    public var exportedAt: Date
    public var mcpServers: [String: JSONValue]
    /// Toolbox-relative path ("CLAUDE.md", "commands/review.md") to text.
    public var files: [String: String]
    /// Values left out, as "server: ENV_NAME", for the teammate to fill in.
    public var blanked: [String]

    public enum Failure: Error, Equatable {
        case notAPack
        case tooLarge
    }

    public struct InstallResult: Equatable, Sendable {
        public var addedServers: [String] = []
        public var skippedServers: [String] = []
        public var addedFiles: [String] = []
        public var skippedFiles: [String] = []
        public var blanked: [String] = []
    }

    /// Reads the Toolbox. Environment variables and headers keep their
    /// names but lose their values; other files (binary, too large,
    /// hidden, links) are left out and listed in `skipped`.
    public static func make(from toolbox: Toolbox, exportedAt: Date = Date()) throws -> (pack: TeamPack, skipped: [String]) {
        var servers: [String: JSONValue] = [:]
        var blanked: [String] = []
        if let data = try? Data(contentsOf: toolbox.mcpConfigFile) {
            for (name, server) in try MCPConfig.servers(in: data) {
                let (clean, names) = blank(server)
                servers[name] = clean
                blanked += names.map { "\(name): \($0)" }
            }
        }
        var files: [String: String] = [:]
        var skipped: [String] = []
        var total = 0
        for item in Toolbox.Item.allCases {
            for (path, url) in textFiles(under: toolbox.url(of: item), relativeTo: item.rawValue, isFolder: item.isFolder, skipped: &skipped) {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size <= maximumFileSize, let data = try? Data(contentsOf: url) else { skipped.append(path); continue }
                guard data.count <= maximumFileSize, let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
                    skipped.append(path)
                    continue
                }
                total += data.count
                guard total <= maximumTotalSize else { throw Failure.tooLarge }
                files[path] = text
            }
        }
        let pack = TeamPack(kind: kind, version: 1, exportedAt: exportedAt, mcpServers: servers, files: files, blanked: blanked.sorted())
        return (pack, skipped.sorted())
    }

    public static func decode(_ data: Data) throws -> TeamPack {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pack = try? decoder.decode(TeamPack.self, from: data), pack.kind == kind else { throw Failure.notAPack }
        return pack
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Adds what the Toolbox doesn't have yet. A server or file with the
    /// same name stays as it is, so the user's own keys and edits are
    /// never overwritten. Paths that would leave the Toolbox are skipped.
    public func install(into toolbox: Toolbox) throws -> InstallResult {
        var result = InstallResult()
        let fileManager = FileManager.default
        var current: [String: JSONValue] = [:]
        if let data = try? Data(contentsOf: toolbox.mcpConfigFile) {
            current = try MCPConfig.servers(in: data)
        }
        for (name, server) in mcpServers.sorted(by: { $0.key < $1.key }) {
            if current[name] != nil {
                result.skippedServers.append(name)
            } else {
                current[name] = server
                result.addedServers.append(name)
            }
        }
        if !result.addedServers.isEmpty {
            try fileManager.createDirectory(at: toolbox.directory, withIntermediateDirectories: true)
            try MCPConfig.file(with: current).write(to: toolbox.mcpConfigFile, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: toolbox.mcpConfigFile.path)
        }
        let added = Set(result.addedServers)
        result.blanked = blanked.filter { entry in added.contains { entry.hasPrefix("\($0): ") } }
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            guard let url = Self.destination(of: path, in: toolbox) else {
                result.skippedFiles.append(path)
                continue
            }
            if fileManager.fileExists(atPath: url.path) || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
                result.skippedFiles.append(path)
                continue
            }
            // One file that can't be written (say a file where the pack has
            // a folder) doesn't stop the rest; it is listed as skipped.
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url, options: .withoutOverwriting)
                result.addedFiles.append(path)
            } catch {
                result.skippedFiles.append(path)
            }
        }
        return result
    }

    /// Where a pack path goes, or nil when it is not under one of the
    /// Toolbox items or climbs out of the Toolbox.
    static func destination(of path: String, in toolbox: Toolbox) -> URL? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let item = Toolbox.Item(rawValue: first),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".") }),
              item.isFolder ? parts.count >= 2 : parts.count == 1 else { return nil }
        var url = toolbox.directory
        for part in parts { url.appendPathComponent(part) }
        // A folder on the way that is a link could lead outside.
        var check = toolbox.directory
        for part in parts.dropLast() {
            check.appendPathComponent(part)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: check.path)) != nil { return nil }
        }
        return url
    }

    /// `env` and `headers` keep their names with empty values.
    static func blank(_ server: JSONValue) -> (JSONValue, [String]) {
        guard case var .object(fields) = server else { return (server, []) }
        var names: [String] = []
        for key in ["env", "headers"] {
            guard case let .object(values)? = fields[key] else { continue }
            var cleared: [String: JSONValue] = [:]
            for name in values.keys {
                cleared[name] = .string("")
                names.append(name)
            }
            fields[key] = .object(cleared)
        }
        // A token in the address: the user name and password go, and the
        // query keeps its parameter names with empty values.
        if case let .string(address)? = fields["url"], var components = URLComponents(string: address) {
            var changed = false
            if components.user != nil || components.password != nil {
                components.user = nil
                components.password = nil
                names.append("url (kullanıcı:parola)")
                changed = true
            }
            if let items = components.queryItems, !items.isEmpty, items.contains(where: { !($0.value ?? "").isEmpty }) {
                components.queryItems = items.map { URLQueryItem(name: $0.name, value: "") }
                names += items.map { "url ?\($0.name)" }
                changed = true
            }
            if components.fragment != nil {
                components.fragment = nil
                changed = true
            }
            if changed, let cleaned = components.string {
                fields["url"] = .string(cleaned)
            }
        }
        return (.object(fields), names.sorted())
    }

    /// Regular, non-hidden files under a Toolbox item, never following links.
    private static func textFiles(under url: URL, relativeTo base: String, isFolder: Bool, skipped: inout [String]) -> [(String, URL)] {
        let fileManager = FileManager.default
        if !isFolder {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return [] }
            return [(base, url)]
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [(String, URL)] = []
        let prefix = url.resolvingSymlinksInPath().path + "/"
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            // The parent folders are real ones here, so resolving names the
            // file itself in the same form as `prefix`.
            let full = file.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(file.lastPathComponent).path
            guard full.hasPrefix(prefix) else { continue }
            let relative = base + "/" + full.dropFirst(prefix.count)
            if values?.isSymbolicLink == true {
                skipped.append(relative)
                enumerator.skipDescendants()
                continue
            }
            guard values?.isRegularFile == true else { continue }
            found.append((relative, file))
        }
        return found
    }
}
