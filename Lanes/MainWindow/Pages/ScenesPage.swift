import LanesCore
import SwiftUI

/// Saved groups of accounts that open together.
struct ScenesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @State private var editing: ProfileScene?
    @State private var isAdding = false

    var body: some View {
        // One Form that always exists; the empty state lies over it, so the
        // first or last scene animates in and out instead of swapping roots.
        Form {
            if !model.library.scenes.isEmpty {
                Section {
                    ForEach(model.library.scenes) { scene in
                        SceneRow(scene: scene) { editing = scene }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("Hesaplar sırayla açılır, sondaki öne gelir. Bir sahneye kısayol vermek için Ayarlar > Kısayollar.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Kısayolları Ayarla…") {
                            router.showSettings(.shortcuts)
                        }
                        .buttonStyle(.link)
                    }
                    .font(DS.Typography.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .libraryForm()
        .dsEmptyState(model.library.scenes.isEmpty) {
            DSEmptyState(
                "Henüz sahne yok",
                systemImage: Destination.scenes.symbol,
                description: Text("Sahne, birlikte açtığın hesapların kayıtlı listesi. Örneğin sabahları İş ve Müşteri hesaplarını tek tıkla açabilirsin.")
            ) {
                Button("Sahne Oluştur") { isAdding = true }
            }
        }
        .animation(DS.Motion.standard, value: model.library.scenes.isEmpty)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("Sahne Oluştur", systemImage: "plus")
                }
                .help("Sahne Oluştur")
                .dsPrimaryAction()
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
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(scene.name)
                        .font(DS.Typography.rowTitle.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    if let shortcut = model.shortcuts.shortcut(for: .scene(scene.id)) {
                        DSShortcutHint(text: shortcut.description)
                    }
                }
                if !profiles.isEmpty {
                    SceneAvatarStrip(profiles: profiles)
                }
                Text(subtitle(profiles))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(subtitle(profiles))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DSIconButton("Düzenle", systemImage: "pencil", action: onEdit)

            Button("Aç") {
                model.open(scene)
            }
            .dsPrimaryAction()
            .controlSize(.small)
            .fixedSize()
            .disabled(profiles.isEmpty)
        }
        .padding(.vertical, DS.Space.xxs)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Aç") {
                model.open(scene)
            }
            .disabled(profiles.isEmpty)
            Button("Düzenle", action: onEdit)
        }
    }

    private func subtitle(_ profiles: [Profile]) -> String {
        let names = profiles.map(\.name).joined(separator: ", ")
        let base = profiles.isEmpty ? String(localized: "Hesap yok") : names
        return scene.opensWhenLanesStarts ? String(localized: "\(base) · Lanes açılınca") : base
    }
}

/// Overlapping monograms, capped so a long scene never pushes the buttons
/// out of the row; the rest shows as "+N".
private struct SceneAvatarStrip: View {
    @Environment(AppModel.self) private var model
    let profiles: [Profile]

    var body: some View {
        let shown = Array(profiles.prefix(DS.Panel.maxStackedAvatars))
        let extra = profiles.count - shown.count
        HStack(spacing: -DS.Space.xs) {
            ForEach(shown) { profile in
                MonogramView(profile: profile, size: DS.Monogram.small, isRunning: model.isRunning(profile))
            }
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(DS.Typography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: DS.Monogram.small)
                    .background(DS.Palette.hoverFill, in: Capsule())
                    .padding(.leading, DS.Space.s)
            }
        }
    }
}

/// Creates or edits a scene: its name, its accounts in order, and whether it
/// opens with Lanes.
private struct SceneEditor: View {
    private enum Field: Hashable {
        case name
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scene: ProfileScene?
    @State private var name = ""
    @State private var selected: [ProfileID] = []
    @State private var opensWhenLanesStarts = false
    @State private var isConfirmingRemoval = false
    @FocusState private var focus: Field?

