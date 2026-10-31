import AppKit
import LanesCore
import SwiftUI

/// Ways other apps can open accounts and scenes: Shortcuts, Spotlight and
/// `lanes://` addresses for Raycast, Alfred or a plain link.
struct IntegrationsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Kestirmeler ve Spotlight") {
                Text("Kestirmeler uygulamasında \"Claude Hesabını Aç\" ve \"Lanes Sahnesini Aç\" eylemleri var. Spotlight'ta Lanes yazınca da çıkarlar. Siri'ye \"Lanes ile Claude hesabı aç\" diyebilirsin.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Kestirmeler'i Aç") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }

            Section("lanes:// adresleri") {
                Text("Raycast, Alfred, bir betik ya da bir bağlantı bu adreslerle Lanes'e iş verebilir. Adresler yalnız hesap ve sahne açar, pencere gösterir. Hiçbir şeyi silmez, kapatmaz ya da ayar değiştirmez, çünkü herhangi bir web sayfası da onları açabilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.library.profiles) { profile in
                    CommandRow(title: profile.name, command: .openAccount(profile.name))
                }
                ForEach(model.library.scenes) { scene in
                    CommandRow(title: String(localized: "Sahne: \(scene.name)"), command: .openScene(scene.name))
                }
                CommandRow(title: String(localized: "Menü çubuğu paneli"), command: .panel)
                CommandRow(title: String(localized: "Sağlık sayfası"), command: .show(page: "health"))
                Text("Hesap adı yerine listedeki sırası da yazılabilir: lanes://open?account=2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Komut satırı") {
                let example = "open \"\(LanesCommand.openAccount(model.library.profiles.first?.name ?? "Ana hesap").url.absoluteString)\""
                Text(example)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Terminalden ya da bir betikten macOS'un open komutuyla.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CommandRow: View {
    let title: String
    let command: LanesCommand
    @State private var copied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(command.url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(copied ? "Kopyalandı" : "Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command.url.absoluteString, forType: .string)
                copied = true
            }
        }
    }
}
