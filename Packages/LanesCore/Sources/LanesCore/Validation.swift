import Foundation

/// The Faz 0 checks: short experiments on a real Mac that settle how Lanes
/// launches, routes links and shows windows. The study document lists them in
/// this order.
public enum ValidationCheckID: String, CaseIterable, Codable, Sendable, Identifiable {
    case linkToSpecificInstance
    case reclaimLinkHandler
    case signedCloneIdentity
    case claudeCodeConfigDirectory
    case appManagementPrompt
    case separateIdentityCowork
    case afterClaudeUpdate
    case panelOnNewMenuBar
    case mainWindowActivation

    public var id: String { rawValue }
}

public enum ValidationMode: String, Codable, Sendable {
    /// Lanes runs it and measures the result.
    case automated
    /// Lanes does the steps, the user says what they saw.
    case assisted
    /// The user does it by hand, Lanes only records the answer.
    case manual
}

public enum ValidationOutcome: String, Codable, CaseIterable, Sendable {
    case notRun
    case passed
    case failed
    case partial
    case skipped

    /// The word used in the Markdown report.
    public var reportLabel: String {
        switch self {
        case .notRun: return "Çalıştırılmadı"
        case .passed: return "Olumlu"
        case .failed: return "Olumsuz"
        case .partial: return "Kısmen"
        case .skipped: return "Atlandı"
        }
    }
}

public struct ValidationCheck: Sendable, Identifiable, Equatable {
    public let id: ValidationCheckID
    public let number: Int
    public let title: String
    /// The question the check answers, as written in the study document.
    public let question: String
    public let mode: ValidationMode
    /// Checks that can wait until the feature they protect is built.
    public let isDeferred: Bool
    /// What the user should do or look at, shown on the check's page.
    public let steps: [String]

