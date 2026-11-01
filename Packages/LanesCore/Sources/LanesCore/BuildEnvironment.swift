import Foundation

/// The machine and the build Lanes runs on, for the diagnostics report.
/// Nothing here names the user or their accounts.
public struct BuildEnvironment: Equatable, Sendable {
    public var macOSVersion: String
    public var architecture: String
    public var claudeVersion: String?
    public var lanesVersion: String
    /// The git commit Lanes was built from, when the build recorded it.
    public var commit: String?
    /// True when the working tree had uncommitted changes at build time.
    public var commitHasLocalChanges: Bool?
    /// How Lanes itself is signed, as `SigningKind.reportLabel` words it.
    public var signing: String?
    /// Where Lanes runs from, with the home folder written as "~".
    public var appPath: String?

    public init(
        macOSVersion: String,
        architecture: String,
        claudeVersion: String?,
        lanesVersion: String,
        commit: String? = nil,
        commitHasLocalChanges: Bool? = nil,
        signing: String? = nil,
        appPath: String? = nil
    ) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.claudeVersion = claudeVersion
        self.lanesVersion = lanesVersion
        self.commit = commit
        self.commitHasLocalChanges = commitHasLocalChanges
        self.signing = signing
        self.appPath = appPath
    }

    /// The commit as the report shows it.
    public var commitDescription: String {
        guard let commit, !commit.isEmpty else { return L("bilinmiyor", "unknown") }
        return commitHasLocalChanges == true ? commit + L(" (kaydedilmemiş değişikliklerle)", " (with uncommitted changes)") : commit
    }
}

/// How a build of Lanes is signed. Automation permission and App Management
/// follow the signature, so the diagnostics report names it.
public enum SigningKind: String, Codable, CaseIterable, Sendable {
    case unsigned
    /// Only the signature the linker adds on Apple silicon, as in CI builds.
    case linkerSigned
    /// "Sign to Run Locally": no certificate, so macOS cannot tell builds apart.
    case adHoc
    case appleDevelopment
    case developerID
    case appleDistribution
    case otherCertificate

    /// `kSecCodeSignatureAdhoc`. The values are part of the on-disk signature
    /// format, so they cannot change; LanesCore cannot import Security on Linux.
    public static let adHocFlag: UInt32 = 0x0002
    /// `kSecCodeSignatureLinkerSigned`.
    public static let linkerSignedFlag: UInt32 = 0x2_0000

    /// Classifies a signature from what the Security framework reports.
    /// - Parameters:
    ///   - flags: `kSecCodeInfoFlags`. Nil means the code carries no signature.
    ///   - leafCertificateSummary: the signing certificate's subject summary.
    ///   - teamID: `kSecCodeInfoTeamIdentifier`.
    public static func classify(flags: UInt32?, leafCertificateSummary: String?, teamID: String? = nil) -> SigningKind {
        guard let flags else { return .unsigned }
        if flags & linkerSignedFlag != 0 { return .linkerSigned }
        if flags & adHocFlag != 0 { return .adHoc }
        guard let summary = leafCertificateSummary else {
            // Signed, but no certificate came back (codesign --omit-adhoc-flag,
            // or a chain the system could not build). Without a team ID macOS
            // can only tell builds apart by their hash, as with ad hoc.
            return teamID == nil ? .adHoc : .otherCertificate
        }
        switch certificateType(summary) {
        case "Developer ID Application": return .developerID
        case "Apple Development", "Mac Developer": return .appleDevelopment
        case "Apple Distribution", "3rd Party Mac Developer Application", "Mac App Distribution": return .appleDistribution
        default: return .otherCertificate
        }
    }

    /// The certificate type: the common name up to its first colon, so
    /// "Apple Development: Ali Veli (ABCDE12345)" gives "Apple Development".
    static func certificateType(_ summary: String) -> String {
        guard let colon = summary.firstIndex(of: ":") else { return summary }
        return String(summary[..<colon])
    }

    public var reportLabel: String {
        switch self {
        case .unsigned: return L("imzasız", "unsigned")
        case .linkerSigned: return L("yalnız bağlayıcı imzası (imzasız derleme)", "linker signature only (unsigned build)")
        case .adHoc: return "ad hoc (Sign to Run Locally)"
        case .appleDevelopment: return L("ekip imzası (Apple Development)", "team signature (Apple Development)")
        case .developerID: return "Developer ID"
        case .appleDistribution: return L("dağıtım imzası (Apple Distribution)", "distribution signature (Apple Distribution)")
        case .otherCertificate: return L("başka bir sertifika", "another certificate")
        }
    }
}

extension DiagnosticsReport {
    /// Writes the home folder as "~" wherever a path starts with it. Claude
    /// Code names its project folders after the project's path with every
    /// character other than an ASCII letter or digit turned into "-", so
    /// "/Users/ali/Lanes" also appears as "-Users-ali-Lanes". That form is
    /// written as "~" too.
    public static func abbreviatingHome(_ home: String, in text: String) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard home.count > 1 else { return text }
        // Only a whole folder name: "/Users/ali" must not turn
        // "/Users/alican" into "~can".
        let slashed = replacingWholeName(home, in: text) { next in
            next == "/" || !(next.isLetter || next.isNumber || next == "." || next == "_" || next == "-")
        }
        let dashed = String(home.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return replacingWholeName(dashed, in: slashed) { next in
            !(next.isASCII && (next.isLetter || next.isNumber))
        }
    }

    /// Replaces `name` with "~" where it ends the text or the next character
    /// passes `endsName`.
    private static func replacingWholeName(_ name: String, in text: String, endsName: (Character) -> Bool) -> String {
        var result = ""
        var rest = Substring(text)
        while let range = rest.range(of: name) {
            let end = rest[range.upperBound...]
            if let next = end.first, !endsName(next) {
                result += rest[..<range.upperBound]
            } else {
                result += rest[..<range.lowerBound]
                result += "~"
            }
            rest = end
        }
        result += rest
        return result
    }

    public static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
