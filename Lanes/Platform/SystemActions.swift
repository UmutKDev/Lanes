import AppKit
import LanesCore
import ServiceManagement

/// Small actions the panel and the main window share.
@MainActor
enum SystemActions {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens Terminal with Claude Code running under the profile's account.
    /// It writes a small `.command` file, which Terminal runs when opened.
    static func openClaudeCodeInTerminal(for profile: Profile, paths: ProfilePaths) throws {
        if let directory = paths.claudeCodeConfigDirectory(for: profile) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let folder = paths.root.appendingPathComponent("Terminal", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("\(profile.id.rawValue).command", isDirectory: false)
        let title = ClaudeCodeCommand.shellQuoted("Lanes: \(profile.name)")
        let contents = """
        #!/bin/zsh -l
        printf '\\e]0;%s\\a' \(title)
        cd ~
        \(ClaudeCodeCommand.command(for: profile, paths: paths))
        exec /bin/zsh -l

        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        _ = NSWorkspace.shared.open(script)
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
