import Foundation
import LanesCore

/// Installs the `lanes` command into `~/.local/bin`, the folder Claude
/// Code's own installer puts on the PATH, and keeps its account map
/// current. Nothing is written outside the user's home folder, so no
/// password is needed.
enum CommandLineTool {
    enum State: Equatable {
        case notInstalled
        case installed
        /// Lanes wrote it, but an older version or in another language.
        case outdated
        /// Another program's `lanes` is there; Lanes leaves it alone.
        case foreign
    }

    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/lanes", isDirectory: false)
    }

    static func state() -> State {
        guard let contents = try? String(contentsOf: installURL, encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: installURL.path) ? .foreign : .notInstalled
        }
        guard LanesCLI.isOurs(contents) else { return .foreign }
        return LanesCLI.isCurrent(contents) ? .installed : .outdated
    }

    /// Writes the script. Refuses to replace another program's `lanes`.
    static func install() throws {
        guard state() != .foreign else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: installURL.path])
        }
        let folder = installURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try LanesCLI.script().write(to: installURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installURL.path)
    }

    static func uninstall() throws {
        guard state() != .foreign, FileManager.default.fileExists(atPath: installURL.path) else { return }
        try FileManager.default.removeItem(at: installURL)
    }

    /// A script left by an older Lanes, or written in the language Lanes
    /// ran in before, is brought up to date at launch.
    static func updateIfOutdated() {
        guard state() == .outdated else { return }
        try? install()
    }

    /// Writes the account map the script reads: names, IDs and folders.
    static func writeMap(library: ProfileLibrary, paths: ProfilePaths, hookSettings: [ProfileID: String] = [:]) {
        let url = paths.root.appendingPathComponent(LanesCLI.mapFileName, isDirectory: false)
        let contents = LanesCLI.map(library: library, paths: paths, hookSettings: hookSettings)
        if (try? String(contentsOf: url, encoding: .utf8)) == contents { return }
        do {
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.app.error("Writing the command line account map failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
