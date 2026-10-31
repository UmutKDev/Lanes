import LanesCore
import SwiftUI

/// Every account's Claude Code sessions in one list, newest first. Read
/// from file names and dates only: the conversations stay unopened.
struct SessionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [Row] = []
    @State private var filter: ProfileID?
    @State private var search = ""
    @State private var isLoading = true

    struct Row: Identifiable {
        var profile: Profile
        var session: ClaudeCodeSessionList.Session
        /// The project's folder name, read back from Claude Code's encoded
        /// folder name ("-Users-u-my-app" shows as "my-app").
        var project: String
        var id: String { "\(profile.id.rawValue)/\(session.id)" }
    }

    var body: some View {
        // The list always exists; loading and the empty state lie over it,
        // so nothing jumps when the scan finishes.
        List(visibleRows) { row in
            SessionRow(row: row)
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
        .dsEmptyState(!isLoading && visibleRows.isEmpty) {
            DSEmptyState(
                "Oturum yok",
                systemImage: Destination.sessions.symbol,
                description: Text("Bir hesapla Claude Code'u açtığında oturumları burada görünür. Lanes yalnız oturum dosyalarının adına ve tarihine bakar, içlerini açmaz.")
            )
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Projede ara")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Hesap", selection: $filter) {
                    Text("Tüm hesaplar").tag(ProfileID?.none)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Hesap")
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
        .task { await load() }
    }

    private var visibleRows: [Row] {
        rows.filter { row in
            (filter == nil || row.profile.id == filter)
                && (search.isEmpty || row.project.localizedCaseInsensitiveContains(search))
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
        let scanned = await Task.detached(priority: .userInitiated) {
            SessionScan.scan(folders)
        }.value
        var collected: [Row] = []
        for (profile, sessions) in zip(profiles, scanned) {
            for item in sessions {
                collected.append(Row(profile: profile, session: item.session, project: item.project))
            }
        }
        rows = collected.sorted { $0.session.modifiedAt > $1.session.modifiedAt }
        isLoading = false
    }
}

/// The pure file scan, kept off the main actor.
private enum SessionScan {
    struct Item: Sendable {
        var session: ClaudeCodeSessionList.Session
        var project: String
    }

    /// One list per folder, in the same order as `folders`.
    static func scan(_ folders: [URL]) -> [[Item]] {
        var names: [String: String] = [:]
        return folders.map { folder -> [Item] in
            ClaudeCodeSessionList.read(folder).sessions.map { session -> Item in
                let folderName = session.projectFolderName
                let project: String
                if let known = names[folderName] {
                    project = known
                } else {
                    project = projectName(forFolderName: folderName)
                    names[folderName] = project
                }
                return Item(session: session, project: project)
            }
        }
    }

    /// The last part of the project's real path when it still exists, so
    /// "my-app" stays "my-app". Otherwise the encoded name without the home
    /// folder prefix, which the row truncates in the middle.
    static func projectName(forFolderName folderName: String) -> String {
        let path = ClaudeCodeSessionList.projectPath(forFolderName: folderName) { candidate in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        if let path {
            let last = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            if !last.isEmpty && last != "/" {
                return last
            }
        }
        let home = NSHomeDirectory()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let prefix = home + "-"
        if folderName.hasPrefix(prefix), folderName.count > prefix.count {
            return String(folderName.dropFirst(prefix.count))
        }
        return folderName
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
            .help("Bu oturumu \(row.profile.name) hesabıyla, kendi proje klasöründe Terminalde sürdür")
        }
        .padding(.vertical, DS.Space.xxs)
        .contextMenu {
            Button("Sürdür") {
                model.resume(row.session, of: row.profile)
            }
            Button("Kimliği Kopyala") {
                SystemActions.copy(row.session.id)
            }
        }
    }
}
