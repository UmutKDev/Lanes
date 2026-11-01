import AppKit
import LanesCore
import SwiftUI
import UniformTypeIdentifiers

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
    /// Server names in the saved `mcp.json`, and whether each is remote.
    @State private var savedServers: [(name: String, isRemote: Bool)] = []
    @State private var mcpAccounts = MCPAccountSettings()

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
            if !savedServers.isEmpty, !model.library.profiles.isEmpty {
                Section {
                    mcpMatrix
                } header: {
                    Text("MCP Stüdyosu")
                } footer: {
                    footerText("Hangi hesabın Claude Code'unun hangi sunucuyu yükleyeceğini seç. Yeni bir sunucu ya da hesap başta açıktır. Değişiklik yeni başlatılan oturumlarda geçerli olur. Claude uygulamasının kendi MCP ayarlarına ve hesapların kendi Claude Code ayarlarına dokunulmaz.")
                }
            }
            Section {
                HStack(spacing: DS.Space.s) {
                    Button("Ekip Paketini Dışa Aktar…", action: exportPack)
                    Button("Ekip Paketini İçe Aktar…", action: importPack)
                    Spacer(minLength: 0)
                }
            } header: {
                Text("Ekip Paketi")
            } footer: {
                footerText("Araç Kutusu'nu tek bir dosyada bir ekip arkadaşına ver: MCP sunucuları, CLAUDE.md, komutlar, ajanlar ve beceriler. Ortam değişkenleri ve başlıkların değerleri dosyaya yazılmaz, yalnız adları; arkadaşın kendi anahtarını girer. Sunucu argümanlarına anahtar yazdıysan dışa aktarmadan önce çıkar. İçe aktarırken aynı adlı sunucu ve dosyalar olduğu gibi kalır.")
            }
        }
        .libraryForm()
        .onAppear {
            loadMCP()
            reloadStates()
        }
        .onChange(of: model.library.profiles.map(\.id)) { _, _ in
            reloadStates()
            reloadServers()
        }
    }

    /// Accounts as rows, the four items as columns: one switch per cell, or
    /// a "Kendi" caption when the account has its own item of that name.
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
            Text("Kendi")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
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

    /// Servers as rows, accounts as columns: one switch per cell.
    private var mcpMatrix: some View {
        let profiles = model.library.profiles.filter { !$0.isArchived }
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.s) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(profiles) { profile in
                        MonogramView(profile: profile, size: DS.Monogram.tiny, isRunning: false)
                            .help(profile.name)
                            .accessibilityLabel(Text(profile.name))
                            .gridColumnAlignment(.center)
                    }
                }
                ForEach(savedServers, id: \.name) { server in
                    Divider()
                    GridRow {
                        Label {
                            Text(verbatim: server.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: server.isRemote ? "globe" : "terminal")
                                .foregroundStyle(.secondary)
                        }
                        .help(server.isRemote ? "Uzak sunucu (adres)" : "Bu Mac'te çalışan komut")
                        .frame(minWidth: 140, alignment: .leading)
                        ForEach(profiles) { profile in
                            Toggle(isOn: Binding(
                                get: { mcpAccounts.isEnabled(server.name, for: profile.id) },
                                set: { on in setServer(server.name, enabled: on, for: profile.id) }
                            )) {
                                Text("\(server.name), \(profile.name)")
                            }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .help("\(profile.name): \(server.name)")
                        }
                    }
                }
            }
            .padding(.vertical, DS.Space.xxs)
        }
        .scrollIndicators(.automatic)
    }

    private func setServer(_ name: String, enabled: Bool, for id: ProfileID) {
        var updated = mcpAccounts
        updated.set(name, enabled: enabled, for: id)
        do {
            try updated.save(to: toolbox.mcpAccountsFile)
            withAnimation(DS.Motion.standard) { mcpAccounts = updated }
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: error.localizedDescription)
        }
    }

    /// Reads the saved server list (not the editor's unsaved text) and
    /// drops switches for servers and accounts that are gone.
    private func reloadServers() {
        let parsed = (try? Data(contentsOf: toolbox.mcpConfigFile)).flatMap { try? MCPConfig.servers(in: $0) }
        let servers = parsed ?? [:]
        savedServers = servers.keys.sorted().map { (name: $0, isRemote: MCPConfig.isRemote(servers[$0] ?? .null)) }
        var settings = MCPAccountSettings.load(from: toolbox.mcpAccountsFile)
        // Forget switches only when both lists were really read; a file
        // that can't be read for a moment must not turn servers back on.
        if let parsed, !model.library.profiles.isEmpty {
            let before = settings
            settings.prune(servers: Set(parsed.keys), profiles: Set(model.library.profiles.map(\.id)))
            if settings != before {
                try? settings.save(to: toolbox.mcpAccountsFile)
            }
        }
        mcpAccounts = settings
    }

    private func exportPack() {
        let made: (pack: TeamPack, skipped: [String])
        do {
            made = try TeamPack.make(from: toolbox)
        } catch TeamPack.Failure.tooLarge {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "Araç Kutusu bir ekip paketi için fazla büyük (en çok 8 MB metin)."))
            return
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "Ekip paketi hazırlanamadı: \(error.localizedDescription)"))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: TeamPack.fileExtension) ?? .json]
        panel.nameFieldStringValue = "Ekip Paketi.\(TeamPack.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try made.pack.encoded().write(to: url, options: .atomic)
            var message = String(localized: "Ekip paketi kaydedildi: \(made.pack.mcpServers.count) sunucu, \(made.pack.files.count) dosya.")
            if !made.pack.blanked.isEmpty {
                message += " " + String(localized: "Değeri yazılmayanlar: \(made.pack.blanked.joined(separator: ", ")).")
            }
            if !made.skipped.isEmpty {
                message += " " + String(localized: "Metin olmadığı ya da büyük olduğu için alınmayanlar: \(made.skipped.joined(separator: ", ")).")
            }
            model.notice = AppModel.Notice(kind: .info, message: message)
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "Ekip paketi yazılamadı: \(error.localizedDescription)"))
        }
    }

    private func importPack() {
        let saved = (try? String(contentsOf: toolbox.mcpConfigFile, encoding: .utf8)) ?? MCPConfig.template
        guard mcpText == saved else {
            model.notice = AppModel.Notice(kind: .warning, message: String(localized: "MCP sunucularında kaydedilmemiş değişiklik var. Önce kaydet, sonra ekip paketini içe aktar."))
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: TeamPack.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try TeamPack.decode(Data(contentsOf: url))
            let result = try pack.install(into: toolbox)
            loadMCP()
            reloadStates()
            var message = String(localized: "Eklendi: \(result.addedServers.count) sunucu, \(result.addedFiles.count) dosya.")
            let skipped = result.skippedServers + result.skippedFiles
            if !skipped.isEmpty {
                message += " " + String(localized: "Zaten olduğu için dokunulmayanlar: \(skipped.joined(separator: ", ")).")
            }
            if !result.blanked.isEmpty {
                message += " " + String(localized: "Değerini MCP sunucuları kutusuna senin yazman gerekenler: \(result.blanked.joined(separator: ", ")).")
            }
            model.notice = AppModel.Notice(kind: .info, message: message)
        } catch TeamPack.Failure.notAPack {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "Bu dosya bir Lanes ekip paketi değil."))
        } catch {
            model.notice = AppModel.Notice(kind: .error, message: String(localized: "Ekip paketi içe aktarılamadı: \(error.localizedDescription)"))
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
        reloadServers()
    }

    private func saveMCP() {
        let data = Data(mcpText.utf8)
        do {
            let names = try MCPConfig.serverNames(in: data)
            try FileManager.default.createDirectory(at: toolbox.directory, withIntermediateDirectories: true)
            try data.write(to: toolbox.mcpConfigFile, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: toolbox.mcpConfigFile.path)
            reloadServers()
            mcpSaved = true
            mcpStatus = names.isEmpty
                ? String(localized: "Kaydedildi. Liste boş.")
                : String(localized: "Kaydedildi: \(names.joined(separator: ", "))")
        } catch MCPConfig.Failure.noServerList {
            mcpSaved = false
            mcpStatus = String(localized: "Kaydedilmedi: \"mcpServers\" nesnesi yok.")
        } catch MCPConfig.Failure.notJSON {
            mcpSaved = false
            mcpStatus = String(localized: "Kaydedilmedi: geçerli bir JSON değil.")
        } catch {
            // The JSON was fine; the folder or file could not be written
            // (permissions, full disk), so say that instead.
            mcpSaved = false
            mcpStatus = String(localized: "Kaydedilmedi: \(error.localizedDescription)")
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
