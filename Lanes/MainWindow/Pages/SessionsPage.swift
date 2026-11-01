import LanesCore
import SwiftUI

/// Every account's Claude Code sessions in one list, newest first. Read
/// from file names and dates only: the conversations stay unopened.
struct SessionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [Row] = []
    @State private var projects: [ProjectRow] = []
    @State private var filter: ProfileID?
    @State private var search = ""
    @State private var isLoading = true
    @AppStorage("sessionsPageMode") private var mode: Mode = .sessions

    enum Mode: String, CaseIterable {
        case sessions, projects
    }

    struct Row: Identifiable {
        var profile: Profile
        var session: ClaudeCodeSessionList.Session
        /// The project's folder name, read back from Claude Code's encoded
        /// folder name ("-Users-u-my-app" shows as "my-app").
        var project: String
        var id: String { "\(profile.id.rawValue)/\(session.id)" }
    }

    struct ProjectRow: Identifiable, Sendable {
        var project: ProjectMap.Project
        var name: String
        /// The project's folder on disk, when it still exists.
        var path: String?
        /// The folder is a git repository's main checkout (its `.git` is a
        /// folder), so a worktree can be made from it.
        var isGitRepository = false
        var id: String { project.id }
    }

    var body: some View {
        // The list always exists; loading and the empty state lie over it,
        // so nothing jumps when the scan finishes.
        Group {
            switch mode {
            case .sessions:
                List(visibleRows) { row in
                    SessionRow(row: row)
                }
            case .projects:
                List(visibleProjects) { row in
                    ProjectRowView(row: row)
                }
            }
        }
        .listStyle(.inset)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .contentMargins(.bottom, DS.Metrics.noticeClearance, for: .scrollContent)
        .overlay {
            if isLoading && rows.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .dsEmptyState(!isLoading && isEmpty) {
            DSEmptyState(
                mode == .sessions ? "Oturum yok" : "Proje yok",
                systemImage: mode == .sessions ? Destination.sessions.symbol : "folder",
                description: mode == .sessions
                    ? Text("Claude Code oturumları burada görünür. Lanes konuşmaların içini okumaz.")
                    : Text("Claude Code'u açtığın klasörler burada görünür.")
            )
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Projede ara")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Görünüm", selection: $mode) {
                    Text("Oturumlar").tag(Mode.sessions)
                    Text("Projeler").tag(Mode.projects)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Hesap", selection: $filter) {
                    Text("Tüm hesaplar").tag(ProfileID?.none)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .help("Yenile")
                .disabled(isLoading)
            }
        }
        // A session Claude Code just wrote shows up without a manual
        // refresh. A new write cancels the pending load, so a busy session
        // rescans at most every few seconds.
        .task(id: model.claudeCodeWriteCount) {
            if !rows.isEmpty {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
            }
            await load()
        }
    }

    private var isEmpty: Bool {
        mode == .sessions ? visibleRows.isEmpty : visibleProjects.isEmpty
    }

    private var visibleRows: [Row] {
        rows.filter { row in
            (filter == nil || row.profile.id == filter)
                && (search.isEmpty || row.project.localizedCaseInsensitiveContains(search))
        }
    }

    private var visibleProjects: [ProjectRow] {
        projects.filter { row in
            (filter == nil || row.project.uses.contains { $0.profileID == filter })
                && (search.isEmpty
                    || row.name.localizedCaseInsensitiveContains(search)
                    || (row.path ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    /// Scans every account's session folder off the main actor (file names
    /// and dates only), then shows the result here.
    private func load() async {
        isLoading = true
        let profiles = model.library.profiles
        let folders = profiles.map { profile in
            model.paths.effectiveClaudeCodeConfigDirectory(for: profile)
                .appendingPathComponent("projects", isDirectory: true)
        }
        let ids = profiles.map(\.id)
        let scanned = await Task.detached(priority: .userInitiated) {
            SessionScan.scan(folders, ids: ids)
        }.value
        var collected: [Row] = []
        for (profile, sessions) in zip(profiles, scanned.items) {
            for item in sessions {
                collected.append(Row(profile: profile, session: item.session, project: item.project))
            }
        }
        rows = collected.sorted { $0.session.modifiedAt > $1.session.modifiedAt }
        projects = scanned.projects
        isLoading = false
    }
}

/// The pure file scan, kept off the main actor.
private enum SessionScan {
    struct Item: Sendable {
        var session: ClaudeCodeSessionList.Session
        var project: String
    }

    struct Result: Sendable {
        /// One list per folder, in the same order as the folders.
        var items: [[Item]]
        var projects: [SessionsPage.ProjectRow]
    }

    static func scan(_ folders: [URL], ids: [ProfileID]) -> Result {
        var names: [String: String] = [:]
        var paths: [String: String?] = [:]
        func resolve(_ folderName: String) -> (name: String, path: String?) {
            if let name = names[folderName], let path = paths[folderName] {
                return (name, path)
            }
            let path = ClaudeCodeProjectName.path(forFolderName: folderName)
            let name = ClaudeCodeProjectName.name(forFolderName: folderName, resolvedPath: path)
            names[folderName] = name
            paths[folderName] = .some(path)
            return (name, path)
        }
        let lists = folders.map(ClaudeCodeSessionList.read)
        let items = lists.map { list -> [Item] in
            list.sessions.map { session in
                Item(session: session, project: resolve(session.projectFolderName).name)
            }
        }
        let map = ProjectMap(lists: Array(zip(ids, lists)).map { (profileID: $0.0, sessions: $0.1) })
        let projects = map.projects.map { project -> SessionsPage.ProjectRow in
            let resolved = resolve(project.folderName)
            let isRepository = resolved.path.map { GitWorktree.isMainCheckout(URL(fileURLWithPath: $0, isDirectory: true)) } ?? false
            return SessionsPage.ProjectRow(project: project, name: resolved.name, path: resolved.path, isGitRepository: isRepository)
        }
        return Result(items: items, projects: projects)
    }
}

/// One project: the accounts that worked in it, when, and a warning when
/// accounts of different kinds shared the folder.
private struct ProjectRowView: View {
    @Environment(AppModel.self) private var model
    let row: SessionsPage.ProjectRow
    @State private var isMakingWorktree = false

    var body: some View {
        let profiles = row.project.uses.compactMap { model.profile(withID: $0.profileID) }
        let mixes = row.project.mixesClasses { model.profile(withID: $0)?.accountClass }
        let working = profiles.first { model.claudeCodeWorkingFolder(for: $0.id) == row.project.folderName }
        HStack(alignment: .center, spacing: DS.Space.m) {
            MonogramStack(profiles: profiles)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    Text(row.name)
                        .font(DS.Typography.rowTitle.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.path ?? row.name)
                    if let working {
                        ClaudeCodePulseIcon(pulse: .working, project: row.name)
                            .help(String(localized: "Claude Code şu an \(working.name) hesabıyla çalışıyor (tahmini)"))
                    }
                    if mixes {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(DS.Palette.warning)
                            .help("Farklı türde hesaplar çalıştı (\(classNames(profiles))). Oturum bilgileri karışmış olabilir.")
                            .accessibilityLabel(Text("Farklı türde hesaplar"))
                    } else if row.project.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Bu projede birden fazla hesap çalıştı.")
                            .accessibilityLabel(Text("Birden fazla hesap"))
                    }
                }
                Text(summary(profiles))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let path = row.path {
                    DSPathText(url: PathRow.displayURL(for: URL(fileURLWithPath: path, isDirectory: true)))
                } else {
                    Text("Klasör bulunamadı")
                        .font(DS.Typography.path)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionsMenu(profiles)
        }
        .padding(.vertical, DS.Space.xxs)
        .contextMenu {
            menuItems(profiles)
        }
        .sheet(isPresented: $isMakingWorktree) {
            if let path = row.path {
                WorktreeSheet(repository: URL(fileURLWithPath: path, isDirectory: true), suggestedProfileID: profiles.first { !$0.isArchived }?.id)
            }
        }
    }

    private func summary(_ profiles: [Profile]) -> String {
        let names = profiles.map(\.name).formatted(.list(type: .and))
        let when = row.project.lastUsed.formatted(.relative(presentation: .named))
        return String(localized: "\(row.project.sessionCount) oturum · \(when) · \(names)")
    }

    private func classNames(_ profiles: [Profile]) -> String {
        var seen: [AccountClass] = []
        for profile in profiles where !seen.contains(profile.accountClass) {
            seen.append(profile.accountClass)
        }
        return seen.map(\.displayName).formatted(.list(type: .and))
    }

    private func actionsMenu(_ profiles: [Profile]) -> some View {
        Menu("Aç") {
            menuItems(profiles)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .fixedSize()
    }

    @ViewBuilder
    private func menuItems(_ profiles: [Profile]) -> some View {
        if let path = row.path {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            let others = model.library.activeProfiles.filter { candidate in !profiles.contains { $0.id == candidate.id } }
            Section("Claude Code'u Aç") {
                ForEach(profiles) { profile in
                    Button(profile.name) {
                        model.openClaudeCode(profile, in: folder)
                    }
                }
                if !others.isEmpty {
                    Menu("Başka Hesapla") {
                        ForEach(others) { profile in
                            Button(profile.name) {
                                model.openClaudeCode(profile, in: folder)
                            }
                        }
                    }
                }
            }
        }
        Section("Son Oturumu Sürdür") {
            ForEach(row.project.uses, id: \.profileID) { use in
                if let profile = model.profile(withID: use.profileID) {
                    Button(profile.name) {
                        model.resume(newestSession(of: use), of: profile)
                    }
                }
            }
            if model.library.activeProfiles.count > 1 {
                Menu("Başka Hesapla Sürdür") {
                    ForEach(row.project.uses, id: \.profileID) { use in
                        if let source = model.profile(withID: use.profileID) {
                            if row.project.uses.count > 1 {
                                Menu(source.name) {
                                    handoffTargets(newestSession(of: use), from: source)
                                }
                            } else {
                                handoffTargets(newestSession(of: use), from: source)
                            }
                        }
                    }
                }
            }
        }
        if row.isGitRepository, row.path != nil {
            Divider()
            Button("Yeni Worktree'de Başlat…") {
                isMakingWorktree = true
            }
        }
        if let path = row.path {
            Divider()
            Button("Finder'da Göster") {
                SystemActions.reveal(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
    }

    private func newestSession(of use: ProjectMap.Use) -> ClaudeCodeSessionList.Session {
        ClaudeCodeSessionList.Session(id: use.newestSessionID, projectFolderName: row.project.folderName, modifiedAt: use.lastUsed)
    }

    @ViewBuilder
    private func handoffTargets(_ session: ClaudeCodeSessionList.Session, from source: Profile) -> some View {
        ForEach(model.library.activeProfiles.filter { $0.id != source.id }) { target in
            Button(target.name) {
                model.continueSession(session, of: source, with: target)
            }
        }
    }
}

/// Up to three account monograms overlapping, then "+N".
private struct MonogramStack: View {
    let profiles: [Profile]

    var body: some View {
        let shown = Array(profiles.prefix(3))
        ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, profile in
                MonogramView(profile: profile, size: DS.Monogram.row)
                    .padding(.leading, CGFloat(index) * DS.Monogram.row * 0.55)
            }
        }
        .frame(width: DS.Monogram.row * (1 + 0.55 * 2), alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            if profiles.count > 3 {
                Text(verbatim: "+\(profiles.count - 3)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(profiles.map(\.name).formatted(.list(type: .and))))
    }
}

private struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let row: SessionsPage.Row

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            MonogramView(profile: row.profile, size: DS.Monogram.row)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(row.project)
                    .font(DS.Typography.rowTitle.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.project)
                Text("\(row.profile.name) · \(row.session.modifiedAt.formatted(.relative(presentation: .named)))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(row.session.id)
                    .font(DS.Typography.path)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Sürdür") {
                model.resume(row.session, of: row.profile)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.vertical, DS.Space.xxs)
        .contextMenu {
            Button("Sürdür") {
                model.resume(row.session, of: row.profile)
            }
            let others = model.library.activeProfiles.filter { $0.id != row.profile.id }
            if !others.isEmpty {
                Menu("Başka Hesapla Sürdür") {
                    ForEach(others) { target in
                        Button(target.name) {
                            model.continueSession(row.session, of: row.profile, with: target)
                        }
                    }
                }
            }
            Button("Kimliği Kopyala") {
                SystemActions.copy(row.session.id)
            }
        }
    }
}

/// "Worktree Fırlatıcı": a branch name and an account, then git makes the
/// worktree next to the repository and Claude Code starts in it.
private struct WorktreeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repository: URL
    let suggestedProfileID: ProfileID?
    @State private var branch = ""
    @State private var profileID: ProfileID?
    @State private var error: String?
    @State private var isWorking = false
    @State private var hasGit = GitWorktree.isAvailable

    var body: some View {
        Form {
            if !hasGit {
                Section {
                    DSStatusRow(.warning, title: Text("Xcode Komut Satırı Araçları gerekiyor")) {
                        Text("Bu Mac'te git kurulu değil. Kurulum bitince Yeniden Dene'ye bas.")
                    } accessory: {
                        HStack {
                            Button("Araçları Kur…") {
                                GitWorktree.installCommandLineTools()
                            }
                            Button("Yeniden Dene") {
                                hasGit = GitWorktree.isAvailable
                            }
                        }
                    }
                }
            }
            Section {
                LabeledContent("Depo", value: repository.lastPathComponent)
                TextField("Dal", text: $branch, prompt: Text("feature/giris"))
                    .font(DS.Typography.code)
                Picker("Hesap", selection: $profileID) {
                    ForEach(model.library.activeProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if WorktreePlan.isValidBranchName(branch) {
                        Text("Klasör: \(targetFolder.path)")
                            .textSelection(.enabled)
                        if folderExists {
                            Text("Bu klasör zaten var. Başka bir dal adı seç.")
                                .foregroundStyle(DS.Palette.warning)
                        }
                    }
                    if let error {
                        Text(error)
                            .foregroundStyle(DS.Palette.warning)
                    }
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Oluştur ve Başlat") {
                    start()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasGit || isWorking || !WorktreePlan.isValidBranchName(branch) || folderExists || selectedProfile == nil)
            }
        }
        .interactiveDismissDisabled(isWorking)
        .presentationSizing(.form)
        .onAppear {
            let suggested = suggestedProfileID.flatMap(model.profile(withID:)).flatMap { $0.isArchived ? nil : $0 }
            let profile = suggested ?? model.library.activeProfiles.first
            profileID = profile?.id
            branch = WorktreePlan.suggestedBranch(accountName: profile?.name ?? "", date: Date())
        }
    }

    private var selectedProfile: Profile? {
        profileID.flatMap(model.profile(withID:))
    }

    private var targetFolder: URL {
        WorktreePlan.folder(forRepository: repository, branch: branch)
    }

    private var folderExists: Bool {
        FileManager.default.fileExists(atPath: targetFolder.path)
    }

    private func start() {
        guard let profile = selectedProfile else { return }
        isWorking = true
        error = nil
        Task {
            let failure = await model.launchWorktree(repository: repository, branch: branch, with: profile)
            isWorking = false
            if let failure {
                error = failure
            } else {
                dismiss()
            }
        }
    }
}
