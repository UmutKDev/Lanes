import Foundation

/// Scores how well a typed query matches a title, for the command palette.
/// Case, accents and Turkish dotted/dotless i are ignored (see
/// `SearchText.fold`).
public enum FuzzyMatch {
    /// Nil when the query's characters do not all appear in order. Higher
    /// is better. Matches fall into tiers, best first:
    ///
    /// 1. the title starts with the query ("hes" in "Hesap Ekle"),
    /// 2. a word of the title starts with it ("ekle" in "Hesap Ekle"),
    /// 3. the query is the initials of words ("ark" in "Ana Rapor Kitap"),
    /// 4. the title contains it mid-word ("ark" in "Mark"),
    /// 5. its letters are scattered through the title.
    ///
    /// Within a tier, the best placement of the letters counts: word
    /// starts and runs of consecutive letters score higher, gaps lower.
    /// Shorter titles win what is left of a tie.
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(SearchText.fold(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(SearchText.fold(text))
        guard !haystack.isEmpty, needle.count <= haystack.count else { return nil }
        guard let placement = bestPlacement(of: needle, in: haystack) else { return nil }
        return (tier(of: needle, in: haystack) + min(placement, 999)) * 100 - min(haystack.count, 99)
    }

    static let separators: Set<Character> = [" ", "-", "_", "/", ".", "·", ":"]

    private static func isWordStart(_ index: Int, in haystack: [Character]) -> Bool {
        index == 0 || separators.contains(haystack[index - 1])
    }

    private static func tier(of needle: [Character], in haystack: [Character]) -> Int {
        var startsWord = false
        var contains = false
        if haystack.count >= needle.count {
            for start in 0...(haystack.count - needle.count) where haystack[start] == needle[0] {
                guard haystack[start..<(start + needle.count)].elementsEqual(needle) else { continue }
                if start == 0 { return 4000 }
                contains = true
                if isWordStart(start, in: haystack) { startsWord = true }
            }
        }
        if startsWord { return 3000 }
        let initials = haystack.indices.filter { isWordStart($0, in: haystack) }.map { haystack[$0] }
        var next = initials.startIndex
        var isInitials = true
        for character in needle {
            guard let found = initials[next...].firstIndex(of: character) else {
                isInitials = false
                break
            }
            next = found + 1
        }
        if isInitials { return 2000 }
        return contains ? 1000 : 0
    }

    /// The highest score over every way of placing the query's letters in
    /// order: 1 per letter, 15 more at a word start, 5 more right after the
    /// previous letter, and minus the gap (at most 3) otherwise.
    private static func bestPlacement(of needle: [Character], in haystack: [Character]) -> Int? {
        let none = Int.min / 2
        func letterScore(_ index: Int) -> Int {
            isWordStart(index, in: haystack) ? 16 : 1
        }
        var previous = haystack.indices.map { haystack[$0] == needle[0] ? letterScore($0) : none }
        for character in needle.dropFirst() {
            var current = Array(repeating: none, count: haystack.count)
            // Best score of the previous letter at least four places back,
            // where the gap penalty stops growing.
            var farBest = none
            for index in haystack.indices {
                if index >= 4 { farBest = max(farBest, previous[index - 4]) }
                guard haystack[index] == character else { continue }
                var best = none
                if index >= 1, previous[index - 1] > none { best = max(best, previous[index - 1] + 5) }
                if index >= 2, previous[index - 2] > none { best = max(best, previous[index - 2] - 1) }
                if index >= 3, previous[index - 3] > none { best = max(best, previous[index - 3] - 2) }
                if farBest > none { best = max(best, farBest - 3) }
                if best > none { current[index] = best + letterScore(index) }
            }
            previous = current
        }
        let best = previous.max() ?? none
        return best > none ? best : nil
    }
}