    var body: some View {
        Form {
            Section {
                TextField("Ad", text: $name, prompt: Text("Örneğin İş"))
                    .multilineTextAlignment(.leading)
                    .focused($focus, equals: .name)
            }
            Section {
                ForEach(model.library.profiles) { profile in
                    Toggle(isOn: binding(for: profile.id)) {
                        HStack(spacing: DS.Space.s) {
                            DSAccountLabel(profile: profile)
                                .layoutPriority(1)
                            Spacer(minLength: DS.Space.s)
                            orderBadge(for: profile.id)
                        }
                    }
                }
            } header: {
                Text("Hesaplar")
            } footer: {
                Text("Seçtiğin sırayla açılır.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Lanes açılınca bu sahneyi aç", isOn: $opensWhenLanesStarts)
            } footer: {
                Text("Ayarlar > Genel'de \"Oturum açıldığında Lanes'i başlat\" açıksa sahne her oturum açılışında da açılır.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let scene {
                SceneLayoutSection(sceneID: scene.id)
            }
        }
        .formStyle(.grouped)
        .animation(DS.Motion.standard, value: selected)
        // A new scene starts in the name field; an existing one opens with
        // nothing focused, so its name is not selected under the cursor.
        .defaultFocus($focus, scene == nil ? Field.name : nil)
        .toolbar {
            if scene != nil {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        isConfirmingRemoval = true
                    } label: {
                        Text("Sahneyi Sil")
                            .foregroundStyle(DS.Palette.danger)
                    }
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(scene == nil ? "Oluştur" : "Kaydet") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .presentationSizing(.form)
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

    /// A new scene needs a name; an edited one keeps its old name when the
    /// field is left empty.
    private var canSave: Bool {
        guard !selected.isEmpty else { return false }
        if scene == nil {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    /// The opening order ("1.", "2." …) in a slot as wide as "00.", so the
    /// label does not move when a toggle flips.
    private func orderBadge(for id: ProfileID) -> some View {
        ZStack(alignment: .trailing) {
            Text(verbatim: "00.")
                .hidden()
            if let position = selected.firstIndex(of: id) {
                Text("\(position + 1).")
                    .transition(.opacity)
            }
        }
        .font(DS.Typography.shortcut)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
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
        // The latest copy, so a layout saved while the editor was open stays.
        if var scene = scene.flatMap({ model.library.scene(withID: $0.id) ?? $0 }) {
            scene.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? scene.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
            scene.profileIDs = selected
            scene.opensWhenLanesStarts = opensWhenLanesStarts
            scene.pruneWindowFrames()
            model.updateScene(scene)
        } else if var created = model.addScene(name: name, profileIDs: selected) {
            created.opensWhenLanesStarts = opensWhenLanesStarts
            if opensWhenLanesStarts { model.updateScene(created) }
        }
    }
}

/// Saves where the scene's Claude windows are now, so opening the scene
/// puts them back there. Uses the Accessibility permission tab mode asks
/// for; Lanes only reads and sets window frames.
private struct SceneLayoutSection: View {
    @Environment(AppModel.self) private var model
    let sceneID: SceneID
    @State private var result: String?

    var body: some View {
        let scene = model.library.scene(withID: sceneID)
        let saved = scene?.windowFrames.count ?? 0
        Section {
            HStack(spacing: DS.Space.s) {
                Button("Şimdiki Yerleşimi Kaydet") {
                    result = model.saveLayout(of: sceneID)
                }
                .fixedSize()
                Button("Yerleşimi Unut") {
                    model.forgetLayout(of: sceneID)
                    result = nil
                }
                .fixedSize()
                .disabled(saved == 0)
                Spacer(minLength: 0)
            }
            if let result, !result.isEmpty {
                DSStatusRow(.info, title: Text(verbatim: result))
                    .transition(.opacity)
            }
        } header: {
            Text("Pencere yerleşimi")
        } footer: {
            Text(saved > 0
                 ? String(localized: "\(saved) hesabın penceresinin yeri kayıtlı. Sahne açılınca pencereler oraya dizilir.")
                 : String(localized: "Sahnedeki hesapları aç, pencerelerini istediğin yere koy ve kaydet. Sahne açılınca pencereler oraya dizilir. Erişilebilirlik izni gerekir."))
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(DS.Motion.standard, value: result)
    }
}

// MARK: - Library page layout

extension View {
    /// The library pages' grouped Form: the app's Form, centred at a
    /// readable width in wide windows.
    func libraryForm() -> some View {
        modifier(LibraryFormLayout())
    }
}

/// Grouped Form with side margins that keep its sections at
/// `DS.Metrics.readableWidth` when the window is wide.
struct LibraryFormLayout: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .dsForm()
            .contentMargins(.horizontal, sideMargin, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newValue in
                width = newValue
            }
    }

    /// Nil (the Form's own inset) until the window is wide enough that the
    /// centred column needs a wider margin than that, so a narrow window
    /// never loses the default inset.
    private var sideMargin: CGFloat? {
        let margin = ((width - DS.Metrics.readableWidth) / 2).rounded(.down)
        return margin > DS.Space.page ? margin : nil
    }
}
