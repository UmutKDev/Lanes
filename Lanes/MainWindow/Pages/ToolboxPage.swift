import AppKit
import LanesCore
import SwiftUI

/// Claude Code items shared by every account: CLAUDE.md, commands, agents,
/// skills and MCP servers, kept once in Lanes's Toolbox folder.
struct ToolboxPage: View {
    @Environment(AppModel.self) private var model
    @State private var refresh = 0
    @State private var error: String?
    @State private var mcpText = ""
    @State private var mcpStatus: String?

    private var toolbox: Toolbox { Toolbox(paths: model.paths) }

    var body: some View {
        Form {
            Section {
                Text("Paylaşılan bir öğe Araç Kutusu klasöründe bir kez durur ve seçtiğin hesapların Claude Code klasörüne bağlanır. Birinde değiştirdiğin komut ya da ajan hepsinde değişir. Hesabın kendine ait aynı adlı bir öğesi varsa Lanes ona dokunmaz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PathRow(url: toolbox.directory)
            }
            ForEach(Toolbox.Item.allCases) { item in
                Section(item.title) {
                    ForEach(model.library.profiles) { profile in
                        itemRow(item, profile: profile)
                    }
                }
            }
            .id(refresh)
            Section("MCP sunucuları") {
                TextEditor(text: $mcpText)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 140)
                HStack {
                    Button("Kaydet", action: saveMCP)
                    if let mcpStatus {
                        Text(mcpStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("claude --mcp-config biçiminde. Lanes'ten açılan her Claude Code bu sunucuları da yükler (\"Klasörde Aç\", oturum sürdürme). Anahtar ya da parola yazacaksan bu dosyanın Mac'inde düz metin durduğunu unutma.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadMCP)
    }

    @ViewBuilder
    private func itemRow(_ item: Toolbox.Item, profile: Profile) -> some View {
        let folder = model.paths.effectiveClaudeCodeConfigDirectory(for: profile)
        let state = toolbox.state(of: item, inAccountFolder: folder)
        HStack {
            Text(profile.name)
            Spacer()
            switch state {
            case .own:
                Text("Hesabın kendi \(item.rawValue) öğesi var")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .shared, .absent:
                Toggle("Paylaş", isOn: Binding(
                    get: { state == .shared },
                    set: { on in toggle(item, folder: folder, on: on) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private func toggle(_ item: Toolbox.Item, folder: URL, on: Bool) {
        do {
            if on {
                try toolbox.share(item, inAccountFolder: folder)
            } else {
                try toolbox.unshare(item, inAccountFolder: folder)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh += 1
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
            mcpStatus = names.isEmpty
                ? String(localized: "Kaydedildi. Liste boş.")
                : String(localized: "Kaydedildi: \(names.joined(separator: ", "))")
        } catch MCPConfig.Failure.noServerList {
            mcpStatus = String(localized: "Kaydedilmedi: \"mcpServers\" nesnesi yok.")
        } catch {
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
