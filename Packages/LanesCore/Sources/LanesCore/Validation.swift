import Foundation

/// The Faz 0 and Faz 0.5 checks: short experiments on a real Mac that settle
/// how Lanes launches, routes links and shows windows. The study document and
/// the Alfa plan list them in this order.
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
    case staleClone
    case cloneOutsideLanes
    case newAccountSignIn
    case crossAccountSignOut
    case claudeCodeLogin
    case coworkStandard
    case claudeCodeSessionRecords
    case cloneRecheck

    public var id: String { rawValue }
}

/// Faz 0 settled the basic decisions. Faz 0.5 measures what Faz 0 did not:
/// Claude's own behaviour around clones, sign-in and Claude Code.
public enum ValidationPhase: String, CaseIterable, Codable, Sendable, Identifiable {
    case faz0
    case faz05

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .faz0: return "Faz 0"
        case .faz05: return "Faz 0.5"
        }
    }
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
    public let phase: ValidationPhase
    /// The check's number within its phase.
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
            id: .linkToSpecificInstance, phase: .faz0, number: 1,
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
            id: .reclaimLinkHandler, phase: .faz0, number: 2,
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
            id: .signedCloneIdentity, phase: .faz0, number: 3,
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
            id: .claudeCodeConfigDirectory, phase: .faz0, number: 4,
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
            id: .appManagementPrompt, phase: .faz0, number: 5,
            title: "App Management izni",
            question: "Klon oluştururken macOS'un App Management izni soruluyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Üçüncü deneme sırasında bir izin penceresi çıktıysa bunu işaretle.",
            ]
        ),
        ValidationCheck(
            id: .separateIdentityCowork, phase: .faz0, number: 6,
            title: "Ayrı kimlikli klonda Cowork",
            question: "Ayrı kimlikli klonda Cowork sanal makinesi çalışıyor mu?",
            mode: .manual, isDeferred: true,
            steps: [
                "Bu deneme ayrı kimlik modu yazılınca yapılacak. Şimdilik atlayabilirsin.",
            ]
        ),
        ValidationCheck(
            id: .afterClaudeUpdate, phase: .faz0, number: 7,
            title: "Claude güncellemesinden sonra",
            question: "Claude güncellemesinden sonra her profil kendi klasörüyle yeniden açılabiliyor mu?",
            mode: .manual, isDeferred: true,
            steps: [
                "Claude bir sonraki güncellemeyi aldığında profilleri yeniden aç.",
                "Çalışan örnekler tablosu her pencerenin hangi klasörle açıldığını gösterir.",
            ]
        ),
        ValidationCheck(
            id: .panelOnNewMenuBar, phase: .faz0, number: 8,
            title: "macOS 27 menü çubuğunda panel",
            question: "Menü çubuğu paneli macOS 27'deki yeni menü çubuğunda sorunsuz çalışıyor mu?",
            mode: .manual, isDeferred: false,
            steps: [
                "Menü çubuğundaki Lanes simgesine tıkla.",
                "Panel doğru yerde açıldı mı, kapanınca odak geri döndü mü, işaretle.",
            ]
        ),
        ValidationCheck(
            id: .mainWindowActivation, phase: .faz0, number: 9,
            title: "Ana pencerenin öne gelmesi",
            question: "Ana pencere panelden açılınca öne geliyor mu, Dock simgesi ve menüleri görünüyor mu?",
            mode: .automated, isDeferred: false,
            steps: [
                "Lanes ana pencereyi panelden art arda açıp kapatır.",
                "Her denemede pencerenin öne gelip gelmediğini ve ne kadar sürdüğünü ölçer.",
                "\"Simgeye Tıklayarak Ölç\" seçilirse paneli sen simgeye tıklayarak açarsın, Lanes paneli ve pencereyi ölçer.",
            ]
        ),
        ValidationCheck(
            id: .staleClone, phase: .faz05, number: 1,
            title: "Eski klon",
            question: "Claude güncellendikten sonra eski sürümden oluşturulan klon hâlâ açılıyor mu, hangi sürümü gösteriyor ve macOS onu hâlâ kabul ediyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Bu denemede \"Klonu Oluştur\"a basma. O düğme eski klonu siler.",
                "Lanes diskteki deneme klonunu inceler. Klonun ve Claude'un sürümünü, imzayı ve Gatekeeper sonucunu kaydeder.",
                "Klonu aç. Açılıp açılmadığını, simgesinin durup durmadığını ve güncelleme isteyip istemediğini işaretle. Bitince klondan Claude'un kendi menüsüyle çık.",
                "Diskte klon yoksa 3. denemeden yeni bir klon oluştur. Bu denemeyi Claude'un bir sonraki güncellemesinden sonra yap.",
            ]
        ),
        ValidationCheck(
            id: .cloneOutsideLanes, phase: .faz05, number: 2,
            title: "Lanes'siz açılan klon",
            question: "Finder, Spotlight ya da Dock'tan açılan klon hangi klasörü kullanıyor? claude:// varsayılanı klona geçiyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Klon açıksa kapat.",
                "\"Finder'da Göster\" ile klonu bul ve Finder'dan aç. İstersen Spotlight ve Dock ile de dene.",
                "Lanes açık pencerelerin hangi klasörle açıldığını ve claude:// bağlantılarını açan uygulamayı kaydeder.",
                "Bitince klondan Claude'un kendi menüsüyle çık. claude:// varsayılanı klona geçtiyse 0.5.3'teki \"Claude'u Geri Yükle\" ile geri al.",
            ]
        ),
        ValidationCheck(
            id: .newAccountSignIn, phase: .faz05, number: 3,
            title: "Yeni hesabın girişi",
            question: "Ana hesap açıkken yeni bir hesapla giriş yapılınca giriş dönüş bağlantısı hangi pencereye düşüyor?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Ana hesap açık olsun. claude:// bağlantılarını Claude açıyor olmalı.",
                "\"Başlangıcı Kaydet\"e bas. Sonra Lanes'te yeni bir hesap ekle ve aç.",
                "Açılan pencerede Google, e-posta bağlantısı ve varsa SSO ile ayrı ayrı giriş yap.",
                "Her girişten sonra girişin hangi pencerede tamamlandığını seç. Lanes bağlantının adresini kaydetmez.",
            ]
        ),
        ValidationCheck(
            id: .crossAccountSignOut, phase: .faz05, number: 4,
            title: "Hesaplar arası çıkış",
            question: "İkinci bir hesap açıkken ana hesapta hesap değiştirilince ikinci hesabın oturumu kapanıyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "İkinci bir hesap açık ve girişli olsun. \"Durumu Kaydet\"e bas.",
                "Ana hesabın penceresinde hesap değiştir.",
                "İki pencereyi de kapat, sonra ikisini de Lanes'ten yeniden aç.",
                "İkinci hesabın oturumu açık kaldı mı, işaretle. Bu deneme 7. denemedeki açıklanamayan çıkışı yeniden üretmeyi deniyor.",
            ]
        ),
        ValidationCheck(
            id: .claudeCodeLogin, phase: .faz05, number: 5,
            title: "Claude Code girişi",
            question: "Terminalde açılan Claude Code, ~/.claude ile bir hesapta ve profilin CLAUDE_CONFIG_DIR klasörüyle başka bir hesapta kalıyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Bu deneme için iki ayrı hesap gerekiyor.",
                "Ana hesap için Claude Code'u Terminalde aç ve A hesabıyla giriş yap. Seçtiğin profil için de aç ve B hesabıyla giriş yap.",
                "İki Terminal penceresini de kapat ve yeniden aç. Her birinde /status komutuyla hangi hesapta olduğuna bak.",
                "Sonucu işaretle. Girişler ortaksa Lanes'in hesap ayrımı yalnız Desktop'taki Code sekmesini kapsar.",
            ]
        ),
        ValidationCheck(
            id: .coworkStandard, phase: .faz05, number: 6,
            title: "Standart modda Cowork",
            question: "Standart modda ikinci bir hesapta Cowork çalışıyor mu? İki hesapta aynı anda çalışıyor mu?",
            mode: .manual, isDeferred: false,
            steps: [
                "İkinci bir hesabı Lanes'ten aç ve Cowork'te kısa bir görev başlat.",
                "Ana hesapta da aynı anda bir Cowork görevi başlat.",
                "İkisinin de çalışıp çalışmadığını işaretle.",
            ]
        ),
        ValidationCheck(
            id: .claudeCodeSessionRecords, phase: .faz05, number: 7,
            title: "Claude Code oturum kayıtları",
            question: "Claude Code oturum kayıtları hangi klasör yapısında duruyor? CLAUDE_CONFIG_DIR ile verilen klasörden bir oturum claude --resume ile sürdürülebiliyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Bir hesap seç. Lanes o hesabın projects/ klasöründeki proje klasörlerini ve oturum dosyalarının sayısını kaydeder. Dosyaların içeriğini açmaz.",
                "\"Komutu Kopyala\" ile en yeni oturumu sürdüren komutu al ve Terminalde çalıştır.",
                "Oturumun kaldığı yerden sürüp sürmediğini işaretle.",
            ]
        ),
        ValidationCheck(
            id: .cloneRecheck, phase: .faz05, number: 8,
            title: "Klon yeniden (3. ve 5. denemeler)",
            question: "Güncel kodla oluşturulan klonu macOS kabul ediyor mu? Var olan bir klon değiştirilirken App Management izni soruluyor mu?",
            mode: .assisted, isDeferred: false,
            steps: [
                "Bu denemeyi en sona bırak. \"Klonu Oluştur\" diskteki eski klonu kalıcı olarak siler.",
                "Deneme klonu açıksa önce klondan Claude'un kendi menüsüyle çık. Lanes açık bir klonu değiştirmez.",
                "Klonu oluştur. Diskte eski klon varsa, değiştirilirken bir izin penceresi çıkıp çıkmadığını işaretle.",
                "Klonu aç ve Dock'ta, Cmd-Tab'da gördüğünü seç.",
            ]
        ),
    ]

    public static func checks(in phase: ValidationPhase) -> [ValidationCheck] {
        all.filter { $0.phase == phase }
    }

    /// The number shown to people: "3" in Faz 0, "0.5.3" in Faz 0.5.
    public var label: String {
        switch phase {
        case .faz0: return "\(number)"
        case .faz05: return "0.5.\(number)"
        }
    }

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
    /// The build and Claude version the outcome or the last evidence was
    /// recorded with. The report's header only shows the versions at the time
    /// it is copied, which can be days later.
    public var environment: ValidationEnvironment?

    public init(
        checkID: ValidationCheckID,
        outcome: ValidationOutcome = .notRun,
        notes: String = "",
        evidence: [String] = [],
        recordedAt: Date? = nil,
        environment: ValidationEnvironment? = nil
    ) {
        self.checkID = checkID
        self.outcome = outcome
        self.notes = notes
        self.evidence = evidence
        self.recordedAt = recordedAt
        self.environment = environment
    }
}

