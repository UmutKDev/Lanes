import LanesCore
import SwiftUI

/// All of Lanes's settings live in the main window. ⌘, opens this page on the
/// pane the user saw last.
struct SettingsPage: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        HStack(spacing: 0) {
            List(selection: paneBinding) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol)
                        .tag(pane)
                }
            }
            // Like the Faz 0 checks: a pane list, not a second sidebar.
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(width: 210)
            Divider()
            paneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var paneBinding: Binding<SettingsPane?> {
        Binding(
            get: { navigation.settingsPane },
            set: { if let pane = $0 { navigation.selectSettingsPane(pane) } }
        )
    }

    @ViewBuilder
    private var paneContent: some View {
        switch navigation.settingsPane {
        case .general:
            GeneralSettings()
        case .menuBarAndDock:
            MenuBarAndDockSettings()
        case .advanced:
            AdvancedSettings()
        case .windowBadges:
            PlannedSettings(text: String(localized: "Her Claude penceresinin köşesinde hangi hesaba ait olduğunu gösteren renkli işaret."))
        case .shortcuts:
            PlannedSettings(text: String(localized: "Paneli her yerden açan genel kısayol ve hesaplara özel kısayollar."))
        case .notifications:
            PlannedSettings(text: String(localized: "Bir hesabın sınırı dolduğunda ya da yeniden açıldığında haber verme."))
        case .updates:
            PlannedSettings(text: String(localized: "Lanes güncellemeleri ve Claude güncellemesinden sonra yapılan kontroller."))
        case .license:
            PlannedSettings(text: String(localized: "Lisans ve deneme süresi."))
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Oturum açıldığında Lanes'i başlat", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchesAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Claude") {
                LabeledContent("Sürüm", value: model.claude?.version ?? String(localized: "Bulunamadı"))
                if let claude = model.claude {
                    PathRow(url: claude.url)
                }
            }
            Section("Bağlantılar") {
                LabeledContent("claude:// bağlantılarını açan", value: handlerName)
                Text("Lanes bağlantıları şimdilik yönlendirmiyor. Faz 0 denemeleri bittiğinde bağlantıların hangi hesapla açılacağını Hesap Haritası'ndan seçebileceksin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var handlerName: String {
        guard let handler = LinkHandlerRegistry.currentHandler() else { return String(localized: "Yok") }
        return handler.deletingPathExtension().lastPathComponent
    }
}

private struct MenuBarAndDockSettings: View {
    @AppStorage(Preferences.Key.showsDockIconWithWindow) private var showsDockIcon = true
    @AppStorage(Preferences.Key.showsRunningCountInMenuBar) private var showsRunningCount = true

    var body: some View {
        Form {
            Section("Menü çubuğu") {
                Toggle("Simgenin yanında açık hesap sayısını göster", isOn: $showsRunningCount)
                Text("Sayı yalnız birden fazla hesap açıkken görünür.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Dock") {
                Toggle("Ana pencere açıkken Dock'ta ve Cmd-Tab'da göster", isOn: $showsDockIcon)
                Text("Pencere kapanınca Lanes yalnız menü çubuğunda kalır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Lanes klasörleri") {
                LabeledContent("Profiller") {
                    PathRow(url: model.paths.root)
                }
                LabeledContent("Klonlar") {
                    PathRow(url: model.paths.clonesDirectory)
                }
                LabeledContent("Tanılama") {
                    PathRow(url: model.paths.diagnosticsDirectory)
                }
            }
            Section("Lanes'in dokunmadıkları") {
                Text("Lanes hiçbir hesabın giriş bilgisini, çerezini ya da Anahtar Zinciri kaydını okumaz, saklamaz, başka yere taşımaz. Giriş her zaman Claude'un kendi penceresinde ya da claude komutunda olur.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PlannedSettings: View {
    let text: String

    var body: some View {
        ContentUnavailableView {
            Label("Alfa sürümünde geliyor", systemImage: "hammer")
        } description: {
            Text(text)
        }
    }
}
