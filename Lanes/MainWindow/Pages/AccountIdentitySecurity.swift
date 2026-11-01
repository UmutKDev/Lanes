import AppKit
import LanesCore
import SwiftUI

/// What the user wrote down about an account. Lanes reads nothing from
/// Claude to fill it.
struct AccountIdentityTab: View {
    private enum Field: Hashable {
        case email
        case note
    }

    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var email = ""
    @State private var note = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                if let account = model.claudeCodeAccounts[profile.id] {
                    LabeledContent("E-posta") {
                        Text(verbatim: account.email)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(account.email)
                    }
                    if let name = account.displayName {
                        LabeledContent("Ad") {
                            Text(verbatim: name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                        }
                    }
                    if let organization = account.organizationName {
                        LabeledContent("Kuruluş") {
                            Text(verbatim: organization)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    // Nothing to read yet: the user may type it. The prompt
                    // says it is optional instead of showing a sample address,
                    // which read as the account's real email.
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("E-posta")
                        TextField("E-posta", text: $email, prompt: Text("Bu hesapla giriş yaptığın adres (isteğe bağlı)"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .email)
                            .onSubmit(commit)
                    }
                }
            } header: {
                Text("Claude hesabı")
            } footer: {
                Text(model.claudeCodeAccounts[profile.id] == nil
                     ? "Bu hesapla Claude Code'a giriş yapıldığında e-posta, ad ve kuruluş kendiliğinden buraya gelir. Lanes yalnız Claude Code'un hesap dosyasındaki bu üç alanı okur; giriş anahtarlarına ve Claude uygulamasının verilerine dokunmaz."
                     : "Claude Code'un bu hesap için tuttuğu dosyadan alındı. Lanes yalnız e-posta, ad ve kuruluş alanlarını okur; giriş anahtarlarına ve Claude uygulamasının verilerine dokunmaz.")
            }
            Section {
                Button("Claude Ayarlarını Aç", action: openClaudeSettings)
                    .disabled(!model.isRunning(profile))
            } footer: {
                Text("Claude'un ayarları bu hesabın kendi penceresinde açılır. Bunun için hesap açık olmalı.")
            }
            Section {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Not")
                    TextField("Not", text: $note, prompt: Text("Örneğin hangi iş için"), axis: .vertical)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .note)
                }
            } footer: {
                Text("Yalnız hesapları birbirinden ayırman için, profiles.json dosyasında durur ve hiçbir yere gönderilmez.")
            }
            Section {
                LabeledContent("Hesap türü", value: profile.accountClass.displayName)
                LabeledContent("Eklendiği tarih", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Kimlik") {
                    HStack(spacing: DS.Space.xs) {
                        Text(verbatim: profile.id.rawValue)
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(profile.id.rawValue)
                        DSCopyButton(text: profile.id.rawValue)
                    }
                }
            }
        }
        .accountForm()
        .onAppear {
            model.refreshClaudeCodeAccounts()
            email = profile.email ?? ""
            note = profile.note ?? ""
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != nil, oldValue != newValue {
                commit()
            }
        }
        .onDisappear(perform: commit)
    }

    /// Sends the settings link to this account's own Claude, the same GURL
    /// event link routing uses, so the settings never open in another
    /// account's window.
    private func openClaudeSettings() {
        guard let pid = model.instance(for: profile)?.pid,
              let url = URL(string: "claude://claude.ai/settings"),
              let link = ClaudeLink(url: url) else { return }
        let name = profile.name
        Task {
            do {
                try await AppleEvents.sendLink(link, to: pid)
                await InstanceLauncher.activate(pid: pid)
            } catch {
                model.notice = AppModel.Notice(kind: .warning, message: String(localized: "Claude'un ayarları \(name) hesabında açılamadı: \(error.localizedDescription)"))
            }
        }
    }

    private func commit() {
        guard var updated = model.profile(withID: profile.id) else { return }
        let newEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (updated.email ?? "") != newEmail || (updated.note ?? "") != newNote else { return }
        updated.email = newEmail.isEmpty ? nil : newEmail
        updated.note = newNote.isEmpty ? nil : newNote
        model.updateProfile(updated)
    }
}

/// Limits on where an account may work: Claude Code folders, and which
/// links Lanes sends to it.
struct AccountSecurityTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let current = model.profile(withID: profile.id) ?? profile
        Form {
            Section {
                ForEach(current.allowedFolders, id: \.self) { folder in
                    AccountFolderRow(url: URL(fileURLWithPath: folder, isDirectory: false)) {
                        DSIconButton("Listeden çıkar", systemImage: "minus.circle.fill", role: .destructive) {
                            setFolders(current.allowedFolders.filter { $0 != folder })
                        }
                    }
                }
                Button(action: addFolder) {
                    Label("Klasör Ekle…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Claude Code klasörleri")
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if current.allowedFolders.isEmpty {
                        Text("Claude Code bu hesapla her klasörde açılabilir.")
                    }
                    Text("Liste boş değilse Lanes, \"Klasörde Aç\" ile Claude Code'u yalnız bu klasörlerde ve alt klasörlerinde açar. Bir müşterinin hesabının başka projelere karışmaması için. Terminalde elle başlatılan claude komutunu sınırlamaz.")
                }
            }
            Section {
                let kinds = model.linkRules.byKind.filter { $0.value == .profile(profile.id) }.map(\.key)
                if kinds.isEmpty && model.linkRules.fallback != .profile(profile.id) {
                    Text("Hesap Haritası'nda bu hesaba yönlenen bağlantı yok.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(kinds.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                        Label(kind.title, systemImage: "link")
                            .lineLimit(1)
                    }
                    if model.linkRules.fallback == .profile(profile.id) {
                        Label("Kurala uymayan bütün bağlantılar", systemImage: "arrow.triangle.branch")
                            .lineLimit(1)
                    }
                }
            } header: {
                Text("Bağlantılar")
            } footer: {
                Text("Giriş ve OAuth bağlantıları hiçbir zaman yönlendirilmez.")
            }
        }
        .accountForm()
    }

    private func addFolder() {
        let urls = ClaudeCodeFolderPicker.chooseFolders(
            prompt: String(localized: "İzin Ver"),
            message: nil,
            allowsMultipleSelection: true
        )
        guard !urls.isEmpty, let current = model.profile(withID: profile.id) else { return }
        var folders = current.allowedFolders
        for url in urls where !folders.contains(url.path) {
            folders.append(url.path)
        }
        setFolders(folders)
    }

    private func setFolders(_ folders: [String]) {
        guard var updated = model.profile(withID: profile.id) else { return }
        updated.allowedFolders = folders
        model.updateProfile(updated)
    }
}
