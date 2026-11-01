import Foundation
import LanesCore

/// Runs `git worktree add` for "Worktree Fırlatıcı". git is started
/// directly with an argument list, never through a shell.
enum GitWorktree {
    static let git = "/usr/bin/git"

    enum Failure: LocalizedError {
        case invalidBranch
        case folderExists(String)
        case git(String)

        var errorDescription: String? {
            switch self {
            case .invalidBranch:
                return String(localized: "Dal adı yalnız harf, rakam, - _ . / içerebilir ve - ile başlayamaz.")
            case let .folderExists(path):
                return String(localized: "\(path) klasörü zaten var.")
            case let .git(text):
                return String(localized: "git: \(text)")
            }
        }
    }

    /// The main checkout of a repository: its `.git` is a folder. A
    /// worktree or a submodule has a `.git` file instead and is left out,
    /// so worktrees are never made inside `<repo>.worktrees`.
    static func isMainCheckout(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Makes the worktree and returns its folder. A branch that already
    /// exists is checked out there; a new one starts from the repository's
    /// current commit.
    static func add(repository: URL, branch: String) async throws -> URL {
        guard WorktreePlan.isValidBranchName(branch) else { throw Failure.invalidBranch }
        let folder = WorktreePlan.folder(forRepository: repository, branch: branch)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw Failure.folderExists(folder.path)
        }
        // git makes the worktree's parent folders itself.
        let exists = await ShellRunner.run(git, ["-C", repository.path, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch]).status == 0
        let arguments = exists
            ? ["-C", repository.path, "worktree", "add", "--", folder.path, branch]
            : ["-C", repository.path, "worktree", "add", "-b", branch, "--", folder.path]
        let output = await ShellRunner.run(git, arguments)
        guard output.status == 0 else {
            throw Failure.git(output.text.isEmpty ? String(localized: "çıkış kodu \(output.status)") : String(output.text.suffix(400)))
        }
        return folder
    }
}
