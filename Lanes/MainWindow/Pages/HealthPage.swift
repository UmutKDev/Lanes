import AppKit
import LanesCore
import SwiftUI

/// Whether everything Lanes depends on is in place, at a glance. It shows
/// nothing about sign-ins: knowing that would mean looking at login data.
struct HealthPage: View {
    @Environment(AppModel.self) private var model
    @State private var permission: AppleEvents.Permission?
    @State private var claudeCommand: String?
    @State private var lookedForClaudeCommand = false
    @State private var orphans: [URL] = []

    var body: some View {
        Form {
            Section("Claude") {
                if let claude = model.claude {
                    HealthRow(state: .good, title: String(localized: "Claude \(claude.version ?? "?")")) {
                        PathRow(url: claude.url)
                    }
                    Text("Claude kendini güncelleyip yeniden açılınca sürüm yeniden okunur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HealthRow(state: .problem, title: String(localized: "Claude bulunamadı")) {
                        Text("Claude'u Uygulamalar klasörüne kurduğunda Lanes onu kendiliğinden bulur.")
                    }
                }
                linkHandlerRow
                permissionRow
            }

            Section("Açık hesaplar") {
                let open = model.instances.filter { $0.profileID != nil }
                if open.isEmpty {
                    Text("Şu an açık hesap yok.")
                        .foregroundStyle(.secondary)
                }
                ForEach(open, id: \.pid) { instance in
                    if let id = instance.profileID, let profile = model.profile(withID: id) {
                        accountRow(profile)
                    }
                }
                let outside = model.instances.filter { $0.profileID == nil }
                if !outside.isEmpty {
                    HealthRow(state: .warning, title: String(localized: "Lanes'in tanımadığı \(outside.count) Claude açık")) {
                        Text("Lanes dışından, kendi klasörü olmadan açılmış bir Claude ya da başka bir kopya. Ana hesabın verilerini kullanıyor olabilir.")
                    }
                }
            }

            Section("Claude Code") {
                if !lookedForClaudeCommand {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("claude komutu aranıyor…")
                            .foregroundStyle(.secondary)
                    }
                } else if let claudeCommand {
                    HealthRow(state: .good, title: String(localized: "claude komutu kurulu")) {
                        Text(claudeCommand.abbreviatingHome)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } else {
                    HealthRow(state: .warning, title: String(localized: "claude komutu bulunamadı")) {
                        Text("\"Claude Code'u Terminalde Aç\" için Claude Code'un komut satırı sürümü gerekiyor.")
                    }
                }
            }

            Section("Lanes klasörleri") {
                if orphans.isEmpty {
                    HealthRow(state: .good, title: String(localized: "Sahipsiz hesap klasörü yok")) {
                        EmptyView()
                    }
                } else {
                    HealthRow(state: .warning, title: String(localized: "\(orphans.count) klasör hiçbir hesaba ait değil")) {
                        Text("Genellikle kaldırılmış hesaplardan kalır. İçlerinde o hesapların girişleri olabilir. Lanes bunları silmez, istersen Finder'dan kendin silebilirsin.")
                    }
                    ForEach(orphans, id: \.self) { folder in
                        HStack {
                            Text(folder.lastPathComponent)
                                .font(.caption.monospaced())
                            Spacer()
                            Button("Finder'da Göster") {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            model.refreshInstances()
            orphans = model.orphanProfileFolders()
            permission = await AppleEvents.reopenPermission(bundleIdentifier: ClaudeInstallation.bundleIdentifier)
            claudeCommand = await Self.findClaudeCommand()
            lookedForClaudeCommand = true
        }
    }

    @ViewBuilder
    private var linkHandlerRow: some View {
        let handler = LinkHandlerRegistry.currentHandler()
        if let handler, let claude = model.claude, handler.standardizedFileURL == claude.url.standardizedFileURL {
            HealthRow(state: .good, title: String(localized: "claude:// bağlantılarını Claude açıyor")) {
                Text("Girişler ve bağlantılar her zamanki gibi çalışır.")
            }
        } else if LinkHandlerRegistry.lanesIsHandler {
            HealthRow(state: .warning, title: String(localized: "claude:// bağlantılarını Lanes açıyor")) {
                Text("Lanes bağlantıları şimdilik yönlendirmiyor ve varsayılanı açılışta Claude'a geri verir.")
            }
        } else {
            HealthRow(state: .warning, title: String(localized: "claude:// bağlantılarını açan: \(handler?.deletingPathExtension().lastPathComponent ?? String(localized: "yok"))")) {
                Text("Girişlerin çalışması için bu bağlantıları Claude'un açması gerekir.")
            }
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch permission {
        case nil:
            HStack {
                ProgressView().controlSize(.small)
                Text("Otomasyon izni denetleniyor…")
                    .foregroundStyle(.secondary)
            }
        case .granted?:
            HealthRow(state: .good, title: String(localized: "Otomasyon izni verilmiş")) {
                Text("Lanes açık bir hesabın penceresini öne getirebilir.")
            }
        case .denied?:
            HealthRow(state: .problem, title: String(localized: "Otomasyon izni kapalı")) {
                Text("Lanes açık bir hesabı öne getirmekte zorlanabilir. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan Lanes altında Claude'u açabilirsin.")
            }
        case .notAskedYet?:
            HealthRow(state: .info, title: String(localized: "Otomasyon izni henüz sorulmadı")) {
                Text("macOS bunu Lanes bir pencereyi ilk kez öne getirirken sorabilir.")
            }
        case .claudeNotRunning?:
            HealthRow(state: .info, title: String(localized: "Otomasyon izni denetlenemedi")) {
                Text("Bu yalnız bir Claude açıkken denetlenebiliyor.")
            }
        case let .unknown(code)?:
            HealthRow(state: .info, title: String(localized: "Otomasyon izni bilinmiyor (\(code))")) {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ profile: Profile) -> some View {
        let folder = model.paths.effectiveDesktopDataDirectory(for: profile)
        if profile.isDefault {
            HealthRow(state: .good, title: profile.name) {
                Text("Claude'un kendi klasörü: \(folder.path.abbreviatingHome)")
            }
        } else if let result = model.separationResults[profile.id], !result.usesOwnFolder {
            HealthRow(state: .problem, title: profile.name) {
                Text("Açıldıktan sonra kendi klasörüne yazmadı. Ana hesabın verilerini kullanıyor olabilir.")
            }
        } else if model.separationResults[profile.id]?.usesOwnFolder == true {
            HealthRow(state: .good, title: profile.name) {
                Text("Kendi klasörünü kullanıyor: \(folder.path.abbreviatingHome)")
            }
        } else {
            HealthRow(state: .info, title: profile.name) {
                Text("Klasörü: \(folder.path.abbreviatingHome). Lanes bu oturumda açılışını görmedi, ayrılık denetlenmedi.")
            }
        }
    }

    /// Looks the command up the way Terminal would, through a login shell.
    private static func findClaudeCommand() async -> String? {
        let output = await ShellRunner.run("/bin/zsh", ["-lc", "command -v claude"])
        guard output.status == 0 else { return nil }
        let path = output.text.split(separator: "\n").last.map(String.init) ?? ""
        return path.hasPrefix("/") ? path : nil
    }
}

private struct HealthRow<Detail: View>: View {
    enum Status {
        case good, info, warning, problem
    }

    let state: Status
    let title: String
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(Text(accessibilityState))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var symbol: String {
        switch state {
        case .good: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .good: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .problem: return .red
        }
    }

    private var accessibilityState: String {
        switch state {
        case .good: return String(localized: "Yolunda")
        case .info: return String(localized: "Bilgi")
        case .warning: return String(localized: "Uyarı")
        case .problem: return String(localized: "Sorun")
        }
    }
}

private extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
