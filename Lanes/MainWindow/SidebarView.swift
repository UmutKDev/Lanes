import LanesCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @State private var profilePendingRemoval: Profile?
    @State private var query = ""
    @AppStorage(Preferences.Key.showsDeveloperPages) private var showsDeveloperPages = Preferences.developerPagesDefault

    var body: some View {
        let active = matching(model.library.activeProfiles)
        let archived = matching(model.library.archivedProfiles)
        List(selection: selection) {
            // While searching only the accounts are listed, so the result is
            // not lost among the page rows.
            if !isSearching {
                Section {
                    rows([.overview, .sessions, .usage])
                }
            }

            // While searching, an empty "Hesaplar" header is hidden too.
            if !isSearching || !active.isEmpty {
                Section("Hesaplar") {
                    ForEach(active) { profile in
                        DSAccountLabel(profile: profile, size: DS.Monogram.small, isRunning: model.isRunning(profile))
                            .badge(shortcutBadge(for: profile))
                            // An explicit tag: inside a movable ForEach the row
                            // would otherwise be tagged with the profile's id,
                            // which the Destination selection never matches.
                            .tag(Destination.account(profile.id))
                            .contextMenu {
                                Button(model.isRunning(profile) ? "Öne Getir" : "Aç") {
                                    model.open(profile)
                                }
                                Button("Claude Code'u Terminalde Aç") {
                                    model.openClaudeCode(profile)
                                }
                                Button("Hesabı Çoğalt") {
                                    if let copy = model.duplicateProfile(profile) {
                                        navigation.navigate(to: .account(copy.id))
                                    }
                                }
                                if !profile.isDefault {
                                    Button("Arşivle") {
                                        model.setArchived(profile, true)
                                    }
                                }
                                Divider()
                                Button("Hesabı Kaldır…", role: .destructive) {
                                    profilePendingRemoval = profile
                                }
                                .disabled(profile.isDefault)
                            }
                    }
                    // Rows can only be dragged in the full list, not a filtered one.
                    .onMove(perform: query.isEmpty ? moveRows : nil)
                }
            }

            if !archived.isEmpty {
                Section("Arşiv") {
                    ForEach(archived) { profile in
                        ArchivedAccountLabel(profile: profile, isRunning: model.isRunning(profile))
                            .badge(shortcutBadge(for: profile))
                            .tag(Destination.account(profile.id))
                            .contextMenu {
                                Button("Arşivden Çıkar") {
                                    model.setArchived(profile, false)
                                }
                                Divider()
                                Button("Hesabı Kaldır…", role: .destructive) {
                                    profilePendingRemoval = profile
                                }
                            }
                    }
                }
            }

            if !isSearching {
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
        }
        .listStyle(.sidebar)
        // The empty search result sits on the list itself, never over the
        // search field.
        .overlay {
            if isSearching && active.isEmpty && archived.isEmpty {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
        // Rows meet a hard edge under the search field and above the bottom
        // "Hesap Ekle" bar instead of showing through behind either.
        .scrollEdgeEffectStyle(.hard, for: .vertical)
        .searchable(text: $query, placement: .sidebar, prompt: Text("Hesap ara"))
        // safeAreaBar (unlike safeAreaInset) gives the bottom edge a scroll
        // edge effect, so rows do not show through the glass button.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Button {
                navigation.isAddingProfile = true
            } label: {
                Label("Hesap Ekle", systemImage: "plus")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .help("Hesap ekle")
            .padding(DS.Space.m)
        }
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

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// "⌘N" as a list badge: the sidebar keeps it readable on a selected row
    /// and never lets it push the name.
    private func shortcutBadge(for profile: Profile) -> Text? {
        guard let number = model.shortcutNumber(for: profile) else { return nil }
        return Text("⌘\(number)")
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
            get: { navigation.selection.displayed(showingDeveloperPages: showsDeveloperPages) },
            set: { if let destination = $0 { navigation.navigate(to: destination) } }
        )
    }

    private func moveRows(_ source: IndexSet, _ destination: Int) {
        model.moveProfiles(fromOffsets: source, toOffset: destination)
    }

    /// Accounts whose name, email or note holds the search text, ignoring
    /// case and accents with Turkish rules. All of them when it is empty.
    private func matching(_ profiles: [Profile]) -> [Profile] {
        let text = trimmedQuery
        guard !text.isEmpty else { return profiles }
        return profiles.filter { profile in
            SearchText.matches(text, in: [profile.name, profile.email ?? "", profile.note ?? ""])
        }
    }

    private var removalTitle: String {
        guard let profile = profilePendingRemoval else { return "" }
        return String(localized: "\(profile.name) Lanes'ten kaldırılsın mı?")
    }

    /// The destinations the developer pages setting lets through.
    private func rows(_ destinations: [Destination]) -> some View {
        ForEach(destinations.filter { $0.isVisible(showingDeveloperPages: showsDeveloperPages) }, id: \.self) { destination in
            Label(destination.title, systemImage: destination.symbol)
                .tag(destination)
        }
    }
}

/// An archived account: the same Label geometry as the active rows, with a
/// secondary title and a grey monogram instead of a dimmed row, so it still
/// reads on the selection highlight.
private struct ArchivedAccountLabel: View {
    let profile: Profile
    let isRunning: Bool

    var body: some View {
        Label {
            Text(profile.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        } icon: {
            MonogramView(profile: profile, size: DS.Monogram.small, isRunning: isRunning)
                .saturation(0)
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
                    LabeledContent("Durum") {
                        DSStatusBadge(isRunning: model.isRunning(profile), font: DS.Typography.rowTitle)
                    }
                    if let instance = model.instance(for: profile) {
                        LabeledContent("İşlem numarası") {
                            Text(verbatim: String(instance.pid))
                                .monospacedDigit()
                                .textSelection(.enabled)
                        }
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
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(instanceTitle(instance))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(verbatim: "PID \(instance.pid)")
                                .font(DS.Typography.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Claude") {
                LabeledContent("Sürüm") {
                    Text(model.claude?.version ?? String(localized: "Bulunamadı"))
                        .monospacedDigit()
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                if let claude = model.claude {
                    LabeledContent("Konum") {
                        DSPathText(url: claude.url.deletingLastPathComponent())
                    }
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
