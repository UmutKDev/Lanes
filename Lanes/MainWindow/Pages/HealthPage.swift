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
            summarySection

            Section {
                if let claude = model.claude {
                    HealthRow(state: .good, title: String(localized: "Claude \(claude.version ?? "?")")) {
                        DSPathText(url: claude.url)
                    } accessory: {
                        DSRevealButton(url: claude.url)
                    }
                } else {
                    HealthRow(state: .problem, title: String(localized: "Claude bulunamadı")) {
                        Text("Claude'u Uygulamalar klasörüne kurduğunda Lanes onu kendiliğinden bulur.")
                    }
                }
                linkHandlerRow
                permissionRow
            } header: {
                Text("Claude")
            } footer: {
                if model.claude != nil {
                    Text("Claude kendini güncelleyip yeniden açılınca sürüm yeniden okunur.")
                }
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
                        Text("Hesabın klasörü olmadan, Claude uygulamasının verileriyle çalışıyor.")
                    } accessory: {
                        Button("Kapat") { model.quitStrayClone(instance) }
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
                let outside = model.instances.filter { $0.profileID == nil && !$0.isStrayClone }
                if !outside.isEmpty {
                    HealthRow(state: .warning, title: String(localized: "Lanes'in tanımadığı \(outside.count) Claude açık")) {
                        Text("Lanes dışından, kendi klasörü olmadan açılmış bir Claude ya da başka bir kopya. Claude uygulamasının verilerini kullanıyor olabilir.")
                    }
                }
            }

            cloneSection

            Section("Claude Code") {
                if !lookedForClaudeCommand {
                    HealthRow(state: .loading, title: String(localized: "claude komutu aranıyor…")) {
                        EmptyView()
                    }
                } else if let claudeCommand {
                    HealthRow(state: .good, title: String(localized: "claude komutu kurulu")) {
                        DSPathText(url: URL(fileURLWithPath: claudeCommand))
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
                        HStack(spacing: DS.Space.s) {
                            Text(verbatim: folder.lastPathComponent)
                                .font(DS.Typography.path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(folder.path)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            DSRevealButton(url: folder)
                        }
                        // Lines up with the titles of the rows above.
                        .padding(.leading, HealthRowMetrics.titleInset)
                    }
                }
            }
        }
        .systemForm()
        .toolbar {
            if !cloneProfiles.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let profiles = cloneProfiles
                        Task { await checkSignatures(profiles) }
                    } label: {
                        Label {
                            Text("İmzaları Denetle")
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                                .symbolEffect(.rotate, isActive: checkingSignatures)
                        }
                    }
                    .help("İmzaları Denetle")
                    .disabled(checkingSignatures)
                }
            }
        }
        .task {
            model.refreshInstances()
            orphans = model.orphanProfileFolders()
            model.refreshCloneStatuses()
            permission = await AppleEvents.reopenPermission(bundleIdentifier: ClaudeInstallation.bundleIdentifier)
            claudeCommand = await Self.findClaudeCommand()
            lookedForClaudeCommand = true
        }
    }

    // MARK: Summary

    /// One line on top: everything fine, or how many checks need a look.
    /// The symbol keeps one slot and the count changes in place.
    private var summarySection: some View {
        let failing = failingChecks
        let status: DSStatus = failing.contains(.error) ? .error : (failing.isEmpty ? .ok : .warning)
        let isChecking = permission == nil || !lookedForClaudeCommand
        return Section {
            HStack(spacing: DS.Space.m) {
                ZStack {
                    Image(systemName: DSStatus.ok.symbol).hidden()
                    Image(systemName: DSStatus.warning.symbol).hidden()
                    Image(systemName: DSStatus.error.symbol).hidden()
                    Image(systemName: status.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(status.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.largeTitle)
                .accessibilityHidden(true)
                Group {
                    if failing.isEmpty {
                        Text("Her şey yolunda")
                    } else {
                        Text("\(failing.count) sorun")
                    }
                }
                .font(DS.Typography.heroTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView()
                    .controlSize(.small)
                    .opacity(isChecking ? 1 : 0)
                    .accessibilityHidden(!isChecking)
            }
            .padding(.vertical, DS.Space.xs)
            .animation(DS.Motion.standard, value: failing.count)
            .animation(DS.Motion.standard, value: status)
        }
    }

    /// The checks on this page that are not fine, by how serious they are.
    /// Mirrors the rows below, so the count matches what the page shows.
    private var failingChecks: [DSStatus] {
        var failing: [DSStatus] = []
        if model.claude == nil {
            failing.append(.error)
        }
        let handlerStatus = linkHandlerStatus
        if handlerStatus != .ok {
            failing.append(handlerStatus)
        }
        if permission == .denied {
            failing.append(.error)
        }
        for instance in model.instances {
            guard let id = instance.profileID, let profile = model.profile(withID: id), !profile.isDefault,
                  let result = model.separationResults[id], !result.usesOwnFolder
            else { continue }
            failing.append(.error)
        }
        failing += model.strayClones.map { _ in DSStatus.error }
        if model.instances.contains(where: { $0.profileID == nil && !$0.isStrayClone }) {
            failing.append(.warning)
        }
        if lookedForClaudeCommand, claudeCommand == nil {
            failing.append(.warning)
        }
        if !orphans.isEmpty {
            failing.append(.warning)
        }
        if !model.legacyClones.isEmpty {
            failing.append(.warning)
        }
        return failing
    }

    /// The same decision as `linkHandlerRow`, as a status only.
    private var linkHandlerStatus: DSStatus {
        let handler = LinkHandlerRegistry.currentHandler()
        if let handler, let claude = model.claude, handler.standardizedFileURL == claude.url.standardizedFileURL {
            return .ok
        }
        if LinkHandlerRegistry.lanesIsHandler {
            return model.isLinkRoutingOn ? .ok : .warning
        }
        return .warning
    }

    // MARK: Clones

    private var cloneProfiles: [Profile] {
        model.library.profiles.filter(CloneCheck.usesClone)
    }

    @ViewBuilder
    private var cloneSection: some View {
        let profiles = cloneProfiles
        let legacyClones = model.legacyClones
        if !profiles.isEmpty || !legacyClones.isEmpty {
            Section {
                ForEach(profiles) { profile in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        DSAccountLabel(profile: profile)
                            .font(DS.Typography.rowTitle)
                        CloneStatusRow(profile: profile)
                        if let signature = signatures[profile.id] {
                            Text(signature.summary)
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, HealthRowMetrics.titleInset)
                                .transition(.opacity)
                        }
                    }
                    .animation(DS.Motion.standard, value: signatures[profile.id])
                }
                if !legacyClones.isEmpty {
                    HealthRow(state: .warning, title: String(localized: "Faz 0'dan kalan \(legacyClones.count) deneme klonu")) {
                        Text("~/Applications/Lanes Profiles içinde. Spotlight'tan açılırsa Claude uygulamasının verileriyle çalışır.")
                    } accessory: {
                        Button("Çöp Sepeti'ne Taşı") { model.trashLegacyClones() }
                            .controlSize(.small)
                            .fixedSize()
                    }
                }
            } header: {
                Text("Klonlar")
            } footer: {
                if !profiles.isEmpty {
                    Text("Klonlarda Anthropic'in imzası korunur. Özel simge paketin köküne bir Finder bilgisi eklediği için codesign'ın sıkı denetimi geçmez. Bu beklenen bir durum, macOS'un açılış denetimi (Gatekeeper) klonu kabul eder. Dock'ta gösterilmeyen klonlar bu Mac'te yeniden imzalanır, onlarda Anthropic'in imzası yoktur.")
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

    // MARK: Rows

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
            HealthRow(state: .loading, title: String(localized: "Otomasyon izni denetleniyor…")) {
                EmptyView()
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

    /// The folder appears with "~" and its ID cut short, so a narrow window
    /// wraps it between folders, never inside an ID. The tooltip has it whole.
    @ViewBuilder
    private func accountRow(_ profile: Profile) -> some View {
        let folder = model.paths.effectiveDesktopDataDirectory(for: profile)
        let shown = folder.path.shortPath
        if profile.isDefault {
            HealthRow(state: .good, title: profile.name) {
                Text("Claude'un kendi klasörü: \(shown)")
                    .help(folder.path)
            }
        } else if let result = model.separationResults[profile.id], !result.usesOwnFolder {
            HealthRow(state: .problem, title: profile.name) {
                Text("Açıldıktan sonra kendi klasörüne yazmadı. Claude uygulamasının verilerini kullanıyor olabilir.")
            }
        } else if model.separationResults[profile.id]?.usesOwnFolder == true {
            HealthRow(state: .good, title: profile.name) {
                Text("Kendi klasörünü kullanıyor: \(shown)")
                    .help(folder.path)
            }
        } else {
            HealthRow(state: .info, title: profile.name) {
                Text("Klasörü: \(shown). Lanes bu oturumda açılışını görmedi, ayrılık denetlenmedi.")
                    .help(folder.path)
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

private enum HealthRowMetrics {
    /// Where a row's title starts: past the status icon and its gap.
    static let titleInset: CGFloat = DS.Metrics.statusIcon + DS.Space.m
}

/// A check: fixed status icon column, title, caption detail, and an optional
/// trailing action. Built like `DSStatusRow`, plus a spoken state on the icon.
/// Loading uses the same geometry, so a finished check does not move.
private struct HealthRow<Detail: View, Accessory: View>: View {
    enum Status {
        case good, info, warning, problem, loading
    }

    let state: Status
    let title: String
    private let detail: Detail
    private let accessory: Accessory

    init(
        state: Status,
        title: String,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.state = state
        self.title = title
        self.detail = detail()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            DSStatusIcon(status: dsStatus)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityState))
                .accessibilityHidden(state == .loading)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(state == .loading ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                detail
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .animation(DS.Motion.standard, value: state)
    }

    private var dsStatus: DSStatus {
        switch state {
        case .good: return .ok
        case .info: return .info
        case .warning: return .warning
        case .problem: return .error
        case .loading: return .loading
        }
    }

    private var accessibilityState: String {
        switch state {
        case .good: return String(localized: "Yolunda")
        case .info: return String(localized: "Bilgi")
        case .warning: return String(localized: "Uyarı")
        case .problem: return String(localized: "Sorun")
        case .loading: return title
        }
    }
}

extension HealthRow where Accessory == EmptyView {
    init(state: Status, title: String, @ViewBuilder detail: () -> Detail) {
        self.init(state: state, title: title, detail: detail, accessory: { EmptyView() })
    }
}

private extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }

    /// "~" for the home folder, and every folder named by a UUID cut to its
    /// first block ("1A2B3C4D…").
    var shortPath: String {
        abbreviatingHome
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { part -> String in
                let name = String(part)
                guard UUID(uuidString: name) != nil, let head = name.split(separator: "-").first else { return name }
                return "\(head)…"
            }
            .joined(separator: "/")
    }
}

// MARK: - Form layout shared by the system pages

extension View {
    /// Grouped Form for Health, Maintenance and Privacy: `dsForm()`, with
    /// side margins that keep the sections at `DS.Metrics.readableWidth`,
    /// centred, when the window is wide.
    func systemForm() -> some View {
        modifier(SystemFormLayout())
    }
}

struct SystemFormLayout: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .dsForm()
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newValue in
                width = newValue
            }
    }

    private var sideMargin: CGFloat {
        max(0, ((width - DS.Metrics.readableWidth) / 2).rounded(.down))
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
