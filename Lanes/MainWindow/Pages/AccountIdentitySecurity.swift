import AppKit
import LanesCore
import SwiftUI

/// What the user wrote down about an account. Lanes reads nothing from
/// Claude to fill it.
struct AccountIdentityTab: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var email = ""
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                TextField("E-posta", text: $email, prompt: Text("ornek@alan.com"))
                    .onSubmit(commit)
                TextField("Not", text: $note, prompt: Text("Örneğin hangi iş için"), axis: .vertical)
                    .lineLimit(2...5)
                Text("Yalnız hesapları birbirinden ayırman için. Lanes bunları Claude'dan okumaz ve hiçbir yere göndermez, profiles.json dosyasında durur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent("Hesap türü", value: profile.accountClass.displayName)
                LabeledContent("Eklendiği tarih", value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Kimlik") {
                    Text(profile.id.rawValue)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            email = profile.email ?? ""
            note = profile.note ?? ""
        }
        .onDisappear(perform: commit)
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
            Section("Claude Code klasörleri") {
                if current.allowedFolders.isEmpty {
                    Text("Claude Code bu hesapla her klasörde açılabilir.")
                        .foregroundStyle(.secondary)
                }
                ForEach(current.allowedFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text((folder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            setFolders(current.allowedFolders.filter { $0 != folder })
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Listeden çıkar")
                    }
                }
                Button("Klasör Ekle…", action: addFolder)
                Text("Liste boş değilse Lanes, \"Klasörde Aç\" ile Claude Code'u yalnız bu klasörlerde ve alt klasörlerinde açar. Bir müşterinin hesabının başka projelere karışmaması için. Terminalde elle başlatılan claude komutunu sınırlamaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Bağlantılar") {
                let kinds = model.linkRules.byKind.filter { $0.value == .profile(profile.id) }.map(\.key)
                if kinds.isEmpty && model.linkRules.fallback != .profile(profile.id) {
                    Text("Hesap Haritası'nda bu hesaba yönlenen bağlantı yok.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(kinds.sorted { $0.rawValue < $1.rawValue }, id: \.self) { kind in
                        Label(kind.title, systemImage: "link")
                    }
                    if model.linkRules.fallback == .profile(profile.id) {
                        Label("Kurala uymayan bütün bağlantılar", systemImage: "arrow.triangle.branch")
                    }
                }
                Text("Giriş ve OAuth bağlantıları hiçbir zaman yönlendirilmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "İzin Ver")
        guard panel.runModal() == .OK, let current = model.profile(withID: profile.id) else { return }
        var folders = current.allowedFolders
        for url in panel.urls where !folders.contains(url.path) {
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
