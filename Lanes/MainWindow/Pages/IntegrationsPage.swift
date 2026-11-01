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
                Text("Terminalde lanes claude yazınca Claude Code, bulunduğun klasörün hesabıyla başlar, Lanes'in açtığı terminallerin dışında da. Klasörün hesabı, klasörde ya da üstünde duran bir .lanes dosyasından ya da hesabın Claude Code sekmesindeki bağlı klasörlerden bulunur. Araç ~/.local/bin/lanes dosyasına kurulur; Claude Code'un kurulumu bu klasörü PATH'e ekler. Araç yalnız hesap adlarını ve klasör yollarını tutan bir listeyi okur.")
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
            } footer: {
                Text("Kestirmeler uygulamasında \"Claude Hesabını Aç\" ve \"Lanes Sahnesini Aç\" eylemleri var. Spotlight'ta Lanes yazınca da çıkarlar. Siri'ye \"Lanes ile Claude hesabı aç\" diyebilirsin.")
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
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Raycast, Alfred, bir betik ya da bir bağlantı bu adreslerle Lanes'e iş verebilir. Adresler yalnız hesap ve sahne açar, pencere gösterir. Hiçbir şeyi silmez, kapatmaz ya da ayar değiştirmez, çünkü herhangi bir web sayfası da onları açabilir.")
                    Text("Hesap adı yerine listedeki sırası da yazılabilir: lanes://open?account=2")
                }
            }

            Section {
                DSCodeBlock(text: cliExample)
            } header: {
                Text("Komut satırı")
            } footer: {
                Text("Terminalden ya da bir betikten macOS'un open komutuyla.")
            }
        }
        .libraryForm()
    }

    private var cliExample: String {
        "open \"\(LanesCommand.openAccount(model.library.profiles.first?.name ?? "İş").url.absoluteString)\""
    }

    private static let toolExamples: [(String, String)] = [
        ("lanes claude", String(localized: "Bu klasörün hesabıyla Claude Code")),
        ("lanes -a İş claude", String(localized: "Belirli bir hesapla")),
        ("lanes use İş", String(localized: "Bu klasörü İş hesabına bağla")),
        ("lanes which", String(localized: "Bu klasör hangi hesapta")),
    ]

    private var toolStateText: String {
        switch toolState {
        case .notInstalled: return String(localized: "Kurulu değil")
        case .installed: return String(localized: "Kurulu")
        case .outdated: return String(localized: "Eski sürüm kurulu")
        case .foreign: return String(localized: "~/.local/bin/lanes başka bir programa ait, Lanes ona dokunmuyor")
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
