import AppKit
import Foundation
import LanesCore

/// Installs the "Bitti Haberi" hook in Lanes's own folder and watches the
/// files it drops. See `ClaudeCodeHooks` for what the hook does and does
/// not read.
@MainActor
final class ClaudeCodeDoneNotices {
    private let folder: URL
    private var source: DispatchSourceFileSystemObject?

    /// Called on the main thread for each event the hook reports.
    var onEvent: ((ClaudeCodeHooks.Event) -> Void)?

    init(paths: ProfilePaths) {
        folder = paths.root.appendingPathComponent(ClaudeCodeHooks.folderName, isDirectory: true)
    }

    private var eventsFolder: URL {
        folder.appendingPathComponent(ClaudeCodeHooks.eventsFolderName, isDirectory: true)
    }

    private var scriptURL: URL {
        folder.appendingPathComponent(ClaudeCodeHooks.scriptName, isDirectory: false)
    }

    func settingsFile(for id: ProfileID) -> URL {
        folder.appendingPathComponent(ClaudeCodeHooks.settingsFileName(for: id), isDirectory: false)
    }

    /// The arguments that add the hooks to a Claude Code Lanes starts, or
    /// none while the feature is off.
    func arguments(for profile: Profile) -> [String] {
        let file = settingsFile(for: profile.id)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return ["--settings", file.path]
    }

    /// Writes the hook and one settings file per account, removes the files
    /// of accounts that are gone, and starts watching.
    func install(profiles: [Profile], kinds: Set<ClaudeCodeHooks.Kind>) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: eventsFolder, withIntermediateDirectories: true)
            try write(Data(ClaudeCodeHooks.script.utf8), to: scriptURL)
            var wanted = Set<String>()
            for profile in profiles {
                let file = settingsFile(for: profile.id)
                wanted.insert(file.lastPathComponent)
                try write(ClaudeCodeHooks.settings(scriptPath: scriptURL.path, profileID: profile.id, kinds: kinds), to: file)
            }
            for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
            where name.hasPrefix("settings-") && name.hasSuffix(".json") && !wanted.contains(name) {
                try? manager.removeItem(at: folder.appendingPathComponent(name))
            }
        } catch {
            Log.app.error("Installing the Claude Code hook failed: \(error.localizedDescription, privacy: .public)")
        }
        // Watches the folder anew each time: one deleted from outside and
        // made again here is another folder, which the old watch misses.
        stopWatching()
        startWatching()
    }

    /// Stops watching and deletes Lanes's hook folder. Sessions already
    /// running keep the hook until they end; its events then go nowhere.
    func uninstall() {
        stopWatching()
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
    }

    // MARK: Watching

    private func startWatching() {
        guard source == nil else { return }
        let fd = open(eventsFolder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
        drain(dropOlderThan: 120)
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }

    /// Reads and deletes every finished event file. Files left from while
    /// Lanes was closed are dropped silently when older than `dropOlderThan`.
    private func drain(dropOlderThan maximumAge: TimeInterval? = nil) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: eventsFolder.path) else { return }
        for name in names.sorted() {
            let url = eventsFolder.appendingPathComponent(name, isDirectory: false)
            if name.hasPrefix(".") {
                // A temporary file the hook never renamed.
                if let date = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                   Date().timeIntervalSince(date) > 60 {
                    try? manager.removeItem(at: url)
                }
                continue
            }
            defer { try? manager.removeItem(at: url) }
            guard name.hasSuffix(".event"),
                  let attributes = try? manager.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? Int, size <= ClaudeCodeHooks.maximumEventSize else { continue }
            if let maximumAge, let date = attributes[.modificationDate] as? Date, Date().timeIntervalSince(date) > maximumAge {
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8),
                  let event = ClaudeCodeHooks.Event(contents: text) else { continue }
            onEvent?(event)
        }
    }
}

/// Brings the terminal a session runs in forward, with its tab selected
/// where the app lets Lanes find it by tty (Terminal and iTerm2).
@MainActor
enum TerminalFocus {
    static func show(tty: String?, terminalProgram: String?) {
        let bundleID = ClaudeCodeHooks.terminalBundleIdentifier(for: terminalProgram) ?? "com.apple.Terminal"
        if let tty, let source = script(bundleID: bundleID, tty: tty) {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error == nil { return }
            Log.app.notice("Selecting the terminal tab failed, bringing the app forward instead")
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
    }

    /// `tty` was checked to be `ttys` and digits, see
    /// `ClaudeCodeHooks.Event`.
    private static func script(bundleID: String, tty: String) -> String? {
        let device = "/dev/" + tty
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select w
                                tell t to select
                                tell s to select
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }
}
