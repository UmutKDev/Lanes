import AppKit
import LanesCore
import Observation
import SwiftUI

/// The state the menu bar panel and the main window share.
@MainActor
@Observable
final class AppModel {
    struct Notice: Identifiable, Equatable {
        enum Kind { case info, warning, error }
        let id = UUID()
        var kind: Kind
        var message: String
    }

    struct ReceivedLink: Identifiable {
        let id = UUID()
        /// What kind of link arrived. The link itself is never kept, because
        /// a sign-in link can carry a one-time code.
        var kind: String
        var receivedAt: Date
        var outcome: String
    }

    let paths: ProfilePaths
    @ObservationIgnored private let store: ProfileStore
    @ObservationIgnored private let monitor = RunningInstanceMonitor()

    private(set) var library: ProfileLibrary
    private(set) var instances: [RunningInstance] = []
    private(set) var claude: ClaudeInstallation?
    private(set) var receivedLinks: [ReceivedLink] = []
    /// True when there was no profiles file yet, so Lanes greets the user.
    private(set) var isFirstLaunch = false
    var notice: Notice?
    /// The overview's "Claude was not found" warning, closed until Lanes
    /// quits. It comes back on the next launch if Claude is still missing.
    var isMissingClaudeNoticeDismissed = false
    /// Lanes runs from a translocated copy or straight from the DMG, see
    /// AppLocation.
    let isTranslocated = AppLocation.isTemporary(
        bundlePath: Bundle.main.bundlePath,
        volumeIsReadOnly: (try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
    )
    var isTranslocationNoticeDismissed = false
    /// The "could not bring forward" warning describes one attempt only, so
    /// the next attempt clears it.
    @ObservationIgnored private var activationWarningID: Notice.ID?

    let validation: ValidationModel
    let updater = Updater()

    /// Global shortcuts, kept in Lanes's defaults.
    private(set) var shortcuts: ShortcutBindings
    /// Folders each account last opened Claude Code in.
    private(set) var recentFolders: [ProfileID: RecentFolders]
    /// What the last separation check after opening an account found.
    private(set) var separationResults: [ProfileID: SeparationResult] = [:]
    @ObservationIgnored private var knownPIDs: Set<pid_t> = []

    struct SeparationResult: Equatable {
        /// True when the account's own folder changed after it opened.
        var usesOwnFolder: Bool
        var checkedAt: Date
    }

    init(paths: ProfilePaths = .standard()) {
        let store = ProfileStore(paths: paths)
        let startup = store.startup(defaultProfileName: String(localized: "Ana hesap"))
        self.paths = paths
        self.store = store
        self.validation = ValidationModel(paths: paths)
        self.library = startup.library
        self.shortcuts = AppModel.loadShortcuts()
        self.recentFolders = AppModel.loadRecentFolders()
        validation.currentClaude = { [weak self] in self?.claude }

        if startup.restoredFromBackup {
            Log.app.error("Profile list unreadable, restored from backup")
            // Saving now moves the unreadable file aside and keeps it.
            save()
            notice = Notice(kind: .warning, message: String(localized: "Profil listesi okunamadı, son sağlam kopyasından geri yüklendi. Okunamayan dosya aynı klasörde başka bir adla saklandı."))
        } else if let loadError = startup.loadError {
            notice = Notice(kind: .error, message: String(localized: "Profil listesi okunamadı: \(loadError.localizedDescription) Lanes bu dosyayı silmez, ilk değişikliği kaydederken onu aynı klasörde başka bir adla saklar."))
        } else if startup.isFirstLaunch {
            isFirstLaunch = true
            save()
        } else if startup.addedMissingDefault {
            save()
            notice = Notice(kind: .warning, message: String(localized: "Profil listesinde Ana hesap yoktu, yeniden eklendi. Claude'un kendi klasörlerini kullanıyor."))
        }
    }

    func start() {
        claude = ClaudeInstallation.find(paths: paths)
        Log.app.info("Started, \(self.library.profiles.count) accounts, Claude \(self.claude?.version ?? "not found", privacy: .public)")
        monitor.onChange = { [weak self] in
            self?.refreshInstances()
        }
        monitor.start()
        refreshInstances()
        Task { await stepAsideFromSignInIfNeeded() }
    }

    // MARK: Instances

    func refreshInstances() {
        if claude == nil {
            claude = ClaudeInstallation.find(paths: paths)
            // Claude may have been installed after Lanes started.
            if claude != nil {
                Task { await stepAsideFromSignInIfNeeded() }
            }
        }
        instances = RunningInstanceScanner.scan(knownBundles: knownBundlePaths, library: library, paths: paths)
        // A Claude that just started may be a new version: Claude updates
        // itself and relaunches.
        let pids = Set(instances.map(\.pid))
        if !pids.subtracting(knownPIDs).isEmpty, let found = ClaudeInstallation.find(paths: paths), found != claude {
            if let old = claude?.version, old != found.version {
                Log.app.info("Claude changed from \(old, privacy: .public) to \(found.version ?? "?", privacy: .public)")
            }
            claude = found
        }
        knownPIDs = pids
        Log.instances.debug("Scan: \(self.instances.count) running, \(self.instances.filter { $0.profileID == nil }.count) outside Lanes")
    }

    /// Claude.app and every clone Lanes made.
    var knownBundlePaths: [String] {
        var bundles: [String] = []
        if let claude { bundles.append(claude.url.path) }
        for profile in library.profiles where profile.mode != .standard {
            bundles.append(paths.cloneBundle(for: profile).path)
        }
        bundles.append(paths.cloneBundle(for: ValidationModel.cloneTestProfile).path)
        return bundles
    }

    func instance(for profile: Profile) -> RunningInstance? {
        instances.first { $0.profileID == profile.id }
    }

    func isRunning(_ profile: Profile) -> Bool {
        instance(for: profile) != nil
    }

    var runningCount: Int {
        instances.filter { $0.profileID != nil }.count
    }

    func cloneURLIfPresent(for profile: Profile) -> URL? {
        let url = paths.cloneBundle(for: profile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Opening

    func open(_ profile: Profile) {
        Task { await openAndWait(profile) }
    }

    func openAndWait(_ profile: Profile) async {
        if let id = activationWarningID, notice?.id == id {
            notice = nil
        }
        activationWarningID = nil
        guard let claude else {
            notice = Notice(kind: .error, message: String(localized: "Claude bulunamadı. Claude'u Uygulamalar klasörüne kurduktan sonra yeniden dene."))
            return
        }
        refreshInstances()
        let action = LaunchPlanner.action(
            for: profile,
            running: instances,
            claudeApp: claude.url,
            cloneApp: cloneURLIfPresent(for: profile),
            paths: paths
        )
        var stayedBehind: pid_t?
        switch action {
        case let .activate(pid):
            let inFront = await InstanceLauncher.activate(pid: pid)
            Log.instances.info("Bring forward PID \(pid): \(inFront ? "in front" : "stayed behind", privacy: .public)")
            if !inFront {
                stayedBehind = pid
            }
        case let .launch(plan):
            let launchedAt = Date()
            do {
                try await InstanceLauncher.launch(plan)
                if let folder = paths.desktopDataDirectory(for: profile) {
                    Task { await checkSeparation(of: profile, folder: folder, since: launchedAt) }
                }
                Log.instances.info("Launched \(plan.applicationURL.lastPathComponent == "Claude.app" ? "Claude" : "a clone", privacy: .public) with \(plan.arguments.isEmpty ? "Claude's own folder" : "its own folder", privacy: .public)")
            } catch {
                Log.instances.error("Launch failed: \(error.localizedDescription)")
                notice = Notice(kind: .error, message: String(localized: "\(profile.name) açılamadı: \(error.localizedDescription)"))
            }
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        refreshInstances()
        // Cmd-Tab only helps while the instance still runs and is still
        // behind. One that quit meanwhile has nothing to switch to.
        if let pid = stayedBehind,
           instance(for: profile)?.pid == pid,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            let warning = Notice(kind: .warning, message: String(localized: "\(profile.name) öne getirilemedi. Cmd-Tab ile geçebilirsin."))
            notice = warning
            activationWarningID = warning.id
        }
    }

    /// A Claude that ignored its folder argument would run on the main
    /// account's data. Its own folder changing soon after launch shows that
    /// it did not. Only modification dates are read, no file is opened.
    private func checkSeparation(of profile: Profile, folder: URL, since start: Date) async {
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if FolderActivity.changed(folder, since: start) {
                Log.instances.info("Separation check: own folder in use")
                separationResults[profile.id] = SeparationResult(usesOwnFolder: true, checkedAt: Date())
                return
            }
        }
        refreshInstances()
        // A window closed in the meantime proves nothing either way.
        guard isRunning(profile) else { return }
        separationResults[profile.id] = SeparationResult(usesOwnFolder: false, checkedAt: Date())
        Log.instances.error("Separation check: own folder unchanged 30 s after launch")
        notice = Notice(kind: .warning, message: String(localized: "\(profile.name) açıldı ama 30 saniyedir kendi klasörüne hiçbir şey yazmadı. Bu pencere Ana hesabın verilerini kullanıyor olabilir. Ayarlar > Gelişmiş'ten tanılama bilgisini hazırlayıp bildirmen çok yardımcı olur."))
    }

    func quit(_ profile: Profile) {
        guard let instance = instance(for: profile) else { return }
        InstanceLauncher.terminate(pid: instance.pid)
    }

    /// Opens Claude Code in Terminal, in `folder` or the home folder.
    func openClaudeCode(_ profile: Profile, in folder: URL? = nil) {
        if let folder {
            guard FileManager.default.fileExists(atPath: folder.path) else {
                forgetRecentFolder(folder.path, for: profile)
                notice = Notice(kind: .warning, message: String(localized: "\(folder.lastPathComponent) klasörü artık yok, listeden çıkarıldı."))
                return
            }
        }
        do {
            try SystemActions.openClaudeCodeInTerminal(for: profile, paths: paths, in: folder)
            if let folder {
                var recent = recentFolders[profile.id] ?? RecentFolders()
                recent.use(folder.path)
                recentFolders[profile.id] = recent
                saveRecentFolders()
            }
        } catch {
            notice = Notice(kind: .error, message: String(localized: "Terminal açılamadı: \(error.localizedDescription)"))
        }
    }

    /// Continues a Claude Code session in Terminal, with the account it
    /// belongs to and in its project folder when that still exists.
    func resume(_ session: ClaudeCodeSessionList.Session, of profile: Profile) {
        let folder = ClaudeCodeSessionList.projectPath(forFolderName: session.projectFolderName) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        do {
            try SystemActions.openClaudeCodeInTerminal(
                for: profile,
                paths: paths,
                in: folder.map { URL(fileURLWithPath: $0, isDirectory: true) },
                arguments: ["--resume", session.id]
            )
            Log.app.info("Resumed a Claude Code session")
        } catch {
            notice = Notice(kind: .error, message: String(localized: "Terminal açılamadı: \(error.localizedDescription)"))
        }
    }

    /// One account's Claude Code sessions, names and dates only.
    func claudeCodeSessions(for profile: Profile) -> ClaudeCodeSessionList {
        let projects = paths.effectiveClaudeCodeConfigDirectory(for: profile).appendingPathComponent("projects", isDirectory: true)
        return ClaudeCodeSessionList.read(projects)
    }

    func recentClaudeCodeFolders(for profile: Profile) -> [URL] {
        (recentFolders[profile.id]?.paths ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func forgetRecentFolder(_ path: String, for profile: Profile) {
        recentFolders[profile.id]?.forget(path)
        saveRecentFolders()
    }

    func claudeCodeCommand(for profile: Profile) -> String {
        ClaudeCodeCommand.command(for: profile, paths: paths)
    }

    // MARK: Editing profiles

    @discardableResult
    func addProfile(name: String, color: ProfileColor, mode: ProfileMode, accountClass: AccountClass) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = Profile(
            name: trimmed.isEmpty ? String(localized: "Yeni hesap") : trimmed,
            color: color,
            mode: mode,
            accountClass: accountClass
        )
        do {
            try library.add(profile)
            save()
            return profile
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
            return nil
        }
    }

    func updateProfile(_ profile: Profile) {
        do {
            try library.update(profile)
            save()
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
        }
    }

    /// Removes the profile from Lanes. Its folders stay on disk, but adding
    /// the account again creates a new, empty folder, so the user signs in
    /// again.
    func removeProfile(_ profile: Profile) {
        guard !profile.isDefault else { return }
        do {
            try library.remove(profile.id)
            save()
            recentFolders[profile.id] = nil
            saveRecentFolders()
            pruneShortcuts()
            notice = Notice(kind: .info, message: String(localized: "\(profile.name) kaldırıldı. Klasörü Lanes > Profiles altında duruyor."))
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
        }
    }

    func moveProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        var profiles = library.profiles
        profiles.move(fromOffsets: source, toOffset: destination)
        library.profiles = profiles
        save()
    }

    // MARK: Scenes

    @discardableResult
    func addScene(name: String, profileIDs: [ProfileID]) -> ProfileScene? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scene = ProfileScene(name: trimmed.isEmpty ? String(localized: "Yeni sahne") : trimmed, profileIDs: profileIDs)
        do {
            try library.addScene(scene)
            save()
            return scene
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
            return nil
        }
    }

    func updateScene(_ scene: ProfileScene) {
        do {
            try library.updateScene(scene)
            save()
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
        }
    }

    func removeScene(_ scene: ProfileScene) {
        library.removeScene(scene.id)
        save()
        pruneShortcuts()
    }

    func open(_ scene: ProfileScene) {
        Task { await openAndWait(scene) }
    }

    /// Opens the accounts one after another, so each window comes up before
    /// the next and the last one ends up in front.
    func openAndWait(_ scene: ProfileScene) async {
        let profiles = scene.profiles(in: library)
        guard !profiles.isEmpty else {
            notice = Notice(kind: .info, message: String(localized: "\(scene.name) sahnesinde hesap yok."))
            return
        }
        Log.instances.info("Opening a scene with \(profiles.count) accounts")
        for profile in profiles {
            await openAndWait(profile)
        }
    }

    /// Scenes marked to open with Lanes, once per launch.
    func openStartupScenes() {
        let scenes = library.scenes.filter(\.opensWhenLanesStarts)
        guard !scenes.isEmpty else { return }
        Task {
            for scene in scenes {
                await openAndWait(scene)
            }
        }
    }

    // MARK: Shortcuts

    func setShortcut(_ shortcut: KeyShortcut?, for target: ShortcutTarget) throws {
        try shortcuts.set(shortcut, for: target)
        saveShortcuts()
    }

    /// The name of what a shortcut opens, for messages and Settings.
    func name(of target: ShortcutTarget) -> String {
        switch target {
        case .panel: return String(localized: "Menü çubuğu paneli")
        case let .profile(id): return profile(withID: id)?.name ?? String(localized: "Silinmiş hesap")
        case let .scene(id): return library.scene(withID: id)?.name ?? String(localized: "Silinmiş sahne")
        }
    }

    private func pruneShortcuts() {
        if shortcuts.prune(profiles: Set(library.profiles.map(\.id)), scenes: Set(library.scenes.map(\.id))) {
            saveShortcuts()
        }
    }

    private static func loadShortcuts() -> ShortcutBindings {
        guard let data = UserDefaults.standard.data(forKey: Preferences.Key.shortcuts) else { return ShortcutBindings() }
        return (try? JSONDecoder().decode(ShortcutBindings.self, from: data)) ?? ShortcutBindings()
    }

    private func saveShortcuts() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(data, forKey: Preferences.Key.shortcuts)
    }

    private static func loadRecentFolders() -> [ProfileID: RecentFolders] {
        let stored = UserDefaults.standard.dictionary(forKey: Preferences.Key.recentClaudeCodeFolders) as? [String: [String]] ?? [:]
        var result: [ProfileID: RecentFolders] = [:]
        for (id, paths) in stored {
            result[ProfileID(rawValue: id)] = RecentFolders(paths: paths)
        }
        return result
    }

    private func saveRecentFolders() {
        var stored: [String: [String]] = [:]
        for (id, recent) in recentFolders where !recent.paths.isEmpty {
            stored[id.rawValue] = recent.paths
        }
        UserDefaults.standard.set(stored, forKey: Preferences.Key.recentClaudeCodeFolders)
    }

    // MARK: Health

    /// Folders under Profiles that belong to no account. Only names are
    /// listed, nothing inside is read.
    func orphanProfileFolders() -> [URL] {
        let profilesDirectory = paths.root.appendingPathComponent("Profiles", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: profilesDirectory.path)) ?? []
        return OrphanProfileFolders.find(folderNames: names, library: library)
            .map { profilesDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    // MARK: Diagnostics

    /// Copies the diagnostics report and saves it in the Diagnostics folder.
    /// Returns the saved file, or nil when it could not be written.
    @discardableResult
    func prepareDiagnostics() -> URL? {
        refreshInstances()
        var folderExists: [ProfileID: Bool] = [:]
        for profile in library.profiles {
            folderExists[profile.id] = FileManager.default.fileExists(atPath: paths.profileDirectory(for: profile.id).path)
        }
        let report = DiagnosticsReport(
            environment: validation.environment(),
            claudePath: claude?.url.path,
            linkHandlerPath: LinkHandlerRegistry.currentHandler()?.path,
            isTranslocated: isTranslocated,
            updatesEnabled: updater.isAvailable,
            profiles: library.profiles,
            folderExists: folderExists,
            instances: instances,
            generatedAt: Date(),
            homeDirectory: NSHomeDirectory()
        ).markdown()
        SystemActions.copy(report)
        let file = paths.diagnosticsDirectory.appendingPathComponent("lanes-tanilama.md", isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: paths.diagnosticsDirectory, withIntermediateDirectories: true)
            try report.write(to: file, atomically: true, encoding: .utf8)
            Log.app.info("Diagnostics saved")
            return file
        } catch {
            Log.app.error("Diagnostics not saved: \(error.localizedDescription)")
            return nil
        }
    }

    func profile(withID id: ProfileID) -> Profile? {
        library.profile(withID: id)
    }

    func shortcutNumber(for profile: Profile) -> Int? {
        library.shortcutNumber(for: profile.id)
    }

    private func save() {
        do {
            let setAside = try store.save(library)
            Log.app.info("Saved \(self.library.profiles.count) accounts")
            if let setAside {
                notice = Notice(kind: .warning, message: String(localized: "Okunamayan profil listesi \(setAside.lastPathComponent) adıyla aynı klasörde saklandı."))
            }
        } catch {
            Log.app.error("Save failed: \(error.localizedDescription)")
            notice = Notice(kind: .error, message: String(localized: "Profil listesi kaydedilemedi: \(error.localizedDescription)"))
        }
    }

    // MARK: Links

    /// Lanes declares `claude://` so Faz 0 can test taking it over. Until
    /// routing is turned on, it must never keep the default: Claude's own
    /// sign-in depends on receiving those links.
    func stepAsideFromSignInIfNeeded() async {
        guard !Preferences.linkRoutingEnabled else { return }
        await giveLinksBackToClaude()
    }

    /// Hands the `claude://` default back to Claude if Lanes holds it.
    private func giveLinksBackToClaude() async {
        guard LinkHandlerRegistry.lanesIsHandler, let claude else { return }
        try? await LinkHandlerRegistry.setHandler(claude.url)
    }

    func receive(_ url: URL) {
        // A link that launches Lanes arrives before start() has looked for
        // Claude.
        if claude == nil {
            claude = ClaudeInstallation.find(paths: paths)
        }
        let link = ClaudeLink(url: url)
        let outcome: String
        switch ClaudeLink.handling(for: url) {
        case .holdBack:
            // Whatever the routing setting says: the next try of this link,
            // a sign-in above all, has to reach Claude directly.
            if claude == nil {
                outcome = String(localized: "İletilmedi. Claude bulunamadığı için varsayılan geri verilemedi.")
                notice = Notice(kind: .warning, message: String(localized: "Lanes'e gelen bir bağlantı iletilmedi. Claude bulunamadığı için bağlantılar Claude'a geri verilemedi. Claude'u kurduktan sonra yeniden dene."))
            } else if link?.mustNotForward == true {
                outcome = String(localized: "İletilmedi, varsayılan Claude'a geri verildi.")
                notice = Notice(kind: .warning, message: String(localized: "Bir giriş bağlantısı Lanes'e geldi. Bağlantıları yeniden Claude açacak, girişi bir kez daha dene."))
            } else {
                outcome = String(localized: "İletilmedi, varsayılan Claude'a geri verildi.")
                notice = Notice(kind: .warning, message: String(localized: "Lanes'in tanımadığı bir bağlantı geldi ve iletilmedi. Bağlantıları yeniden Claude açacak, bağlantıyı bir kez daha aç."))
            }
            Task { await giveLinksBackToClaude() }
        case .openWithClaude:
            if let claude {
                outcome = String(localized: "Claude'a iletildi.")
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([url], withApplicationAt: claude.url, configuration: configuration, completionHandler: nil)
            } else {
                outcome = String(localized: "Claude bulunamadı, iletilmedi.")
            }
        }
        receivedLinks.insert(ReceivedLink(kind: Self.kindName(link), receivedAt: Date(), outcome: outcome), at: 0)
    }

    /// Names a link's kind without any part of the link.
    static func kindName(_ link: ClaudeLink?) -> String {
        guard let link else { return String(localized: "Claude bağlantısı değil") }
        switch link.kind {
        case .signIn: return String(localized: "Giriş bağlantısı")
        case .oauthCallback: return String(localized: "OAuth dönüşü")
        case .unknown: return String(localized: "Tanınmayan bağlantı")
        case let .routable(route):
            switch route {
            case .newChat: return String(localized: "Yeni sohbet")
            case .newCodeSession: return String(localized: "Yeni Code oturumu")
            case .continueCodeSession: return String(localized: "Code oturumunu sürdür")
            case .codeNeedsInput: return String(localized: "Yanıt bekleyen Code oturumu")
            case .resume: return String(localized: "Sohbeti sürdür")
            case .cowork: return String(localized: "Cowork")
            case .settings: return String(localized: "Ayarlar")
            }
        }
    }
}
