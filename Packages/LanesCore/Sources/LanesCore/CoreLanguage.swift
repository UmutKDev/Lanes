import Foundation

/// The language of the text LanesCore makes for people: error messages,
/// durations, CSV headers, the diagnostics report and the `lanes` script.
/// The app sets `current` once at launch from its own localization.
/// LanesCore keeps both languages in code rather than in a resource bundle,
/// so it builds and tests the same on Linux.
public enum CoreLanguage: String, Sendable, CaseIterable {
    case turkish = "tr"
    case english = "en"

    /// Set once by the app at launch, before anything reads LanesCore text.
    /// Turkish by default, which is what the tests expect.
    nonisolated(unsafe) public static var current: CoreLanguage = .turkish

    /// The language for a localization identifier such as "en" or "en-GB":
    /// English for any "en", Turkish otherwise.
    public static func from(localization: String?) -> CoreLanguage {
        guard let localization, localization.lowercased().hasPrefix("en") else { return .turkish }
        return .english
    }

    /// The text in this language.
    func text(_ turkish: String, _ english: String) -> String {
        self == .english ? english : turkish
    }
}

/// The text in the current language: `L("Hesap", "Account")`.
func L(_ turkish: String, _ english: String) -> String {
    CoreLanguage.current.text(turkish, english)
}
