import Foundation
import XCTest
@testable import LanesCore

final class ValidationTests: XCTestCase {
    func testChecksAreNumberedInOrder() {
        XCTAssertEqual(ValidationCheck.all.map(\.number), Array(1...9))
        XCTAssertEqual(ValidationCheck.all.map(\.id), ValidationCheckID.allCases)
        XCTAssertEqual(ValidationCheck.check(.mainWindowActivation).mode, .automated)
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
    }

    func testSuggestedOutcome() {
        XCTAssertEqual(ActivationTrials().suggestedOutcome, .notRun)
        XCTAssertEqual(ActivationTrials(trials: [.init(becameKey: true, appBecameActive: true, duration: 0.1, method: "a")]).suggestedOutcome, .passed)
        XCTAssertEqual(ActivationTrials(trials: [.init(becameKey: false, appBecameActive: false, duration: 1, method: "a")]).suggestedOutcome, .failed)
    }

    func testMarkdownReport() {
        let report = ValidationReport(
            environment: ValidationEnvironment(macOSVersion: "26.4", architecture: "arm64", claudeVersion: "1.2.3", lanesVersion: "0.1.0"),
            results: [
                .mainWindowActivation: ValidationResult(checkID: .mainWindowActivation, outcome: .passed, evidence: ["10/10 denemede pencere öne geldi."]),
                .signedCloneIdentity: ValidationResult(checkID: .signedCloneIdentity, outcome: .failed, notes: "Dock'ta Claude yazıyor."),
            ],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let markdown = report.markdown()
        XCTAssertTrue(markdown.hasPrefix("# Lanes Faz 0 sonuçları\n"))
        XCTAssertTrue(markdown.contains("- macOS: 26.4 (arm64)"))
        XCTAssertTrue(markdown.contains("| 3 | İmzası korunan klonun görünüşü | Olumsuz |"))
        XCTAssertTrue(markdown.contains("| 1 | Bağlantıyı belirli bir pencereye teslim etme | Çalıştırılmadı |"))
        XCTAssertTrue(markdown.contains("## 9. Ana pencerenin öne gelmesi\n\nSonuç: Olumlu\n\n```\n10/10 denemede pencere öne geldi.\n```"))
        XCTAssertTrue(markdown.contains("Not: Dock'ta Claude yazıyor."))
        XCTAssertFalse(markdown.contains("## 1."), "checks with nothing to say get no section")
    }
}
