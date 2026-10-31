import AppKit
import LanesCore
import SwiftUI
import UniformTypeIdentifiers

/// How much room each account takes, and a way to empty Claude's caches.
struct MaintenancePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("Boyutlar dosyaların yalnız kapladığı yerden toplanır, hiçbir dosya açılmaz. Önbellek, Claude'un yeniden indirebildiği sayfa ve kod kopyalarıdır. Silinince giriş ve sohbetler yerinde kalır, Claude ilk açılışta biraz yavaş olabilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.library.profiles) { profile in
                Section(profile.name) {
                    AccountStorageView(profile: profile)
                }
            }
            Section("Yedekleme") {
                Text("Lanes hesap klasörlerini kendisi yedeklemez, çünkü içlerinde giriş bilgileri var. Time Machine ~/Library/Application Support/Lanes klasörünü de yedekler.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AccountListTransferSection()
        }
        .formStyle(.grouped)
    }
}

/// Saves the account list to a file and adds accounts from one, for a new
/// Mac or a backup. The file holds no sign-in data.
private struct AccountListTransferSection: View {
    @Environment(AppModel.self) private var model
    @State private var result: String?

    var body: some View {
        Section("Hesap listesini taşı") {
            HStack {
                Button("Dışa Aktar…", action: export)
                Button("İçe Aktar…", action: importFile)
            }
            Text("Hesapların adı, rengi, açılış biçimi, notları ve sahneler bir dosyaya yazılır. Giriş bilgileri ve sohbetler dosyaya girmez, bu yüzden başka bir Mac'te her hesapta yeniden giriş yapman gerekir. İçe aktarma yalnız eksik hesapları ve sahneleri ekler, var olanları değiştirmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let result {
                Text(result)
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
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
/// Maintenance page and on the account's Storage tab.
struct AccountStorageView: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var sizes: StorageSizes?
    @State private var confirmingCleanup = false
    @State private var cleanupMessage: String?

    var body: some View {
        Group {
            row(String(localized: "Claude verisi"), url: model.paths.effectiveDesktopDataDirectory(for: profile), size: sizes?.desktop)
            row(String(localized: "Önbellek"), url: nil, size: sizes?.cache)
            row(String(localized: "Claude Code"), url: model.paths.effectiveClaudeCodeConfigDirectory(for: profile), size: sizes?.claudeCode)
            if CloneCheck.usesClone(profile) {
                row(String(localized: "Klon"), url: model.paths.cloneFolder(for: profile.id), size: sizes?.clone)
            }
            HStack {
                Button("Önbelleği Temizle…") { confirmingCleanup = true }
                    .disabled(model.isRunning(profile) || (sizes?.cache ?? 0) == 0)
                    .help(model.isRunning(profile) ? "Önce bu hesabın Claude'unu kapat." : "Claude'un önbellek klasörlerini sil")
                if let cleanupMessage {
                    Text(cleanupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    @ViewBuilder
    private func row(_ title: String, url: URL?, size: Int64?) -> some View {
        LabeledContent(title) {
            HStack {
                if let size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
                if let url {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Finder'da göster")
                }
            }
        }
    }

    private func measure() async {
        let desktop = model.paths.effectiveDesktopDataDirectory(for: profile)
        let claudeCode = model.paths.effectiveClaudeCodeConfigDirectory(for: profile)
        let clone = CloneCheck.usesClone(profile) ? model.paths.cloneFolder(for: profile.id) : nil
        sizes = await Task.detached(priority: .utility) {
            StorageSizes(
                desktop: FolderSize.of(desktop),
                cache: CacheFolders.urls(in: desktop).reduce(0) { $0 + FolderSize.of($1) },
                claudeCode: FolderSize.of(claudeCode),
                clone: clone.map(FolderSize.of) ?? 0
            )
        }.value
    }

    private func cleanCache() async {
        guard !model.isRunning(profile) else { return }
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
        sizes = nil
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
