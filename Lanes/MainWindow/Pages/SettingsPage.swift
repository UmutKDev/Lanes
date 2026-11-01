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
                    Label {
                        Text(pane.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        SettingsPaneIcon(pane: pane)
                    }
                    .tag(pane)
                }
            }
            // A pane list like System Settings, not a second glass sidebar.
            .listStyle(.sidebar)
            .frame(
                minWidth: DS.Metrics.paneListMin,
                idealWidth: DS.Metrics.paneListIdeal,
                maxWidth: DS.Metrics.paneListMax
            )
            // One layout slot for the cross-fade: the outgoing and incoming
            // panes overlap in the ZStack instead of sitting side by side in
            // the HStack while the outgoing one fades out.
            ZStack {
                paneContent
                    .id(pane)
                    .transition(.opacity)
            }
            .frame(minWidth: DS.Metrics.paneContentMin, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(DS.Motion.standard, value: pane)
        }
    }

    private var paneBinding: Binding<SettingsPane?> {
        Binding(
            get: { pane },
            set: { if let pane = $0 { navigation.selectSettingsPane(pane) } }
        )
    }

    /// The pane the user saw last.
    private var pane: SettingsPane {
        navigation.settingsPane
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
        case .shortcuts:
            ShortcutsSettings()
        case .notifications:
            NotificationSettings()
        case .updates:
            UpdateSettings()
        }
    }
}

// MARK: - Pane list icon

/// System Settings-style icon: a white symbol on a small coloured badge.
private struct SettingsPaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(DS.Space.xs)
            .frame(width: DS.Monogram.small, height: DS.Monogram.small)
            .background(
                pane.badgeColor.gradient,
                in: RoundedRectangle(cornerRadius: DS.Radius.small - 1, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

private extension SettingsPane {
    var badgeColor: Color {
        switch self {
        case .general: return .gray
        case .menuBarAndDock: return .blue
        case .tabs: return .indigo
        case .shortcuts: return .purple
        case .notifications: return .red
        case .updates: return .green
        case .advanced: return .orange
        }
    }
}

// MARK: - Shared pane form

extension View {
    /// Every settings pane: the app's grouped Form, kept to a readable width
    /// and centred when the window is wide.
    func settingsForm() -> some View {
        modifier(SettingsFormModifier())
    }
}

private struct SettingsFormModifier: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .dsForm()
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self, of: { proxy in
                proxy.size.width
            }, action: { newWidth in
                width = newWidth
            })
    }

    private var sideMargin: CGFloat {
        max(DS.Space.page, (width - DS.Metrics.readableWidth) / 2)
    }
}

// MARK: - Launch at login

/// The launch-at-login switch, shared by Settings and Kurulum so both turn
/// the same login item on and off the same way. The caller shows `error`
/// where it fits its layout.
struct LoginItemToggle: View {
    let title: LocalizedStringKey
    @Binding var error: String?
    @State private var isOn = LoginItem.isEnabled
    @State private var isReverting = false

    var body: some View {
        Toggle(title, isOn: $isOn)
            .onChange(of: isOn) { _, enabled in
                // Putting the switch back after a failure fires this
                // again. Skip that pass, or it would call unregister
                // and hide or replace the error that explains why.
                if isReverting {
                    isReverting = false
                    return
                }
                do {
                    try LoginItem.setEnabled(enabled)
                    // register() succeeds but the item stays off
                    // until the user allows it in System Settings.
                    if enabled, LoginItem.requiresApproval {
                        error = String(localized: "Lanes'in oturum açıldığında başlaması için Sistem Ayarları > Genel > Giriş Öğeleri'nde izin ver.")
                    } else {
                        error = nil
                    }
                } catch let failure {
                    error = failure.localizedDescription
                    if isOn != LoginItem.isEnabled {
                        isReverting = true
                        isOn = LoginItem.isEnabled
                    }
                }
            }
    }
}

// MARK: - Panes

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loginItemError: String?
    @AppStorage(Preferences.Key.focusModeEnabled) private var focusMode = false
    @AppStorage(Preferences.Key.reopensLastAccounts) private var reopensLast = false
    @AppStorage(Preferences.Key.accountFrameEnabled) private var accountFrame = false
    @AppStorage(Preferences.Key.clipboardGuardEnabled) private var clipboardGuard = false

    var body: some View {
        Form {
            Section {
                LoginItemToggle(title: "Oturum açıldığında Lanes'i başlat", error: $loginItemError)
                Toggle("Lanes açılınca son açık hesapları yeniden aç", isOn: $reopensLast)
            } header: {
                Text("Lanes")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    if let loginItemError {
                        Label {
                            Text(loginItemError)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Palette.danger)
                        }
                    }
                }
                .animation(DS.Motion.standard, value: loginItemError)
            }
            Section {
                Toggle("Bir hesap öne gelince öteki hesapları gizle", isOn: $focusMode)
            } header: {
                Text("Odak")
            } footer: {
                Text("Gizlenen hesaplar kapanmaz. Sekmeli mod açıkken bu ayar kullanılmaz.")
            }
            Section {
                Toggle("Öndeki Claude penceresini hesabın renginde çerçevele", isOn: $accountFrame)
                Toggle("Başka hesapta kopyalananı yapıştırmadan önce uyar", isOn: Binding(
                    get: { clipboardGuard },
                    set: { isOn in
                        clipboardGuard = isOn
                        if isOn {
                            Task { _ = await Notifier.requestPermission() }
                        }
                    }
                ))
            } header: {
                Text("Hesapları karıştırma")
            } footer: {
                Text("Lanes panonun içeriğini okumaz, yalnız değişip değişmediğine bakar.")
            }
            .onChange(of: accountFrame) { model.updateAccountGuards() }
            .onChange(of: clipboardGuard) { model.updateAccountGuards() }
            Section {
                LabeledContent("Sürüm") {
                    Text(model.claude?.version ?? String(localized: "Bulunamadı"))
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if let claude = model.claude {
                    LabeledContent {
                        DSRevealButton(url: claude.url)
                    } label: {
                        DSPathText(url: claude.url)
                    }
                }
            } header: {
                Text("Claude")
            }
            Section {
                LabeledContent("claude:// bağlantılarını açan") {
                    Text(handlerName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } header: {
                Text("Bağlantılar")
            } footer: {
                Text("Bağlantıların hangi hesapla açılacağını Hesap Haritası'nda seçebilirsin.")
            }
        }
        .settingsForm()
    }

    private var handlerName: String {
        guard let handler = LinkHandlerRegistry.currentHandler() else { return String(localized: "Yok") }
        return handler.deletingPathExtension().lastPathComponent
    }
}

