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
        case .tabs:
            TabSettings()
        case .windowBadges:
            WindowBadgeSettings()
        case .shortcuts:
            ShortcutsSettings()
        case .notifications:
            NotificationSettings()
        case .updates:
            UpdateSettings()
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchesAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @AppStorage(Preferences.Key.focusModeEnabled) private var focusMode = false
    @AppStorage(Preferences.Key.reopensLastAccounts) private var reopensLast = false

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
                Toggle("Lanes açılınca son açık hesapları yeniden aç", isOn: $reopensLast)
                Text("Örneğin Mac yeniden başladıktan sonra, Lanes kapanırken açık olan hesaplar sırayla açılır. Lanes açılınca açılan sahneler de ayrıca açılır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Odak") {
                Toggle("Bir hesap öne gelince öteki hesapları gizle", isOn: $focusMode)
                Text("Ekranda yalnız öndeki hesabın Claude'u kalır, ötekiler Cmd-H ile gizlenir gibi gizlenir. Kapanmazlar; Dock'tan, Cmd-Tab'dan ya da Lanes'ten açınca geri gelirler. Sekmeli mod açıkken bu ayar kullanılmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Claude") {
                LabeledContent("Sürüm", value: model.claude?.version ?? String(localized: "Bulunamadı"))
                if let claude = model.claude {
                    PathRow(url: claude.url)
                }
            }
            Section("Bağlantılar") {
                LabeledContent("claude:// bağlantılarını açan", value: handlerName)
                Text("Bağlantıların hangi hesapla açılacağını Hesap Haritası'ndan seçebilirsin. Yönlendirme kapalıyken bağlantıları her zaman Claude açar.")
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
    @State private var diagnosticsPrepared = false
    @State private var diagnosticsFile: URL?
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault

    var body: some View {
        Form {
            Section("Geliştirme") {
                Toggle("Faz 0 denemelerini göster", isOn: $showsDeveloperPages)
                Text("Denemeleri yeniden yapmak için.")
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
            Section("Tanılama") {
                HStack {
                    Button("Tanılama Bilgisini Hazırla") {
                        diagnosticsFile = model.prepareDiagnostics()
                        diagnosticsPrepared = true
                    }
                    if diagnosticsPrepared {
                        Text(diagnosticsFile == nil ? "Panoya kopyalandı, dosyaya yazılamadı." : "Panoya kopyalandı ve Tanılama klasörüne kaydedildi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Lanes'in ve Claude'un sürümünü, hesapları ve çalışan her Claude'un kullandığı klasörü içerir. Hesap adları yerine numaralar, ev klasörün yerine ~ yazar. Hesap klasörlerinin içi okunmaz. Bir sorunu bildirirken bu metni yapıştırabilirsin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
