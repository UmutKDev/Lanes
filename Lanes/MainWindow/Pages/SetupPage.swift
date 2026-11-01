import AppKit
import LanesCore
import SwiftUI
import UserNotifications

/// Kurulum: what Lanes needs, and a button for each missing piece. Nothing
/// is installed, downloaded or asked for until the user presses a button.
struct SetupPage: View {
    @Environment(AppModel.self) private var model
    @State private var requestingAutomation = false
    @State private var requestingNotifications = false
    @State private var loginItemError: String?
    @State private var copiedCommand = false

    private var setup: SetupStatus { model.setup }

    var body: some View {
        Form {
            introSection

            Section {
                claudeAppRow
            } header: {
                Text("Gerekli")
            }

            Section {
                claudeCodeRow
                automationRow
                accessibilityRow
            } header: {
                Text("Önerilen")
            }

            Section {
                notificationsRow
                LoginItemToggle(title: "Oturum açıldığında Lanes'i başlat", error: $loginItemError)
            } header: {
                Text("İsteğe bağlı")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Lanes açılınca menü çubuğunda bekler, bir pencere açmaz.")
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
        }
        .systemForm()
        .onAppear {
            UserDefaults.standard.set(true, forKey: Preferences.Key.setupShown)
        }
        .task {
            model.refreshInstances()
            await setup.refresh()
            // Permissions change in System Settings, outside Lanes: check
            // them every two seconds while the page is open, so a row turns
            // green by itself. The task ends when the page goes away.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                // Claude dragged into Applications shows up without a click.
                if model.claude == nil { model.refreshInstances() }
                await setup.refreshPermissions()
            }
        }
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: "checklist")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Lanes'in çalışması için gerekenler burada. Sen bir düğmeye basmadan Lanes hiçbir şey kurmaz, indirmez ya da izin istemez.")
                    .font(DS.Typography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, DS.Space.xs)
        }
    }

    // MARK: Claude

    @ViewBuilder
    private var claudeAppRow: some View {
        if let claude = model.claude {
            DSStatusRow(.ok, title: Text("Claude uygulaması")) {
                Text("Sürüm \(claude.version ?? "?") kurulu.")
                    .lineLimit(1)
                    .truncationMode(.tail)
            } accessory: {
                DSRevealButton(url: claude.url)
            }
        } else {
            DSStatusRow(.error, title: Text("Claude uygulaması")) {
                Text("Hesapları açmak için gerekiyor. İndirip Uygulamalar klasörüne taşıdığında Lanes onu kendiliğinden bulur.")
            } accessory: {
                HStack(spacing: DS.Space.s) {
                    DSIconButton("Yeniden Denetle", systemImage: "arrow.clockwise") {
                        // Looks for Claude again when it is missing.
                        model.refreshInstances()
                    }
                    Button("Claude'u İndir") {
                        NSWorkspace.shared.open(SetupLinks.claudeDownload)
                    }
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Claude Code

    private var claudeCodeRow: some View {
        let installer = setup.installer
        let failed: Bool = {
            if case .failed = installer.phase { return true }
            return false
        }()
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            claudeCodeStatus
            if installer.isWorking || (failed && !installer.log.isEmpty) {
                InstallLogView(lines: installer.log)
                    .padding(.leading, SetupMetrics.titleInset)
                    .transition(.opacity)
            }
            if failed, setup.claudeCommand == nil {
                terminalFallback
                    .padding(.leading, SetupMetrics.titleInset)
                    .transition(.opacity)
            }
        }
        .animation(DS.Motion.standard, value: installer.phase)
    }

    @ViewBuilder
    private var claudeCodeStatus: some View {
        let installer = setup.installer
        let title = Text("Claude Code komut satırı aracı")
        if installer.isWorking {
            DSStatusRow(.loading, title: title) {
                Text(workingText(installer.phase))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } accessory: {
                Button("Durdur") {
                    installer.stop()
                }
                .disabled(!installer.canStop)
                .fixedSize()
            }
        } else if let path = setup.claudeCommand {
            DSStatusRow(.ok, title: title) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(installedText(version: setup.claudeCommandVersion, justInstalled: installer.phase == .succeeded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    DSPathText(url: URL(fileURLWithPath: path))
                }
            }
        } else if !setup.hasLookedForClaudeCommand {
            DSStatusRow(.loading, title: title) {
                Text("Aranıyor…")
            }
        } else if case let .failed(message) = installer.phase {
            DSStatusRow(.error, title: title) {
                Text(message)
            } accessory: {
                installButton(String(localized: "Yeniden Dene"))
            }
        } else {
            DSStatusRow(.warning, title: title) {
                Text("\"Claude Code'u Terminalde Aç\", oturumlar ve kaldığın yerden sürdürme için gerekiyor. Kur'a basınca Lanes resmî kurulum betiğini claude.ai'dan indirip çalıştırır.")
            } accessory: {
                installButton(String(localized: "Kur"))
            }
        }
    }

    private func installButton(_ title: String) -> some View {
        Button(title) {
            Task { await setup.installClaudeCode() }
        }
        .fixedSize()
    }

    /// The official command, for Terminal or for pasting by hand, when the
    /// install inside Lanes did not work.
    private var terminalFallback: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Terminalde kurmayı deneyebilirsin. Terminal şu komutu çalıştırır:")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DSCodeBlock(text: ClaudeCodeInstallScript.terminalCommand, showsCopyButton: false)
            HStack(spacing: DS.Space.s) {
                Button("Terminalde Kur") {
                    do {
                        try SystemActions.openClaudeCodeInstallInTerminal(paths: model.paths)
                    } catch {
                        model.notice = AppModel.Notice(kind: .error, message: String(localized: "Terminal açılamadı: \(error.localizedDescription)"))
                    }
                }
                .fixedSize()
                Button {
                    SystemActions.copy(ClaudeCodeInstallScript.terminalCommand)
                    copiedCommand = true
                } label: {
                    // Same label either way, so the button keeps its width.
                    Label("Komutu Kopyala", systemImage: copiedCommand ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .fixedSize()
            }
        }
        .task(id: copiedCommand) {
            guard copiedCommand else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copiedCommand = false
        }
    }

    private func workingText(_ phase: ClaudeCodeInstaller.Phase) -> String {
        switch phase {
        case .downloading: return String(localized: "Kurulum betiği indiriliyor…")
        case .running: return String(localized: "Kuruluyor…")
        case .verifying: return String(localized: "Kurulum denetleniyor…")
        case .idle, .succeeded, .failed: return ""
        }
    }

    private func installedText(version: String?, justInstalled: Bool) -> String {
        switch (version, justInstalled) {
        case let (version?, true): return String(localized: "Kuruldu: \(version)")
        case let (version?, false): return version
        case (nil, true): return String(localized: "Kuruldu.")
        case (nil, false): return String(localized: "Kurulu.")
        }
    }

    // MARK: Permissions

    @ViewBuilder
    private var automationRow: some View {
        let title = Text("Otomasyon izni")
        let purpose = String(localized: "Lanes'in açık bir hesabın penceresini öne getirebilmesi için.")
        switch setup.automation {
        case nil:
            DSStatusRow(.loading, title: title) {
                Text("Denetleniyor…")
            }
        case .granted?:
            DSStatusRow(.ok, title: title) {
                Text("Verilmiş. Lanes açık bir hesabın penceresini öne getirebilir.")
            }
        case .denied?:
            DSStatusRow(.error, title: title) {
                Text("Kapalı. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan Lanes altında Claude'u açabilirsin.")
            } accessory: {
                Button("Sistem Ayarları'nı Aç") {
                    NSWorkspace.shared.open(SetupLinks.automationSettings)
                }
                .fixedSize()
            }
        case .notAskedYet?:
            DSStatusRow(.warning, title: title) {
                automationDetail(purpose + " " + String(localized: "macOS bir kez sorar."))
            } accessory: {
                requestAutomationButton
            }
        case .claudeNotRunning?:
            DSStatusRow(.info, title: title) {
                automationDetail(purpose)
            } accessory: {
                requestAutomationButton
            }
        case let .unknown(code)?:
            DSStatusRow(.info, title: title) {
                automationDetail(String(localized: "Durumu okunamadı (\(code))."))
            } accessory: {
                requestAutomationButton
            }
        }
    }

    /// macOS can only ask about a running Claude; with none open, the row
    /// says so instead of offering a button that does nothing.
    private func automationDetail(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(text)
            if model.instances.isEmpty {
                Text("Bir hesap açıkken sorulabilir.")
            }
        }
    }

    private var requestAutomationButton: some View {
        Button("İzin İste") {
            requestingAutomation = true
            Task {
                await setup.requestAutomation()
                requestingAutomation = false
            }
        }
        .disabled(model.instances.isEmpty || requestingAutomation)
        .fixedSize()
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        let title = Text("Erişilebilirlik izni")
        if setup.accessibilityGranted {
            DSStatusRow(.ok, title: title) {
                Text("Verilmiş. Sekme çubuğu ve sahne pencerelerinin yerleşimi çalışabilir.")
            }
        } else {
            DSStatusRow(.warning, title: title) {
                Text("Sekme çubuğu ve sahne pencerelerinin yerleşimi için gerekiyor. Sistem Ayarları'nda Lanes'i açınca bu satır kendiliğinden güncellenir.")
            } accessory: {
                Button("İzin Ver") {
                    AccessibilityPermission.request()
                    AccessibilityPermission.openSettings()
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var notificationsRow: some View {
        let title = Text("Bildirimler")
        switch setup.notifications {
        case nil:
            DSStatusRow(.loading, title: title) {
                Text("Denetleniyor…")
            }
        case .notDetermined?:
            DSStatusRow(.info, title: title) {
                Text("Ayarlar > Bildirimler'de açtığın olaylar için. macOS bir kez sorar.")
            } accessory: {
                Button("İzin İste") {
                    requestingNotifications = true
                    Task {
                        await setup.requestNotifications()
                        requestingNotifications = false
                    }
                }
                .disabled(requestingNotifications)
                .fixedSize()
            }
        case .denied?:
            DSStatusRow(.warning, title: title) {
                Text("Kapalı. Sistem Ayarları > Bildirimler'den Lanes'e izin verebilirsin.")
            } accessory: {
                Button("Sistem Ayarları'nı Aç") {
                    NSWorkspace.shared.open(SetupLinks.notificationSettings)
                }
                .fixedSize()
            }
        case .authorized?, .provisional?:
            DSStatusRow(.ok, title: title) {
                Text("Verilmiş. Hangi olaylarda bildirim geleceğini Ayarlar > Bildirimler'den seçebilirsin.")
            }
        default:
            DSStatusRow(.info, title: title) {
                Text("Durumu okunamadı.")
            }
        }
    }
}

private enum SetupLinks {
    static let claudeDownload = URL(string: "https://claude.ai/download")!
    static let automationSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    static let notificationSettings = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
}

private enum SetupMetrics {
    /// Where a row's title starts: past the status icon and its gap.
    static let titleInset: CGFloat = DS.Metrics.statusIcon + DS.Space.m
    /// About eight lines of the installer's output.
    static let logHeight: CGFloat = 136
}

/// The installer's output: a fixed-height box that keeps the newest line in
/// view, so the row never grows while the script prints.
private struct InstallLogView: View {
    let lines: [ClaudeCodeInstaller.LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        Text(verbatim: line.text)
                            .font(DS.Typography.path)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .textSelection(.enabled)
                .padding(DS.Space.s)
            }
            .frame(height: SetupMetrics.logHeight)
            .background(DS.Palette.codeFill, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            .accessibilityLabel(Text("Kurulum çıktısı"))
            .onAppear {
                scrollToEnd(proxy)
            }
            .onChange(of: lines.last?.id) { _, _ in
                scrollToEnd(proxy)
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = lines.last?.id else { return }
        proxy.scrollTo(last, anchor: .bottom)
    }
}
