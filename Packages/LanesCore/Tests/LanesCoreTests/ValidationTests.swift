import Foundation
import XCTest
@testable import LanesCore

final class ValidationTests: XCTestCase {
    func testChecksAreNumberedInOrder() {
        XCTAssertEqual(ValidationCheck.checks(in: .faz0).map(\.number), Array(1...9))
        XCTAssertEqual(ValidationCheck.checks(in: .faz05).map(\.number), Array(1...8))
        XCTAssertEqual(ValidationCheck.all.map(\.id), ValidationCheckID.allCases)
        XCTAssertEqual(ValidationCheck.check(.mainWindowActivation).mode, .automated)
        XCTAssertEqual(ValidationCheck.check(.signedCloneIdentity).label, "3")
        XCTAssertEqual(ValidationCheck.check(.newAccountSignIn).label, "0.5.3")
    }

    func testActivationTrialStatistics() {
        let trials = ActivationTrials(trials: [
            .init(becameKey: true, appBecameActive: true, duration: 0.040, method: "activate"),
            .init(becameKey: true, appBecameActive: true, duration: 0.050, method: "activate"),
            .init(becameKey: true, appBecameActive: true, duration: 0.210, method: "activate(from:)"),
            .init(becameKey: false, appBecameActive: true, duration: 1.000, method: "gave up"),
        ])
        XCTAssertEqual(trials.successCount, 3)
        XCTAssertEqual(trials.successRate, 0.75)
        XCTAssertEqual(trials.medianDuration, 0.050)
        XCTAssertEqual(trials.p95Duration, 1.000)
        XCTAssertEqual(trials.suggestedOutcome, .partial)
        XCTAssertEqual(trials.methodCounts.first?.method, "activate")
        XCTAssertEqual(trials.evidenceLines.first, "3/4 denemede pencere öne geldi.")
        XCTAssertEqual(trials.evidenceLines[1], "Süre: ortanca 50 ms, p95 1000 ms.")
        XCTAssertNil(trials.medianPanelLatency)
        XCTAssertEqual(trials.evidenceLines.count, 3, "no panel line when the panel was opened from code")
    }

    func testPanelLatencyFromIconClicks() {
        let trials = ActivationTrials(trials: [
            .init(becameKey: true, appBecameActive: true, duration: 0.2, method: "activate(from:)", panelLatency: 0.030),
            .init(becameKey: true, appBecameActive: true, duration: 0.2, method: "activate(from:)", panelLatency: 0.045),
            .init(becameKey: true, appBecameActive: true, duration: 0.2, method: "activate(from:)", panelLatency: nil),
        ])
        XCTAssertEqual(trials.medianPanelLatency, 0.030)
        XCTAssertEqual(trials.p95PanelLatency, 0.045)
        XCTAssertEqual(trials.evidenceLines.last, "Simgeye tıklandıktan sonra panel 2 denemede ortanca 30 ms, p95 45 ms içinde açıldı.")
    }

    func testPanelLatencySources() {
        let trials = ActivationTrials(trials: [
            .init(becameKey: true, appBecameActive: true, duration: 0.2, method: "activate(from:)", panelLatency: 0.120, panelLatencySource: "mouseDown"),
            .init(becameKey: true, appBecameActive: true, duration: 0.2, method: "activate(from:)", panelLatency: 0.020, panelLatencySource: "callback"),
            .init(becameKey: true, appBecameActive: true, duration: 0.2, method: "activate(from:)", panelLatency: 0.110, panelLatencySource: "mouseDown"),
        ])
        XCTAssertEqual(trials.evidenceLines.last, "Panel süresinin başladığı an: Lanes'e haber geldiği an (1 deneme), simgeye basış (2 deneme).")
    }

    func testSuggestedOutcome() {
        XCTAssertEqual(ActivationTrials().suggestedOutcome, .notRun)
        XCTAssertEqual(ActivationTrials(trials: [.init(becameKey: true, appBecameActive: true, duration: 0.1, method: "a")]).suggestedOutcome, .passed)
        XCTAssertEqual(ActivationTrials(trials: [.init(becameKey: false, appBecameActive: false, duration: 1, method: "a")]).suggestedOutcome, .failed)
    }

