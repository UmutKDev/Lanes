import AppKit
import LanesCore

/// Finds Claude data folders other launchers made, for "Mevcut Claude
/// klasörünü içe aktar", and the old launchers that opened them. Only names,
/// existence and dates are read in a data folder; nothing inside is listed
/// or opened, and no folder size is measured.
enum ClaudeFolderScanner {
    /// An AppleScript applet that opened one of the folders.
    struct Launcher: Equatable, Identifiable {
        var url: URL
        /// Decompiled text of the applet's own script; kept only to match.
        var script: String
        var id: URL { url }
        /// "Claude Work", without ".app".
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    struct Candidate: Equatable, Identifiable {
        var url: URL
        var name: String
        var lastUsed: Date?
        var inUse: Bool
        /// Every applet that pointed at this folder.
        var launchers: [Launcher]
        var id: URL { url }
    }

    static func applicationSupport(home: URL) -> URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    /// The Claude-looking folders at the top level of Application Support,
    /// newest first. Folders in use are listed but marked.
    static func candidates(paths: ProfilePaths, library: ProfileLibrary, userDataDirectories: [String]) async -> [Candidate] {
        let support = applicationSupport(home: paths.home)
        let found = await Task.detached(priority: .userInitiated) { () -> [ClaudeFolderImport.Candidate] in
            let manager = FileManager.default
            let names = (try? manager.contentsOfDirectory(atPath: support.path)) ?? []
            let folders = names.filter { name in
                let url = support.appendingPathComponent(name, isDirectory: true)
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                return values?.isSymbolicLink != true && values?.isDirectory == true
            }
            return ClaudeFolderImport.candidates(
                in: support.path,
                names: folders,
                paths: paths,
                library: library,
                userDataDirectories: userDataDirectories,
                exists: { manager.fileExists(atPath: $0) }
            )
        }.value
        let applets = await Self.launchers(home: paths.home)
        return found.map { candidate in
            let url = URL(fileURLWithPath: candidate.path, isDirectory: true)
            return Candidate(
                url: url,
                name: candidate.name,
                lastUsed: lastUsed(url),
                inUse: candidate.inUse,
                launchers: applets.filter { LauncherScript.pointsAt(script: $0.script, folder: candidate.path, home: paths.home.path) }
            )
        }
        .sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    /// One picked folder, described like a listed one.
    static func candidate(for url: URL, paths: ProfilePaths, userDataDirectories: [String]) async -> Candidate {
        let applets = await Self.launchers(home: paths.home)
        return Candidate(
            url: url,
            name: url.lastPathComponent,
            lastUsed: lastUsed(url),
            inUse: ClaudeFolderImport.isInUse(path: url.path, userDataDirectories: userDataDirectories),
            launchers: applets.filter { LauncherScript.pointsAt(script: $0.script, folder: url.path, home: paths.home.path) }
        )
    }

    /// Whether a picked folder looks like Claude data, by existence only.
    static func looksLikeClaudeData(_ url: URL) -> Bool {
        ClaudeFolderImport.looksLikeClaudeData(name: url.lastPathComponent) { name in
            FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
        }
    }

    /// The later of the folder's and its `Local State`'s modification
    /// dates: metadata only.
    static func lastUsed(_ folder: URL) -> Date? {
        let state = folder.appendingPathComponent(ClaudeFolderImport.requiredMarker, isDirectory: false)
        return [folder, state]
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }

    /// AppleScript applets at the top level of /Applications and
    /// ~/Applications whose script can be decompiled. Run-only scripts are
    /// skipped. The script is read, never run.
    static func launchers(home: URL) async -> [Launcher] {
        let folders = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
        let manager = FileManager.default
        var applets: [URL] = []
        for folder in folders {
            let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasSuffix(".app") {
                let bundle = folder.appendingPathComponent(name, isDirectory: true)
                let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
                if manager.fileExists(atPath: contents.appendingPathComponent("MacOS/applet").path),
                   manager.fileExists(atPath: contents.appendingPathComponent("Resources/Scripts/main.scpt").path) {
                    applets.append(bundle)
                }
            }
        }
        var result: [Launcher] = []
        for applet in applets {
            let script = applet.appendingPathComponent("Contents/Resources/Scripts/main.scpt", isDirectory: false)
            let output = await ShellRunner.run("/usr/bin/osadecompile", [script.path])
            guard output.status == 0, !output.text.isEmpty else { continue }
            result.append(Launcher(url: applet, script: output.text))
        }
        return result
    }

    /// Whether `url` is on the same volume as `other`, so moving it is a
    /// rename. Unknown counts as not.
    static func isSameVolume(_ url: URL, _ other: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        guard let a = try? url.resourceValues(forKeys: keys).volumeIdentifier as? NSObject,
              let b = try? other.resourceValues(forKeys: keys).volumeIdentifier as? NSObject else { return false }
        return a.isEqual(b)
    }
}
