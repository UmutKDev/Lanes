import Foundation

/// Scores how well a typed query matches a title, for the command palette.
/// Case, accents and Turkish dotted/dotless i are ignored (see
/// `SearchText.fold`).
public enum FuzzyMatch {
    /// Nil when the query's characters do not all appear in order. Higher
    /// is better: a title that starts with the query beats one that only
    /// contains it, which beats scattered letters at word starts, which
    /// beats scattered letters anywhere.
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(SearchText.fold(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(SearchText.fold(text))
        guard !haystack.isEmpty else { return nil }

        var score = 0
        var position = 0
        var previousMatch: Int?
        for character in needle {
            guard let index = haystack[position...].firstIndex(of: character) else { return nil }
            score += 1
            if index == 0 || Self.separators.contains(haystack[index - 1]) {
                score += 15
            }
            if let previousMatch {
                if index == previousMatch + 1 {
                    score += 5
                } else {
                    score -= min(index - previousMatch - 1, 3)
                }
            }
            previousMatch = index
            position = index + 1
        }
        let folded = String(haystack)
        let joined = String(needle)
        if folded.hasPrefix(joined) {
            score += 40
        } else if folded.contains(joined) {
            score += 10
        }
        // Shorter titles win ties.
        return score * 100 - min(haystack.count, 99)
    }

    static let separators: Set<Character> = [" ", "-", "_", "/", ".", "·", ":"]
}
