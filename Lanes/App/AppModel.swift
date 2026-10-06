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
        var url: URL
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
    /// The "could not bring forward" warning describes one attempt only, so
    /// the next attempt clears it.
    @ObservationIgnored private var activationWarningID: Notice.ID?

    let validation: ValidationModel

    init(paths: ProfilePaths = .standard()) {
        let store = ProfileStore(paths: paths)
        var loaded = ProfileLibrary()
        var loadError: Error?
        do {
            loaded = try store.load()
        } catch {
            loadError = error
        }
        self.paths = paths
        self.store = store
        self.validation = ValidationModel(paths: paths)
        self.library = loaded

        if let loadError {
            notice = Notice(kind: .error, message: String(localized: "Profil listesi okunamadı: \(loadError.localizedDescription) Lanes bu dosyayı silmez, ilk değişikliği kaydederken onu aynı klasörde başka bir adla saklar."))
        } else if library.profiles.isEmpty {
            isFirstLaunch = true
            // The account the user is already signed in to keeps using
            // Claude's own folders, so nothing changes for it.
            try? library.add(Profile(name: String(localized: "Ana hesap"), color: .orange, isDefault: true))
            save()
        }
    }

    func start() {
        claude = ClaudeInstallation.find(paths: paths)
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
        }
        instances = RunningInstanceScanner.scan(knownBundles: knownBundlePaths, library: library, paths: paths)
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
            if !inFront {
                stayedBehind = pid
            }
        case let .launch(plan):
            do {
                try await InstanceLauncher.launch(plan)
            } catch {
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

    func quit(_ profile: Profile) {
        guard let instance = instance(for: profile) else { return }
        InstanceLauncher.terminate(pid: instance.pid)
    }

    func openClaudeCode(_ profile: Profile) {
        do {
            try SystemActions.openClaudeCodeInTerminal(for: profile, paths: paths)
        } catch {
            notice = Notice(kind: .error, message: String(localized: "Terminal açılamadı: \(error.localizedDescription)"))
        }
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

    func profile(withID id: ProfileID) -> Profile? {
        library.profile(withID: id)
    }

    func shortcutNumber(for profile: Profile) -> Int? {
        library.shortcutNumber(for: profile.id)
    }

    private func save() {
        do {
            if let setAside = try store.save(library) {
                notice = Notice(kind: .warning, message: String(localized: "Okunamayan profil listesi \(setAside.lastPathComponent) adıyla aynı klasörde saklandı."))
            }
        } catch {
            notice = Notice(kind: .error, message: String(localized: "Profil listesi kaydedilemedi: \(error.localizedDescription)"))
        }
    }

    // MARK: Links

    /// Lanes declares `claude://` so Faz 0 can test taking it over. Until
    /// routing is turned on, it must never keep the default: Claude's own
    /// sign-in depends on receiving those links.
    func stepAsideFromSignInIfNeeded() async {
        guard !Preferences.linkRoutingEnabled, LinkHandlerRegistry.lanesIsHandler, let claude else { return }
        try? await LinkHandlerRegistry.setHandler(claude.url)
    }

    func receive(_ url: URL) {
        let link = ClaudeLink(url: url)
        let outcome: String
        if link?.mustNotForward == true {
            outcome = String(localized: "Giriş bağlantısı. İletilmedi, varsayılan Claude'a geri verildi.")
            notice = Notice(kind: .warning, message: String(localized: "Bir giriş bağlantısı Lanes'e geldi. Bağlantıları yeniden Claude açacak, girişi bir kez daha dene."))
            Task { await stepAsideFromSignInIfNeeded() }
        } else if let claude {
            outcome = String(localized: "Claude'a iletildi.")
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: claude.url, configuration: configuration, completionHandler: nil)
        } else {
            outcome = String(localized: "Claude bulunamadı, iletilmedi.")
        }
        receivedLinks.insert(ReceivedLink(url: url, receivedAt: Date(), outcome: outcome), at: 0)
    }
}
