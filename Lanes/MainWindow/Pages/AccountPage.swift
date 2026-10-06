import LanesCore
import SwiftUI

/// One account: a header with its identity and state, then tabs.
struct AccountPage: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    let profileID: ProfileID

    var body: some View {
        if let profile = model.profile(withID: profileID) {
            VStack(spacing: 0) {
                AccountHeader(profile: profile)
                Picker("Bölüm", selection: tabBinding) {
                    ForEach(AccountTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                Divider()
                tabContent(for: profile)
            }
        } else {
            ContentUnavailableView("Hesap bulunamadı", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private var tabBinding: Binding<AccountTab> {
        Binding(get: { navigation.accountTab }, set: { navigation.accountTab = $0 })
    }

    @ViewBuilder
    private func tabContent(for profile: Profile) -> some View {
        switch navigation.accountTab {
        case .general:
            AccountGeneralTab(profile: profile)
        case .desktop:
            AccountDesktopTab(profile: profile)
        case .claudeCode:
            AccountClaudeCodeTab(profile: profile)
        case .identity:
            AccountPlannedTab(text: String(localized: "Hesabın e-postası, planı ve kuruluşu Claude'un kendi ekranlarından okunarak burada görünecek. Lanes giriş bilgilerini okumaz."))
        case .security:
            AccountPlannedTab(text: String(localized: "Bu hesabın hangi klasörlerde ve hangi bağlantılarla açılabileceğini sınırlayan kurallar."))
        case .storage:
            AccountPlannedTab(text: String(localized: "Bu hesabın klasörlerinin boyutu, önbellek temizliği ve yedekleme."))
        }
    }
}

private struct AccountHeader: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let isRunning = model.isRunning(profile)
        HStack(spacing: 16) {
            MonogramView(profile: profile, size: 56, isRunning: isRunning)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Text(isRunning ? "Açık" : "Kapalı")
                    Text(verbatim: "·")
                    Text(profile.accountClass.displayName)
                    Text(verbatim: "·")
                    Text(profile.mode.displayName)
                    if let number = model.shortcutNumber(for: profile) {
                        Text(verbatim: "·")
                        Text(verbatim: "⌘\(number)")
                            .monospacedDigit()
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isRunning {
                Button("Claude'dan Çık") {
                    model.quit(profile)
                }
            }
            Button(isRunning ? "Öne Getir" : "Aç") {
                model.open(profile)
            }
            .buttonStyle(.borderedProminent)
            .tint(profile.color.swatch)
        }
        .padding(24)
    }
}

private struct AccountGeneralTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("Ad", text: $name)
                    .onSubmit(commitName)
                LabeledContent("Renk") {
                    ColorChooser(selection: binding(\.color))
                }
                TextField("Harf", text: monogramBinding)
                    .frame(maxWidth: 160)
                Picker("Hesap türü", selection: binding(\.accountClass)) {
                    ForEach(AccountClass.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
            }
            Section {
                Picker("Açılış biçimi", selection: binding(\.mode)) {
                    ForEach(modeChoices, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(profile.isDefault || modeChoices.count < 2)
                Text(modeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if profile.isDefault {
                Section {
                    Text("Bu hesap Claude'un kendi klasörlerini kullanıyor. Lanes'i kaldırsan bile bu hesap olduğu gibi kalır.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { _, newValue in
            name = newValue
        }
        .onDisappear(perform: commitName)
    }

    /// Only Standart works today: Lanes makes no clones for real accounts
    /// until Faz 0 checks 3 and 5 settle how. An account saved earlier with
    /// another mode opens with Claude itself and can be switched back here.
    private var modeChoices: [ProfileMode] {
        profile.mode == .standard ? [.standard] : [.standard, profile.mode]
    }

    private var modeCaption: String {
        if profile.isDefault {
            return String(localized: "Ana hesap her zaman Claude'un kendisiyle açılır.")
        }
        if profile.mode == .standard {
            return String(localized: "\(ProfileMode.standard.explanation) Her hesabın kendi simgesiyle açılacağı Klon biçimi, Faz 0 denemelerinden sonra gelecek.")
        }
        return String(localized: "\(profile.mode.displayName) biçimi henüz hazır değil. Bu hesap şimdilik Claude'un kendisiyle, kendi klasörüyle açılıyor. İstersen Standart'a geçir.")
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.name, var updated = model.profile(withID: profile.id) else { return }
        let oldDefaultMonogram = Profile.defaultMonogram(for: updated.name)
        updated.name = trimmed
        if updated.monogram == oldDefaultMonogram {
            updated.monogram = Profile.defaultMonogram(for: trimmed)
        }
        model.updateProfile(updated)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Profile, Value>) -> Binding<Value> {
        Binding(
            get: { (model.profile(withID: profile.id) ?? profile)[keyPath: keyPath] },
            set: { newValue in
                guard var updated = model.profile(withID: profile.id) else { return }
                updated[keyPath: keyPath] = newValue
                model.updateProfile(updated)
            }
        )
    }

    private var monogramBinding: Binding<String> {
        Binding(
            get: { (model.profile(withID: profile.id) ?? profile).monogram },
            set: { newValue in
                guard var updated = model.profile(withID: profile.id) else { return }
                let trimmed = String(newValue.trimmingCharacters(in: .whitespaces).prefix(2))
                updated.monogram = trimmed.isEmpty ? Profile.defaultMonogram(for: updated.name) : trimmed
                model.updateProfile(updated)
            }
        )
    }
}

private struct AccountDesktopTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let dataDirectory = model.paths.effectiveDesktopDataDirectory(for: profile)
        Form {
            Section("Claude Desktop") {
                LabeledContent("Durum") {
                    if let instance = model.instance(for: profile) {
                        Text("Açık, işlem \(String(instance.pid))")
                    } else {
                        Text("Kapalı")
                    }
                }
                LabeledContent("Uygulama") {
                    Text(applicationPath)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Section("Veri klasörü") {
                PathRow(url: dataDirectory)
                if !profile.isDefault {
                    LabeledContent("Açılış bayrağı") {
                        Text(verbatim: "--user-data-dir")
                            .monospaced()
                    }
                }
                Text(profile.isDefault
                     ? String(localized: "Ana hesap Claude'un kendi klasörünü kullanır.")
                     : String(localized: "Oturumların, ayarların ve önbellek bu klasörde durur. Başka hiçbir hesap bu klasörü görmez."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var applicationPath: String {
        if profile.mode != .standard, let clone = model.cloneURLIfPresent(for: profile) {
            return clone.path
        }
        return model.claude?.url.path ?? String(localized: "Claude bulunamadı")
    }
}

private struct AccountClaudeCodeTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let command = model.claudeCodeCommand(for: profile)
        Form {
            Section("Yerel Claude Code") {
                PathRow(url: model.paths.effectiveClaudeCodeConfigDirectory(for: profile))
                Text(profile.isDefault
                     ? String(localized: "Ana hesap Claude Code'un kendi klasörünü (~/.claude) kullanır.")
                     : String(localized: "Bu hesabın Claude Code oturumları ve ayarları bu klasörde durur. Diğer hesaplar aynı anda kendi klasörleriyle çalışabilir."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Komut") {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Kopyala") {
                        SystemActions.copy(command)
                    }
                    Button("Terminalde Aç") {
                        model.openClaudeCode(profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountPlannedTab: View {
    let text: String

    var body: some View {
        ContentUnavailableView {
            Label("Alfa sürümünde geliyor", systemImage: "hammer")
        } description: {
            Text(text)
        }
    }
}

/// A folder path with a button that shows it in Finder.
struct PathRow: View {
    let url: URL

    var body: some View {
        HStack {
            Text(abbreviated)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Finder'da Göster") {
                SystemActions.reveal(url)
            }
            .controlSize(.small)
        }
    }

    private var abbreviated: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
