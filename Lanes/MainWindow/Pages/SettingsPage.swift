import LanesCore
import SwiftUI

/// All of Lanes's settings live in the main window. ⌘, opens this page on the
/// pane the user saw last.
struct SettingsPage: View {
    @Environment(NavigationModel.self) private var navigation
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault

    var body: some View {
        HStack(spacing: 0) {
            List(selection: paneBinding) {
                ForEach(SettingsPane.visible(showingDeveloperPages: showsDeveloperPages)) { pane in
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
            get: { pane },
            set: { if let pane = $0 { navigation.selectSettingsPane(pane) } }
        )
    }

    /// The remembered pane, or General when the setting hides it.
    private var pane: SettingsPane {
        navigation.settingsPane.isBuilt || showsDeveloperPages ? navigation.settingsPane : .general
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
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
            UpdateSettings()
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

private struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Lanes") {
                LabeledContent("Sürüm", value: version)
                if model.updater.isAvailable {
                    Toggle("Güncellemeleri kendiliğinden denetle", isOn: Binding(
                        get: { model.updater.automaticallyChecks },
                        set: { model.updater.setAutomaticallyChecks($0) }
                    ))
                    HStack {
                        Button("Şimdi Denetle") {
                            model.updater.checkNow()
                        }
                        if let lastCheck = model.updater.lastCheck {
                            Text("Son denetim: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Lanes güncelleme olup olmadığını GitHub'daki sürüm listesinden öğrenir. Bu denetim Lanes'in yaptığı tek ağ isteği. Güncelleme yüklenmeden önce Lanes'in imzası denetlenir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Bu derleme kendini güncellemez. Güncellemeler yalnız DMG ile dağıtılan sürümlerde açık.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault

    var body: some View {
        Form {
            Section("Geliştirme") {
                Toggle("Faz 0 denemelerini ve yapım aşamasındaki sayfaları göster", isOn: $showsDeveloperPages)
                Text("Denemeleri yeniden yapmak için. Henüz çalışmayan sayfalar \"Alfa sürümünde geliyor\" yazar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
