import LanesCore
import Observation
import SwiftUI

/// What the menu bar controller tells the panel each time it opens: how tall
/// the scrolling list may get on this screen, and a counter that changes on
/// every opening so the panel can reset its search.
@MainActor
@Observable
final class CommandPanelState {
    /// Height the accounts and scenes list may take before it scrolls.
    var maxListHeight: CGFloat = 480
    /// Goes up by one each time the panel is shown.
    var presentation = 0
}

/// The panel that opens from the menu bar: every account at a glance, one
/// click to open it, and the way into the main window.
struct CommandPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    var state: CommandPanelState
    var onClose: () -> Void
    @State private var query = ""
    @State private var listContentHeight: CGFloat = 0
    @FocusState private var isSearchFocused: Bool
    @AppStorage(Preferences.Key.panelSortsByRecent) private var sortsByRecent = false

    init(state: CommandPanelState, onClose: @escaping () -> Void) {
        self.state = state
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsSearch {
                searchField
                    .padding(.horizontal, DS.Panel.contentInset)
                    .padding(.bottom, DS.Space.s + 2)
            }
            Divider().padding(.horizontal, DS.Panel.contentInset)
            if let notice = model.notice {
                NoticeRow(notice: notice) { model.notice = nil }
                    .padding(.horizontal, DS.Panel.contentInset)
                    .padding(.top, DS.Space.s + 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            list
            Divider().padding(.horizontal, DS.Panel.contentInset)
            footer
        }
        .frame(width: DS.Panel.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(DS.Motion.notice, value: model.notice?.id)
        .modifier(PanelSurface())
        .onExitCommand(perform: onClose)
        .background(shortcuts)
        .onAppear(perform: prepareForShowing)
        .onChange(of: state.presentation) {
            prepareForShowing()
        }
        .onDisappear {
            query = ""
        }
    }

    /// A fresh opening starts with an empty search, focused when shown.
    private func prepareForShowing() {
        query = ""
        isSearchFocused = showsSearch
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.xs) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Lanes")
                    .font(DS.Typography.sectionTitle)
                    .lineLimit(1)
                Text(statusLine)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.numericText())
                    .animation(DS.Motion.standard, value: statusLine)
            }
            .layoutPriority(1)
            Spacer(minLength: DS.Space.s)
            DSIconButton("Ayarlar", systemImage: "gearshape") {
                router.showSettings()
            }
            DSIconButton("Lanes'i aç", systemImage: "macwindow") {
                router.showMainWindow()
            }
        }
        .focusEffectDisabled()
        .padding(.leading, DS.Panel.contentInset)
        .padding(.trailing, DS.Panel.contentInset - DS.Space.xs)
        .padding(.vertical, DS.Space.m)
    }

    private var statusLine: String {
        guard model.claude != nil else {
            return String(localized: "Claude bulunamadı")
        }
        let count = model.runningCount
        guard count > 0 else { return String(localized: "Açık hesap yok") }
        guard model.totalMemoryBytes > 0 else { return String(localized: "\(count) hesap açık") }
        let memory = ByteCountFormatter.string(fromByteCount: Int64(clamping: model.totalMemoryBytes), countStyle: .memory)
        return String(localized: "\(count) hesap açık · \(memory)")
    }

    // MARK: Search

    private var showsSearch: Bool {
        model.library.activeProfiles.count >= 4
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.s - 2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Hesap ara", text: $query, prompt: Text("Hesap ara"))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($isSearchFocused)
                .onSubmit {
                    guard let first = matchingProfiles.first else { return }
                    onClose()
                    model.open(first)
                }
                .onKeyPress(.escape) {
                    if query.isEmpty {
                        onClose()
                    } else {
                        query = ""
                    }
                    return .handled
                }
        }
        .padding(.horizontal, DS.Space.s + 2)
        .padding(.vertical, DS.Space.xs + 2)
        .background(DS.Palette.cardFill, in: Capsule())
    }

    // MARK: List

    /// Accounts and scenes scroll between the pinned header and footer once
    /// they are taller than the screen allows.
    private var list: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                accounts
                    .padding(.vertical, DS.Space.s)
                if !model.library.scenes.isEmpty {
                    Divider().padding(.horizontal, DS.Panel.contentInset - DS.Panel.rowInset)
                    scenes
                        .padding(.vertical, DS.Space.s)
                }
            }
            .padding(.horizontal, DS.Panel.rowInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                listContentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .frame(height: min(listContentHeight, max(state.maxListHeight, DS.Monogram.panel * 3)))
    }

    @ViewBuilder
    private var accounts: some View {
        if model.library.activeProfiles.isEmpty {
            Text("Henüz hesap yok.")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.xxl)
        } else {
            VStack(spacing: DS.Space.xxs) {
                ForEach(matchingProfiles) { profile in
                    AccountCardView(profile: profile, onClose: onClose)
                }
                if matchingProfiles.isEmpty {
                    Text("\"\(query)\" ile eşleşen hesap yok.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.s)
                }
            }
        }
    }

    /// Accounts whose name, email or note holds the search text, ignoring
    /// case and accents with Turkish rules.
    private var matchingProfiles: [Profile] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let profiles = (sortsByRecent ? model.profilesByRecentUse : model.library.activeProfiles)
            .filter(model.isShownUnderFocus)
        guard !text.isEmpty else { return profiles }
        return profiles.filter { profile in
            SearchText.matches(text, in: [profile.name, model.email(for: profile) ?? "", profile.note ?? ""])
        }
    }

    /// Saved groups of accounts, one click opens them all.
    private var scenes: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("Sahneler")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, DS.Panel.rowPaddingH)
                .padding(.bottom, DS.Space.xxs)
            ForEach(model.library.scenes) { scene in
                Button {
                    onClose()
                    model.open(scene)
                } label: {
                    SceneRowLabel(
                        name: scene.name,
                        profiles: scene.profiles(in: model.library),
                        shortcut: model.shortcuts.shortcut(for: .scene(scene.id))?.description
                    )
                }
                .buttonStyle(DSRowButtonStyle())
                .help("Sahnedeki hesapları aç")
            }
        }
    }

    // MARK: Footer

    /// Seconds all accounts spent in front today.
    private var todayTotal: Double {
        model.library.profiles.reduce(0) { $0 + model.frontSeconds(for: $1.id, days: 1) }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                router.showAddProfile()
            } label: {
                Label("Hesap Ekle", systemImage: "plus")
                    .lineLimit(1)
            }
            .dsPrimaryAction()
            .controlSize(.small)
            .fixedSize()
            Spacer(minLength: DS.Space.s)
            Label {
                Text("Bugün \(FrontTimeLog.describe(seconds: todayTotal))")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "clock")
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help("Bugün Claude hesaplarının önde geçirdiği toplam süre. Ayrıntısı Kullanım sayfasında.")
            .opacity(todayTotal >= 60 ? 1 : 0)
            .accessibilityHidden(todayTotal < 60)
            moreMenu
        }
        .padding(.leading, DS.Panel.contentInset)
        .padding(.trailing, DS.Panel.contentInset - DS.Space.xs)
        .padding(.vertical, DS.Space.s + 2)
    }

    private var moreMenu: some View {
        Menu {
            if showsDeveloperPages {
                Button("Faz 0 Doğrulama") {
                    router.showMainWindow(.validation)
                }
                Divider()
            }
            Toggle("Son kullanılan hesap üstte", isOn: $sortsByRecent)
            Divider()
            if !model.library.archivedProfiles.isEmpty {
                Menu("Arşivdeki Hesaplar") {
                    ForEach(model.library.archivedProfiles) { profile in
                        Button(model.isRunning(profile) ? String(localized: "\(profile.name) (açık)") : profile.name) {
                            onClose()
                            model.open(profile)
                        }
                    }
                }
            }
            if model.closedActiveProfiles.count > 1 {
                Button("Kapalı Hesapların Tümünü Aç") {
                    onClose()
                    model.openAllClosedAccounts()
                }
            }
            if model.quittableOpenCount > 0 {
                Button("Lanes Hesaplarının Tümünü Kapat") {
                    model.quitAllLanesAccounts()
                }
                Divider()
            }
            if model.updater.isAvailable {
                Button("Güncellemeleri Denetle…") {
                    model.updater.checkNow()
                }
            }
            Button("Lanes'ten Çık") {
                NSApp.terminate(nil)
            }
        } label: {
            Label("Diğer İşlemler", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: DS.Metrics.iconButton, height: DS.Metrics.iconButton)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help("Diğer İşlemler")
    }

    /// Invisible buttons that give ⌘1 to ⌘9 to the first nine accounts.
    /// The ⌘N hints on the rows come from the same order
    /// (`AppModel.shortcutNumber(for:)` counts active profiles).
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(model.library.activeProfiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                Button("") {
                    onClose()
                    model.open(profile)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// The panel's surface. Regular Liquid Glass, with a light tint in light mode
/// so a colourful desktop behind it does not make it look two-toned.
private struct PanelSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .containerShape(shape)
            .glassEffect(glass, in: shape)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Panel.radius, style: .continuous)
    }

    private var glass: Glass {
        colorScheme == .light ? Glass.regular.tint(Color.white.opacity(0.55)) : Glass.regular
    }
}

