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
        var id: String { "\(profile.id.rawValue)/\(session.id)" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Hesap", selection: $filter) {
                    Text("Tüm hesaplar").tag(ProfileID?.none)
                    ForEach(model.library.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .fixedSize()
                TextField("Projede ara", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Button {
                    load()
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
            }
            .padding(12)
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleRows.isEmpty {
                ContentUnavailableView {
                    Label("Oturum yok", systemImage: Destination.sessions.symbol)
                } description: {
                    Text("Bir hesapla Claude Code'u açtığında oturumları burada görünür. Lanes yalnız oturum dosyalarının adına ve tarihine bakar, içlerini açmaz.")
                }
            } else {
                List(visibleRows) { row in
                    SessionRow(row: row)
                }
            }
        }
        .task { load() }
    }

    private var visibleRows: [Row] {
        rows.filter { row in
            (filter == nil || row.profile.id == filter)
                && (search.isEmpty || Self.projectName(row.session.projectFolderName).localizedCaseInsensitiveContains(search))
        }
    }

    private func load() {
        isLoading = true
        let profiles = model.library.profiles
        var collected: [Row] = []
        for profile in profiles {
            for session in model.claudeCodeSessions(for: profile).sessions {
                collected.append(Row(profile: profile, session: session))
            }
        }
        rows = collected.sorted { $0.session.modifiedAt > $1.session.modifiedAt }
        isLoading = false
    }

    /// The last part of the project path, readable without guessing the
    /// rest: "-Users-u-lanes" shows as "lanes".
    static func projectName(_ folderName: String) -> String {
        folderName.split(separator: "-").last.map(String.init) ?? folderName
    }
}

private struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let row: SessionsPage.Row

    var body: some View {
        HStack(spacing: 10) {
            MonogramView(profile: row.profile, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(SessionsPage.projectName(row.session.projectFolderName))
                    .font(.body.weight(.medium))
                Text("\(row.profile.name) · \(row.session.modifiedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(row.session.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Sürdür") {
                model.resume(row.session, of: row.profile)
            }
            .help("Bu oturumu \(row.profile.name) hesabıyla, kendi proje klasöründe Terminalde sürdür")
        }
        .padding(.vertical, 2)
    }
}