    public static let all: [ValidationCheck] = [
        ValidationCheck(
            id: .linkToSpecificInstance, number: 1,
            title: "Bağlantıyı belirli bir pencereye teslim etme",
            question: "Bağlantıyı aynı paket kimliğini taşıyan iki örnekten belirli birine teslim edebiliyor muyuz?",
            mode: .assisted, isDeferred: false,
            steps: [
                "İki profil açık olsun.",
                "Lanes bir claude://claude.ai/new bağlantısını seçtiğin profilin işlemine gönderir.",
                "Yeni sohbet hangi pencerede açıldı, onu seç.",
            ]
        ),
        ValidationCheck(
            id: .reclaimLinkHandler, number: 2,
            title: "claude:// varsayılanını geri alma",
            question: "Claude açıldıktan sonra claude:// varsayılanını sessizce geri alabiliyor muyuz? macOS 26.4 ve 27'de onay penceresi çıkıyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Lanes claude:// varsayılanını kendine alır.",
                "Onay penceresi çıktıysa bunu işaretle.",
                "Lanes varsayılanı Claude'a geri verir ve sonucu kaydeder.",
            ]
        ),
        ValidationCheck(
            id: .signedCloneIdentity, number: 3,
            title: "İmzası korunan klonun görünüşü",
            question: "İmzası korunan klonun Finder simgesi ve adı Dock'ta ve Cmd-Tab'da görünüyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Lanes Claude.app'in bir klonunu oluşturur ve simgesini değiştirir.",
                "codesign ve spctl çıktısı otomatik kaydedilir. İkisi de klonu kabul ederse imza korunmuş sayılır.",
                "codesign'ın katı modu, simge dosyası yüzünden klonu her zaman reddeder. Bu çıktı raporda not olarak kalır.",
                "Klonu açınca Dock'ta ve Cmd-Tab'da gördüğünü seç.",
            ]
        ),
        ValidationCheck(
            id: .claudeCodeConfigDirectory, number: 4,
            title: "Code sekmesi ve CLAUDE_CONFIG_DIR",
            question: "Desktop'un Code sekmesi açılışta verilen CLAUDE_CONFIG_DIR değerini kullanıyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Lanes bir profili kendi CLAUDE_CONFIG_DIR klasörüyle açar.",
                "O pencerede Code sekmesinde kısa bir oturum başlat.",
                "Lanes profil klasöründe projects/ altına yazı düşüp düşmediğini izler.",
            ]
        ),
        ValidationCheck(
            id: .appManagementPrompt, number: 5,
            title: "App Management izni",
            question: "Klon oluştururken macOS'un App Management izni soruluyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Üçüncü deneme sırasında bir izin penceresi çıktıysa bunu işaretle.",
            ]
        ),
        ValidationCheck(
            id: .separateIdentityCowork, number: 6,
            title: "Ayrı kimlikli klonda Cowork",
            question: "Ayrı kimlikli klonda Cowork sanal makinesi çalışıyor mu?",
            mode: .manual, isDeferred: true,
            steps: [
                "Bu deneme ayrı kimlik modu yazılınca yapılacak. Şimdilik atlayabilirsin.",
            ]
        ),
        ValidationCheck(
            id: .afterClaudeUpdate, number: 7,
            title: "Claude güncellemesinden sonra",
            question: "Claude güncellemesinden sonra her profil kendi klasörüyle yeniden açılabiliyor mu?",
            mode: .manual, isDeferred: true,
            steps: [
                "Claude bir sonraki güncellemeyi aldığında profilleri yeniden aç.",
                "Çalışan örnekler tablosu her pencerenin hangi klasörle açıldığını gösterir.",
            ]
        ),
        ValidationCheck(
            id: .panelOnNewMenuBar, number: 8,
            title: "macOS 27 menü çubuğunda panel",
            question: "Menü çubuğu paneli macOS 27'deki yeni menü çubuğunda sorunsuz çalışıyor mu?",
            mode: .manual, isDeferred: false,
            steps: [
                "Menü çubuğundaki Lanes simgesine tıkla.",
                "Panel doğru yerde açıldı mı, kapanınca odak geri döndü mü, işaretle.",
            ]
        ),
        ValidationCheck(
            id: .mainWindowActivation, number: 9,
            title: "Ana pencerenin öne gelmesi",
            question: "Ana pencere panelden açılınca öne geliyor mu, Dock simgesi ve menüleri görünüyor mu?",
            mode: .automated, isDeferred: false,
            steps: [
                "Lanes ana pencereyi panelden art arda açıp kapatır.",
                "Her denemede pencerenin öne gelip gelmediğini ve ne kadar sürdüğünü ölçer.",
            ]
        ),
    ]

    public static func check(_ id: ValidationCheckID) -> ValidationCheck {
        all.first(where: { $0.id == id })!
    }
}

public struct ValidationResult: Codable, Equatable, Sendable {
    public var checkID: ValidationCheckID
    public var outcome: ValidationOutcome
    /// What the user said they saw, in their own words.
    public var notes: String
    /// Command output and measurements Lanes collected.
    public var evidence: [String]
    public var recordedAt: Date?

    public init(
        checkID: ValidationCheckID,
        outcome: ValidationOutcome = .notRun,
        notes: String = "",
        evidence: [String] = [],
        recordedAt: Date? = nil
    ) {
        self.checkID = checkID
        self.outcome = outcome
        self.notes = notes
        self.evidence = evidence
        self.recordedAt = recordedAt
    }
}

/// The machine the checks ran on. Lanes fills it in; nothing here identifies
/// the user or their accounts.
public struct ValidationEnvironment: Codable, Equatable, Sendable {
    public var macOSVersion: String
    public var architecture: String
    public var claudeVersion: String?
    public var lanesVersion: String

    public init(macOSVersion: String, architecture: String, claudeVersion: String?, lanesVersion: String) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.claudeVersion = claudeVersion
        self.lanesVersion = lanesVersion
    }
}

