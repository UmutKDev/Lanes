import LanesCore
import SwiftUI

/// Saved groups of accounts that open together.
struct ScenesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @State private var editing: ProfileScene?
    @State private var isAdding = false

    var body: some View {
        Group {
            if model.library.scenes.isEmpty {
                ContentUnavailableView {
                    Label("Henüz sahne yok", systemImage: Destination.scenes.symbol)
                } description: {
                    Text("Sahne, birlikte açtığın hesapların kayıtlı listesi. Örneğin sabahları İş ve Müşteri hesaplarını tek tıkla açabilirsin.")
                } actions: {
                    Button("Sahne Oluştur") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Form {
                    Section {
                        ForEach(model.library.scenes) { scene in
                            SceneRow(scene: scene) { editing = scene }
                        }
                    } footer: {
                        Text("Hesaplar sırayla açılır, sondaki öne gelir. Bir sahneye kısayol vermek için Ayarlar > Kısayollar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button {
                            isAdding = true
                        } label: {
                            Label("Sahne Oluştur", systemImage: "plus")
                        }
                        Button("Kısayolları Ayarla…") {
                            router.showSettings(.shortcuts)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .sheet(isPresented: $isAdding) {
            SceneEditor(scene: nil)
        }
        .sheet(item: $editing) { scene in
            SceneEditor(scene: scene)
        }
    }
}

private struct SceneRow: View {
    @Environment(AppModel.self) private var model
    let scene: ProfileScene
    var onEdit: () -> Void

    var body: some View {
        let profiles = scene.profiles(in: model.library)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(scene.name)
                        .font(.body.weight(.medium))
                    if let shortcut = model.shortcuts.shortcut(for: .scene(scene.id)) {
                        Text(shortcut.description)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: -4) {
                    ForEach(profiles) { profile in
                        MonogramView(profile: profile, size: 20, isRunning: model.isRunning(profile))
                    }
                }
                Text(subtitle(profiles))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Düzenle", action: onEdit)
            Button("Aç") {
                model.open(scene)
            }
            .buttonStyle(.borderedProminent)
            .disabled(profiles.isEmpty)
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ profiles: [Profile]) -> String {
        let names = profiles.map(\.name).joined(separator: ", ")
        let base = profiles.isEmpty ? String(localized: "Hesap yok") : names
        return scene.opensWhenLanesStarts ? String(localized: "\(base) · Lanes açılınca") : base
    }
}

/// Creates or edits a scene: its name, its accounts in order, and whether it
/// opens with Lanes.
private struct SceneEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scene: ProfileScene?
    @State private var name = ""
    @State private var selected: [ProfileID] = []
    @State private var opensWhenLanesStarts = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Ad", text: $name, prompt: Text("Örneğin İş"))
                }
                Section {
                    ForEach(model.library.profiles) { profile in
                        Toggle(isOn: binding(for: profile.id)) {
                            HStack(spacing: 8) {
                                MonogramView(profile: profile, size: 20)
                                Text(profile.name)
                                if let position = selected.firstIndex(of: profile.id) {
                                    Text("\(position + 1).")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Hesaplar")
                } footer: {
                    Text("Seçtiğin sırayla açılır.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Lanes açılınca bu sahneyi aç", isOn: $opensWhenLanesStarts)
                    Text("Ayarlar > Genel'de \"Oturum açıldığında Lanes'i başlat\" açıksa sahne her oturum açılışında da açılır.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            HStack {
                if scene != nil {
                    Button("Sahneyi Sil", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                }
                Spacer()
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(scene == nil ? "Oluştur" : "Kaydet") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 520)
        .onAppear {
            if let scene {
                name = scene.name
                selected = scene.profileIDs.filter { model.profile(withID: $0) != nil }
                opensWhenLanesStarts = scene.opensWhenLanesStarts
            }
        }
        .confirmationDialog("\(name) sahnesi silinsin mi?", isPresented: $isConfirmingRemoval) {
            Button("Sil", role: .destructive) {
                if let scene { model.removeScene(scene) }
                dismiss()
            }
        } message: {
            Text("Hesaplar silinmez, yalnız bu liste ve kısayolu gider.")
        }
    }

    private func binding(for id: ProfileID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn {
                    if !selected.contains(id) { selected.append(id) }
                } else {
                    selected.removeAll { $0 == id }
                }
            }
        )
    }

    private func save() {
        if var scene {
            scene.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? scene.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
            scene.profileIDs = selected
            scene.opensWhenLanesStarts = opensWhenLanesStarts
            model.updateScene(scene)
        } else if var created = model.addScene(name: name, profileIDs: selected) {
            created.opensWhenLanesStarts = opensWhenLanesStarts
            if opensWhenLanesStarts { model.updateScene(created) }
        }
    }
}
