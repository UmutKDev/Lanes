import AppKit
import LanesCore
import SwiftUI
import UniformTypeIdentifiers

/// How much room each account takes, and a way to empty Claude's caches.
struct MaintenancePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            ForEach(model.library.profiles) { profile in
                Section {
                    AccountStorageView(profile: profile)
                } header: {
                    Text(profile.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Section {
                PathRow(url: model.paths.root)
            } header: {
                Text("Yedekleme")
            } footer: {
                Text("Lanes hesap klasörlerini, giriş bilgileri içerdiği için yedeklemez. Time Machine bu klasörü yedekler.")
            }
            AccountListTransferSection()
        }
        .systemForm()
    }
}

/// Saves the account list to a file and adds accounts from one, for a new
/// Mac or a backup. The file holds no sign-in data.
private struct AccountListTransferSection: View {
    @Environment(AppModel.self) private var model
    @State private var result: String?

    var body: some View {
        Section {
            ButtonRow {
                Button("Dışa Aktar…", action: export)
                Button("İçe Aktar…", action: importFile)
            }
        } header: {
            Text("Hesap listesini taşı")
        } footer: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Giriş bilgileri ve sohbetler dosyaya girmez. İçe aktarma yalnız eksik hesapları ve sahneleri ekler.")
                // The result line keeps its place, so the page does not grow
                // when a transfer finishes.
                Text(verbatim: result ?? " ")
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .opacity(result == nil ? 0 : 1)
                    .accessibilityHidden(result == nil)
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "Lanes hesapları.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportLibrary(to: url)
            result = String(localized: "Hesap listesi \(url.lastPathComponent) dosyasına yazıldı.")
        } catch {
            result = String(localized: "Dışa aktarılamadı: \(error.localizedDescription)")
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        result = model.importLibrary(from: url)
    }
}

/// One account's folders with their sizes, and cache cleanup. Used on the
/// Maintenance page and on the account's Storage tab. It emits rows only;
/// the caller wraps them in a `Section`.
struct AccountStorageView: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var sizes: StorageSizes?
    @State private var isMeasuring = false
    @State private var confirmingCleanup = false
    @State private var cleanupMessage: String?

    var body: some View {
        let isRunning = model.isRunning(profile)
        Group {
            row(String(localized: "Claude verisi"), url: model.paths.effectiveDesktopDataDirectory(for: profile), size: sizes?.desktop)
            row(String(localized: "Önbellek"), url: nil, size: sizes?.cache)
            row(String(localized: "Claude Code"), url: model.paths.effectiveClaudeCodeConfigDirectory(for: profile), size: sizes?.claudeCode)
            if CloneCheck.usesClone(profile) {
                row(String(localized: "Klon"), url: model.paths.cloneFolder(for: profile.id), size: sizes?.clone)
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.s) {
                    Button("Önbelleği Temizle…") { confirmingCleanup = true }
                        // Off while measuring too, as when the sizes were
                        // cleared during a re-measure: the old cache size is
                        // still on screen, but the folders may be gone.
                        // Never for the plain Claude.app account: its folders
                        // belong to Claude itself, and Lanes does not change them.
                        .disabled(profile.isDefault || isRunning || isMeasuring || (sizes?.cache ?? 0) == 0)
                        .fixedSize()
                    // Says why the button is off while the account is open.
                    // Always laid out, so opening or quitting moves nothing.
                    Text(profile.isDefault ? "Claude uygulamasının kendi klasörü" : "Önce bu hesabın Claude'unu kapat.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(profile.isDefault || isRunning ? 1 : 0)
                        .accessibilityHidden(!(profile.isDefault || isRunning))
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isMeasuring && sizes != nil ? 1 : 0)
                        .accessibilityHidden(!(isMeasuring && sizes != nil))
                }
                if let cleanupMessage {
                    Text(cleanupMessage)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(DS.Motion.standard, value: isRunning)
        }
        .task(id: profile.id) { await measure() }
        .confirmationDialog("\(profile.name) hesabının önbelleği silinsin mi?", isPresented: $confirmingCleanup) {
            Button("Önbelleği Sil", role: .destructive) {
                Task { await cleanCache() }
            }
        } message: {
            Text("Giriş, ayarlar ve sohbetler kalır.")
        }
    }

    /// Title, then a right-aligned size column and a folder button. Rows
    /// without a folder keep an invisible button, so all sizes line up.
    @ViewBuilder
    private func row(_ title: String, url: URL?, size: Int64?) -> some View {
        LabeledContent(title) {
            HStack(spacing: DS.Space.s) {
                ZStack(alignment: .trailing) {
                    Text(verbatim: size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    ProgressView()
                        .controlSize(.small)
                        .opacity(size == nil ? 1 : 0)
                        .accessibilityHidden(size != nil)
                }
                .frame(minWidth: 70, alignment: .trailing)
                if let url {
                    DSIconButton("Finder'da Göster", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } else {
                    DSIconButton("Finder'da Göster", systemImage: "folder") {}
                        .hidden()
                }
            }
        }
    }

    private func measure() async {
        isMeasuring = true
        defer { isMeasuring = false }
        let desktop = model.paths.effectiveDesktopDataDirectory(for: profile)
        let claudeCode = model.paths.effectiveClaudeCodeConfigDirectory(for: profile)
        let clone = CloneCheck.usesClone(profile) ? model.paths.cloneFolder(for: profile.id) : nil
        let measured = await Task.detached(priority: .utility) {
            StorageSizes(
                desktop: FolderSize.of(desktop),
                cache: CacheFolders.urls(in: desktop).reduce(0) { $0 + FolderSize.of($1) },
                claudeCode: FolderSize.of(claudeCode),
                clone: clone.map(FolderSize.of) ?? 0
            )
        }.value
        withAnimation(DS.Motion.standard) {
            sizes = measured
        }
    }

    private func cleanCache() async {
        guard !profile.isDefault, !model.isRunning(profile) else { return }
        let folders = CacheFolders.urls(in: model.paths.effectiveDesktopDataDirectory(for: profile))
        let freed = sizes?.cache ?? 0
        var failed = false
        for folder in folders {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                failed = true
            }
        }
        Log.app.info("Cache cleaned for an account")
        cleanupMessage = failed
            ? String(localized: "Bazı klasörler silinemedi.")
            : String(localized: "\(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) boşaldı.")
        // The old sizes stay until the new ones arrive, with a small spinner.
        await measure()
    }
}

struct StorageSizes: Equatable {
    var desktop: Int64
    var cache: Int64
    var claudeCode: Int64
    var clone: Int64
}

/// Chromium's caches inside Claude's data folder. Claude rebuilds them.
enum CacheFolders {
    static let names = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache"]

    static func urls(in dataFolder: URL) -> [URL] {
        names.map { dataFolder.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum FolderSize {
    /// The space a folder takes, from file attributes only.
    static func of(_ folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
