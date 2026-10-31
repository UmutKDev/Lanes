import AppKit
import LanesCore
import SwiftUI

/// Claude Code items shared by every account: CLAUDE.md, commands, agents,
/// skills and MCP servers, kept once in Lanes's Toolbox folder.
struct ToolboxPage: View {
    @Environment(AppModel.self) private var model
    /// Share state per account and item, keyed by `key(_:_:)`. Kept here so
    /// a switch flips with its animation instead of the whole list rebuilding.
    @State private var states: [String: Toolbox.ItemState] = [:]
    @State private var mcpText = ""
    @State private var mcpStatus: String?
    @State private var mcpSaved = false

    private var toolbox: Toolbox { Toolbox(paths: model.paths) }

    var body: some View {
        Form {
            Section {
                PathRow(url: toolbox.directory)
            } footer: {
                footerText("Paylaşılan bir öğe Araç Kutusu klasöründe bir kez durur ve seçtiğin hesapların Claude Code klasörüne bağlanır. Birinde değiştirdiğin komut ya da ajan hepsinde değişir. Hesabın kendine ait aynı adlı bir öğesi varsa Lanes ona dokunmaz.")
            }
            if !model.library.profiles.isEmpty {
                Section {
                    shareMatrix
                }
            }
            Section {
                TextEditor(text: $mcpText)
                    .font(DS.Typography.code)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.s)
                    .background(DS.Palette.codeFill, in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
                    .frame(minHeight: 140, maxHeight: 260)
                HStack(alignment: .center, spacing: DS.Space.s) {
                    Button("Kaydet", action: saveMCP)
                        .fixedSize()
                    if let mcpStatus {
                        DSStatusIcon(status: mcpSaved ? .ok : .error)
                        Text(mcpStatus)
                            .font(DS.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .help(mcpStatus)
                    }
                    Spacer(minLength: 0)
                }
                .animation(DS.Motion.standard, value: mcpStatus)
            } header: {
                Text("MCP sunucuları")
            } footer: {
                footerText("claude --mcp-config biçiminde. Lanes'ten açılan her Claude Code bu sunucuları da yükler (\"Klasörde Aç\", oturum sürdürme). Anahtar ya da parola yazacaksan bu dosyanın Mac'inde düz metin durduğunu unutma.")
            }
        }
        .libraryForm()
        .onAppear {
            loadMCP()
            reloadStates()
        }
        .onChange(of: model.library.profiles.map(\.id)) { _, _ in
            reloadStates()
        }
    }

    /// Accounts as rows, the four items as columns: one switch per cell, or
    /// a person symbol when the account has its own item of that name.
    private var shareMatrix: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.s) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Toolbox.Item.allCases) { item in
                    Text(verbatim: item.rawValue)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(item.title)
                        .gridColumnAlignment(.center)
                }
            }
            ForEach(model.library.profiles) { profile in
                Divider()
                GridRow {
                    DSAccountLabel(profile: profile)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Toolbox.Item.allCases) { item in
                        cell(item, profile: profile)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: Toolbox.Item, profile: Profile) -> some View {
        let folder = model.paths.effectiveClaudeCodeConfigDirectory(for: profile)
        let state = states[key(profile, item)] ?? toolbox.state(of: item, inAccountFolder: folder)
        switch state {
        case .own:
            Image(systemName: "person.crop.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .help("Hesabın kendi \(item.rawValue) öğesi var")
                .accessibilityLabel(Text("Hesabın kendi \(item.rawValue) öğesi var"))
        case .shared, .absent:
            Toggle("Paylaş", isOn: Binding(
                get: { state == .shared },
                set: { on in toggle(item, profile: profile, folder: folder, on: on) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(item.title)
        }
    }

    private func key(_ profile: Profile, _ item: Toolbox.Item) -> String {
        "\(profile.id.rawValue)/\(item.rawValue)"
    }

    private func reloadStates() {
        var fresh: [String: Toolbox.ItemState] = [:]
        for profile in model.library.profiles {
            let folder = model.paths.effectiveClaudeCodeConfigDirectory(for: profile)
            for item in Toolbox.Item.allCases {
                fresh[key(profile, item)] = toolbox.state(of: item, inAccountFolder: folder)
            }
        }
        states = fresh
    }

    private func toggle(_ item: Toolbox.Item, profile: Profile, folder: URL, on: Bool) {
        do {
            if on {
                try toolbox.share(item, inAccountFolder: folder)
            } else {
                try toolbox.unshare(item, inAccountFolder: folder)
            }
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: error.localizedDescription)
        }
        let newState = toolbox.state(of: item, inAccountFolder: folder)
        withAnimation(DS.Motion.standard) {
            states[key(profile, item)] = newState
        }
    }

    private func footerText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadMCP() {
        mcpText = (try? String(contentsOf: toolbox.mcpConfigFile, encoding: .utf8)) ?? MCPConfig.template
    }

    private func saveMCP() {
        let data = Data(mcpText.utf8)
        do {
            let names = try MCPConfig.serverNames(in: data)
            try FileManager.default.createDirectory(at: toolbox.directory, withIntermediateDirectories: true)
            try data.write(to: toolbox.mcpConfigFile, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: toolbox.mcpConfigFile.path)
            mcpSaved = true
            mcpStatus = names.isEmpty
                ? String(localized: "Kaydedildi. Liste boş.")
                : String(localized: "Kaydedildi: \(names.joined(separator: ", "))")
        } catch MCPConfig.Failure.noServerList {
            mcpSaved = false
            mcpStatus = String(localized: "Kaydedilmedi: \"mcpServers\" nesnesi yok.")
        } catch {
            mcpSaved = false
            mcpStatus = String(localized: "Kaydedilmedi: geçerli bir JSON değil.")
        }
    }
}

extension Toolbox.Item {
    var title: String {
        switch self {
        case .claudeMD: return String(localized: "CLAUDE.md (genel talimatlar)")
        case .commands: return String(localized: "Komutlar (commands)")
        case .agents: return String(localized: "Ajanlar (agents)")
        case .skills: return String(localized: "Beceriler (skills)")
        }
    }
}
