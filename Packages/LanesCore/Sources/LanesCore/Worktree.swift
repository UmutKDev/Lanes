import Foundation

/// "Worktree Fırlatıcı": a new git worktree next to a repository, so one
/// account's Claude Code can work on a branch while another works on the
/// main checkout.
///
/// Worktrees go into a sibling folder named after the repository,
/// `<parent>/<repo>.worktrees/<branch>`, so they stay out of the repository
/// itself and are easy to find and remove.
public enum WorktreePlan {
    /// Whether a branch name is one Lanes passes to git. git has its own,
    /// longer list (`git check-ref-format`); this one is stricter so the name
    /// also makes a plain folder name and can never read as an option.
    public static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100,
              !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"),
              !name.hasPrefix("."), !name.hasSuffix("."), !name.hasSuffix(".lock"),
              !name.contains(".."), !name.contains("//"), !name.contains("@{"), name != "@" else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !name.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// `feature/login` becomes `feature-login`.
    public static func folderName(forBranch branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }

    public static func worktreesFolder(forRepository repository: URL) -> URL {
        let repo = repository.standardizedFileURL
        return repo.deletingLastPathComponent()
            .appendingPathComponent(repo.lastPathComponent + ".worktrees", isDirectory: true)
    }

    public static func folder(forRepository repository: URL, branch: String) -> URL {
        worktreesFolder(forRepository: repository)
            .appendingPathComponent(folderName(forBranch: branch), isDirectory: true)
    }

    /// A short suggestion for the branch field.
    public static func suggestedBranch(accountName: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMdd-HHmm"
        let ascii = accountName
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "İ", with: "I")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let slug = ascii.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.hasSuffix("-") || result.isEmpty { return }
                result.append(character)
            }
        let trimmed = slug.hasSuffix("-") ? String(slug.dropLast()) : slug
        return "lanes/\(trimmed.isEmpty ? "is" : String(trimmed.prefix(20)))-\(formatter.string(from: date))"
    }
}
