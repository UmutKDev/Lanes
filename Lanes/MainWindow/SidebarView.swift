import LanesCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @State private var profilePendingRemoval: Profile?
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault

    var body: some View {
        List(selection: selection) {
            Section {
                rows([.overview, .sessions, .usage])
            }

            Section {
                ForEach(model.library.profiles) { profile in
                    NavigationLink(value: Destination.account(profile.id)) {
                        SidebarAccountRow(profile: profile)
                    }
                    .contextMenu {
                        Button(model.isRunning(profile) ? "Öne Getir" : "Aç") {
                            model.open(profile)
                        }
                        Button("Claude Code'u Terminalde Aç") {
                            model.openClaudeCode(profile)
                        }
                        Divider()
                        Button("Hesabı Kaldır…", role: .destructive) {
                            profilePendingRemoval = profile
                        }
                        .disabled(profile.isDefault)
                    }
                }
                .onMove { source, destination in
                    model.moveProfiles(fromOffsets: source, toOffset: destination)
                }
            } header: {
                HStack {
                    Text("Hesaplar")
                    Spacer()
                    Button {
                        navigation.isAddingProfile = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Hesap ekle")
                }
            }

            if showsDeveloperPages {
                Section("Yönlendirme") {
                    rows([.accountMap, .links])
                }

                Section("Kitaplık") {
                    rows([.toolbox, .scenes])
                }
            }

            Section("Sistem") {
                rows([.health, .maintenance, .privacy, .integrations, .validation, .settings])
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { profilePendingRemoval != nil },
                set: { if !$0 { profilePendingRemoval = nil } }
            ),
            presenting: profilePendingRemoval
        ) { profile in
            Button("Kaldır", role: .destructive) {
                navigation.forget(profile.id)
                model.removeProfile(profile)
            }
        } message: { profile in
            Text(removalMessage(for: profile))
        }
    }

    private func removalMessage(for profile: Profile) -> String {
        let folder = (model.paths.profileDirectory(for: profile.id).path as NSString).abbreviatingWithTildeInPath
        var message = String(localized: "Hesabın klasörü silinmez: \(folder). Hesabı yeniden eklersen boş bir klasörle başlar ve Claude'a yeniden giriş yapman gerekir.")
        if model.isRunning(profile) {
            message += "\n\n" + String(localized: "Bu hesabın Claude'u şu an açık. Kaldırmadan önce onu kapatman iyi olur.")
        }
        return message
    }

    private var selection: Binding<Destination?> {
        Binding(
            get: { navigation.selection },
            set: { if let destination = $0 { navigation.navigate(to: destination) } }
        )
    }

    private var removalTitle: String {
        guard let profile = profilePendingRemoval else { return "" }
        return String(localized: "\(profile.name) Lanes'ten kaldırılsın mı?")
    }

    /// The destinations the developer pages setting lets through.
    private func rows(_ destinations: [Destination]) -> some View {
        ForEach(destinations.filter { $0.isVisible(showingDeveloperPages: showsDeveloperPages) }, id: \.self) { destination in
            NavigationLink(value: destination) {
                Label(destination.title, systemImage: destination.symbol)
            }
        }
    }
}

private struct SidebarAccountRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        HStack(spacing: 8) {
            MonogramView(profile: profile, size: 20, isRunning: model.isRunning(profile))
            Text(profile.name)
                .lineLimit(1)
            Spacer()
            if let number = model.shortcutNumber(for: profile) {
                Text("⌘\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        Form {
            if case let .account(id) = navigation.selection, let profile = model.profile(withID: id) {
                Section("Bu hesap") {
                    LabeledContent("Durum", value: model.isRunning(profile) ? String(localized: "Açık") : String(localized: "Kapalı"))
                    if let instance = model.instance(for: profile) {
                        LabeledContent("İşlem numarası", value: String(instance.pid))
                    }
                    LabeledContent("Mod", value: profile.mode.displayName)
                    LabeledContent("Tür", value: profile.accountClass.displayName)
                }
            }
            Section("Çalışan Claude pencereleri") {
                if model.instances.isEmpty {
                    Text("Şu an açık Claude yok.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.instances) { instance in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instanceTitle(instance))
                            Text(verbatim: "PID \(instance.pid)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Claude") {
                LabeledContent("Sürüm", value: model.claude?.version ?? String(localized: "Bulunamadı"))
                if let claude = model.claude {
                    LabeledContent("Konum", value: claude.url.deletingLastPathComponent().path)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func instanceTitle(_ instance: RunningInstance) -> String {
        if let id = instance.profileID, let profile = model.profile(withID: id) {
            return profile.name
        }
        return String(localized: "Lanes dışında açılmış")
    }
}
