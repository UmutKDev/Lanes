import Foundation

/// Matching for the account search fields. Turkish letters are folded to
/// their plain Latin forms first ("İ", "ı" → "i"), so typing "ikinci" or
/// "IKINCI" on any keyboard finds "İkinci Hesap". Case and accents are
/// ignored after that.
public enum SearchText {
    public static func fold(_ text: String) -> String {
        var plain = ""
        plain.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "İ", "I", "ı": plain.append("i")
            default: plain.append(character)
            }
        }
        return plain.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Whether any of the fields holds the query. An empty query matches.
    public static func matches(_ query: String, in fields: [String]) -> Bool {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        return fields.contains { fold($0).contains(needle) }
    }
}
