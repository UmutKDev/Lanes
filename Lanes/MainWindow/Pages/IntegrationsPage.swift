import AppKit
import LanesCore
import SwiftUI

/// Ways other apps can open accounts and scenes: Shortcuts, Spotlight and
/// `lanes://` addresses for Raycast, Alfred or a plain link.
struct IntegrationsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
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
