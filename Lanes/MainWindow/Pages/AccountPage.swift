import AppKit
import LanesCore
import SwiftUI

/// One account: the selected tab's Form under a tab picker. The open button
/// and the other actions live in the window toolbar; the state line is the
/// window subtitle. The picker stays out of the toolbar: six segments next
/// to the title and the actions pushed every item into the overflow menu.
struct AccountPage: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    let profileID: ProfileID

    var body: some View {
        if let profile = model.profile(withID: profileID) {
            tabContent(for: profile)
                // A bar, not an inset: the Form scrolls under a scroll edge
                // effect instead of showing through the picker.
                .safeAreaBar(edge: .top, spacing: 0) {
                    tabPicker(for: profile)
                }
                .navigationSubtitle(statusLine(for: profile))
                .toolbar {
                    toolbarContent(for: profile)
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

    /// One line: state, class and mode, shortcut, archive. One string, so it
    /// truncates as a whole instead of wrapping chip by chip.
    private func statusLine(for profile: Profile) -> String {
        var parts = [model.isRunning(profile) ? String(localized: "Açık") : String(localized: "Kapalı")]
        if profile.isDefault {
            parts.append(String(localized: "Claude uygulamasının kendi hesabı"))
        } else {
            parts.append(profile.accountClass.displayName)
            parts.append(profile.mode.displayName)
        }
        if let number = model.shortcutNumber(for: profile) {
            parts.append("⌘\(number)")
        }
        if profile.isArchived {
            parts.append(String(localized: "Arşivde"))
        }
        return parts.joined(separator: " · ")
    }

    /// The tabs as one segmented control, centred above the Form. Segments
    /// share the width the page has, so a narrow window never hides a tab.
    private func tabPicker(for profile: Profile) -> some View {
        Picker("Bölüm", selection: tabBinding) {
            ForEach(tabs(for: profile)) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: DS.Metrics.readableWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.s)
    }

    @ToolbarContentBuilder
    private func toolbarContent(for profile: Profile) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            AccountOpenButton(profile: profile)
        }

        // Claude.app's own account has nothing to archive or quit from here.
        if !profile.isDefault {
            ToolbarItem(placement: .primaryAction) {
                AccountMoreMenu(profile: profile)
            }
        }
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
            .accountForm()
        }
    }
}

/// The page's one prominent action. Its label keeps the wider title's width,
/// so the toolbar does not move when the account opens or quits.
private struct AccountOpenButton: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let isRunning = model.isRunning(profile)
        Button {
            model.open(profile)
        } label: {
            Label {
                ZStack {
                    Text("Öne Getir").hidden()
                    Text("Aç").hidden()
                    isRunning ? Text("Öne Getir") : Text("Aç")
                }
            } icon: {
                Image(systemName: "arrow.up.forward.app")
            }
            .labelStyle(.titleAndIcon)
        }
        .help(isRunning ? "Bu hesabın Claude penceresini öne getir" : "Bu hesapla Claude'u aç")
        .dsPrimaryAction(tint: profile.color.buttonTint)
    }
}

/// Archive and quit, always in the same place. Quit stays listed and is
/// disabled while the account is closed.
private struct AccountMoreMenu: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        Menu {
            Button(profile.isArchived ? "Arşivden Çıkar" : "Arşivle") {
                model.setArchived(profile, !profile.isArchived)
            }
            .help(profile.isArchived
                ? "Hesabı genel bakışa, panele ve ⌘1-9'a geri getirir."
                : "Hesabı genel bakıştan, panelden, Dock menüsünden ve ⌘1-9'dan kaldırır. Girişi ve verileri kalır.")
            Divider()
            Button("Claude'dan Çık") {
                model.quit(profile)
            }
            .disabled(!model.isRunning(profile))
        } label: {
            Label("Diğer İşlemler", systemImage: "ellipsis.circle")
        }
        .help("Diğer İşlemler")
    }
}

/// The account's monogram, name and state, as the first row of General.
private struct AccountIdentityRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let isRunning = model.isRunning(profile)
        HStack(spacing: DS.Space.l) {
            // The running state is shown once, by the status badge below.
            MonogramView(profile: profile, size: DS.Monogram.hero, isRunning: false)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(verbatim: profile.name)
                    .font(DS.Typography.heroTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                DSStatusBadge(isRunning: isRunning)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.xs)
    }
}

