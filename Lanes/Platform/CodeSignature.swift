import Foundation
import LanesCore
import Security

/// How this copy of Lanes is signed, for the Faz 0 report. Automation and
/// App Management permissions follow the signature, so a check only carries
/// over to a build signed the same way.
///
/// This type only reads raw facts from the Security framework.
/// `SigningKind.classify` in LanesCore decides what they mean, so those rules
/// are tested on Linux.
struct CodeSignature: Sendable {
    /// `kSecCodeInfoFlags`, the `SecCodeSignatureFlags` bits. Nil when the
    /// bundle carries no signature at all.
    let flags: UInt32?
    /// `kSecCodeInfoTeamIdentifier`. Nil for ad hoc and linker signatures.
    let teamID: String?
    /// The signing certificate's subject summary (its common name), for
    /// example "Apple Development: Name (ID)". It names a person or a company,
    /// so it never goes into the report; only `kind` does.
    let leafSummary: String?

    var kind: SigningKind {
        SigningKind.classify(flags: flags, leafCertificateSummary: leafSummary, teamID: teamID)
    }

    /// Read once: the signature does not change while Lanes runs. Nil when the
    /// Security framework could not read it; the report then says "bilinmiyor".
    static let current: CodeSignature? = read(Bundle.main.bundleURL)

    /// Asking for the certificates runs a trust evaluation, which can be slow
    /// for a certificate-signed build. Reading `current` once off the main
    /// thread at launch keeps that wait out of the first saved result.
    static func readInBackground() {
        Task.detached(priority: .utility) {
            _ = CodeSignature.current
        }
    }

    /// Reads the signature without validating it: the report needs to know how
    /// the build was signed, not whether it is intact.
    static func read(_ bundleURL: URL) -> CodeSignature? {
        // `[]` is kSecCSDefaultFlags, which Swift does not import by name.
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        // This succeeds for unsigned code too; the dictionary then has neither
        // flags nor an identifier.
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any]
        else { return nil }

        return CodeSignature(
            flags: (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value,
            teamID: info[kSecCodeInfoTeamIdentifier as String] as? String,
            leafSummary: leafCertificateSummary(in: info[kSecCodeInfoCertificates as String])
        )
    }

    /// The chain runs leaf first. Swift does not check element types when it
    /// casts to a CoreFoundation type, hence the explicit type ID check.
    private static func leafCertificateSummary(in certificates: Any?) -> String? {
        guard let chain = certificates as? [SecCertificate],
              let leaf = chain.first,
              CFGetTypeID(leaf) == SecCertificateGetTypeID()
        else { return nil }
        return SecCertificateCopySubjectSummary(leaf).map { $0 as String }
    }
}
