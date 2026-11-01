import LanesCore
import SwiftUI

/// A small terminal symbol that shows an account's estimated Claude Code
/// state: tinted and pulsing while it is working, grey when it was used in
/// the last minutes, absent when idle.
struct ClaudeCodePulseIcon: View {
    let pulse: ClaudeCodePulse?
    var project: String?

    var body: some View {
        if let pulse, pulse != .idle {
            Image(systemName: "terminal.fill")
                .font(.caption)
                .foregroundStyle(pulse == .working ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .symbolEffect(.pulse, options: .repeating, isActive: pulse == .working)
                .help(Self.describe(pulse, project: project))
                .accessibilityLabel(Text(Self.describe(pulse, project: project)))
                .transition(.opacity)
        }
    }

    static func describe(_ pulse: ClaudeCodePulse, project: String?) -> String {
        switch (pulse, project) {
        case let (.working, project?):
            return String(localized: "Claude Code \(project) projesinde çalışıyor (tahmini)")
        case (.working, nil):
            return String(localized: "Claude Code çalışıyor (tahmini)")
        case let (.recent, project?):
            return String(localized: "Claude Code birkaç dakika önce \(project) projesinde kullanıldı")
        case (.recent, nil):
            return String(localized: "Claude Code birkaç dakika önce kullanıldı")
        case (.idle, _):
            return ""
        }
    }
}

/// Readable names for Claude Code's encoded project folder names.
enum ClaudeCodeProjectName {
    /// The project's real path when one reading of the name exists on disk.
    static func path(forFolderName folderName: String) -> String? {
        ClaudeCodeSessionList.projectPath(forFolderName: folderName) { candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// The last part of the project's real path when it still exists, so
    /// "my-app" stays "my-app". Otherwise the encoded name without the home
    /// folder prefix.
    static func name(forFolderName folderName: String) -> String {
        name(forFolderName: folderName, resolvedPath: path(forFolderName: folderName))
    }

    /// Like `name(forFolderName:)`, with the path already looked up.
    static func name(forFolderName folderName: String, resolvedPath resolved: String?) -> String {
        if let resolved {
            let last = URL(fileURLWithPath: resolved, isDirectory: true).lastPathComponent
            if !last.isEmpty && last != "/" {
                return last
            }
        }
        let home = NSHomeDirectory()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let prefix = home + "-"
        if folderName.hasPrefix(prefix), folderName.count > prefix.count {
            return String(folderName.dropFirst(prefix.count))
        }
        return folderName
    }
}