private struct AccountGeneralTab: View {
    private enum Field: Hashable {
        case name
        case monogram
    }

    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var name = ""
    @State private var monogram = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        if profile.isDefault {
            Form {
                Section {
                    AccountIdentityRow(profile: profile)
                } footer: {
                    Text("Bu, Claude uygulamasında kullandığın hesap. Lanes onu yalnız gösterir, açar ve öne getirir. Adı, simgesi, girişi ve klasörleri Claude'un kendisine ait, Lanes bunları değiştirmez. Lanes'te eklediğin hesaplar ise kendi renkli simgeli kopyalarıyla, kendi klasörleriyle açılır.")
                }
            }
            .accountForm()
        } else {
            editableForm
        }
    }

    private var editableForm: some View {
        Form {
            Section {
                AccountIdentityRow(profile: profile)
            }
            Section {
                TextField("Ad", text: $name)
                    .focused($focusedField, equals: .name)
                    .onSubmit(commitName)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Renk")
                    ColorChooser(selection: binding(\.color))
                }
                TextField("Harf", text: $monogram)
                    .focused($focusedField, equals: .monogram)
                    .onSubmit(commitMonogram)
                    .onChange(of: monogram) { _, newValue in
                        let limited = String(newValue.prefix(2))
                        guard limited == newValue else {
                            monogram = limited
                            return
                        }
                        if focusedField == .monogram {
                            applyMonogram(limited, fallbackWhenEmpty: false)
                        }
                    }
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
                .disabled(modeChoices.count < 2)
                if CloneCheck.usesClone(profile) {
                    CloneStatusRow(profile: profile)
                }
            } footer: {
                Text(modeCaption)
            }
            if CloneCheck.usesClone(profile) {
                Section {
                    Toggle("Dock'ta gösterme (Deneysel)", isOn: binding(\.hidesFromDock))
                } footer: {
                    Text(String(localized: "\(ProfileMode.dockHidingCost) Değişiklik, hesap kapalıyken bir sonraki açılışta uygulanır."))
                }
            }
            if profile.mode.usesClaudeApp {
                memorySections
            }
        }
        .accountForm()
        .onAppear {
            name = profile.name
            monogram = profile.monogram
        }
        .onChange(of: profile.name) { _, newValue in
            name = newValue
        }
        .onChange(of: profile.monogram) { _, newValue in
            if focusedField != .monogram {
                monogram = newValue
            }
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .name, newValue != .name {
                commitName()
            }
            if oldValue == .monogram, newValue != .monogram {
                commitMonogram()
            }
        }
        .onDisappear {
            commitName()
            commitMonogram()
        }
    }

    /// Idle quitting, time in front and the daily reminder. The live rows
    /// are always there and show a dash when they do not apply, so the
    /// Form does not jump when the account opens or quits.
    @ViewBuilder
    private var memorySections: some View {
        let isRunning = model.isRunning(profile)
        Section {
            Picker("Kullanılmayınca kapat", selection: idleBinding) {
                Text("Hiçbir zaman").tag(0)
                ForEach(IdleQuitPolicy.choices, id: \.self) { minutes in
                    Text(IdleQuitPolicy.describe(minutes: minutes)).tag(minutes)
                }
            }
            LabeledContent("Şu an") {
                liveValue(isRunning ? model.resourceUsage[profile.id]?.summary : nil)
            }
        } header: {
            Text("Bellek")
        } footer: {
            Text("Hesap bu kadar süre öne gelmezse Lanes Claude'unu kapatır, bellek boşalır. Claude o an çalışıyorsa (örneğin uzun bir yanıt ya da Claude Code işi) kapatmaz. Giriş ve sohbetler kalır, yeniden açınca kaldığın yerden devam edersin.")
        }
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Önde geçen süre")
                    Text(String(localized: "Bugün \(FrontTimeLog.describe(seconds: model.frontSeconds(for: profile.id, days: 1))) · 7 gün \(FrontTimeLog.describe(seconds: model.frontSeconds(for: profile.id, days: 7))) · 30 gün \(FrontTimeLog.describe(seconds: model.frontSeconds(for: profile.id, days: 30)))"))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent("Son kullanım") {
                liveValue(lastUsedText(isRunning: isRunning))
            }
            Picker("Günlük süre hatırlatması", selection: limitBinding) {
                Text("Yok").tag(0)
                ForEach([30, 60, 120, 240, 480], id: \.self) { minutes in
                    Text(IdleQuitPolicy.describe(minutes: minutes)).tag(minutes)
                }
            }
            // Shown for the reminder the user picked just above, not for live state.
            if let progress = model.dailyLimitProgress(for: profile) {
                ProgressView(value: Double(min(progress.used, progress.limit)), total: Double(progress.limit)) {
                    Text("Bugün \(progress.used)/\(progress.limit) dk")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .tint(progress.used >= progress.limit ? DS.Palette.warning : profile.color.swatch)
            }
        } footer: {
            Text("Hesap bir günde bu kadar süre önde kalınca Lanes bir bildirim gösterir. Hesabı kapatmaz.")
        }
    }

    private func lastUsedText(isRunning: Bool) -> String? {
        // Said in words while open: a dash read as "never used". The row
        // stays, so the form never shifts on launch or quit.
        if isRunning { return String(localized: "Şu an açık") }
        guard let last = model.lastUsedAt[profile.id] else { return nil }
        return AccountCardView.relative(last)
    }

    /// A trailing value in the same font as every other row, or a dash.
    private func liveValue(_ value: String?) -> some View {
        Text(verbatim: value ?? "—")
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .truncationMode(.tail)
    }

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

    /// The clone with its own icon, or the web version. Plain Claude.app
    /// and Ayrı kimlik are only listed for an account that still uses them,
    /// so it can be moved to the clone.
    private var modeChoices: [ProfileMode] {
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

    /// Saves the letters while typing. An empty field falls back to the
    /// name's default letters only when editing ends.
    private func applyMonogram(_ text: String, fallbackWhenEmpty: Bool) {
        guard var updated = model.profile(withID: profile.id) else { return }
        let trimmed = String(text.trimmingCharacters(in: .whitespaces).prefix(2))
        let value: String
        if trimmed.isEmpty {
            guard fallbackWhenEmpty else { return }
            value = Profile.defaultMonogram(for: updated.name)
        } else {
            value = trimmed
        }
        guard value != updated.monogram else { return }
        updated.monogram = value
        model.updateProfile(updated)
    }

    private func commitMonogram() {
        applyMonogram(monogram, fallbackWhenEmpty: true)
        if let current = model.profile(withID: profile.id), current.monogram != monogram {
            monogram = current.monogram
        }
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
                    Group {
                        if let instance = model.instance(for: profile) {
                            Text("Açık, işlem \(String(instance.pid))")
                        } else {
                            Text("Kapalı")
                        }
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                }
                LabeledContent {
                    if let url = applicationURL {
                        DSRevealButton(url: url)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Uygulama")
                        if let url = applicationURL {
                            DSPathText(url: url)
                        } else {
                            Text("Claude bulunamadı")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Section {
                PathRow(url: dataDirectory)
                if !profile.isDefault {
                    LabeledContent("Açılış bayrağı") {
                        Text(verbatim: "--user-data-dir")
                            .monospaced()
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("Veri klasörü")
            } footer: {
                Text(profile.isDefault
                     ? String(localized: "Ana hesap Claude'un kendi klasörünü kullanır.")
                     : String(localized: "Oturumların, ayarların ve önbellek bu klasörde durur. Başka hiçbir hesap bu klasörü görmez."))
            }
        }
        .accountForm()
    }

    private var applicationURL: URL? {
        if profile.mode != .standard, let clone = model.cloneURLIfPresent(for: profile) {
            return clone
        }
        return model.claude?.url
    }
}

private struct AccountClaudeCodeTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let command = model.claudeCodeCommand(for: profile)
        let recent = model.recentClaudeCodeFolders(for: profile)
        Form {
            Section {
                PathRow(url: model.paths.effectiveClaudeCodeConfigDirectory(for: profile))
            } header: {
                Text("Yerel Claude Code")
            } footer: {
                Text(profile.isDefault
                     ? String(localized: "Ana hesap Claude Code'un kendi klasörünü (~/.claude) kullanır.")
                     : String(localized: "Bu hesabın Claude Code oturumları ve ayarları bu klasörde durur. Diğer hesaplar aynı anda kendi klasörleriyle çalışabilir."))
            }
            Section("Komut") {
                CommandLineBlock(text: command)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s) {
                        terminalButton
                        folderButton
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        terminalButton
                        folderButton
                    }
                }
            }
            if !recent.isEmpty {
                Section {
                    ForEach(recent, id: \.self) { folder in
                        AccountFolderRow(url: folder) {
                            Button("Aç") {
                                model.openClaudeCode(profile, in: folder)
                            }
                            DSIconButton("Listeden çıkar", systemImage: "minus.circle.fill", role: .destructive) {
                                model.forgetRecentFolder(folder.path, for: profile)
                            }
                        }
                    }
                } header: {
                    Text("Son klasörler")
                } footer: {
                    Text("Claude Code bu hesapla seçtiğin klasörde başlar. Liste yalnız Lanes'in ayarlarında durur, klasörlerin içine bakılmaz.")
                }
            }
        }
        .accountForm()
    }

    private var terminalButton: some View {
        Button("Terminalde Aç") {
            model.openClaudeCode(profile)
        }
        .fixedSize()
    }

    private var folderButton: some View {
        Button("Klasörde Aç…") {
            if let folder = ClaudeCodeFolderPicker.choose() {
                model.openClaudeCode(profile, in: folder)
            }
        }
        .fixedSize()
    }
}

