import AppKit
import LanesCore
import SwiftUI

/// Whether everything Lanes depends on is in place, at a glance. It shows
/// nothing about sign-ins: knowing that would mean looking at login data.
struct HealthPage: View {
    @Environment(AppModel.self) private var model
    @State private var permission: AppleEvents.Permission?
    @State private var claudeCommand: String?
    @State private var lookedForClaudeCommand = false
    @State private var orphans: [URL] = []
    @State private var signatures: [ProfileID: CloneSignatureSummary] = [:]
    @State private var checkingSignatures = false

    var body: some View {
        Form {
            Section("Claude") {
                if let claude = model.claude {
                    HealthRow(state: .good, title: String(localized: "Claude \(claude.version ?? "?")")) {
                        PathRow(url: claude.url)
                    }
                    Text("Claude kendini güncelleyip yeniden açılınca sürüm yeniden okunur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HealthRow(state: .problem, title: String(localized: "Claude bulunamadı")) {
                        Text("Claude'u Uygulamalar klasörüne kurduğunda Lanes onu kendiliğinden bulur.")
                    }
                }
                linkHandlerRow
                permissionRow
            }

            Section("Açık hesaplar") {
                let open = model.instances.filter { $0.profileID != nil }
                if open.isEmpty {
                    Text("Şu an açık hesap yok.")
                        .foregroundStyle(.secondary)
                }
                ForEach(open, id: \.pid) { instance in
                    if let id = instance.profileID, let profile = model.profile(withID: id) {
                        accountRow(profile)
                    }
                }
                ForEach(model.strayClones, id: \.pid) { instance in
                    HealthRow(state: .problem, title: String(localized: "\(URL(fileURLWithPath: instance.applicationBundlePath).deletingPathExtension().lastPathComponent) Lanes dışından açıldı")) {
                        HStack {
                            Text("Hesabın klasörü olmadan, Ana hesabın verileriyle çalışıyor.")
                            Button("Kapat") { model.quitStrayClone(instance) }
                        }
                    }
                }
                let outside = model.instances.filter { $0.profileID == nil && !$0.isStrayClone }
                if !outside.isEmpty {
                    HealthRow(state: .warning, title: String(localized: "Lanes'in tanımadığı \(outside.count) Claude açık")) {
                        Text("Lanes dışından, kendi klasörü olmadan açılmış bir Claude ya da başka bir kopya. Ana hesabın verilerini kullanıyor olabilir.")
                    }
                }
            }

            cloneSection

            Section("Claude Code") {
                if !lookedForClaudeCommand {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("claude komutu aranıyor…")
                            .foregroundStyle(.secondary)
                    }
                } else if let claudeCommand {
                    HealthRow(state: .good, title: String(localized: "claude komutu kurulu")) {
                        Text(claudeCommand.abbreviatingHome)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } else {
                    HealthRow(state: .warning, title: String(localized: "claude komutu bulunamadı")) {
                        Text("\"Claude Code'u Terminalde Aç\" için Claude Code'un komut satırı sürümü gerekiyor.")
                    }
                }
            }

            Section("Lanes klasörleri") {
                if orphans.isEmpty {
                    HealthRow(state: .good, title: String(localized: "Sahipsiz hesap klasörü yok")) {
                        EmptyView()
                    }
                } else {
                    HealthRow(state: .warning, title: String(localized: "\(orphans.count) klasör hiçbir hesaba ait değil")) {
                        Text("Genellikle kaldırılmış hesaplardan kalır. İçlerinde o hesapların girişleri olabilir. Lanes bunları silmez, istersen Finder'dan kendin silebilirsin.")
                    }
                    ForEach(orphans, id: \.self) { folder in
                        HStack {
                            Text(folder.lastPathComponent)
                                .font(.caption.monospaced())
                            Spacer()
                            Button("Finder'da Göster") {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            model.refreshInstances()
            orphans = model.orphanProfileFolders()
            model.refreshCloneStatuses()
            permission = await AppleEvents.reopenPermission(bundleIdentifier: ClaudeInstallation.bundleIdentifier)
            claudeCommand = await Self.findClaudeCommand()
            lookedForClaudeCommand = true
        }
    }

    @ViewBuilder
    private var cloneSection: some View {
        let cloneProfiles = model.library.profiles.filter(CloneCheck.usesClone)
        if !cloneProfiles.isEmpty || !model.legacyClones.isEmpty {
            Section("Klonlar") {
                ForEach(cloneProfiles) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                        CloneStatusRow(profile: profile)
                        if let signature = signatures[profile.id] {
                            Text(signature.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !cloneProfiles.isEmpty {
                    HStack {
                        Button("İmzaları Denetle") {
                            Task { await checkSignatures(cloneProfiles) }
                        }
                        .disabled(checkingSignatures)
                        if checkingSignatures {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text("Klonlarda Anthropic'in imzası korunur. Özel simge paketin köküne bir Finder bilgisi eklediği için codesign'ın sıkı denetimi geçmez. Bu beklenen bir durum, macOS'un açılış denetimi (Gatekeeper) klonu kabul eder. Dock'ta gösterilmeyen klonlar bu Mac'te yeniden imzalanır, onlarda Anthropic'in imzası yoktur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.legacyClones.isEmpty {
                    HealthRow(state: .warning, title: String(localized: "Faz 0'dan kalan \(model.legacyClones.count) deneme klonu")) {
                        HStack {
                            Text("~/Applications/Lanes Profiles içinde. Spotlight'tan açılırsa Ana hesabın verileriyle çalışır.")
                            Button("Çöp Sepeti'ne Taşı") { model.trashLegacyClones() }
                        }
                    }
                }
            }
        }
    }

    private func checkSignatures(_ profiles: [Profile]) async {
        checkingSignatures = true
        defer { checkingSignatures = false }
        for profile in profiles {
            guard let bundle = model.cloneURLIfPresent(for: profile) else {
                signatures[profile.id] = nil
                continue
            }
            var summary = await CloneSignatureSummary.check(bundle)
            summary.signedHere = CloneRecord.read(from: model.paths.cloneRecordFile(for: profile.id))?.hiddenFromDock == true
            signatures[profile.id] = summary
        }
    }

    @ViewBuilder
    private var linkHandlerRow: some View {
        let handler = LinkHandlerRegistry.currentHandler()
        if let handler, let claude = model.claude, handler.standardizedFileURL == claude.url.standardizedFileURL {
            HealthRow(state: .good, title: String(localized: "claude:// bağlantılarını Claude açıyor")) {
                Text("Girişler ve bağlantılar her zamanki gibi çalışır.")
            }
        } else if LinkHandlerRegistry.lanesIsHandler, model.isLinkRoutingOn {
            HealthRow(state: .good, title: String(localized: "claude:// bağlantılarını Lanes yönlendiriyor")) {
                Text("Hesap Haritası'ndaki kurallara göre. Giriş bağlantıları yönlendirilmez.")
            }
        } else if LinkHandlerRegistry.lanesIsHandler {
            HealthRow(state: .warning, title: String(localized: "claude:// bağlantılarını Lanes açıyor")) {
                Text("Yönlendirme kapalıyken Lanes varsayılanı açılışta Claude'a geri verir.")
            }
        } else {
            HealthRow(state: .warning, title: String(localized: "claude:// bağlantılarını açan: \(handler?.deletingPathExtension().lastPathComponent ?? String(localized: "yok"))")) {
                Text("Girişlerin çalışması için bu bağlantıları Claude'un açması gerekir.")
            }
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch permission {
        case nil:
            HStack {
                ProgressView().controlSize(.small)
                Text("Otomasyon izni denetleniyor…")
                    .foregroundStyle(.secondary)
            }
        case .granted?:
            HealthRow(state: .good, title: String(localized: "Otomasyon izni verilmiş")) {
                Text("Lanes açık bir hesabın penceresini öne getirebilir.")
            }
        case .denied?:
            HealthRow(state: .problem, title: String(localized: "Otomasyon izni kapalı")) {
                Text("Lanes açık bir hesabı öne getirmekte zorlanabilir. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan Lanes altında Claude'u açabilirsin.")
            }
        case .notAskedYet?:
            HealthRow(state: .info, title: String(localized: "Otomasyon izni henüz sorulmadı")) {
                Text("macOS bunu Lanes bir pencereyi ilk kez öne getirirken sorabilir.")
            }
        case .claudeNotRunning?:
            HealthRow(state: .info, title: String(localized: "Otomasyon izni denetlenemedi")) {
                Text("Bu yalnız bir Claude açıkken denetlenebiliyor.")
            }
        case let .unknown(code)?:
            HealthRow(state: .info, title: String(localized: "Otomasyon izni bilinmiyor (\(code))")) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ profile: Profile) -> some View {
        let folder = model.paths.effectiveDesktopDataDirectory(for: profile)
        if profile.isDefault {
            HealthRow(state: .good, title: profile.name) {
                Text("Claude'un kendi klasörü: \(folder.path.abbreviatingHome)")
            }
        } else if let result = model.separationResults[profile.id], !result.usesOwnFolder {
            HealthRow(state: .problem, title: profile.name) {
                Text("Açıldıktan sonra kendi klasörüne yazmadı. Ana hesabın verilerini kullanıyor olabilir.")
            }
        } else if model.separationResults[profile.id]?.usesOwnFolder == true {
            HealthRow(state: .good, title: profile.name) {
                Text("Kendi klasörünü kullanıyor: \(folder.path.abbreviatingHome)")
            }
        } else {
            HealthRow(state: .info, title: profile.name) {
                Text("Klasörü: \(folder.path.abbreviatingHome). Lanes bu oturumda açılışını görmedi, ayrılık denetlenmedi.")
            }
        }
    }

    /// Looks the command up the way Terminal would, through a login shell.
    private static func findClaudeCommand() async -> String? {
        let output = await ShellRunner.run("/bin/zsh", ["-lc", "command -v claude"])
        guard output.status == 0 else { return nil }
        let path = output.text.split(separator: "\n").last.map(String.init) ?? ""
        return path.hasPrefix("/") ? path : nil
    }
}

private struct HealthRow<Detail: View>: View {
    enum Status {
        case good, info, warning, problem
    }

    let state: Status
    let title: String
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(Text(accessibilityState))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var symbol: String {
        switch state {
        case .good: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .good: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .problem: return .red
        }
    }

    private var accessibilityState: String {
        switch state {
        case .good: return String(localized: "Yolunda")
        case .info: return String(localized: "Bilgi")
        case .warning: return String(localized: "Uyarı")
        case .problem: return String(localized: "Sorun")
        }
    }
}

private extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

/// What macOS's own tools say about a clone's signature. Run in the
/// background, only when the user asks.
struct CloneSignatureSummary: Equatable {
    var valid: Bool
    var strict: Bool
    var gatekeeper: Bool
    /// The clone was signed again on this Mac to stay out of the Dock.
    var signedHere = false

    static func check(_ bundle: URL) async -> CloneSignatureSummary {
        async let deep = ShellRunner.run("/usr/bin/codesign", ["--verify", "--deep", bundle.path])
        async let strict = ShellRunner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path])
        async let assess = ShellRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", bundle.path])
        return await CloneSignatureSummary(valid: deep.status == 0, strict: strict.status == 0, gatekeeper: assess.status == 0)
    }

    var summary: String {
        if signedHere {
            return valid
                ? String(localized: "Dock'ta görünmemesi için bu Mac'te imzalandı, imza geçerli. Anthropic'in imzası olmadığı için Gatekeeper'ın kabul etmemesi beklenen bir durum.")
                : String(localized: "Bu Mac'te yapılan imza geçersiz. Hesap kapalıyken Dock ayarını kapatıp açarak klonu yenileyebilirsin.")
        }
        let signature = valid ? String(localized: "İmza geçerli") : String(localized: "İmza geçersiz")
        let gate = gatekeeper ? String(localized: "Gatekeeper kabul ediyor") : String(localized: "Gatekeeper kabul etmiyor")
        let strictText = strict ? String(localized: "sıkı denetim de geçti") : String(localized: "sıkı denetim simge yüzünden geçmedi (beklenen)")
        return "\(signature), \(gate), \(strictText)."
    }
}
