import AppKit
import LanesCore
import SwiftUI

/// Ways other apps can open accounts and scenes: Shortcuts, Spotlight and
/// `lanes://` addresses for Raycast, Alfred or a plain link.
struct IntegrationsPage: View {
    @Environment(AppModel.self) private var model
    @State private var toolState = CommandLineTool.state()
    @State private var toolError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Durum") {
                    Text(toolStateText)
                        .foregroundStyle(toolState == .installed ? Color.secondary : DS.Palette.warning)
                }
                HStack(spacing: DS.Space.s) {
                    switch toolState {
                    case .notInstalled:
                        Button("Kur") { run(CommandLineTool.install) }
                    case .outdated:
                        Button("Güncelle") { run(CommandLineTool.install) }
                        Button("Kaldır") { run(CommandLineTool.uninstall) }
                    case .installed:
                        Button("Kaldır") { run(CommandLineTool.uninstall) }
                    case .foreign:
                        EmptyView()
                    }
                }
                .fixedSize()
                if let toolError {
                    Text(toolError)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.warning)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(Self.toolExamples.indices, id: \.self) { index in
                        let (command, meaning) = Self.toolExamples[index]
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            Text(verbatim: command)
                                .font(DS.Typography.code)
                                .textSelection(.enabled)
                            Text(meaning)
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("lanes komut satırı aracı")
            } footer: {
                Text("Terminal \"lanes\" komutunu bulamazsa ~/.local/bin klasörünü PATH'e ekle.")
            }

            Section {
                Toggle("Bitti Haberi", isOn: Binding(
                    get: { model.doneNoticesEnabled },
                    set: { model.setDoneNotices(enabled: $0) }
                ))
                if model.doneNoticesEnabled {
                    Toggle("Claude cevabını bitirince", isOn: kindBinding(.done))
                    Toggle("Claude onay isteyince", isOn: kindBinding(.waiting))
                    Toggle("Terminal öndeyken de bildir", isOn: Binding(
                        get: { model.doneNoticesWhileTerminalInFront },
                        set: { model.doneNoticesWhileTerminalInFront = $0 }
                    ))
                }
            } header: {
                Text("Claude Code bildirimleri")
            } footer: {
                Text("Yalnız Lanes'in başlattığı oturumlar bildirim gönderir. Bu ayarı açmadan önce başlamış oturumları yeniden başlat.")
            }

            Section {
                Button("Kestirmeler'i Aç") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                .fixedSize()
            } header: {
                Text("Kestirmeler ve Spotlight")
            }

            Section {
                ForEach(model.library.profiles) { profile in
                    CommandRow(title: profile.name, command: .openAccount(profile.name))
                }
                ForEach(model.library.scenes) { scene in
                    CommandRow(title: String(localized: "Sahne: \(scene.name)"), command: .openScene(scene.name))
                }
                CommandRow(title: String(localized: "Menü çubuğu paneli"), command: .panel)
                CommandRow(title: String(localized: "Sağlık sayfası"), command: .show(page: "health"))
            } header: {
                Text("lanes:// adresleri")
            } footer: {
                Text("Bu adresler yalnız hesap, sahne ve pencere açar; hiçbir şeyi silmez ya da değiştirmez.")
                    .help("Hesap adı yerine sıra numarası da yazılabilir: lanes://open?account=2")
            }

            Section {
                DSCodeBlock(text: cliExample)
            } header: {
                Text("Komut satırı")
            }
        }
        .libraryForm()
    }

    private func kindBinding(_ kind: ClaudeCodeHooks.Kind) -> Binding<Bool> {
        Binding(
            get: { model.doneNoticeKinds.contains(kind) },
            set: { model.setDoneNoticeKind(kind, enabled: $0) }
        )
    }

    private var cliExample: String {
        "open \"\(LanesCommand.openAccount(model.library.profiles.first?.name ?? String(localized: "İş")).url.absoluteString)\""
    }

    private static var toolExamples: [(String, String)] {
        let work = String(localized: "İş")
        return [
        ("lanes claude", String(localized: "Bu klasörün hesabıyla Claude Code")),
        ("lanes -a \(work) claude", String(localized: "Belirli bir hesapla")),
        ("lanes use \(work)", String(localized: "Bu klasörü İş hesabına bağla")),
        ("lanes which", String(localized: "Bu klasör hangi hesapta")),
        ]
    }

    private var toolStateText: String {
        switch toolState {
        case .notInstalled: return String(localized: "Kurulu değil")
        case .installed: return String(localized: "Kurulu")
        case .outdated: return String(localized: "Eski sürüm kurulu")
        case .foreign: return String(localized: "~/.local/bin/lanes başka bir programa ait")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            toolError = nil
        } catch {
            toolError = error.localizedDescription
        }
        toolState = CommandLineTool.state()
    }
}

/// A title over the address in a code block; the block's copy button
/// shows a checkmark for a moment and keeps its size.
private struct CommandRow: View {
    let title: String
    let command: LanesCommand

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .font(DS.Typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            DSCodeBlock(text: command.url.absoluteString)
        }
        .padding(.vertical, DS.Space.xxs)
    }
}