/// The machine and the build the checks ran on. Lanes fills it in; nothing
/// here names the user or their accounts.
public struct ValidationEnvironment: Codable, Equatable, Sendable {
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
        guard let commit, !commit.isEmpty else { return "bilinmiyor" }
        return commitHasLocalChanges == true ? "\(commit) (kaydedilmemiş değişikliklerle)" : commit
    }

    /// One line naming what can differ between two runs of a check.
    public var summary: String {
        [
            "Claude \(claudeVersion ?? "bulunamadı")",
            "Lanes \(lanesVersion)",
            "commit \(commitDescription)",
            "imza: \(signing ?? "bilinmiyor")",
            "macOS \(macOSVersion)",
        ].joined(separator: " · ")
    }
}

/// How a build of Lanes is signed. Automation permission and App Management
/// follow the signature, so a check's result only carries over to a build
/// signed the same way.
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
        case .unsigned: return "imzasız"
        case .linkerSigned: return "yalnız bağlayıcı imzası (imzasız derleme)"
        case .adHoc: return "ad hoc (Sign to Run Locally)"
        case .appleDevelopment: return "ekip imzası (Apple Development)"
        case .developerID: return "Developer ID"
        case .appleDistribution: return "dağıtım imzası (Apple Distribution)"
        case .otherCertificate: return "başka bir sertifika"
        }
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
        /// Seconds from a real click on the menu bar icon until the panel
        /// took keyboard focus. Nil when the panel was opened from code.
        public var panelLatency: Double?
        /// What `panelLatency` was measured from: "mouseDown" (the press on
        /// the icon), "event" (the click event Lanes was handed) or
        /// "callback" (the moment Lanes was told, without the system's delay).
        public var panelLatencySource: String?

        public init(
            becameKey: Bool,
            appBecameActive: Bool,
            duration: Double,
            method: String,
            panelLatency: Double? = nil,
            panelLatencySource: String? = nil
        ) {
            self.becameKey = becameKey
            self.appBecameActive = appBecameActive
            self.duration = duration
            self.method = method
            self.panelLatency = panelLatency
            self.panelLatencySource = panelLatencySource
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

    public var medianDuration: Double? { ActivationTrials.percentile(0.5, of: trials.map(\.duration)) }
    public var p95Duration: Double? { ActivationTrials.percentile(0.95, of: trials.map(\.duration)) }

    private var panelLatencies: [Double] { trials.compactMap(\.panelLatency) }
    public var medianPanelLatency: Double? { ActivationTrials.percentile(0.5, of: panelLatencies) }
    public var p95PanelLatency: Double? { ActivationTrials.percentile(0.95, of: panelLatencies) }

    /// How many trials each activation step finished, most used first.
    public var methodCounts: [(method: String, count: Int)] {
        let counts = Dictionary(grouping: trials, by: \.method).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (method: $0.key, count: $0.value) }
    }

    /// Nearest-rank percentile.
    static func percentile(_ p: Double, of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
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
        if let median = medianPanelLatency, let p95 = p95PanelLatency {
            lines.append("Simgeye tıklandıktan sonra panel \(panelLatencies.count) denemede ortanca \(ValidationReport.milliseconds(median)), p95 \(ValidationReport.milliseconds(p95)) içinde açıldı.")
        }
        let sources = Dictionary(grouping: trials.compactMap(\.panelLatencySource), by: { $0 }).mapValues(\.count)
        if !sources.isEmpty {
            let labels = ["mouseDown": "simgeye basış", "event": "tıklama olayı", "callback": "Lanes'e haber geldiği an"]
            let parts = sources.sorted { $0.key < $1.key }.map { "\(labels[$0.key] ?? $0.key) (\($0.value) deneme)" }
            lines.append("Panel süresinin başladığı an: \(parts.joined(separator: ", ")).")
        }
        return lines
    }
}

