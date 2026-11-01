import AppKit
import LanesCore
import SwiftUI

/// What the user wrote down about an account, with the account Claude Code
/// is signed in to. From the Claude app Lanes reads only its account number,
/// to tell whether Claude Code is signed in to the same account.
struct AccountIdentityTab: View {
    private enum Field: Hashable {
        case email
        case note
        case domains
    }

    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var email = ""
    @State private var note = ""
    @State private var domains = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                if model.accountMatch(for: profile) != .different, let account = model.claudeCodeAccounts[profile.id] {
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
                        TextField("E-posta", text: $email, prompt: Text("İsteğe bağlı"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .email)
                            .onSubmit(commit)
                    }
                    // Claude Code is signed in to another account than the
                    // app: show its address apart, not as the account's.
                    if model.accountMatch(for: profile) == .different,
                       let other = model.claudeCodeAccounts[profile.id] {
                        LabeledContent("Claude Code") {
                            Text(verbatim: other.email)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .help(other.email)
                        }
                    }
                }
            } header: {
                Text("Claude hesabı")
            } footer: {
                Group {
                    if model.accountMatch(for: profile) == .different {
                        Text("Claude Code ile uygulama farklı hesaplarda.")
                    } else if model.claudeCodeAccounts[profile.id] == nil {
                        Text("Claude Code'a giriş yapılınca kendiliğinden dolar.")
                    } else {
                        Text("Claude Code'un hesap dosyasından alındı.")
                    }
                }
                .help("Lanes giriş anahtarlarına dokunmaz.")
            }
            Section {
                let current = model.profile(withID: profile.id) ?? profile
                if let wrong = model.identityMismatch(for: current) {
                    DSStatusRow(.error, title: Text("Beklenmeyen hesap: \(wrong)")) {
                        Text("Başka bir hesabın verisi bu hesaba karışabilir. Claude Code'da /logout ile çıkıp doğru adresle giriş yap.")
                    }
                } else if !current.expectedEmailDomains.isEmpty, model.claudeCodeAccounts[profile.id] != nil {
                    DSStatusRow(.ok, title: Text("Claude Code beklenen hesapla giriş yapmış"))
                }
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Beklenen alan adları")
                    TextField("Beklenen alan adları", text: $domains, prompt: Text("Örneğin musteri.com, ortak.io"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .domains)
                        .onSubmit(commit)
                }
            } header: {
                Text("Kimlik Bekçisi")
            } footer: {
                Text("Virgülle ayır. Yalnız Claude Code'un girişi denetlenir, Claude uygulamasınınki değil.")
            }
            Section {
                Button("Claude Ayarlarını Aç", action: openClaudeSettings)
                    .disabled(!model.isRunning(profile))
            } footer: {
                Text("Hesap açık olmalı.")
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
                Text("Yalnız bu Mac'te durur, hiçbir yere gönderilmez.")
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
            domains = profile.expectedEmailDomains.joined(separator: ", ")
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
        let newDomains = domains.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard (updated.email ?? "") != newEmail || (updated.note ?? "") != newNote || updated.expectedEmailDomains != newDomains else { return }
        updated.email = newEmail.isEmpty ? nil : newEmail
        updated.note = newNote.isEmpty ? nil : newNote
        if updated.expectedEmailDomains != newDomains {
            updated.expectedEmailDomains = newDomains
        }
        model.updateProfile(updated)
        model.refreshClaudeCodeAccounts()
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
                    } else {
                        Text("\"Klasörde Aç\" yalnız bu klasörlerde çalışır. Elle başlatılan claude komutu sınırlanmaz.")
                    }
                }
            }
            Section {
                let kinds = model.linkRules.byKind.filter { $0.value == .profile(profile.id) }.map(\.key)
                let smartRules = model.linkRules.rules.filter { $0.target == .profile(profile.id) }
                if kinds.isEmpty && smartRules.isEmpty && model.linkRules.fallback != .profile(profile.id) {
                    Text("Hesap Haritası'nda bu hesaba yönlenen bağlantı yok.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(smartRules) { rule in
                        Label(rule.isEnabled ? rule.name : String(localized: "\(rule.name) (kapalı)"), systemImage: "wand.and.stars")
                            .lineLimit(1)
                    }
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
