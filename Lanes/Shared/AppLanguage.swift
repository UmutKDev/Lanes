import AppKit
import Foundation

/// The language Lanes shows itself in: the Mac's own choice, or one picked
/// in Settings. Stored the way macOS stores a per-app language
/// (`AppleLanguages` in Lanes's own defaults), so it matches Sistem
/// Ayarları > Genel > Dil ve Bölge > Uygulamalar. Takes effect on relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    /// Names are shown in their own language, as macOS does.
    var title: String {
        switch self {
        case .system: return String(localized: "Sistem")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    static var current: AppLanguage {
        // Only Lanes's own domain: the global list is the Mac's language.
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        guard let first = (domain?["AppleLanguages"] as? [String])?.first else { return .system }
        if first.hasPrefix("tr") { return .turkish }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// The choice Lanes was launched with, so Settings can tell whether a
    /// relaunch would change anything.
    static let atLaunch = current

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// Opens a fresh copy of Lanes once this one has quit.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"", "sh", String(ProcessInfo.processInfo.processIdentifier), path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