/// A one-line command on a soft fill. It scrolls sideways instead of
/// breaking inside a path or an identifier.
private struct CommandLineBlock: View {
    let text: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            ScrollView(.horizontal) {
                Text(verbatim: text)
                    .font(DS.Typography.code)
                    .lineLimit(1)
                    .fixedSize()
                    .textSelection(.enabled)
                    .padding(.vertical, DS.Space.s)
            }
            // A legacy scroller ("Always show scroll bars" or a mouse) would
            // sit inside the block over the command; the hover help, text
            // selection and the copy button still give the whole command.
            .scrollIndicators(.never)
            .help(text)
            DSCopyButton(text: text)
        }
        .padding(.leading, DS.Space.m)
        .padding(.trailing, DS.Space.xs)
        .background(DS.Palette.codeFill, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
    }
}

/// One folder row for the account pages: name, short path, then actions.
struct AccountFolderRow<Actions: View>: View {
    let url: URL
    private let actions: Actions

    init(url: URL, @ViewBuilder actions: () -> Actions) {
        self.url = url
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Label {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(verbatim: url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    DSPathText(url: PathRow.displayURL(for: url))
                }
            } icon: {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            actions
        }
    }
}

extension View {
    /// Every account tab's Form: the app's grouped Form, centred at a
    /// readable width in wide windows.
    func accountForm() -> some View {
        modifier(AccountFormLayout())
    }
}

