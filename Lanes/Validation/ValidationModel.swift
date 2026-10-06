import AppKit
import LanesCore
import Observation

/// Faz 0 results, kept on disk so a check can be finished another day.
@MainActor
@Observable
final class ValidationModel {
    /// A stand-in profile for the clone check. It never joins the user's
    /// profile list, and its folders sit apart from real profiles.
    static let cloneTestProfile = Profile(
        id: ProfileID(rawValue: "faz0-clone-test"),
        name: "Lanes Deneme",
        monogram: "L",
        color: .purple,
        mode: .signedClone
    )

    @ObservationIgnored private let paths: ProfilePaths
    private(set) var results: [ValidationCheckID: ValidationResult] = [:]
    var selectedCheck: ValidationCheckID = .linkToSpecificInstance
    var isRunningActivationTrials = false

    init(paths: ProfilePaths) {
        self.paths = paths
        load()
    }

    var resultsFile: URL {
        paths.diagnosticsDirectory.appendingPathComponent("faz0-results.json", isDirectory: false)
    }

    var reportFile: URL {
        paths.diagnosticsDirectory.appendingPathComponent("faz0-report.md", isDirectory: false)
    }

    func result(for id: ValidationCheckID) -> ValidationResult {
        results[id] ?? ValidationResult(checkID: id)
    }

    func setOutcome(_ outcome: ValidationOutcome, for id: ValidationCheckID) {
        var result = result(for: id)
        result.outcome = outcome
        result.recordedAt = Date()
        results[id] = result
        save()
    }

    func setNotes(_ notes: String, for id: ValidationCheckID) {
        var result = result(for: id)
        result.notes = notes
        results[id] = result
        save()
    }

    /// Adds lines to the evidence, stamped with the time so repeated runs
    /// stay readable.
    func appendEvidence(_ lines: [String], for id: ValidationCheckID) {
        guard !lines.isEmpty else { return }
        var result = result(for: id)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        result.evidence.append("[\(formatter.string(from: Date()))]")
        result.evidence.append(contentsOf: lines)
        result.recordedAt = Date()
        results[id] = result
        save()
    }

    func clear(_ id: ValidationCheckID) {
        results[id] = nil
        save()
    }

    var completedCount: Int {
        results.values.filter { $0.outcome != .notRun }.count
    }

    func environment(claude: ClaudeInstallation?) -> ValidationEnvironment {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let lanesVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return ValidationEnvironment(
            macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: architecture,
            claudeVersion: claude?.version,
            lanesVersion: "\(lanesVersion) (\(build))"
        )
    }

    func report(claude: ClaudeInstallation?) -> String {
        ValidationReport(environment: environment(claude: claude), results: results, generatedAt: Date()).markdown()
    }

    /// Copies the report and keeps a file copy next to the results.
    func copyReport(claude: ClaudeInstallation?) {
        let markdown = report(claude: claude)
        SystemActions.copy(markdown)
        try? FileManager.default.createDirectory(at: paths.diagnosticsDirectory, withIntermediateDirectories: true)
        try? markdown.write(to: reportFile, atomically: true, encoding: .utf8)
    }

    private func load() {
        guard let data = try? Data(contentsOf: resultsFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([ValidationResult].self, from: data) else { return }
        results = Dictionary(list.map { ($0.checkID, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let list = ValidationCheckID.allCases.compactMap { results[$0] }
        guard let data = try? encoder.encode(list) else { return }
        try? FileManager.default.createDirectory(at: paths.diagnosticsDirectory, withIntermediateDirectories: true)
        try? data.write(to: resultsFile, options: [.atomic])
    }
}
