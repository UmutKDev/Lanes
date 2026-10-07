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

    /// What a clone check (3, or 0.5.8) has found so far. It lives here, not
    /// in the page, so looking at another check on the way does not lose it.
    struct CloneCheckProgress {
        var signatureValid: Bool?
        var dockIcon: Bool?
        var dockName: Bool?
        var switcherIcon: Bool?
        var appManagementPrompted: Bool?
        /// Whether the last "Klonu Oluştur" found a clone on disk to replace,
        /// whether or not the replacement went through. 0.5.8 asks about
        /// App Management only then.
        var replacedExisting: Bool?
    }

    /// A check 9 run in which the user opens the panel by clicking the menu
    /// bar icon, then opens the main window from it.
    struct IconClickRun {
        let id = UUID()
        var target: Int
        var trials: [ActivationTrials.Trial] = []
        /// True once Lanes has closed the window and handed focus to Finder
        /// for the next try. A window opened before that is not a trial.
        var isArmed = false
    }

    @ObservationIgnored private let paths: ProfilePaths
    @ObservationIgnored private let store: ValidationStore
    /// Keeps the entries this build could not read, for the next save.
    @ObservationIgnored private var records = ValidationRecords()
    private(set) var results: [ValidationCheckID: ValidationResult] = [:]
    /// Said on the page when the results file could not be read or was set aside.
    private(set) var fileProblem: String?
    /// Said on the page while the last save failed. The next good save clears it.
    private(set) var saveProblem: String?
    /// The results file could not be read at launch, so the first save moves
    /// it aside whatever it holds by then.
    @ObservationIgnored private var resultsFileWasUnreadable = false
    var selectedCheck: ValidationCheckID = .linkToSpecificInstance
    var isRunningActivationTrials = false
    /// True while a helper creates, inspects or trashes the test clone, so
    /// another check's helper does not change it at the same time.
    var isCloneBusy = false
    /// Nil unless an icon-click run is in progress.
    var iconClickRun: IconClickRun?
    var cloneProgress: [ValidationCheckID: CloneCheckProgress] = [:]
    /// Yes/no answers given on a Faz 0.5 check's page but not saved yet.
    var draftAnswers: [ValidationCheckID: [String: Bool]] = [:]
    /// The Claude installation the app found, for stamping results.
    @ObservationIgnored var currentClaude: () -> ClaudeInstallation? = { nil }

    init(paths: ProfilePaths) {
        self.paths = paths
        self.store = ValidationStore(paths: paths)
        load()
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
        result.environment = environment()
        results[id] = result
        save()
    }

    func setNotes(_ notes: String, for id: ValidationCheckID) {
        let isNew = results[id] == nil
        var result = result(for: id)
        guard result.notes != notes else { return }
        result.notes = notes
        // Only a result the note starts gets this build's environment. A
        // result an older Lanes recorded keeps none, so the report goes on
        // saying its environment is unknown rather than naming this build.
        if isNew {
            result.environment = environment()
        }
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
        result.environment = environment()
        results[id] = result
        save()
    }

    /// Deletes a check's records and starts its helper afresh.
    func clear(_ id: ValidationCheckID) {
        results[id] = nil
        draftAnswers[id] = nil
        cloneProgress[id] = nil
        save()
    }

    func completedCount(in phase: ValidationPhase) -> Int {
        ValidationCheck.checks(in: phase).filter { result(for: $0.id).outcome != .notRun }.count
    }

    func environment() -> ValidationEnvironment {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let info = Bundle.main.infoDictionary
        let lanesVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return ValidationEnvironment(
            macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: architecture,
            claudeVersion: currentClaude()?.version,
            lanesVersion: "\(lanesVersion) (\(build))",
            commit: info?["LanesGitCommit"] as? String,
            commitHasLocalChanges: info?["LanesGitTreeDirty"] as? Bool,
            signing: CodeSignature.current?.kind.reportLabel,
            appPath: (Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath
        )
    }

    func report() -> String {
        ValidationReport(environment: environment(), results: results, generatedAt: Date(), homeDirectory: NSHomeDirectory()).markdown()
    }

    /// Copies the report and keeps a file copy next to the results.
    func copyReport() {
        let markdown = report()
        SystemActions.copy(markdown)
        try? FileManager.default.createDirectory(at: paths.diagnosticsDirectory, withIntermediateDirectories: true)
        try? markdown.write(to: reportFile, atomically: true, encoding: .utf8)
    }

    private func load() {
        let source = store.sourceURL
        do {
            records = try store.load()
            results = records.results
        } catch {
            let name = source?.lastPathComponent ?? store.fileURL.lastPathComponent
            if source == store.fileURL {
                resultsFileWasUnreadable = true
                fileProblem = String(localized: "Deneme sonuçları (\(name)) okunamadı: \(error.localizedDescription) Lanes bu dosyayı silmez, ilk kayıtta aynı klasörde başka bir adla saklar.")
            } else {
                fileProblem = String(localized: "Eski deneme sonuçları (\(name)) okunamadı: \(error.localizedDescription) Lanes bu dosyaya dokunmaz, yeni sonuçları \(store.fileURL.lastPathComponent) dosyasına yazar.")
            }
        }
    }

    private func save() {
        records.results = results
        do {
            if let setAside = try store.save(records, setAsideExisting: resultsFileWasUnreadable) {
                fileProblem = String(localized: "Okunamayan deneme sonuçları \(setAside.lastPathComponent) adıyla aynı klasörde saklandı.")
            }
            resultsFileWasUnreadable = false
            saveProblem = nil
        } catch {
            saveProblem = String(localized: "Deneme sonuçları kaydedilemedi: \(error.localizedDescription)")
        }
    }
}