/// Grouped Form with side margins that keep its sections at
/// `DS.Metrics.readableWidth` when the window is wide.
struct AccountFormLayout: ViewModifier {
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

    /// Nil (the Form's own inset) until the window is wide enough that the
    /// centred column needs a wider margin than that, so a narrow window
    /// never loses the default inset.
    private var sideMargin: CGFloat? {
        let margin = ((width - DS.Metrics.readableWidth) / 2).rounded(.down)
        return margin > DS.Space.page ? margin : nil
    }
}

/// Asks for the folder Claude Code should start in.
@MainActor
enum ClaudeCodeFolderPicker {
    static func choose() -> URL? {
        chooseFolders(
            prompt: String(localized: "Claude Code'u Burada Aç"),
            message: String(localized: "Claude Code'un başlayacağı klasörü seç."),
            allowsMultipleSelection: false
        ).first
    }

    /// The one folder panel of the account pages. Brings Lanes forward first,
    /// so the panel never opens behind another app.
    static func chooseFolders(prompt: String, message: String?, allowsMultipleSelection: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.prompt = prompt
        if let message {
            panel.message = message
        }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// A folder path with a button that shows it in Finder.
struct PathRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 0) {
            DSPathText(url: Self.displayURL(for: url))
                .layoutPriority(1)
            Spacer(minLength: DS.Space.s)
            DSRevealButton(url: url)
        }
    }

    /// The same location without a directory URL's trailing slash, which
    /// `DSPathText` would otherwise show ("~/Projects/app/").
    static func displayURL(for url: URL) -> URL {
        guard url.isFileURL else { return url }
        return URL(fileURLWithPath: url.path, isDirectory: false)
    }
}

/// One line on whether the account's clone is ready, and a way to renew it.
/// The icon slot and the button stay in place in every state.
struct CloneStatusRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let isPreparing = model.clonesInProgress.contains(profile.id)
        let needsWork = model.cloneStatuses[profile.id]?.needsWork == true
        let isRunning = model.isRunning(profile)
        DSStatusRow(isPreparing ? .loading : dsStatus, title: Text(isPreparing ? String(localized: "Klon hazırlanıyor…") : text)) {
            EmptyView()
        } accessory: {
            Button("Şimdi Hazırla") {
                Task { await model.prepareClone(for: profile) }
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(isRunning || isPreparing || !needsWork)
            .help(isRunning ? "Açık bir klon yenilenmez. Hesabı kapatınca yeniden dene." : "Klonu şimdi oluştur ya da yenile")
            .opacity(needsWork ? 1 : 0)
            .accessibilityHidden(!needsWork)
        }
    }

    private var status: CloneStatus {
        model.cloneStatuses[profile.id] ?? .missing
    }

    private var dsStatus: DSStatus {
        switch status {
        case .ready, .notNeeded: return .ok
        case .missing, .needsRenewal: return .warning
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
        Section {
            LabeledContent("Durum", value: model.webAccounts.isOpen(profile.id) ? String(localized: "Sekmesi açık") : String(localized: "Kapalı"))
            Button("Bu Hesabın Girişini Sil…", role: .destructive) {
                confirmingForget = true
            }
        } header: {
            Text("Lanes içinde")
        } footer: {
            Text("Giriş ve claude.ai'nin sakladığı her şey bu hesaba ayrılmış, Lanes'e ait bir WebKit deposunda durur. Lanes onu okumaz. Öbür hesaplar ve Safari bu girişi görmez.")
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
