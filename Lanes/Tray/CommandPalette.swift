import AppKit
import LanesCore
import Observation
import SwiftUI

/// "Komut Paleti": a Spotlight-like panel in the middle of the screen that
/// finds accounts, scenes, Claude Code projects and Lanes pages with one
/// fuzzy search. It takes the keyboard without activating Lanes, so the app
/// the user was in stays in front behind it.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private weak var router: WindowRouter?
    private var panel: CommandPanel?
    private let state = PaletteState()

    init(model: AppModel, router: WindowRouter) {
        self.model = model
        self.router = router
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.refreshInstances()
        state.presentation += 1
        loadSessionFolders()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> CommandPanel {
        let root = PaletteView(state: state, items: { [weak self] in self?.items() ?? [] }, onClose: { [weak self] in self?.close() })
            .environment(model)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = CommandPanel(content: hosting)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }

    /// Centred on the screen with the pointer, a quarter down from the top.
    private func position(_ panel: CommandPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.anchoredTop = visible.maxY - visible.height * 0.22
        panel.minimumBottom = visible.minY + 8
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: 0, width: size.width, height: size.height), display: true)
    }

    /// The project folders of each account's Claude Code sessions, as the
    /// Projects view lists them, read off the main thread. Only folder and
    /// file names are read; nothing is opened.
    private func loadSessionFolders() {
        let model = model
        let folders = model.library.activeProfiles.map { profile in
            (profile.id, model.paths.effectiveClaudeCodeConfigDirectory(for: profile).appendingPathComponent("projects", isDirectory: true))
        }
        let state = state
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> [ProfileID: [String]] in
                var result: [ProfileID: [String]] = [:]
                for (id, projects) in folders {
                    var seen = Set<String>()
                    for session in ClaudeCodeSessionList.read(projects).sessions where seen.insert(session.projectFolderName).inserted {
                        if let path = ClaudeCodeProjectName.path(forFolderName: session.projectFolderName) {
                            result[id, default: []].append(path)
                        }
                    }
                }
                return result
            }.value
            state.sessionFolders = found
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    // MARK: Items

    private func items() -> [PaletteItem] {
        var items: [PaletteItem] = []
        let model = model
        for profile in model.profilesByRecentUse {
            let running = model.isRunning(profile)
            items.append(PaletteItem(
                id: "account:\(profile.id.rawValue)",
                title: profile.name,
                subtitle: running ? String(localized: "Öne getir") : String(localized: "Aç"),
                kind: .account(profile),
                run: { model.open(profile) }
            ))
            items.append(PaletteItem(
                id: "code:\(profile.id.rawValue)",
                title: String(localized: "\(profile.name) · Claude Code"),
                subtitle: String(localized: "Terminalde aç"),
                kind: .claudeCode(profile),
                run: { model.openClaudeCode(profile) }
            ))
            for folder in Self.folders(of: profile, model: model, sessionFolders: state.sessionFolders[profile.id] ?? []) {
                items.append(PaletteItem(
                    id: "project:\(profile.id.rawValue):\(folder.path)",
                    title: String(localized: "\(folder.lastPathComponent) · \(profile.name)"),
                    subtitle: PathRow.displayURL(for: folder).path,
                    kind: .project(profile),
                    run: { model.openClaudeCode(profile, in: folder) }
                ))
            }
        }
        for scene in model.library.scenes {
            items.append(PaletteItem(
                id: "scene:\(scene.id.rawValue)",
                title: String(localized: "Sahne: \(scene.name)"),
                subtitle: String(localized: "Sahnedeki hesapları aç"),
                kind: .symbol("rectangle.stack"),
                run: { model.open(scene) }
            ))
        }
        let router = router
        let pages: [Destination] = [.overview, .sessions, .usage, .timesheet, .scenes, .accountMap, .links, .toolbox, .integrations, .setup, .health, .maintenance, .privacy, .settings]
        for page in pages {
            items.append(PaletteItem(
                id: "page:\(page.title)",
                title: page.title,
                subtitle: String(localized: "Lanes sayfası"),
                kind: .symbol(page.symbol),
                run: { router?.showMainWindow(page) }
            ))
        }
        items.append(PaletteItem(id: "action:add", title: String(localized: "Hesap Ekle…"), subtitle: String(localized: "Eylem"), kind: .symbol("plus"), run: { router?.showAddProfile() }))
        if model.closedActiveProfiles.count > 1 {
            items.append(PaletteItem(id: "action:openAll", title: String(localized: "Kapalı Hesapların Tümünü Aç"), subtitle: String(localized: "Eylem"), kind: .symbol("square.stack.3d.up"), run: { model.openAllClosedAccounts() }))
        }
        if model.quittableOpenCount > 0 {
            items.append(PaletteItem(id: "action:quitAll", title: String(localized: "Lanes Hesaplarının Tümünü Kapat"), subtitle: String(localized: "Eylem"), kind: .symbol("xmark.circle"), run: { model.quitAllLanesAccounts() }))
        }
        return items
    }

    /// The account's default, linked and recent Claude Code folders, and
    /// those of its sessions, that still exist, without repeats.
    private static func folders(of profile: Profile, model: AppModel, sessionFolders: [String]) -> [URL] {
        var seen = Set<String>()
        var folders: [URL] = []
        let candidates = [profile.defaultProjectFolder].compactMap { $0 } + profile.linkedFolders
            + model.recentClaudeCodeFolders(for: profile).map(\.path) + sessionFolders
        // Folders the account may not open Claude Code in are left out,
        // so a pick never ends in a warning nobody sees.
        for path in candidates where !seen.contains(path) && profile.allowsFolder(path) {
            seen.insert(path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                folders.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        return folders
    }
}

@MainActor
@Observable
final class PaletteState {
    /// Bumped on every showing, so the view starts fresh.
    var presentation = 0
    /// Project folders of each account's Claude Code sessions, filled in
    /// shortly after the palette opens.
    var sessionFolders: [ProfileID: [String]] = [:]
}

struct PaletteItem: Identifiable {
    enum Kind {
        case account(Profile)
        case claudeCode(Profile)
        case project(Profile)
        case symbol(String)
    }

    let id: String
    let title: String
    let subtitle: String
    let kind: Kind
    let run: @MainActor () -> Void
}

/// The palette: a search field over a ranked list. ↑ ↓ move, Return runs,
/// Escape clears the search or closes.
struct PaletteView: View {
    @Bindable var state: PaletteState
    let items: () -> [PaletteItem]
    let onClose: () -> Void
    @State private var query = ""
    @State private var all: [PaletteItem] = []
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private static let limit = 40

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Hesap, proje, sahne ya da sayfa ara", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit(runSelection)
                    .onKeyPress(.downArrow) {
                        move(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        move(-1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if query.isEmpty { onClose() } else { query = "" }
                        return .handled
                    }
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    // A plain stack: at most 40 rows, and every row is
                    // rebuilt when the results change.
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            PaletteRow(item: item, isSelected: index == selection)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = index
                                    runSelection()
                                }
                        }
                        if results.isEmpty {
                            Text("Sonuç yok")
                                .font(DS.Typography.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Space.l)
                        }
                    }
                    .padding(DS.Space.s)
                }
                .frame(height: 360)
                .onChange(of: selection) {
                    let list = results
                    if list.indices.contains(selection) {
                        proxy.scrollTo(list[selection].id)
                    }
                }
            }
        }
        .frame(width: 560)
        .modifier(PanelSurface())
        .onAppear(perform: refresh)
        .onChange(of: state.presentation) { refresh() }
        // Session folders arrive after the palette opened: add them
        // without clearing what was typed.
        .onChange(of: state.sessionFolders) { all = items() }
        .onChange(of: query) { selection = 0 }
    }

    private func refresh() {
        all = items()
        query = ""
        selection = 0
        isFocused = true
    }

    private var results: [PaletteItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Without a search: accounts, then scenes and actions; no
            // per-folder rows, which would crowd the list.
            return Array(all.filter {
                if case .project = $0.kind { return false }
                if case .claudeCode = $0.kind { return false }
                return true
            }.prefix(Self.limit))
        }
        let scored = all.compactMap { item -> (PaletteItem, Int)? in
            guard let score = FuzzyMatch.score(text, in: item.title) else { return nil }
            return (item, score)
        }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(Self.limit).map(\.0))
    }

    private func move(_ step: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + step + count) % count
    }

    private func runSelection() {
        let list = results
        guard list.indices.contains(selection) else { return }
        let item = list[selection]
        onClose()
        item.run()
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DS.Space.m) {
            icon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs + 2)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.Panel.rowRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case let .account(profile):
            MonogramView(profile: profile, size: 24)
        case let .claudeCode(profile), let .project(profile):
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "terminal")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(profile.color.swatch)
                    .frame(width: 9, height: 9)
            }
        case let .symbol(name):
            Image(systemName: name)
                .font(.body)
                .foregroundStyle(.tint)
        }
    }
}
