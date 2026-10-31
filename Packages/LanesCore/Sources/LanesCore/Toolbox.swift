import Foundation

/// Things every account's Claude Code can share, kept once in Lanes's own
/// Toolbox folder: a CLAUDE.md, slash commands, agents, skills and a list of
/// MCP servers.
///
/// Sharing links the item into an account's Claude Code folder. Lanes never
/// reads or changes the account's own files: an item the account already
/// has stays as it is, and only Lanes's own links are ever removed.
public struct Toolbox: Sendable {
    public enum Item: String, CaseIterable, Sendable, Identifiable {
        case claudeMD = "CLAUDE.md"
        case commands
        case agents
        case skills

        public var id: String { rawValue }

        public var isFolder: Bool { self != .claudeMD }
    }

    public enum ItemState: Equatable, Sendable {
        /// Linked to the Toolbox.
        case shared
        /// The account has its own, which Lanes leaves alone.
        case own
        case absent
    }

    public enum Failure: Error, Equatable {
        case accountHasItsOwn(Item)
        case notALanesLink(Item)
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public init(paths: ProfilePaths) {
        self.init(directory: paths.root.appendingPathComponent("Toolbox", isDirectory: true))
    }

    public func url(of item: Item) -> URL {
        directory.appendingPathComponent(item.rawValue, isDirectory: item.isFolder)
    }

    /// Shared MCP servers, in the format `claude --mcp-config` reads.
    public var mcpConfigFile: URL {
        directory.appendingPathComponent("mcp.json", isDirectory: false)
    }

    public func state(of item: Item, inAccountFolder folder: URL) -> ItemState {
        let link = folder.appendingPathComponent(item.rawValue)
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
            return pointsIntoToolbox(destination, from: folder) ? .shared : .own
        }
        return FileManager.default.fileExists(atPath: link.path) ? .own : .absent
    }

    public func share(_ item: Item, inAccountFolder folder: URL) throws {
        let fileManager = FileManager.default
        switch state(of: item, inAccountFolder: folder) {
        case .shared: return
        case .own: throw Failure.accountHasItsOwn(item)
        case .absent: break
        }
        let source = url(of: item)
        if !fileManager.fileExists(atPath: source.path) {
            if item.isFolder {
                try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data().write(to: source)
            }
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(atPath: folder.appendingPathComponent(item.rawValue).path, withDestinationPath: source.path)
    }

    /// Removes Lanes's link. The Toolbox copy stays for the other accounts.
    public func unshare(_ item: Item, inAccountFolder folder: URL) throws {
        guard state(of: item, inAccountFolder: folder) == .shared else { throw Failure.notALanesLink(item) }
        try FileManager.default.removeItem(atPath: folder.appendingPathComponent(item.rawValue).path)
    }

    private func pointsIntoToolbox(_ destination: String, from folder: URL) -> Bool {
        let absolute = destination.hasPrefix("/") ? destination : folder.appendingPathComponent(destination).path
        let target = InstanceMatcher.normalize(absolute)
        let base = InstanceMatcher.normalize(directory.path)
        return target == base || target.hasPrefix(base + "/")
    }

    /// The arguments that add the shared MCP servers to a Claude Code
    /// started by Lanes, or none when there are none to add.
    public func mcpArguments() -> [String] {
        guard let data = try? Data(contentsOf: mcpConfigFile),
              let names = try? MCPConfig.serverNames(in: data), !names.isEmpty else { return [] }
        return ["--mcp-config", mcpConfigFile.path]
    }
}

public enum MCPConfig {
    public enum Failure: Error, Equatable {
        case notJSON
        case noServerList
    }

    /// The server names in an `{"mcpServers": {...}}` file, sorted.
    public static func serverNames(in data: Data) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.notJSON }
        guard let servers = object["mcpServers"] as? [String: Any] else { throw Failure.noServerList }
        return servers.keys.sorted()
    }

    public static let template = """
    {
      "mcpServers": {
      }
    }

    """
}
