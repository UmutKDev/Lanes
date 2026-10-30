import LanesCore
import SwiftUI

/// The panel that opens from the menu bar: every account at a glance, one
/// click to open it, and the way into the main window.
struct CommandPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault
    var onClose: () -> Void

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
        return count == 0
            ? String(localized: "Açık hesap yok")
            : String(localized: "\(count) hesap açık")
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
                ForEach(model.library.profiles) { profile in
                    AccountCardView(profile: profile, onClose: onClose)
                }
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
            return String(localized: "\(state) · Varsayılan")
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