/// Summary of repeated activation trials for check 9.
public struct ActivationTrials: Codable, Equatable, Sendable {
    public struct Trial: Codable, Equatable, Sendable {
        public var becameKey: Bool
        public var appBecameActive: Bool
        /// Seconds from the click until the window was key, or until the
        /// trial gave up.
        public var duration: Double
        /// Which step of the activation sequence finally worked.
        public var method: String

        public init(becameKey: Bool, appBecameActive: Bool, duration: Double, method: String) {
            self.becameKey = becameKey
            self.appBecameActive = appBecameActive
            self.duration = duration
            self.method = method
        }

        public var succeeded: Bool { becameKey && appBecameActive }
    }

    public var trials: [Trial]

    public init(trials: [Trial] = []) {
        self.trials = trials
    }

    public var successCount: Int { trials.filter(\.succeeded).count }

    public var successRate: Double {
        trials.isEmpty ? 0 : Double(successCount) / Double(trials.count)
    }

    public var medianDuration: Double? { percentile(0.5) }
    public var p95Duration: Double? { percentile(0.95) }

    /// How many trials each activation step finished, most used first.
    public var methodCounts: [(method: String, count: Int)] {
        let counts = Dictionary(grouping: trials, by: \.method).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (method: $0.key, count: $0.value) }
    }

    /// Nearest-rank percentile of the trial durations.
    func percentile(_ p: Double) -> Double? {
        guard !trials.isEmpty else { return nil }
        let sorted = trials.map(\.duration).sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    /// The outcome Lanes proposes: passed when every trial worked.
    public var suggestedOutcome: ValidationOutcome {
        if trials.isEmpty { return .notRun }
        if successCount == trials.count { return .passed }
        if successCount == 0 { return .failed }
        return .partial
    }

    public var evidenceLines: [String] {
        guard !trials.isEmpty else { return [] }
        var lines = ["\(successCount)/\(trials.count) denemede pencere öne geldi."]
        if let median = medianDuration, let p95 = p95Duration {
            lines.append("Süre: ortanca \(ValidationReport.milliseconds(median)), p95 \(ValidationReport.milliseconds(p95)).")
        }
        let methods = methodCounts.map { "\($0.method) \($0.count)" }.joined(separator: ", ")
        lines.append("İşe yarayan adım: \(methods).")
        return lines
    }
}

/// The Markdown report the user copies and pastes back into the project.
public struct ValidationReport: Sendable {
    public var environment: ValidationEnvironment
    public var results: [ValidationCheckID: ValidationResult]
    public var generatedAt: Date

    public init(environment: ValidationEnvironment, results: [ValidationCheckID: ValidationResult], generatedAt: Date) {
        self.environment = environment
        self.results = results
        self.generatedAt = generatedAt
    }

    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# Lanes Faz 0 sonuçları")
        lines.append("")
        lines.append("- Tarih: \(ValidationReport.dateString(generatedAt))")
        lines.append("- macOS: \(environment.macOSVersion) (\(environment.architecture))")
        lines.append("- Claude: \(environment.claudeVersion ?? "bulunamadı")")
        lines.append("- Lanes: \(environment.lanesVersion)")
        lines.append("")
        lines.append("| # | Deneme | Sonuç |")
        lines.append("| - | ------ | ----- |")
        for check in ValidationCheck.all {
            let outcome = results[check.id]?.outcome ?? .notRun
            lines.append("| \(check.number) | \(check.title) | \(outcome.reportLabel) |")
        }
        for check in ValidationCheck.all {
            guard let result = results[check.id], result.outcome != .notRun || !result.notes.isEmpty || !result.evidence.isEmpty else {
                continue
            }
            lines.append("")
            lines.append("## \(check.number). \(check.title)")
            lines.append("")
            lines.append("Sonuç: \(result.outcome.reportLabel)")
            let notes = result.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                lines.append("")
                lines.append("Not: \(notes)")
            }
            if !result.evidence.isEmpty {
                lines.append("")
                lines.append("```")
                lines.append(contentsOf: result.evidence)
                lines.append("```")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}
