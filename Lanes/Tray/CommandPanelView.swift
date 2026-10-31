import LanesCore
import SwiftUI

/// The panel that opens from the menu bar: every account at a glance, one
/// click to open it, and the way into the main window.
struct CommandPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    var onClose: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 12)
            if let notice = model.notice {
                NoticeRow(notice: notice) { model.notice = nil }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
            accounts
                .padding(8)
            if !model.library.scenes.isEmpty {
                Divider().padding(.horizontal, 12)
                scenes
                    .padding(8)
            }
            Divider().padding(.horizontal, 12)
            footer
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(PanelBackground(cornerRadius: 16))
        .onExitCommand(perform: onClose)
        .background(shortcuts)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lanes")
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                router.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Ayarlar")
            Button {
                router.showMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.borderless)
            .help("Lanes'i aç")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    @ViewBuilder
    private var accounts: some View {
        if model.library.profiles.isEmpty {
            Text("Henüz hesap yok.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            VStack(spacing: 2) {
                if model.library.profiles.count >= 4 {
                    TextField("Hesap ara", text: $query, prompt: Text("Hesap ara"))
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                        .onSubmit {
                            guard let first = matchingProfiles.first else { return }
                            onClose()
                            model.open(first)
                        }
                }
                ForEach(matchingProfiles) { profile in
                    AccountCardView(profile: profile, onClose: onClose)
                }
                if matchingProfiles.isEmpty {
                    Text("\"\(query)\" ile eşleşen hesap yok.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    /// Accounts whose name, email or note holds the search text, ignoring
    /// case and accents with Turkish rules.
    private var matchingProfiles: [Profile] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return model.library.profiles }
        let locale = Locale(identifier: "tr_TR")
        return model.library.profiles.filter { profile in
            [profile.name, profile.email ?? "", profile.note ?? ""].contains {
                $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
            }
        }
    }

    /// Saved groups of accounts, one click opens them all.
    private var scenes: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sahneler")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            ForEach(model.library.scenes) { scene in
                Button {
                    onClose()
                    model.open(scene)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Destination.scenes.symbol)
                            .frame(width: 20)
                        Text(scene.name)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        HStack(spacing: -4) {
                            ForEach(scene.profiles(in: model.library)) { profile in
                                MonogramView(profile: profile, size: 16)
                            }
                        }
                        if let shortcut = model.shortcuts.shortcut(for: .scene(scene.id)) {
                            Text(shortcut.description)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sahnedeki hesapları aç")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                router.showAddProfile()
            } label: {
                Label("Hesap Ekle", systemImage: "plus")
            }
            Spacer()
            Menu {
                if showsDeveloperPages {
                    Button("Faz 0 Doğrulama") {
                        router.showMainWindow(.validation)
                    }
                    Divider()
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
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Invisible buttons that give ⌘1 to ⌘9 to the first nine accounts.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(model.library.profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
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

/// One account in the panel.
struct AccountCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    let profile: Profile
    var onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        let isRunning = model.isRunning(profile)
        HStack(spacing: 10) {
            MonogramView(profile: profile, size: 32, isRunning: isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: profile.accountClass.symbol)
                    Text(subtitle(isRunning: isRunning))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let number = model.shortcutNumber(for: profile) {
                Text("⌘\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Menu {
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
                Divider()
                Button("Hesap Ayarları…") {
                    router.showAccount(profile)
                }
                if isRunning {
                    Divider()
                    Button("Claude'dan Çık") {
                        model.quit(profile)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovered ? 1 : 0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onClose()
            model.open(profile)
        }
        .help(isRunning ? "Öne getir" : "Aç")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func subtitle(isRunning: Bool) -> String {
        let state = isRunning ? String(localized: "Açık") : String(localized: "Kapalı")
        if profile.isDefault {
            return String(localized: "\(state) · Claude uygulaması")
        }
        return "\(state) · \(profile.accountClass.displayName)"
    }
}

/// A one-line message with a close button, used for errors and warnings.
struct NoticeRow: View {
    let notice: AppModel.Notice
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(notice.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Kapat")
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch notice.kind {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}
