import Foundation
import LanesCore

/// Finds Claude Code's `claude` command. Health and Kurulum share it, so
/// both pages always agree on whether the command is installed.
enum ClaudeCommandLocator {
    /// Looks in the folders Claude Code's installers use, then asks an
    /// interactive login shell: the official installer adds its folder to
    /// PATH only in `~/.zshrc`, which a plain login shell does not read.
    static func find() async -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let path = ClaudeCodeCommand.candidatePaths(home: home).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        let output = await ShellRunner.run("/bin/zsh", ["-lic", "command -v claude"])
        guard output.status == 0 else { return nil }
        // An interactive shell may print its own lines first.
        return output.text.split(separator: "\n").map(String.init).last { $0.hasPrefix("/") }
    }

    /// The first line `claude --version` prints, such as "2.0.14 (Claude
    /// Code)". Nil when the command fails, so an error message never shows
    /// up as a version.
    static func version(at path: String) async -> String? {
        let output = await ShellRunner.run(path, ["--version"])
        guard output.status == 0 else { return nil }
        let first = output.text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return first?.isEmpty == false ? first : nil
    }
}
