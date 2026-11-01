import AppKit
import LanesCore
import SwiftUI

/// "Mevcut Claude klasörünü içe aktar": takes a Claude data folder another
/// launcher made into Lanes as a new account, keeping its sign-in and its
/// sessions. Lanes only checks names and dates in the folder; it never
/// reads what is inside.
struct ImportClaudeFolderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [ClaudeFolderScanner.Candidate] = []
    @State private var isLoading = true
    @State private var selection: URL?
    @State private var usedDirectories: [String] = []
    /// Why a folder picked with "Başka klasör seç…" can't be used, or why
    /// the last import did not happen.
    @State private var pickError: String?
    /// Folders picked with "Başka klasör seç…"; kept in the list on reload.
    @State private var pickedFolders: [URL] = []
    /// Old launchers still open after the import; offered again on retry.
    @State private var runningLaunchers: [ClaudeFolderScanner.Launcher] = []
    @State private var isAskingToQuit = false
    @State private var importedProfile: Profile?
    /// Picked folders that don't look like Claude data; Lanes asks once.
    @State private var unlikelyFolders: Set<URL> = []
    @State private var isConfirmingUnlikely = false

    @State private var name = ""
    @State private var suggestedName = ""
    @State private var color: ProfileColor = .blue
    @State private var accountClass: AccountClass = .personal
    @State private var sharesClaudeCode = true
    @State private var opensAfterImport = true

    var body: some View {
        Form {
            folderSection
            Section("Hesap") {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Ad")
                    TextField("Ad", text: $name)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("Renk")
                    ColorChooser(selection: $color)
                }
                Picker("Hesap türü", selection: $accountClass) {
                    ForEach(AccountClass.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.symbol).tag(kind)
                    }
                }
            }
            Section {
                Toggle("~/.claude ile ortak", isOn: $sharesClaudeCode)
            } header: {
                Text("Claude Code")
            } footer: {
                if sharesClaudeCode {
                    Text("Eski oturumlar görünür kalır.")
                }
            }
            Section {
                Toggle("Ekledikten sonra bu hesabı aç", isOn: $opensAfterImport)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("İçe Aktar") {
                    if let selected, unlikelyFolders.contains(selected.url) {
                        isConfirmingUnlikely = true
                    } else {
                        runImport()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .confirmationDialog("Claude klasörüne benzemiyor. Yine de aktarılsın mı?", isPresented: $isConfirmingUnlikely) {
            Button("İçe Aktar") {
                runImport()
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .alert("Önce kapat", isPresented: $isAskingToQuit) {
            Button("Tekrar Dene") {
                offerToTrash(runningLaunchers)
            }
            Button("Kalsın", role: .cancel) {
                finish()
            }
        } message: {
            Text(String(localized: "\(runningLaunchers.map(\.name).joined(separator: ", ")) hâlâ açık."))
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 560)
        .presentationSizing(.fitted)
        .onAppear {
            color = nextFreeColor()
        }
        .onChange(of: selection) {
            suggestName()
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        Section("Klasör") {
            if isLoading {
                Text("Aranıyor…")
                    .foregroundStyle(.secondary)
            } else if candidates.isEmpty {
                Text("Claude klasörü bulunamadı.")
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { candidate in
                CandidateRow(candidate: candidate, isSelected: selection == candidate.url) {
                    selection = candidate.url
                }
            }
            Button("Başka klasör seç…") {
                chooseFolder()
            }
            .buttonStyle(.link)
            if let pickError {
                Text(pickError)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.warning)
            }
        }
    }

    private var selected: ClaudeFolderScanner.Candidate? {
        candidates.first { $0.url == selection }
    }

    private var canImport: Bool {
        guard let selected, !selected.inUse else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() async {
        usedDirectories = RunningInstanceScanner.userDataDirectories() + model.instances.compactMap(\.userDataDirectory)
        var found = await ClaudeFolderScanner.candidates(paths: model.paths, library: model.library, userDataDirectories: usedDirectories)
        // Picked folders stay listed while they are still there; only
        // whether they are in use is refreshed.
        for url in pickedFolders where !found.contains(where: { $0.url == url }) && FileManager.default.fileExists(atPath: url.path) {
            found.append(await ClaudeFolderScanner.candidate(for: url, paths: model.paths, userDataDirectories: usedDirectories))
        }
        candidates = found
        isLoading = false
        if selection == nil {
            selection = found.first(where: { !$0.inUse })?.url
        }
    }

    /// Fills the name from the launcher or the folder, unless the user
    /// typed one of their own.
    private func suggestName() {
        guard let selected else { return }
        let suggestion = ClaudeFolderImport.suggestedName(
            folderName: selected.name,
            launcherName: selected.launchers.first?.name
        )
        if name.isEmpty || name == suggestedName {
            name = suggestion
        }
        suggestedName = suggestion
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = ClaudeFolderScanner.applicationSupport(home: model.paths.home)
        panel.prompt = String(localized: "Seç")
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        pickError = nil
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            pickError = ClaudeFolderImport.Refusal.symbolicLink.message
            return
        }
        let refusal = ClaudeFolderImport.refusal(for: url.path, paths: model.paths, library: model.library, userDataDirectories: usedDirectories)
        if let refusal, refusal != .inUse {
            pickError = refusal.message
            return
        }
        if !isOnLanesVolume(url) {
            pickError = ClaudeFolderImport.Refusal.otherVolume.message
            return
        }
        if !ClaudeFolderScanner.looksLikeClaudeData(url) {
            unlikelyFolders.insert(url)
        }
        Task {
            let candidate = await ClaudeFolderScanner.candidate(for: url, paths: model.paths, userDataDirectories: usedDirectories)
            if !pickedFolders.contains(url) {
                pickedFolders.append(url)
            }
            if let index = candidates.firstIndex(where: { $0.url == url }) {
                candidates[index] = candidate
            } else {
                candidates.append(candidate)
            }
            selection = url
        }
    }

    /// Lanes' own folder may not exist yet; its nearest existing parent is
    /// on the same volume.
    private func isOnLanesVolume(_ url: URL) -> Bool {
        var target = model.paths.root
        while !FileManager.default.fileExists(atPath: target.path), target.pathComponents.count > 1 {
            target.deleteLastPathComponent()
        }
        return ClaudeFolderScanner.isSameVolume(url, target)
    }

    private func runImport() {
        guard canImport, let selected else { return }
        pickError = nil
        let result = model.importClaudeFolder(
            selected.url,
            name: name,
            color: color,
            accountClass: accountClass,
            sharesClaudeCode: sharesClaudeCode
        )
        switch result {
        case .failure(let failure):
            pickError = failure.message
            // The list may be out of date, e.g. Claude opened the folder.
            Task { await load() }
        case .success(let profile):
            importedProfile = profile
            offerToTrash(selected.launchers)
        }
    }

    /// Asks once per old launcher. One that is still open is offered again
    /// after the user quits it.
    private func offerToTrash(_ launchers: [ClaudeFolderScanner.Launcher]) {
        var stillRunning: [ClaudeFolderScanner.Launcher] = []
        for launcher in launchers {
            if model.isLauncherRunning(launcher.url) {
                stillRunning.append(launcher)
                continue
            }
            let alert = NSAlert()
            alert.messageText = String(localized: "\(launcher.name) artık gerekmiyor. Çöp Sepeti'ne taşınsın mı?")
            alert.addButton(withTitle: String(localized: "Çöp Sepeti'ne Taşı"))
            alert.addButton(withTitle: String(localized: "Kalsın"))
            if alert.runModal() == .alertFirstButtonReturn, !model.trashLauncher(launcher.url), model.isLauncherRunning(launcher.url) {
                stillRunning.append(launcher)
            }
        }
        runningLaunchers = stillRunning
        if stillRunning.isEmpty {
            finish()
        } else {
            isAskingToQuit = true
        }
    }

    private func finish() {
        guard let profile = importedProfile else { return }
        importedProfile = nil
        dismiss()
        navigation.navigate(to: .account(profile.id))
        if opensAfterImport {
            model.open(profile)
        }
    }

    private func nextFreeColor() -> ProfileColor {
        let used = Set(model.library.profiles.map(\.color))
        return ProfileColor.allCases.first { !used.contains($0) } ?? .blue
    }
}

private struct CandidateRow: View {
    let candidate: ClaudeFolderScanner.Candidate
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: candidate.name)
                        .font(DS.Typography.caption.monospaced())
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if candidate.inUse {
                    Text("Açık")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(candidate.inUse)
        .help(candidate.inUse ? String(localized: "Önce bu klasörü kullanan Claude'u kapat.") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var detail: String {
        var parts: [String] = []
        if !candidate.launchers.isEmpty {
            let names = candidate.launchers.map(\.name).joined(separator: ", ")
            parts.append(String(localized: "\(names) açıyordu"))
        }
        if let lastUsed = candidate.lastUsed {
            let relative = lastUsed.formatted(.relative(presentation: .named))
            parts.append(String(localized: "Son kullanım: \(relative)"))
        }
        return parts.joined(separator: " · ")
    }
}
