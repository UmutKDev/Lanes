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
        /// The account it went to, when Lanes routed it.
        var target: ProfileID? = nil
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
    /// Which account routable links open in.
    private(set) var linkRules: LinkRules
    /// The account whose Claude was last in front, for links that follow
    /// the front account. Lanes itself coming forward doesn't change it.
    @ObservationIgnored private var lastFrontProfileID: ProfileID?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var knownPIDs: Set<pid_t> = []
    /// Whether each clone matches Claude and its profile. Lanes renews a
    /// clone that doesn't the next time its account opens.
    private(set) var cloneStatuses: [ProfileID: CloneStatus] = [:]
    /// Accounts whose clone Lanes is making right now.
    private(set) var clonesInProgress: Set<ProfileID> = []
    @ObservationIgnored private var warnedStrayPIDs: Set<pid_t> = []

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
        self.linkRules = AppModel.loadLinkRules()
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
        refreshCloneStatuses()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, pid != ProcessInfo.processInfo.processIdentifier else { return }
                if let id = self.instances.first(where: { $0.pid == pid })?.profileID {
                    self.lastFrontProfileID = id
                }
            }
        }
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
            refreshCloneStatuses()
        }
        knownPIDs = pids
        warnAboutStrayClones()
        Log.instances.debug("Scan: \(self.instances.count) running, \(self.instances.filter { $0.profileID == nil }.count) outside Lanes")
    }

    /// Claude.app and every clone on disk, including Faz 0 clones in the
    /// old folder, so none of them passes for Claude itself.
    var knownBundlePaths: [String] {
        var bundles: [String] = []
        if let claude { bundles.append(claude.url.path) }
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(at: paths.clonesDirectory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            if let bundle = CloneMaker.existingBundle(in: folder) {
                bundles.append(bundle.path)
            }
        }
        let legacy = (try? fileManager.contentsOfDirectory(at: paths.legacyClonesDirectory, includingPropertiesForKeys: nil)) ?? []
        bundles += legacy.filter { $0.pathExtension == "app" }.map(\.path)
        return bundles
    }

    /// Clones opened from Finder, Spotlight or the Dock, without their
    /// account's folder.
    var strayClones: [RunningInstance] {
        instances.filter(\.isStrayClone)
    }

    private func warnAboutStrayClones() {
        let stray = strayClones
        warnedStrayPIDs.formIntersection(stray.map(\.pid))
        guard let first = stray.first(where: { !warnedStrayPIDs.contains($0.pid) }) else { return }
        warnedStrayPIDs.insert(first.pid)
        let name = paths.profileID(forCloneBundle: first.applicationBundlePath).flatMap { profile(withID: $0)?.name }
            ?? URL(fileURLWithPath: first.applicationBundlePath).deletingPathExtension().lastPathComponent
        Log.instances.info("A clone was opened without its folder")
        notice = Notice(kind: .warning, message: String(localized: "\(name) klonu Lanes dışından açıldı ve Ana hesabın verileriyle çalışıyor. Kapatıp Lanes'ten aç. Sağlık sayfasından tek tıkla kapatabilirsin."))
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
        CloneMaker.existingBundle(in: paths.cloneFolder(for: profile.id))
    }

    // MARK: Clones

    func refreshCloneStatuses() {
        var statuses: [ProfileID: CloneStatus] = [:]
        for profile in library.profiles where CloneCheck.usesClone(profile) {
            let folder = paths.cloneFolder(for: profile.id)
            statuses[profile.id] = CloneCheck.status(
                for: profile,
                bundleName: CloneMaker.existingBundle(in: folder)?.lastPathComponent,
                record: CloneRecord.read(from: paths.cloneRecordFile(for: profile.id)),
                claudeVersion: claude?.version
            )
        }
        if statuses != cloneStatuses {
            cloneStatuses = statuses
        }
    }

    /// Makes or renews the account's clone when it needs it and the account
    /// is closed, and returns the clone to open. A running clone is never
    /// replaced. Returns nil when the account opens with Claude itself or
    /// the clone could not be made; `notice` then says why.
    @discardableResult
    func prepareClone(for profile: Profile) async -> URL? {
        guard CloneCheck.usesClone(profile), let claude else { return nil }
        refreshCloneStatuses()
        let existing = cloneURLIfPresent(for: profile)
        guard let status = cloneStatuses[profile.id], status.needsWork, !isRunning(profile) else { return existing }
        guard !clonesInProgress.contains(profile.id) else { return existing }
        clonesInProgress.insert(profile.id)
        defer { clonesInProgress.remove(profile.id) }

        let folder = paths.cloneFolder(for: profile.id)
        let destination = paths.cloneBundle(for: profile)
        let source = claude.url
        let clonePaths = self.paths
        let start = Date()
        do {
            CloneMaker.removeLeftovers(in: folder)
            let temporary = try await Task.detached(priority: .userInitiated) {
                try CloneMaker.copyForRenewal(of: source, into: folder, paths: clonePaths)
            }.value
            // The account may have opened while the copy ran.
            guard !isRunning(profile) else {
                try? FileManager.default.removeItem(at: temporary)
                return existing
            }
            let current = self.profile(withID: profile.id) ?? profile
            try CloneMaker.install(temporary, as: paths.cloneBundle(for: current), icon: MonogramIcon.image(for: current), paths: paths)
            try CloneRecord(profile: current, claudeVersion: claude.version).write(to: paths.cloneRecordFile(for: profile.id))
            Log.app.info("Clone ready in \(Date().timeIntervalSince(start), format: .fixed(precision: 1), privacy: .public) s")
            refreshCloneStatuses()
            return CloneMaker.existingBundle(in: folder) ?? destination
        } catch {
            Log.app.error("Clone failed: \(error.localizedDescription, privacy: .public)")
            CloneMaker.removeLeftovers(in: folder)
            notice = Notice(kind: .error, message: String(localized: "\(profile.name) için klon hazırlanamadı. \(CloneMaker.explanation(for: error))"))
            refreshCloneStatuses()
            return existing
        }
    }

    /// Moves an account's clone folder to the Trash. A running clone stays
    /// until the account closes.
    private func removeClone(of id: ProfileID) {
        let folder = paths.cloneFolder(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        if instances.contains(where: { $0.profileID == id && paths.isClonePath($0.applicationBundlePath) }) { return }
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        } catch {
            Log.app.error("Could not trash a clone: \(error.localizedDescription, privacy: .public)")
        }
        refreshCloneStatuses()
    }

    /// Faz 0 put its test clones in ~/Applications, where Spotlight finds
    /// them and opens them without an account folder.
    var legacyClones: [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: paths.legacyClonesDirectory, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "app" }
    }

    func trashLegacyClones() {
        for clone in legacyClones where !instances.contains(where: { $0.applicationBundlePath == InstanceMatcher.normalize(clone.path) }) {
            try? FileManager.default.trashItem(at: clone, resultingItemURL: nil)
        }
    }

    /// Closes a clone opened without its folder. It only asks the app to
    /// quit, like ⌘Q, so Claude can save what it needs.
    func quitStrayClone(_ instance: RunningInstance) {
        guard instance.isStrayClone else { return }
        NSRunningApplication(processIdentifier: instance.pid)?.terminate()
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
        let clone = isRunning(profile) ? nil : await prepareClone(for: profile)
        let action = LaunchPlanner.action(
            for: profile,
            running: instances,
            claudeApp: claude.url,
            cloneApp: clone,
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
            if plan.fallsBackToClaude {
                notice = Notice(kind: .warning, message: String(localized: "\(profile.name) klonu olmadığı için Claude'un kendisiyle, kendi klasörüyle açılıyor. Klonu Sağlık sayfasından yeniden oluşturabilirsin."))
            }
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
            if CloneCheck.usesClone(profile) {
                Task { await prepareClone(for: profile) }
            }
            return profile
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
            return nil
        }
    }

    func updateProfile(_ profile: Profile) {
        let before = self.profile(withID: profile.id)
        do {
            try library.update(profile)
            save()
            if CloneCheck.usesClone(profile) {
                refreshCloneStatuses()
                // A new clone right away; renewing a working one can wait
                // for the next open.
                if before.map(CloneCheck.usesClone) == false || cloneStatuses[profile.id] == .missing {
                    Task { await prepareClone(for: profile) }
                }
            } else if before.map(CloneCheck.usesClone) == true {
                removeClone(of: profile.id)
            }
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
            removeClone(of: profile.id)
            recentFolders[profile.id] = nil
            saveRecentFolders()
            pruneShortcuts()
            var rules = linkRules
            rules.prune(profiles: Set(library.profiles.map(\.id)))
            if rules != linkRules { setLinkRules(rules) }
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

    /// Lanes declares `claude://` so it can route links. With routing off
    /// it must never keep the default: Claude's own sign-in depends on
    /// receiving those links. With routing on it takes the default back
    /// whenever it lost it.
    func stepAsideFromSignInIfNeeded() async {
        if Preferences.linkRoutingEnabled {
            await takeLinks()
        } else {
            await giveLinksBackToClaude()
        }
    }

    var isLinkRoutingOn: Bool {
        Preferences.linkRoutingEnabled
    }

    func setLinkRouting(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Preferences.Key.linkRoutingEnabled)
        Task {
            if enabled {
                await takeLinks()
            } else {
                await giveLinksBackToClaude()
            }
        }
    }

    func setLinkRules(_ rules: LinkRules) {
        linkRules = rules
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Preferences.Key.linkRules)
        }
    }

    private static func loadLinkRules() -> LinkRules {
        guard let data = UserDefaults.standard.data(forKey: Preferences.Key.linkRules) else { return LinkRules() }
        return (try? JSONDecoder().decode(LinkRules.self, from: data)) ?? LinkRules()
    }

    private func takeLinks() async {
        guard !LinkHandlerRegistry.lanesIsHandler else { return }
        do {
            try await LinkHandlerRegistry.setHandler(Bundle.main.bundleURL)
            Log.app.info("Link routing: Lanes holds the claude:// default")
        } catch {
            Log.app.error("Link routing: could not take the default: \(error.localizedDescription)")
            notice = Notice(kind: .warning, message: String(localized: "Lanes claude:// bağlantılarını üstlenemedi: \(error.localizedDescription)"))
        }
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
            Task {
                await giveLinksBackToClaude()
                // Routing stays on: after a pause long enough to finish
                // signing in, Lanes takes the default again.
                if Preferences.linkRoutingEnabled {
                    try? await Task.sleep(nanoseconds: 180_000_000_000)
                    if Preferences.linkRoutingEnabled { await takeLinks() }
                }
            }
        case .openWithClaude where Preferences.linkRoutingEnabled:
            if let link, case let .routable(route) = link.kind {
                Task { await deliver(link, route: route) }
                return
            }
            outcome = String(localized: "İletilmedi.")
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

    /// Sends a routable link to the account the rules pick, opening it first
    /// when it is closed.
    private func deliver(_ link: ClaudeLink, route: ClaudeLink.Route) async {
        let kind = Self.kindName(link)
        guard let profile = linkRules.profile(for: route, frontmost: lastFrontProfileID, library: library) else {
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "Hedef hesap yok, iletilmedi.")), at: 0)
            return
        }
        var justOpened = false
        if !isRunning(profile) {
            await openAndWait(profile)
            justOpened = true
            for _ in 0..<20 where !isRunning(profile) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshInstances()
            }
        }
        guard let pid = instance(for: profile)?.pid else {
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "\(profile.name) açılamadı, iletilmedi."), target: profile.id), at: 0)
            return
        }
        if justOpened {
            // A Claude that just started needs a moment before it takes links.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
        do {
            try await AppleEvents.sendLink(link, to: pid)
            _ = await InstanceLauncher.activate(pid: pid)
            Log.app.info("Link routed to an account")
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "\(profile.name) hesabına iletildi."), target: profile.id), at: 0)
        } catch {
            Log.app.error("Link routing failed: \(error.localizedDescription)")
            notice = Notice(kind: .warning, message: String(localized: "Bağlantı \(profile.name) hesabına iletilemedi: \(error.localizedDescription)"))
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "İletilemedi: \(error.localizedDescription)"), target: profile.id), at: 0)
        }
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
