import XCTest
@testable import LanesCore

final class DiagnosticsTests: XCTestCase {
    let home = "/Users/ali"
    let claudePath = "/Applications/Claude.app"

    func report(profiles: [Profile], instances: [RunningInstance], folderExists: [ProfileID: Bool] = [:]) -> String {
        DiagnosticsReport(
            environment: BuildEnvironment(
                macOSVersion: "27.0.1",
                architecture: "arm64",
                claudeVersion: "2.26454.0",
                lanesVersion: "0.1.0 (19)",
                commit: "5c6f41ed475c",
                commitHasLocalChanges: false,
                signing: "Developer ID",
                appPath: "/Applications/Lanes.app"
            ),
            claudePath: claudePath,
            linkHandlerPath: claudePath,
            isTranslocated: false,
            updatesEnabled: true,
            profiles: profiles,
            folderExists: folderExists,
            instances: instances,
            generatedAt: Date(timeIntervalSince1970: 0),
            homeDirectory: home
        ).markdown()
    }

    func testAccountNamesNeverAppear() {
        let main = Profile(name: "Kişisel Gizli", color: .blue, isDefault: true)
        let work = Profile(name: "Şirket Gizli", color: .red, accountClass: .employer)
        let text = report(profiles: [main, work], instances: [])
        XCTAssertFalse(text.contains("Gizli"))
        XCTAssertTrue(text.contains("| Hesap 1 (ana) |"))
        XCTAssertTrue(text.contains("| Hesap 2 |"))
    }

    func testCloneNamesAreHiddenAndHomeIsAbbreviated() {
        let work = Profile(name: "Şirket", color: .red, mode: .signedClone)
        let clone = RunningInstance(
            pid: 42,
            applicationBundlePath: "/Users/ali/Applications/Lanes Profiles/Claude – Şirket.app",
            userDataDirectory: "/Users/ali/Library/Application Support/Lanes/Profiles/\(work.id.rawValue)/Desktop",
            profileID: work.id
        )
        let text = report(profiles: [work], instances: [clone], folderExists: [work.id: true])
        XCTAssertFalse(text.contains("Şirket"))
        XCTAssertFalse(text.contains("/Users/ali"))
        XCTAssertTrue(text.contains("| 42 | Hesap 1 | klon | ~/Library/Application Support/Lanes/Profiles/"))
        XCTAssertTrue(text.contains("| var | açık, PID 42 |"))
    }

    func testClaudeOpenedOutsideLanesIsMarked() {
        let main = Profile(name: "Ana", color: .blue, isDefault: true)
        let stray = RunningInstance(pid: 7, applicationBundlePath: claudePath, userDataDirectory: nil, profileID: nil)
        let text = report(profiles: [main], instances: [stray])
        XCTAssertTrue(text.contains("| 7 | Lanes dışında açılmış | Claude | Claude'un kendi klasörü |"))
    }

    func testAbbreviatingHome() {
        XCTAssertEqual(DiagnosticsReport.abbreviatingHome("/Users/ali/", in: "/Users/ali/a /Users/ali.b /Users/ali"), "~/a /Users/ali.b ~")
        XCTAssertEqual(DiagnosticsReport.abbreviatingHome("/", in: "/Users/ali"), "/Users/ali")
        XCTAssertEqual(
            DiagnosticsReport.abbreviatingHome("/Users/ali", in: "-Users-ali-Lanes: 2 oturum (-Users-ali) -Users-alican-X"),
            "~-Lanes: 2 oturum (~) -Users-alican-X"
        )
        XCTAssertEqual(DiagnosticsReport.abbreviatingHome("/Users/ümit", in: "-Users--mit-Lanes"), "~-Lanes")
    }

    func testHomeIsHiddenInClaudeCodeFolderNames() {
        let text = DiagnosticsReport.abbreviatingHome("/Users/ali", in: "-Users-ali-Lanes: 2 oturum")
        XCTAssertFalse(text.contains("Users-ali"))
        XCTAssertEqual(text, "~-Lanes: 2 oturum")
    }

    func testSigningKinds() {
        XCTAssertEqual(SigningKind.classify(flags: nil, leafCertificateSummary: nil), .unsigned)
        XCTAssertEqual(SigningKind.classify(flags: 0x20002, leafCertificateSummary: nil), .linkerSigned)
        XCTAssertEqual(SigningKind.classify(flags: 0x10002, leafCertificateSummary: nil), .adHoc)
        XCTAssertEqual(SigningKind.classify(flags: 0x10000, leafCertificateSummary: nil), .adHoc)
        XCTAssertEqual(SigningKind.classify(flags: 0x10000, leafCertificateSummary: nil, teamID: "ABCDE12345"), .otherCertificate)
        XCTAssertEqual(SigningKind.classify(flags: 0x10000, leafCertificateSummary: "Apple Development: Ali Veli (QWERTY1234)", teamID: "ABCDE12345"), .appleDevelopment)
        XCTAssertEqual(SigningKind.classify(flags: 0, leafCertificateSummary: "Mac Developer: Ali Veli (QWERTY1234)", teamID: "ABCDE12345"), .appleDevelopment)
        XCTAssertEqual(SigningKind.classify(flags: 0x10000, leafCertificateSummary: "Developer ID Application: Ali Veli (ABCDE12345)", teamID: "ABCDE12345"), .developerID)
        XCTAssertEqual(SigningKind.classify(flags: 0, leafCertificateSummary: "Apple Distribution: Ali Veli (ABCDE12345)", teamID: "ABCDE12345"), .appleDistribution)
        XCTAssertEqual(SigningKind.classify(flags: 0, leafCertificateSummary: "3rd Party Mac Developer Application: Ali Veli (ABCDE12345)", teamID: "ABCDE12345"), .appleDistribution)
        XCTAssertEqual(SigningKind.classify(flags: 0, leafCertificateSummary: "Apple Mac OS Application Signing", teamID: "ABCDE12345"), .otherCertificate)
        XCTAssertEqual(SigningKind.classify(flags: 0, leafCertificateSummary: "Apple Developmentish: Ali", teamID: "ABCDE12345"), .otherCertificate)
        XCTAssertFalse(SigningKind.allCases.contains { $0.reportLabel.contains("Ali") })
    }
}