/// One scene row: symbol slot, name, up to four avatars plus "+N", shortcut.
private struct SceneRowLabel: View {
    let name: String
    let profiles: [Profile]
    let shortcut: String?

    var body: some View {
        HStack(spacing: DS.Space.s + 2) {
            Image(systemName: Destination.scenes.symbol)
                .foregroundStyle(.secondary)
                .frame(width: DS.Panel.leadingSlot)
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: DS.Space.s)
            avatars
            if let shortcut {
                DSShortcutHint(text: shortcut)
            }
        }
    }

    private var avatars: some View {
        let shown = Array(profiles.prefix(DS.Panel.maxStackedAvatars))
        let extra = profiles.count - shown.count
        return HStack(spacing: -DS.Space.xs) {
            ForEach(shown) { profile in
                MonogramView(profile: profile, size: DS.Monogram.tiny)
            }
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(DS.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, DS.Space.xs + 2)
            }
        }
        .fixedSize()
    }
}

/// One account in the panel.
struct AccountCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let profile: Profile
    var onClose: () -> Void

    var body: some View {
        let isRunning = model.isRunning(profile)
        Button {
            onClose()
            model.open(profile)
        } label: {
            HStack(spacing: DS.Space.s + 2) {
                MonogramView(profile: profile, size: DS.Monogram.panel, isRunning: isRunning)
                    .frame(width: DS.Panel.leadingSlot)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.xs) {
                        Text(profile.name)
                            .font(DS.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        ClaudeCodePulseIcon(
                            pulse: model.claudeCodePulse[profile.id],
                            project: model.claudeCodeActiveProject(for: profile)
                        )
                        RestingIcon(profile: profile)
                    }
                    Text(subtitle(isRunning: isRunning))
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.numericText())
                }
                .layoutPriority(1)
                Spacer(minLength: DS.Space.s)
                if let number = model.shortcutNumber(for: profile) {
                    Text("⌘\(number)")
                        .font(DS.Typography.shortcut)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                // Room for the actions menu laid over the row.
                Color.clear
                    .frame(width: DS.Metrics.iconButton, height: DS.Metrics.iconButton)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(DSRowButtonStyle())
        .help(helpText(isRunning: isRunning))
        .contextMenu {
            actions(isRunning: isRunning)
        }
        .overlay(alignment: .trailing) {
            Menu {
                actions(isRunning: isRunning)
            } label: {
                Label("Diğer İşlemler", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(width: DS.Metrics.iconButton, height: DS.Metrics.iconButton)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("Diğer İşlemler")
            .padding(.trailing, DS.Panel.rowPaddingH)
        }
    }

    @ViewBuilder
    private func actions(isRunning: Bool) -> some View {
        Button("Claude Code'u Terminalde Aç") {
            onClose()
            model.openClaudeCode(profile)
        }
        Button("Claude Code'u Klasörde Aç…") {
            onClose()
            if let folder = ClaudeCodeFolderPicker.choose() {
                model.openClaudeCode(profile, in: folder)
            }
        }
        let recent = model.recentClaudeCodeFolders(for: profile)
        if !recent.isEmpty {
            Menu("Son Klasörler") {
                ForEach(recent, id: \.self) { folder in
                    Button(folder.lastPathComponent) {
                        onClose()
                        model.openClaudeCode(profile, in: folder)
                    }
                }
            }
        }
        Button("Claude Code Komutunu Kopyala") {
            SystemActions.copy(model.claudeCodeCommand(for: profile))
        }
        LimitMenu(profile: profile)
        Divider()
        Button("Hesap Sayfası") {
            router.showAccount(profile)
        }
        if isRunning {
            Divider()
            Button("Claude'dan Çık") {
                model.quit(profile)
            }
        }
    }

    /// The action, and the account's note when it has one.
    private func helpText(isRunning: Bool) -> String {
        let action = isRunning ? String(localized: "Öne getir") : String(localized: "Aç")
        guard let note = profile.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return action }
        return "\(action)\n\(note)"
    }

    private func subtitle(isRunning: Bool) -> String {
        let state = isRunning ? String(localized: "Açık") : String(localized: "Kapalı")
        let base = profile.isDefault
            ? String(localized: "\(state) · Claude uygulaması")
            : "\(state) · \(profile.accountClass.displayName)"
        if !isRunning, let last = model.lastUsedAt[profile.id] {
            return String(localized: "\(base) · \(Self.relative(last))")
        }
        if let progress = model.dailyLimitProgress(for: profile) {
            return String(localized: "\(base) · bugün \(progress.used)/\(progress.limit) dk")
        }
        let today = model.frontSeconds(for: profile.id, days: 1)
        guard today >= 60 else { return base }
        return String(localized: "\(base) · bugün \(FrontTimeLog.describe(seconds: today))")
    }
}

extension AccountCardView {
    /// "2 saat önce" style text for when a closed account was last in front.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "az önce") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// A one-line message with a close button, used for errors and warnings.
/// Kept for callers; the look comes from `DSNoticeRow`.
struct NoticeRow: View {
    let notice: AppModel.Notice
    var onDismiss: () -> Void

    var body: some View {
        DSNoticeRow(notice: notice, onDismiss: onDismiss)
    }
}