private struct MenuBarAndDockSettings: View {
    @AppStorage(Preferences.Key.showsDockIconWithWindow) private var showsDockIcon = true
    @AppStorage(Preferences.Key.showsRunningCountInMenuBar) private var showsRunningCount = true
    @AppStorage(Preferences.Key.showsFrontAccountInMenuBar) private var showsFrontAccount = true

    var body: some View {
        Form {
            Section {
                Toggle("Simge öndeki Claude'un hesabını göstersin", isOn: $showsFrontAccount)
                Toggle("Simgenin yanında açık hesap sayısını göster", isOn: $showsRunningCount)
            } header: {
                Text("Menü çubuğu")
            } footer: {
                Text("Sayı yalnız birden fazla hesap açıkken görünür.")
            }
            Section {
                Toggle("Ana pencere açıkken Dock'ta ve Cmd-Tab'da göster", isOn: $showsDockIcon)
            } header: {
                Text("Dock")
            } footer: {
                Text("Pencere kapanınca Lanes yalnız menü çubuğunda kalır.")
            }
        }
        .settingsForm()
    }
}

private struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Sürüm") {
                    Text(version)
                        .monospacedDigit()
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                if model.updater.isAvailable {
                    Toggle("Güncellemeleri kendiliğinden denetle", isOn: Binding(
                        get: { model.updater.automaticallyChecks },
                        set: { model.updater.setAutomaticallyChecks($0) }
                    ))
                    LabeledContent {
                        Button("Şimdi Denetle") {
                            model.updater.checkNow()
                        }
                        .fixedSize()
                    } label: {
                        Text("Güncellemeler")
                            .lineLimit(1)
                        lastCheckLine
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            } header: {
                Text("Lanes")
            } footer: {
                if model.updater.isAvailable {
                    Text("Lanes güncellemeleri GitHub'dan denetler ve yüklemeden önce imzayı doğrular. Claude Code kurulumu dışında Lanes'in yaptığı tek ağ isteği budur.")
                } else {
                    Text("Bu derleme kendini güncellemez; güncellemeler yalnız DMG sürümlerinde var.")
                }
            }
        }
        .settingsForm()
    }

    /// Always present, so the row keeps its height before the first check.
    private var lastCheckLine: Text {
        if let lastCheck = model.updater.lastCheck {
            return Text("Son denetim: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
        }
        return Text(verbatim: "—")
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
            Section {
                Toggle("Faz 0 denemelerini göster", isOn: $showsDeveloperPages)
            } header: {
                Text("Geliştirme")
            }
            Section {
                folderRow("Lanes", url: model.paths.root)
                folderRow("Hesap klasörleri", url: model.paths.root.appendingPathComponent("Profiles", isDirectory: true))
                folderRow("Klonlar", url: model.paths.clonesDirectory)
                folderRow("Tanılama", url: model.paths.diagnosticsDirectory)
            } header: {
                Text("Lanes klasörleri")
            }
            Section {
                LabeledContent {
                    Button("Tanılama Bilgisini Hazırla") {
                        diagnosticsFile = model.prepareDiagnostics()
                        diagnosticsPrepared = true
                    }
                    .fixedSize()
                } label: {
                    Text("Tanılama")
                        .lineLimit(1)
                    diagnosticsLine
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Tanılama")
            } footer: {
                Text("Sürümleri, hesapları ve klasör yollarını içerir. Hesap adları yerine numara, ev klasörü yerine ~ yazar; hesap klasörlerinin içi okunmaz.")
            }
            Section {
                DSStatusRow(.info, title: Text("Lanes'in dokunmadıkları")) {
                    Text("Lanes hiçbir hesabın giriş bilgisini, çerezini ya da Anahtar Zinciri kaydını okumaz ve saklamaz. Claude Code'un hesap dosyasından yalnız e-posta, ad ve kuruluş adını okur.")
                }
            }
        }
        .settingsForm()
    }

    /// The result of the last "prepare", in a slot that is always present.
    private var diagnosticsLine: Text {
        guard diagnosticsPrepared else { return Text(verbatim: "—") }
        return diagnosticsFile == nil
            ? Text("Panoya kopyalandı, dosyaya yazılamadı.")
            : Text("Panoya kopyalandı ve Tanılama klasörüne kaydedildi.")
    }

    /// Folder name with its path underneath, reveal button trailing.
    private func folderRow(_ title: LocalizedStringKey, url: URL) -> some View {
        LabeledContent {
            DSRevealButton(url: url)
        } label: {
            Text(title)
                .lineLimit(1)
            DSPathText(url: url)
        }
    }
}