/// The Markdown report the user copies and pastes back into the project.
public struct ValidationReport: Sendable {
    public var environment: ValidationEnvironment
    public var results: [ValidationCheckID: ValidationResult]
    public var generatedAt: Date
    /// The user's home folder. The report writes it as "~", so paths in the
    /// log lines do not carry the user's account name.
    public var homeDirectory: String?

    public init(environment: ValidationEnvironment, results: [ValidationCheckID: ValidationResult], generatedAt: Date, homeDirectory: String? = nil) {
        self.environment = environment
        self.results = results
        self.generatedAt = generatedAt
        self.homeDirectory = homeDirectory
    }

    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# Lanes doğrulama sonuçları")
        lines.append("")
        lines.append("- Tarih: \(ValidationReport.dateString(generatedAt))")
        lines.append("- macOS: \(environment.macOSVersion) (\(environment.architecture))")
        lines.append("- Claude: \(environment.claudeVersion ?? "bulunamadı")")
        lines.append("- Lanes: \(environment.lanesVersion)")
        lines.append("- Commit: \(environment.commitDescription)")
        lines.append("- İmza: \(environment.signing ?? "bilinmiyor")")
        lines.append("- Uygulama: \(environment.appPath ?? "bilinmiyor")")
        lines.append("")
        lines.append("Her denemenin altındaki \"Kaydedildiği ortam\" satırı, deneme bu başlıktakinden farklı bir Lanes ya da Claude ile kaydedildiyse görünür. Lanes bu bilgiyi tutmaya başlamadan önce kaydedilen denemelerde \"bilinmiyor\" yazar.")
        for phase in ValidationPhase.allCases {
            let checks = ValidationCheck.checks(in: phase)
            lines.append("")
            lines.append("## \(phase.title)")
            lines.append("")
            lines.append("| # | Deneme | Sonuç |")
            lines.append("| - | ------ | ----- |")
            for check in checks {
                let outcome = results[check.id]?.outcome ?? .notRun
                lines.append("| \(check.label) | \(check.title) | \(outcome.reportLabel) |")
            }
            for check in checks {
                guard let result = results[check.id], result.outcome != .notRun || !result.notes.isEmpty || !result.evidence.isEmpty else {
                    continue
                }
                lines.append(contentsOf: details(of: check, result: result))
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        guard let homeDirectory else { return text }
        return ValidationReport.abbreviatingHome(homeDirectory, in: text)
    }

    private func details(of check: ValidationCheck, result: ValidationResult) -> [String] {
        var lines = ["", "### \(check.label). \(check.title)", "", "Sonuç: \(result.outcome.reportLabel)"]
        if let recorded = result.environment {
            if recorded.summary != environment.summary {
                lines.append("")
                lines.append("Kaydedildiği ortam: \(recorded.summary)")
            }
        } else {
            lines.append("")
            lines.append("Kaydedildiği ortam: bilinmiyor")
        }
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
        return lines
    }

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

    static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func milliseconds(_ seconds: Double) -> String {
        "\(Int((seconds * 1000).rounded())) ms"
    }
}