    static let environment = ValidationEnvironment(
        macOSVersion: "26.4", architecture: "arm64", claudeVersion: "1.2.3", lanesVersion: "0.1.0 (1)",
        commit: "0123456789ab", commitHasLocalChanges: false, signing: SigningKind.adHoc.reportLabel,
        appPath: "~/Library/Developer/Xcode/DerivedData/Lanes/Build/Products/Debug/Lanes.app"
    )

    func testMarkdownReport() throws {
        let report = ValidationReport(
            environment: Self.environment,
            results: [
                .mainWindowActivation: ValidationResult(checkID: .mainWindowActivation, outcome: .passed, evidence: ["10/10 denemede pencere öne geldi."], environment: Self.environment),
                .signedCloneIdentity: ValidationResult(checkID: .signedCloneIdentity, outcome: .failed, notes: "Dock'ta Claude yazıyor.", environment: Self.environment),
                .coworkStandard: ValidationResult(checkID: .coworkStandard, outcome: .passed, environment: Self.environment),
            ],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let markdown = report.markdown()
        XCTAssertTrue(markdown.hasPrefix("# Lanes doğrulama sonuçları\n"))
        XCTAssertTrue(markdown.contains("- macOS: 26.4 (arm64)"))
        XCTAssertTrue(markdown.contains("- Commit: 0123456789ab\n"))
        XCTAssertTrue(markdown.contains("- İmza: ad hoc (Sign to Run Locally)\n"))
        XCTAssertTrue(markdown.contains("- Uygulama: ~/Library/Developer/Xcode/DerivedData/Lanes/Build/Products/Debug/Lanes.app\n"))
        XCTAssertTrue(markdown.contains("## Faz 0\n\n| # | Deneme | Sonuç |"))
        XCTAssertTrue(markdown.contains("| 3 | İmzası korunan klonun görünüşü | Olumsuz |"))
        XCTAssertTrue(markdown.contains("| 1 | Bağlantıyı belirli bir pencereye teslim etme | Çalıştırılmadı |"))
        XCTAssertTrue(markdown.contains("## Faz 0.5\n\n| # | Deneme | Sonuç |"))
        XCTAssertTrue(markdown.contains("| 0.5.6 | Standart modda Cowork | Olumlu |"))
        XCTAssertTrue(markdown.contains("### 9. Ana pencerenin öne gelmesi\n\nSonuç: Olumlu\n\n```\n10/10 denemede pencere öne geldi.\n```"))
        XCTAssertTrue(markdown.contains("### 0.5.6. Standart modda Cowork\n\nSonuç: Olumlu\n"))
        XCTAssertTrue(markdown.contains("Not: Dock'ta Claude yazıyor."))
        XCTAssertFalse(markdown.contains("### 1."), "checks with nothing to say get no section")
        XCTAssertFalse(markdown.contains("Kaydedildiği ortam:"), "a result recorded in the header's environment needs no line")
        let faz05 = try XCTUnwrap(markdown.range(of: "## Faz 0.5"))
        let check9 = try XCTUnwrap(markdown.range(of: "### 9."))
        XCTAssertLessThan(check9.lowerBound, faz05.lowerBound, "Faz 0 details stay under the Faz 0 heading")
    }

    func testAResultRecordedBeforeEnvironmentsWereKeptSaysSo() {
        let report = ValidationReport(
            environment: Self.environment,
            results: [.signedCloneIdentity: ValidationResult(checkID: .signedCloneIdentity, outcome: .passed)],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(report.markdown().contains("Sonuç: Olumlu\n\nKaydedildiği ortam: bilinmiyor\n"))
    }

    func testANoteAddedLaterLeavesTheEnvironmentUnknown() {
        var result = ValidationResult(checkID: .signedCloneIdentity, outcome: .passed)
        result.notes = "Dock'ta doğru simge vardı."
        let report = ValidationReport(
            environment: Self.environment,
            results: [.signedCloneIdentity: result],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(report.markdown().contains("Kaydedildiği ortam: bilinmiyor\n"))
    }

    func testReportNamesTheEnvironmentAResultWasRecordedIn() {
        var older = Self.environment
        older.claudeVersion = "1.2.2"
        older.commit = "fedcba987654"
        older.commitHasLocalChanges = true
        let report = ValidationReport(
            environment: Self.environment,
            results: [.signedCloneIdentity: ValidationResult(checkID: .signedCloneIdentity, outcome: .passed, environment: older)],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(report.markdown().contains("Sonuç: Olumlu\n\nKaydedildiği ortam: Claude 1.2.2 · Lanes 0.1.0 (1) · commit fedcba987654 (kaydedilmemiş değişikliklerle) · imza: ad hoc (Sign to Run Locally) · macOS 26.4\n"))
    }

    func testUnknownBuildDetailsAreSaidToBeUnknown() {
        let environment = ValidationEnvironment(macOSVersion: "27.0.1", architecture: "arm64", claudeVersion: nil, lanesVersion: "0.1.0 (1)")
        let markdown = ValidationReport(environment: environment, results: [:], generatedAt: Date(timeIntervalSince1970: 0)).markdown()
        XCTAssertTrue(markdown.contains("- Claude: bulunamadı\n- Lanes: 0.1.0 (1)\n- Commit: bilinmiyor\n- İmza: bilinmiyor\n- Uygulama: bilinmiyor\n"))
    }

    func testReportWritesTheHomeFolderAsTilde() {
        let report = ValidationReport(
            environment: Self.environment,
            results: [.claudeCodeConfigDirectory: ValidationResult(checkID: .claudeCodeConfigDirectory, outcome: .passed, evidence: [
                "/Users/ali/Library/Application Support/Lanes/Profiles/x/ClaudeCode",
                "/Users/alican/Documents",
                "ev: /Users/ali",
            ])],
            generatedAt: Date(timeIntervalSince1970: 0),
            homeDirectory: "/Users/ali"
        )
        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains("\n~/Library/Application Support/Lanes/Profiles/x/ClaudeCode\n"))
        XCTAssertTrue(markdown.contains("\n/Users/alican/Documents\n"), "another user's folder that starts the same stays as it is")
        XCTAssertTrue(markdown.contains("\nev: ~\n"))
    }

    func testAbbreviatingHome() {
        XCTAssertEqual(ValidationReport.abbreviatingHome("/Users/ali/", in: "/Users/ali/a /Users/ali.b /Users/ali"), "~/a /Users/ali.b ~")
        XCTAssertEqual(ValidationReport.abbreviatingHome("/", in: "/Users/ali"), "/Users/ali")
        XCTAssertEqual(
            ValidationReport.abbreviatingHome("/Users/ali", in: "-Users-ali-Lanes: 2 oturum (-Users-ali) -Users-alican-X"),
            "~-Lanes: 2 oturum (~) -Users-alican-X"
        )
        XCTAssertEqual(ValidationReport.abbreviatingHome("/Users/ümit", in: "-Users--mit-Lanes"), "~-Lanes")
    }

    func testReportHidesTheHomeFolderInClaudeCodeFolderNames() {
        let folder = ClaudeCodeSessionFolder(
            projects: [.init(folderName: "-Users-ali-Lanes", sessionCount: 2)],
            newestSession: .init(projectFolderName: "-Users-ali-Lanes", id: "abc", modifiedAt: Date(timeIntervalSince1970: 0))
        )
        let report = ValidationReport(
            environment: Self.environment,
            results: [.claudeCodeSessionRecords: ValidationResult(checkID: .claudeCodeSessionRecords, outcome: .passed, evidence: folder.evidenceLines, environment: Self.environment)],
            generatedAt: Date(timeIntervalSince1970: 0),
            homeDirectory: "/Users/ali"
        )
        let markdown = report.markdown()
        XCTAssertFalse(markdown.contains("Users-ali"))
        XCTAssertTrue(markdown.contains("~-Lanes: 2 oturum"))
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

final class ValidationStoreTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LanesCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    var fileURL: URL {
        directory.appendingPathComponent("validation-results.json")
    }

    var legacyFileURL: URL {
        directory.appendingPathComponent("faz0-results.json")
    }

    func savedEntries() throws -> [NSDictionary] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [NSDictionary])
    }

    func testMissingFileHasNoResults() throws {
        XCTAssertEqual(try ValidationStore(fileURL: fileURL).load(), ValidationRecords())
    }

    func testReadsAFileWrittenBeforeResultsCarriedTheirEnvironment() throws {
        let file = """
        [
          {
            "checkID" : "signedCloneIdentity",
            "evidence" : ["Simge uygulandı."],
            "notes" : "",
            "outcome" : "passed",
            "recordedAt" : "2026-10-05T21:40:00Z"
          }
        ]
        """
        try Data(file.utf8).write(to: fileURL)
        let records = try ValidationStore(fileURL: fileURL).load()
        let result = try XCTUnwrap(records.results[.signedCloneIdentity])
        XCTAssertEqual(result.outcome, .passed)
        XCTAssertEqual(result.evidence, ["Simge uygulandı."])
        XCTAssertNil(result.environment)
    }

    func testSavesAndReadsBack() throws {
        let store = ValidationStore(fileURL: fileURL)
        var records = ValidationRecords()
        records.results[.staleClone] = ValidationResult(checkID: .staleClone, outcome: .partial, notes: "Simge gitti.", environment: ValidationTests.environment)
        records.results[.linkToSpecificInstance] = ValidationResult(checkID: .linkToSpecificInstance, outcome: .passed, recordedAt: Date(timeIntervalSince1970: 1_790_000_000))

        XCTAssertNil(try store.save(records))
        XCTAssertEqual(try store.load(), records)
    }

    func testKeepsEntriesItCannotRead() throws {
        let file = """
        [
          {"checkID": "linkToSpecificInstance", "outcome": "passed", "notes": "", "evidence": []},
          {"checkID": "someLaterCheck", "outcome": "passed", "notes": "", "evidence": ["x"]},
          {"checkID": "reclaimLinkHandler", "outcome": "blocked", "notes": "", "evidence": []}
        ]
        """
        try Data(file.utf8).write(to: fileURL)
        let store = ValidationStore(fileURL: fileURL)
        var records = try store.load()
        XCTAssertEqual(Array(records.results.keys), [.linkToSpecificInstance])

        records.results[.panelOnNewMenuBar] = ValidationResult(checkID: .panelOnNewMenuBar, outcome: .passed)
        try store.save(records)

        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [NSDictionary])
        XCTAssertEqual(saved.compactMap { $0["checkID"] as? String }, ["linkToSpecificInstance", "panelOnNewMenuBar", "someLaterCheck", "reclaimLinkHandler"])
        XCTAssertEqual(saved[3]["outcome"] as? String, "blocked")
    }

    func testANewResultReplacesAKeptEntryForTheSameCheck() throws {
        try Data(#"[{"checkID": "reclaimLinkHandler", "outcome": "blocked", "notes": "", "evidence": []}]"#.utf8).write(to: fileURL)
        let store = ValidationStore(fileURL: fileURL)
        var records = try store.load()
        XCTAssertTrue(records.results.isEmpty)

        records.results[.reclaimLinkHandler] = ValidationResult(checkID: .reclaimLinkHandler, outcome: .passed)
        try store.save(records)

        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [NSDictionary])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0]["outcome"] as? String, "passed")
    }

    func testUnreadableFileIsSetAsideOnSave() throws {
        try Data("not json".utf8).write(to: fileURL)
        let store = ValidationStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load())

        var records = ValidationRecords()
        records.results[.coworkStandard] = ValidationResult(checkID: .coworkStandard, outcome: .passed)
        let setAside = try XCTUnwrap(try store.save(records, now: Date(timeIntervalSince1970: 0)))

        XCTAssertTrue(setAside.lastPathComponent.hasPrefix("validation-results-unreadable-"))
        XCTAssertEqual(try String(contentsOf: setAside, encoding: .utf8), "not json")
        XCTAssertEqual(try store.load().results[.coworkStandard]?.outcome, .passed)
    }
    func testUnreadableAtLaunchIsSetAsideEvenIfRepairedSince() throws {
        try Data(#"[{"checkID": "linkToSpecificInstance", "outcome": "passed", "notes": "", "evidence": []}]"#.utf8).write(to: fileURL)
        let store = ValidationStore(fileURL: fileURL)
        var records = ValidationRecords()
        records.results[.coworkStandard] = ValidationResult(checkID: .coworkStandard, outcome: .passed)
        let setAside = try XCTUnwrap(try store.save(records, setAsideExisting: true, now: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(try String(contentsOf: setAside, encoding: .utf8).contains("linkToSpecificInstance"))
        XCTAssertEqual(Array(try store.load().results.keys), [.coworkStandard])
    }

    func testReadsTheOlderFileUntilTheNewOneExistsAndNeverWritesIt() throws {
        let older = #"[{"checkID": "linkToSpecificInstance", "outcome": "passed", "notes": "", "evidence": []}]"#
        try Data(older.utf8).write(to: legacyFileURL)
        let store = ValidationStore(fileURL: fileURL, legacyFileURL: legacyFileURL)
        XCTAssertEqual(store.sourceURL, legacyFileURL)
        var records = try store.load()
        XCTAssertEqual(records.results[.linkToSpecificInstance]?.outcome, .passed)

        records.results[.staleClone] = ValidationResult(checkID: .staleClone, outcome: .failed)
        XCTAssertNil(try store.save(records))

        XCTAssertEqual(try String(contentsOf: legacyFileURL, encoding: .utf8), older, "builds before Faz 0.5 still read the older file")
        XCTAssertEqual(store.sourceURL, fileURL)
        XCTAssertEqual(Set(try store.load().results.keys), [.linkToSpecificInstance, .staleClone])
    }

    func testANoteAloneLeavesAKeptEntryForTheSameCheck() throws {
        try Data(#"[{"checkID": "reclaimLinkHandler", "outcome": "blocked", "notes": "", "evidence": ["x"]}]"#.utf8).write(to: fileURL)
        let store = ValidationStore(fileURL: fileURL)
        var records = try store.load()
        records.results[.reclaimLinkHandler] = ValidationResult(checkID: .reclaimLinkHandler, notes: "a")
        try store.save(records)

        let saved = try savedEntries()
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved[0]["notes"] as? String, "a")
        XCTAssertEqual(saved[1]["outcome"] as? String, "blocked")
        XCTAssertEqual(saved[1]["evidence"] as? [String], ["x"])
        XCTAssertEqual(try store.load().results[.reclaimLinkHandler]?.notes, "a")
    }

    func testFieldsANewerLanesAddedSurviveUntilTheResultChanges() throws {
        let file = """
        [
          {"checkID": "linkToSpecificInstance", "outcome": "passed", "notes": "", "evidence": [], "futureField": "keep me"},
          {"checkID": "panelOnNewMenuBar", "outcome": "passed", "notes": "", "evidence": [], "futureField": "old"}
        ]
        """
        try Data(file.utf8).write(to: fileURL)
        let store = ValidationStore(fileURL: fileURL)
        var records = try store.load()
        records.results[.panelOnNewMenuBar]?.outcome = .failed
        try store.save(records)

        let saved = try savedEntries()
        XCTAssertEqual(saved[0]["futureField"] as? String, "keep me")
        XCTAssertNil(saved[1]["futureField"], "a field about the old recording goes with it")
        XCTAssertEqual(saved[1]["outcome"] as? String, "failed")
    }
}
