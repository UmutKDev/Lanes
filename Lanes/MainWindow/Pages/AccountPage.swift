import AppKit
import LanesCore
import SwiftUI

/// One account: a header with its identity and state, then tabs.
struct AccountPage: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    let profileID: ProfileID

    var body: some View {
        if let profile = model.profile(withID: profileID) {
            VStack(spacing: 0) {
                AccountHeader(profile: profile)
                Picker("Bölüm", selection: tabBinding) {
                    ForEach(tabs(for: profile)) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                Divider()
                tabContent(for: profile)
            }
        } else {
            ContentUnavailableView("Hesap bulunamadı", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    /// Claude.app's own account only shows what Lanes can do with it.
    private func tabs(for profile: Profile) -> [AccountTab] {
        let visible = AccountTab.visible(showingDeveloperPages: showsDeveloperPages)
        return profile.isDefault ? visible.filter { [.general, .claudeCode].contains($0) } : visible
    }

    private var tabBinding: Binding<AccountTab> {
        Binding(get: { tab }, set: { navigation.accountTab = $0 })
    }

    /// The chosen tab, or General when the setting hides it.
    private var tab: AccountTab {
        navigation.accountTab.isBuilt || showsDeveloperPages ? navigation.accountTab : .general
    }

    @ViewBuilder
    private func tabContent(for profile: Profile) -> some View {
        switch tabs(for: profile).contains(tab) ? tab : .general {
        case .general:
            AccountGeneralTab(profile: profile)
        case .desktop:
            AccountDesktopTab(profile: profile)
        case .claudeCode:
            AccountClaudeCodeTab(profile: profile)
        case .identity:
            AccountIdentityTab(profile: profile)
        case .security:
            AccountSecurityTab(profile: profile)
        case .storage:
            Form {
                Section {
                    AccountStorageView(profile: profile)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct AccountHeader: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let isRunning = model.isRunning(profile)
        HStack(spacing: 16) {
            MonogramView(profile: profile, size: 56, isRunning: isRunning)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Text(isRunning ? "Açık" : "Kapalı")
                    Text(verbatim: "·")
                    if profile.isDefault {
                        Text("Claude uygulamasının kendi hesabı")
                    } else {
                        Text(profile.accountClass.displayName)
                        Text(verbatim: "·")
                        Text(profile.mode.displayName)
                    }
                    if let number = model.shortcutNumber(for: profile) {
                        Text(verbatim: "·")
                        Text(verbatim: "⌘\(number)")
                            .monospacedDigit()
                    }
                    if profile.isArchived {
                        Text(verbatim: "·")
                        Text("Arşivde")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !profile.isDefault {
                Button(profile.isArchived ? "Arşivden Çıkar" : "Arşivle") {
                    model.setArchived(profile, !profile.isArchived)
                }
                .help(profile.isArchived
                    ? "Hesabı genel bakışa, panele ve ⌘1-9'a geri getirir."
                    : "Hesabı genel bakıştan, panelden, Dock menüsünden ve ⌘1-9'dan kaldırır. Girişi ve verileri kalır.")
            }
            if isRunning && !profile.isDefault {
                Button("Claude'dan Çık") {
                    model.quit(profile)
                }
            }
            Button(isRunning ? "Öne Getir" : "Aç") {
                model.open(profile)
            }
            .buttonStyle(.borderedProminent)
            .tint(profile.color.swatch)
        }
        .padding(24)
    }
}

private struct AccountGeneralTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var name = ""

    var body: some View {
        if profile.isDefault {
            Form {
                Section {
                    Text("Bu, Claude uygulamasında kullandığın hesap. Lanes onu yalnız gösterir, açar ve öne getirir. Adı, simgesi, girişi ve klasörleri Claude'un kendisine ait, Lanes bunları değiştirmez. Lanes'te eklediğin hesaplar ise kendi renkli simgeli kopyalarıyla, kendi klasörleriyle açılır.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        } else {
            editableForm
        }
    }

    private var editableForm: some View {
        Form {
            Section {
                TextField("Ad", text: $name)
                    .onSubmit(commitName)
                LabeledContent("Renk") {
                    ColorChooser(selection: binding(\.color))
                }
                TextField("Harf", text: monogramBinding)
                    .frame(maxWidth: 160)
                Picker("Hesap türü", selection: binding(\.accountClass)) {
                    ForEach(AccountClass.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
            }
            Section {
                Picker("Açılış biçimi", selection: binding(\.mode)) {
                    ForEach(modeChoices, id: \.self) { mode in
                        Text(modeTitle(mode)).tag(mode)
                    }
                }
                .disabled(profile.isDefault || modeChoices.count < 2)
                Text(modeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if CloneCheck.usesClone(profile) {
                    CloneStatusRow(profile: profile)
                }
            }
            if CloneCheck.usesClone(profile) {
                Section {
                    Toggle("Dock'ta gösterme (Deneysel)", isOn: binding(\.hidesFromDock))
                    Text(String(localized: "\(ProfileMode.dockHidingCost) Değişiklik, hesap kapalıyken bir sonraki açılışta uygulanır."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if profile.mode.usesClaudeApp {
                Section("Bellek") {
                    Picker("Kullanılmayınca kapat", selection: idleBinding) {
                        Text("Hiçbir zaman").tag(0)
                        ForEach(IdleQuitPolicy.choices, id: \.self) { minutes in
                            Text(IdleQuitPolicy.describe(minutes: minutes)).tag(minutes)
                        }
                    }
                    Text("Hesap bu kadar süre öne gelmezse Lanes Claude'unu kapatır, bellek boşalır. Claude o an çalışıyorsa (örneğin uzun bir yanıt ya da Claude Code işi) kapatmaz. Giriş ve sohbetler kalır, yeniden açınca kaldığın yerden devam edersin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let usage = model.resourceUsage[profile.id] {
                        LabeledContent("Şu an", value: usage.summary)
                    }
                    Picker("Günlük süre hatırlatması", selection: limitBinding) {
                        Text("Yok").tag(0)
                        ForEach([30, 60, 120, 240, 480], id: \.self) { minutes in
                            Text(IdleQuitPolicy.describe(minutes: minutes)).tag(minutes)
                        }
                    }
                    Text("Hesap bir günde bu kadar süre önde kalınca Lanes bir bildirim gösterir. Hesabı kapatmaz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let progress = model.dailyLimitProgress(for: profile) {
                        ProgressView(value: Double(min(progress.used, progress.limit)), total: Double(progress.limit)) {
                            Text("Bugün \(progress.used)/\(progress.limit) dk")
                                .font(.caption)
                        }
                        .tint(progress.used >= progress.limit ? .orange : profile.color.swatch)
                    }
                }
            }
            if profile.isDefault {
                Section {
                    Text("Bu hesap Claude'un kendi klasörlerini kullanıyor. Lanes'i kaldırsan bile bu hesap olduğu gibi kalır.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { _, newValue in
            name = newValue
        }
        .onDisappear(perform: commitName)
    }

    /// The clone with its own icon, or the web version. Plain Claude.app
    /// and Ayrı kimlik are only listed for an account that still uses them,
    /// so it can be moved to the clone.
    private var limitBinding: Binding<Int> {
        Binding(
            get: { profile.dailyLimitMinutes ?? 0 },
            set: { minutes in
                var updated = profile
                updated.dailyLimitMinutes = minutes > 0 ? minutes : nil
                model.updateProfile(updated)
                if minutes > 0 { Task { _ = await Notifier.requestPermission() } }
            }
        )
    }

    private var idleBinding: Binding<Int> {
        Binding(
            get: { profile.idleQuitMinutes ?? 0 },
            set: { minutes in
                var updated = profile
                updated.idleQuitMinutes = minutes > 0 ? minutes : nil
                model.updateProfile(updated)
            }
        )
    }

        private var modeChoices: [ProfileMode] {
        if profile.isDefault { return [.standard] }
        var choices: [ProfileMode] = [.signedClone, .insideLanes]
        if profile.mode == .standard || profile.mode == .separateIdentity { choices.append(profile.mode) }
        return choices
    }

    private func modeTitle(_ mode: ProfileMode) -> String {
        switch mode {
        case .standard: return String(localized: "Claude uygulaması")
        case .signedClone: return String(localized: "Claude uygulaması, kendi simgesiyle")
        case .insideLanes: return String(localized: "Lanes içinde, web sürümü")
        default: return mode.displayName
        }
    }

    private var modeCaption: String {
        if profile.isDefault {
            return String(localized: "Ana hesap her zaman Claude'un kendisiyle açılır.")
        }
        switch profile.mode {
        case .insideLanes:
            return String(localized: "\(ProfileMode.insideLanes.explanation) Claude uygulamasına geçersen bu hesaba orada yeniden giriş yapman gerekir.")
        case .standard:
            return ProfileMode.standard.explanation
        case .signedClone, .separateIdentity:
            return String(localized: "\(ProfileMode.signedClone.explanation) Claude güncellenince ya da hesabın adı, rengi veya harfi değişince klon, hesap kapalıyken bir sonraki açılışta yenilenir. Klonu Finder'dan açma, Lanes'ten aç.")
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.name, var updated = model.profile(withID: profile.id) else { return }
        updated.rename(to: trimmed)
        model.updateProfile(updated)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Profile, Value>) -> Binding<Value> {
        Binding(
            get: { (model.profile(withID: profile.id) ?? profile)[keyPath: keyPath] },
            set: { newValue in
                guard var updated = model.profile(withID: profile.id) else { return }
                updated[keyPath: keyPath] = newValue
                model.updateProfile(updated)
            }
        )
    }

    private var monogramBinding: Binding<String> {
        Binding(
            get: { (model.profile(withID: profile.id) ?? profile).monogram },
            set: { newValue in
                guard var updated = model.profile(withID: profile.id) else { return }
                let trimmed = String(newValue.trimmingCharacters(in: .whitespaces).prefix(2))
                updated.monogram = trimmed.isEmpty ? Profile.defaultMonogram(for: updated.name) : trimmed
                model.updateProfile(updated)
            }
        )
    }
}

private struct AccountDesktopTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let dataDirectory = model.paths.effectiveDesktopDataDirectory(for: profile)
        Form {
            if model.runsInsideLanes(profile) {
                InsideLanesSection(profile: profile)
            }
            Section("Claude Desktop") {
                LabeledContent("Durum") {
                    if let instance = model.instance(for: profile) {
                        Text("Açık, işlem \(String(instance.pid))")
                    } else {
                        Text("Kapalı")
                    }
                }
                LabeledContent("Uygulama") {
                    Text(applicationPath)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Section("Veri klasörü") {
                PathRow(url: dataDirectory)
                if !profile.isDefault {
                    LabeledContent("Açılış bayrağı") {
                        Text(verbatim: "--user-data-dir")
                            .monospaced()
                    }
                }
                Text(profile.isDefault
                     ? String(localized: "Ana hesap Claude'un kendi klasörünü kullanır.")
                     : String(localized: "Oturumların, ayarların ve önbellek bu klasörde durur. Başka hiçbir hesap bu klasörü görmez."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var applicationPath: String {
        if profile.mode != .standard, let clone = model.cloneURLIfPresent(for: profile) {
            return clone.path
        }
        return model.claude?.url.path ?? String(localized: "Claude bulunamadı")
    }
}

private struct AccountClaudeCodeTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let command = model.claudeCodeCommand(for: profile)
        Form {
            Section("Yerel Claude Code") {
                PathRow(url: model.paths.effectiveClaudeCodeConfigDirectory(for: profile))
                Text(profile.isDefault
                     ? String(localized: "Ana hesap Claude Code'un kendi klasörünü (~/.claude) kullanır.")
                     : String(localized: "Bu hesabın Claude Code oturumları ve ayarları bu klasörde durur. Diğer hesaplar aynı anda kendi klasörleriyle çalışabilir."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Komut") {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Kopyala") {
                        SystemActions.copy(command)
                    }
                    Button("Terminalde Aç") {
                        model.openClaudeCode(profile)
                    }
                    Button("Klasörde Aç…") {
                        if let folder = ClaudeCodeFolderPicker.choose() {
                            model.openClaudeCode(profile, in: folder)
                        }
                    }
                }
            }
            let recent = model.recentClaudeCodeFolders(for: profile)
            if !recent.isEmpty {
                Section {
                    ForEach(recent, id: \.self) { folder in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.lastPathComponent)
                                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Aç") {
                                model.openClaudeCode(profile, in: folder)
                            }
                            Button {
                                model.forgetRecentFolder(folder.path, for: profile)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Listeden çıkar")
                        }
                    }
                } header: {
                    Text("Son klasörler")
                } footer: {
                    Text("Claude Code bu hesapla seçtiğin klasörde başlar. Liste yalnız Lanes'in ayarlarında durur, klasörlerin içine bakılmaz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Asks for the folder Claude Code should start in.
@MainActor
enum ClaudeCodeFolderPicker {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Claude Code'u Burada Aç")
        panel.message = String(localized: "Claude Code'un başlayacağı klasörü seç.")
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// A folder path with a button that shows it in Finder.
struct PathRow: View {
    let url: URL

    var body: some View {
        HStack {
            Text(abbreviated)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Finder'da Göster") {
                SystemActions.reveal(url)
            }
            .controlSize(.small)
        }
    }

    private var abbreviated: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// One line on whether the account's clone is ready, and a way to renew it.
struct CloneStatusRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        HStack {
            if model.clonesInProgress.contains(profile.id) {
                ProgressView().controlSize(.small)
                Text("Klon hazırlanıyor…")
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(text)
                Spacer()
                if model.cloneStatuses[profile.id]?.needsWork == true {
                    Button("Şimdi Hazırla") {
                        Task { await model.prepareClone(for: profile) }
                    }
                    .disabled(model.isRunning(profile))
                    .help(model.isRunning(profile) ? "Açık bir klon yenilenmez. Hesabı kapatınca yeniden dene." : "Klonu şimdi oluştur ya da yenile")
                }
            }
        }
        .font(.callout)
    }

    private var status: CloneStatus {
        model.cloneStatuses[profile.id] ?? .missing
    }

    private var symbol: String {
        switch status {
        case .ready, .notNeeded: return "checkmark.circle.fill"
        case .missing: return "exclamationmark.triangle.fill"
        case .needsRenewal: return "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch status {
        case .ready, .notNeeded: return .green
        case .missing: return .orange
        case .needsRenewal: return .secondary
        }
    }

    private var text: String {
        switch status {
        case .notNeeded, .ready:
            return String(localized: "Klon hazır.")
        case .missing:
            return String(localized: "Klon yok. Hesap açılırken oluşturulur.")
        case let .needsRenewal(reasons):
            return String(localized: "Klon bir sonraki açılışta yenilenecek: \(reasons.map(\.displayText).joined(separator: ", ")).")
        }
    }
}

extension CloneRenewalReason {
    var displayText: String {
        switch self {
        case let .claudeUpdated(_, to):
            return String(localized: "Claude \(to) sürümüne güncellendi")
        case .renamed:
            return String(localized: "hesabın adı değişti")
        case .iconChanged:
            return String(localized: "simge değişti")
        case .dockSettingChanged:
            return String(localized: "Dock ayarı değişti")
        case .unknownOrigin:
            return String(localized: "klonun kaydı yok")
        }
    }
}

/// An account that runs in a Lanes tab: its state, and a way to sign out
/// for good.
private struct InsideLanesSection: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var confirmingForget = false

    var body: some View {
        Section("Lanes içinde") {
            LabeledContent("Durum", value: model.webAccounts.isOpen(profile.id) ? String(localized: "Sekmesi açık") : String(localized: "Kapalı"))
            Text("Giriş ve claude.ai'nin sakladığı her şey bu hesaba ayrılmış, Lanes'e ait bir WebKit deposunda durur. Lanes onu okumaz. Öbür hesaplar ve Safari bu girişi görmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Bu Hesabın Girişini Sil…", role: .destructive) {
                confirmingForget = true
            }
        }
        .confirmationDialog("\(profile.name) hesabının girişi ve claude.ai verisi silinsin mi?", isPresented: $confirmingForget) {
            Button("Girişi Sil", role: .destructive) {
                Task { await model.webAccounts.removeData(for: profile.id) }
            }
        } message: {
            Text("Sohbetlerin claude.ai'de kalır. Bir sonraki açılışta yeniden giriş yaparsın.")
        }
    }
}
