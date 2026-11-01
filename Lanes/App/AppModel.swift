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
    /// The clone being made for each account, so a second request, such as
    /// opening an account right after adding it, waits for the same copy.
    @ObservationIgnored private var cloneTasks: [ProfileID: Task<URL?, Never>] = [:]
    /// Clones of removed accounts that were still running at removal; each
    /// goes to the Trash once its Claude closes.
    @ObservationIgnored private var pendingCloneRemovals: Set<ProfileID> = []
    /// Accounts being opened right now, so a second request (a double
    /// click, a startup scene and the reopen list together) does not start
    /// a second Claude on the same folder.
    @ObservationIgnored private var launchesInProgress: Set<ProfileID> = []
    @ObservationIgnored private var warnedStrayPIDs: Set<pid_t> = []
    /// The account Claude Code is signed in to for each profile, read from
    /// its `.claude.json` (email, name and organization only).
    private(set) var claudeCodeAccounts: [ProfileID: ClaudeCodeAccount] = [:]
    /// Memory and CPU of each open account's Claude, read every few seconds.
    private(set) var resourceUsage: [ProfileID: ResourceUsage] = [:]
    /// When each open account was last in front or opened, for quitting
    /// accounts left unused.
    @ObservationIgnored private var lastActiveAt: [ProfileID: Date] = [:]
    @ObservationIgnored private let sampler = ResourceSampler()
    @ObservationIgnored private var resourceTimer: Timer?
    /// The day each account's daily limit reminder last showed.
    @ObservationIgnored private var limitRemindedOn: [ProfileID: String] = [:]
    @ObservationIgnored private var lastMemoryAlert: Date?
    /// How long each account was in front, per day.
    private(set) var frontTime: FrontTimeLog = AppModel.loadFrontTime()
    /// The account in front now and since when, not yet in frontTime.
    @ObservationIgnored private var currentFront: (id: ProfileID, since: Date)?
    /// True while time in front is paused because nobody touched the Mac.
    @ObservationIgnored private var frontPausedForIdle = false
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    /// When each account was last in front, kept across launches, for the
    /// panel's "most recent first" order.
    private(set) var lastUsedAt: [ProfileID: Date] = AppModel.loadLastUsed()
    /// Set when the Mac shuts down or logs out, so the accounts quitting
    /// then don't replace the list Lanes reopens next time.
    @ObservationIgnored private var isPoweringOff = false
    /// The accounts open when Lanes last ran, read before the first scan
    /// replaces the saved list with what is open now.
    @ObservationIgnored private let accountsOpenAtLastRun: [String] = UserDefaults.standard.stringArray(forKey: Preferences.Key.lastOpenAccounts) ?? []

    struct SeparationResult: Equatable {
        /// True when the account's own folder changed after it opened.
        var usesOwnFolder: Bool
        var checkedAt: Date
    }

    init(paths: ProfilePaths = .standard()) {
        let store = ProfileStore(paths: paths)
        let claudeFolder = paths.claudeDesktopDefaultDataDirectory
        let startup = store.startup(
            claudeAppAccountName: FileManager.default.fileExists(atPath: claudeFolder.path) ? String(localized: "Claude uygulaması") : nil
        )
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
            notice = Notice(kind: .warning, message: String(localized: "Hesap listesi okunamadı, son sağlam kopyasından geri yüklendi. Okunamayan dosya aynı klasörde başka bir adla saklandı."))
        } else if let loadError = startup.loadError {
            notice = Notice(kind: .error, message: String(localized: "Hesap listesi okunamadı: \(loadError.localizedDescription) Lanes bu dosyayı silmez, ilk değişikliği kaydederken onu aynı klasörde başka bir adla saklar."))
        } else if startup.isFirstLaunch {
            isFirstLaunch = true
            save()
        } else if startup.addedClaudeAppAccount {
            save()
        }
    }

    func start() {
        claude = ClaudeInstallation.find(paths: paths)
        Log.app.info("Started, \(self.library.profiles.count) accounts, Claude \(self.claude?.version ?? "not found", privacy: .public)")
        SpotlightIndex.update(library.activeProfiles)
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
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let isClaude = app?.bundleIdentifier == ClaudeInstallation.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                // A Claude that just opened may not be in the list yet.
                if isClaude, !self.instances.contains(where: { $0.pid == pid }) {
                    self.refreshInstances()
                }
                self.frontChanged(to: self.instances.first(where: { $0.pid == pid })?.profileID)
                guard pid != ProcessInfo.processInfo.processIdentifier else { return }
                self.hideOtherAccountsIfFocusing(front: pid)
                if let id = self.instances.first(where: { $0.pid == pid })?.profileID {
                    self.lastFrontProfileID = id
                    self.lastActiveAt[id] = Date()
                    self.noteUsed(id)
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frontChanged(to: nil) }
            },
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frontChanged(to: nil) }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frontChangedToCurrentApp() }
            },
        ]
        // Time with another macOS user active is nobody's time in front.
        sleepObservers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontChanged(to: nil) }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontChangedToCurrentApp() }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPoweringOff = true
                // The running interval would otherwise be lost with Lanes.
                self.flushFrontTime()
                // Lanes still running five minutes later means the shut down
                // or log out was cancelled. The reopen list is left as it was
                // saved before the power-off began: a slow shut down may still
                // be quitting accounts, and saving now would shorten it.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    guard let self else { return }
                    self.isPoweringOff = false
                    self.frontChangedToCurrentApp()
                }
            }
        })
        frontChangedToCurrentApp()
        Task { await stepAsideFromSignInIfNeeded() }
        resourceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleResources()
            }
        }
        sampleResources()
    }

    // MARK: Resources and idle accounts

    /// Reads each open account's memory and CPU, then quits accounts that
    /// asked to be quit after sitting unused.
    private func sampleResources() {
        pauseFrontTimeWhileIdle()
        let owned = instances.compactMap { instance in
            instance.profileID.map { (id: $0, pid: instance.pid) }
        }
        let usage = sampler.sample(roots: owned.map(\.pid))
        var byProfile: [ProfileID: ResourceUsage] = [:]
        for item in owned {
            byProfile[item.id] = usage[item.pid]
        }
        resourceUsage = byProfile
        lastActiveAt = lastActiveAt.filter { byProfile[$0.key] != nil }

        let now = Date()
        checkDailyLimits(now: now)
        checkMemory(now: now)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for item in owned {
            guard let profile = profile(withID: item.id), !profile.isDefault else { continue }
            // The account in front is in use: idle time starts when it leaves.
            if front == item.pid {
                lastActiveAt[item.id] = now
                continue
            }
            // An account first seen now gets its whole time from now.
            let lastActive = lastActiveAt[item.id] ?? now
            lastActiveAt[item.id] = lastActive
            guard IdleQuitPolicy.shouldQuit(
                idleMinutes: profile.idleQuitMinutes,
                lastActive: lastActive,
                now: now,
                isFrontmost: front == item.pid,
                cpuPercent: byProfile[item.id]?.cpuPercent
            ) else { continue }
            Log.instances.info("Quitting an account left unused for \(profile.idleQuitMinutes ?? 0) minutes")
            InstanceLauncher.terminate(pid: item.pid)
            lastActiveAt[item.id] = nil
            Notifier.post(.idleQuit, body: String(localized: "\(profile.name) \(IdleQuitPolicy.describe(minutes: profile.idleQuitMinutes ?? 0)) kullanılmadığı için kapatıldı. Lanes'ten yeniden açabilirsin."))
        }
    }

    // MARK: Focus

    /// With focus mode on, hides every other account's Claude when one comes
    /// forward. Hiding is what Cmd-H does: nothing quits.
    private func hideOtherAccountsIfFocusing(front pid: pid_t) {
        guard Preferences.focusModeEnabled, !Preferences.tabModeEnabled,
              instances.contains(where: { $0.pid == pid && $0.profileID != nil }) else { return }
        for instance in instances where instance.pid != pid && instance.profileID != nil {
            NSRunningApplication(processIdentifier: instance.pid)?.hide()
        }
    }

    // MARK: Reopening and recent order

    /// Keeps the list of open accounts, in the list's order, for reopening
    /// them at the next launch.
    private func rememberOpenAccounts() {
        guard !isPoweringOff else { return }
        let open = library.profiles.filter { instance(for: $0) != nil }.map(\.id.rawValue)
        if UserDefaults.standard.stringArray(forKey: Preferences.Key.lastOpenAccounts) != open {
            UserDefaults.standard.set(open, forKey: Preferences.Key.lastOpenAccounts)
        }
    }

    /// Opens the accounts that were open when Lanes last ran and aren't
    /// open now, when the setting is on.
    func reopenLastAccountsIfWanted() {
        guard Preferences.reopensLastAccounts else { return }
        let profiles = accountsOpenAtLastRun.compactMap { profile(withID: ProfileID(rawValue: $0)) }.filter { !isRunning($0) }
        guard !profiles.isEmpty else { return }
        Log.instances.info("Reopening \(profiles.count) accounts from the last run")
        Task {
            for profile in profiles {
                await openAndWait(profile)
            }
        }
    }

    private func noteUsed(_ id: ProfileID) {
        lastUsedAt[id] = Date()
        let raw = Dictionary(uniqueKeysWithValues: lastUsedAt.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(raw, forKey: Preferences.Key.lastUsedAccounts)
    }

    private static func loadLastUsed() -> [ProfileID: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: Preferences.Key.lastUsedAccounts) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.map { (ProfileID(rawValue: $0.key), Date(timeIntervalSince1970: $0.value)) })
    }

    /// The accounts with the most recently used first; never used ones keep
    /// the list's order at the end.
    var profilesByRecentUse: [Profile] {
        let order = Dictionary(uniqueKeysWithValues: library.activeProfiles.enumerated().map { ($0.element.id, $0.offset) })
        return library.activeProfiles.sorted { a, b in
            switch (lastUsedAt[a.id], lastUsedAt[b.id]) {
            case let (x?, y?): return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return (order[a.id] ?? 0) < (order[b.id] ?? 0)
            }
        }
    }

    // MARK: Cycling and duplicating

    /// Brings the next (or previous) open account forward, in the list's
    /// order, starting from the account last in front.
    func cycleOpenAccounts(forward: Bool) {
        refreshInstances()
        let openIDs = Set(library.profiles.filter { isRunning($0) }.map(\.id))
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let current = instances.first(where: { $0.pid == frontPID })?.profileID ?? lastFrontProfileID
        guard let id = AccountCycle.target(current: current, open: openIDs, order: library.profiles.map(\.id), forward: forward),
              let profile = profile(withID: id) else {
            notice = Notice(kind: .info, message: String(localized: "Açık hesap yok."))
            return
        }
        open(profile)
    }

    /// A new account with this one's settings: colour, kind, mode, note,
    /// allowed folders and Dock and idle settings. It starts signed out
    /// with its own empty folders.
    @discardableResult
    func duplicateProfile(_ source: Profile) -> Profile? {
        var copy = Profile(
            name: String(localized: "\(source.name) kopyası"),
            color: source.color,
            mode: source.mode,
            accountClass: source.accountClass,
            note: source.note,
            allowedFolders: source.allowedFolders,
            hidesFromDock: source.hidesFromDock,
            idleQuitMinutes: source.idleQuitMinutes
        )
        if source.isDefault {
            copy.mode = .signedClone
        }
        do {
            try library.add(copy)
            save()
            if CloneCheck.usesClone(copy) {
                Task { await prepareClone(for: copy) }
            }
            return copy
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
            return nil
        }
    }

    // MARK: Time in front

    private func frontChanged(to id: ProfileID?) {
        let now = Date()
        if let current = currentFront {
            if current.id == id { return }
            frontTime.record(current.id, from: current.since, to: now)
            // Leaving the front is the last moment it was used.
            noteUsed(current.id)
            if lastActiveAt[current.id] != nil {
                lastActiveAt[current.id] = now
            }
            frontTime.prune(now: now, keeping: Set(library.profiles.map(\.id)))
            if let data = try? JSONEncoder().encode(frontTime) {
                UserDefaults.standard.set(data, forKey: "frontTime")
            }
        }
        currentFront = id.map { (id: $0, since: now) }
    }

    /// Time in front stops after five minutes with no keyboard, mouse or
    /// trackpad input, counted up to the last input. A Claude window left in
    /// front overnight (with the screen never locked) filled hours before.
    private func pauseFrontTimeWhileIdle() {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= Self.frontIdleThreshold {
            guard !frontPausedForIdle, let current = currentFront else { return }
            frontPausedForIdle = true
            let lastInput = Date().addingTimeInterval(-idle)
            if lastInput > current.since {
                frontTime.record(current.id, from: current.since, to: lastInput)
                if let data = try? JSONEncoder().encode(frontTime) {
                    UserDefaults.standard.set(data, forKey: "frontTime")
                }
            }
            currentFront = nil
        } else if frontPausedForIdle {
            frontPausedForIdle = false
            frontChangedToCurrentApp()
        }
    }

    private static let frontIdleThreshold: TimeInterval = 5 * 60

    /// Writes the running front interval, before Lanes quits or the Mac
    /// powers off.
    func flushFrontTime() {
        frontChanged(to: nil)
    }

    private func frontChangedToCurrentApp() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        frontChanged(to: instances.first(where: { $0.pid == pid })?.profileID)
    }

    /// Seconds the account was in front over the last `days` days,
    /// counting the time it has been in front right now.
    func frontSeconds(for id: ProfileID, days: Int) -> Double {
        let now = Date()
        var total = frontTime.seconds(for: id, days: days, now: now)
        if let current = currentFront, current.id == id {
            // Only the part inside the counted days: an interval that began
            // before midnight must not fill today's limit.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let windowStart = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: today) ?? today
            total += max(0, now.timeIntervalSince(max(current.since, windowStart)))
        }
        return total
    }

    private static func loadFrontTime() -> FrontTimeLog {
        guard let data = UserDefaults.standard.data(forKey: "frontTime") else { return FrontTimeLog() }
        return (try? JSONDecoder().decode(FrontTimeLog.self, from: data)) ?? FrontTimeLog()
    }

    // MARK: Quitting every account

    /// Memory of every open account's Claude together.
    var totalMemoryBytes: UInt64 {
        resourceUsage.values.reduce(0) { $0 + $1.memoryBytes }
    }

    /// Accounts "Tümünü Kapat" would quit: Lanes's own, open ones. The
    /// Claude app's account belongs to Claude and stays.
    var quittableOpenCount: Int {
        library.profiles.filter { !$0.isDefault && isRunning($0) }.count
    }

    /// Quits every open Lanes account the way Claude's own Quit does.
    func quitAllLanesAccounts() {
        let profiles = library.profiles.filter { !$0.isDefault && isRunning($0) }
        for profile in profiles {
            quit(profile)
        }
        Log.instances.info("Quit all: \(profiles.count) accounts")
    }

    /// Accounts in the lists (not archived) whose Claude is closed.
    var closedActiveProfiles: [Profile] {
        library.activeProfiles.filter { !isRunning($0) }
    }

    /// Opens every closed account that is not archived, one after another,
    /// like a scene does.
    func openAllClosedAccounts() {
        let profiles = closedActiveProfiles
        guard !profiles.isEmpty else { return }
        Log.instances.info("Open all: \(profiles.count) accounts")
        Task {
            for profile in profiles {
                await openAndWait(profile)
            }
        }
    }

    /// Today's minutes in front and the daily limit, for accounts that have
    /// a limit.
    func dailyLimitProgress(for profile: Profile) -> (used: Int, limit: Int)? {
        guard let limit = profile.dailyLimitMinutes, limit > 0 else { return nil }
        return (Int(frontSeconds(for: profile.id, days: 1) / 60), limit)
    }

    /// Posts a reminder once a day when an account passes its daily limit.
    private func checkDailyLimits(now: Date) {
        let today = FrontTimeLog.dayKey(now)
        for profile in library.profiles {
            guard let limit = profile.dailyLimitMinutes, limit > 0, limitRemindedOn[profile.id] != today else { continue }
            if frontSeconds(for: profile.id, days: 1) >= Double(limit * 60) {
                limitRemindedOn[profile.id] = today
                Notifier.post(.dailyLimit, body: String(localized: "\(profile.name) bugün \(IdleQuitPolicy.describe(minutes: limit)) önde kaldı."), force: true)
            }
        }
    }

    /// Posts a warning when the open accounts together pass the memory
    /// limit set in Settings, at most once an hour.
    private func checkMemory(now: Date) {
        let limit = UserDefaults.standard.double(forKey: Preferences.Key.memoryAlertGigabytes)
        guard limit > 0, Double(totalMemoryBytes) >= limit * 1_073_741_824 else { return }
        if let last = lastMemoryAlert, now.timeIntervalSince(last) < 3600 { return }
        lastMemoryAlert = now
        let memory = ByteCountFormatter.string(fromByteCount: Int64(clamping: totalMemoryBytes), countStyle: .memory)
        Notifier.post(.memoryHigh, body: String(localized: "Açık hesaplar toplam \(memory) bellek kullanıyor. Kullanmadıklarını kapatabilirsin."), force: true)
    }

    /// The last 30 days of time in front as CSV, for a spreadsheet.
    func frontTimeCSV() -> String {
        frontTime.csv(accounts: library.profiles.map { (id: $0.id, name: $0.name) }, days: FrontTimeLog.keptDays, now: Date())
    }

    // MARK: Moving the account list

    /// Writes the account list and scenes, without any sign-in data.
    func exportLibrary(to url: URL) throws {
        try LibraryExport(library: library).encoded().write(to: url, options: .atomic)
        Log.app.info("Exported \(self.library.profiles.count) accounts")
    }

    /// Adds the accounts and scenes from an exported file that aren't here
    /// yet. Returns a line describing what happened.
    func importLibrary(from url: URL) -> String {
        do {
            let export = try LibraryExport.decode(Data(contentsOf: url))
            let result = export.merge(into: library)
            guard result.addedProfiles + result.addedScenes > 0 else {
                return String(localized: "Dosyadaki hesaplar ve sahneler zaten burada, hiçbir şey eklenmedi.")
            }
            library = result.library
            save()
            refreshCloneStatuses()
            Log.app.info("Imported \(result.addedProfiles) accounts and \(result.addedScenes) scenes")
            return String(localized: "\(result.addedProfiles) hesap ve \(result.addedScenes) sahne eklendi. Hesaplar ilk açılışta girişsiz başlar, her birinde yeniden giriş yapman gerekir.")
        } catch {
            return String(localized: "İçe aktarılamadı: \(error.localizedDescription)")
        }
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
        monitor.watchExits(of: Set(instances.map(\.pid)))
        // A closed account's last reading must not linger until the next sample.
        let openIDs = Set(instances.compactMap(\.profileID))
        if resourceUsage.keys.contains(where: { !openIDs.contains($0) }) {
            resourceUsage = resourceUsage.filter { openIDs.contains($0.key) }
        }
        // A Claude that just started may be a new version: Claude updates
        // itself and relaunches.
        let pids = Set(instances.map(\.pid))
        if !pids.subtracting(knownPIDs).isEmpty, let found = ClaudeInstallation.find(paths: paths), found != claude {
            if let old = claude?.version, old != found.version {
                Log.app.info("Claude changed from \(old, privacy: .public) to \(found.version ?? "?", privacy: .public)")
                Notifier.post(.claudeUpdated, body: String(localized: "\(old) sürümünden \(found.version ?? "?") sürümüne. Klonlar bir sonraki açılışta yenilenir."))
            }
            claude = found
            refreshCloneStatuses()
        }
        knownPIDs = pids
        refreshClaudeCodeAccounts()
        rememberOpenAccounts()
        warnAboutStrayClones()
        for id in pendingCloneRemovals {
            // An account that uses a clone again keeps it.
            if profile(withID: id).map(CloneCheck.usesClone) == true {
                pendingCloneRemovals.remove(id)
            } else {
                removeClone(of: id)
            }
        }
        Log.instances.debug("Scan: \(self.instances.count) running, \(self.instances.filter { $0.profileID == nil }.count) outside Lanes")
    }

    /// Re-reads which account Claude Code is signed in to for every profile.
    /// Only `oauthAccount`'s email, display name and organization name are
    /// read from each `.claude.json`; nothing that signs in is touched.
    func refreshClaudeCodeAccounts() {
        var found: [ProfileID: ClaudeCodeAccount] = [:]
        for profile in library.profiles {
            if let account = ClaudeCodeAccount.read(from: paths.claudeCodeAccountFile(for: profile)) {
                found[profile.id] = account
            }
        }
        if found != claudeCodeAccounts {
            claudeCodeAccounts = found
        }
    }

    /// The account's email: what Claude Code reports, else what the user typed.
    func email(for profile: Profile) -> String? {
        claudeCodeAccounts[profile.id]?.email ?? profile.email
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
        Notifier.post(.strayClone, body: String(localized: "\(name) klonu Claude uygulamasının verileriyle çalışıyor. Kapatıp Lanes'ten aç."))
        notice = Notice(kind: .warning, message: String(localized: "\(name) klonu Lanes dışından açıldı ve Claude uygulamasının verileriyle çalışıyor. Kapatıp Lanes'ten aç. Sağlık sayfasından tek tıkla kapatabilirsin."))
    }

    func instance(for profile: Profile) -> RunningInstance? {
        instances.first { $0.profileID == profile.id }
    }

    func isRunning(_ profile: Profile) -> Bool {
        instance(for: profile) != nil
    }

    var runningCount: Int {
        Set(instances.compactMap(\.profileID)).count
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
        if let running = cloneTasks[profile.id] {
            return await running.value
        }
        let task = Task { await makeClone(for: profile) }
        cloneTasks[profile.id] = task
        let url = await task.value
        cloneTasks[profile.id] = nil
        return url
    }

    private func makeClone(for profile: Profile) async -> URL? {
        guard CloneCheck.usesClone(profile), let claude else { return nil }
        refreshCloneStatuses()
        let existing = cloneURLIfPresent(for: profile)
        guard let status = cloneStatuses[profile.id], status.needsWork, !isRunning(profile) else { return existing }
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
            // Or it may have been removed: no clone for an account that is gone.
            guard let current = self.profile(withID: profile.id) else {
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
            if current.hidesFromDock {
                // Signing again takes a few seconds, so it runs off the main thread.
                try await Task.detached(priority: .userInitiated) {
                    try CloneMaker.hideFromDock(temporary)
                }.value
                guard self.profile(withID: profile.id) != nil else {
                    try? FileManager.default.removeItem(at: temporary)
                    return nil
                }
            }
            try CloneMaker.install(temporary, as: paths.cloneBundle(for: current), icon: MonogramIcon.image(for: current), paths: paths)
            try CloneRecord(profile: current, claudeVersion: claude.version).write(to: paths.cloneRecordFile(for: profile.id))
            Log.app.info("Clone ready in \(Date().timeIntervalSince(start), format: .fixed(precision: 1), privacy: .public) s")
            refreshCloneStatuses()
            Notifier.post(.cloneRenewed, body: String(localized: "\(current.name) klonu hazır."))
            return CloneMaker.existingBundle(in: folder) ?? destination
        } catch {
            CloneMaker.removeLeftovers(in: folder)
            // Removing the account trashes the folder the copy writes into;
            // that is no error to report.
            guard self.profile(withID: profile.id) != nil else { return nil }
            Log.app.error("Clone failed: \(error.localizedDescription, privacy: .public)")
            notice = Notice(kind: .error, message: String(localized: "\(profile.name) için klon hazırlanamadı. \(CloneMaker.explanation(for: error))"))
            Notifier.post(.cloneRenewed, body: String(localized: "\(profile.name) için klon hazırlanamadı."))
            refreshCloneStatuses()
            return existing
        }
    }

    /// Moves an account's clone folder to the Trash. A running clone stays
    /// until the account closes; refreshInstances then removes it.
    private func removeClone(of id: ProfileID) {
        let folder = paths.cloneFolder(for: id)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            pendingCloneRemovals.remove(id)
            return
        }
        // Matched by the bundle's folder, since a removed account's running
        // clone no longer maps to a profile.
        if instances.contains(where: { paths.profileID(forCloneBundle: $0.applicationBundlePath) == id }) {
            pendingCloneRemovals.insert(id)
            return
        }
        pendingCloneRemovals.remove(id)
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

    /// The panel, the Dock menu, a hotkey and Spotlight open accounts with
    /// no Lanes window on screen, where a notice would go unseen until the
    /// next time one opens. A notification says it there instead.
    private func notifyIfNoWindow(_ message: String) {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) else { return }
        Notifier.post(.launchFailed, body: message, force: true)
    }

    func openAndWait(_ profile: Profile) async {
        // A removed account is not opened, even from a list made before.
        guard self.profile(withID: profile.id) != nil, !launchesInProgress.contains(profile.id) else { return }
        launchesInProgress.insert(profile.id)
        defer { launchesInProgress.remove(profile.id) }
        lastActiveAt[profile.id] = Date()
        if let id = activationWarningID, notice?.id == id {
            notice = nil
        }
        activationWarningID = nil
        guard let claude else {
            let message = String(localized: "Claude bulunamadı. Claude'u Uygulamalar klasörüne kurduktan sonra yeniden dene.")
            notice = Notice(kind: .error, message: message)
            notifyIfNoWindow(message)
            return
        }
        refreshInstances()
        let clone = isRunning(profile) ? nil : await prepareClone(for: profile)
        // The account may have been removed while its clone was made.
        guard self.profile(withID: profile.id) != nil else { return }
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
                let message = String(localized: "\(profile.name) açılamadı: \(error.localizedDescription)")
                notice = Notice(kind: .error, message: message)
                notifyIfNoWindow(message)
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
        notice = Notice(kind: .warning, message: String(localized: "\(profile.name) açıldı ama 30 saniyedir kendi klasörüne hiçbir şey yazmadı. Bu pencere Claude uygulamasının verilerini kullanıyor olabilir. Ayarlar > Gelişmiş'ten tanılama bilgisini hazırlayıp bildirmen çok yardımcı olur."))
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
            guard profile.allowsFolder(folder.path) else {
                notice = Notice(kind: .warning, message: String(localized: "\(profile.name) hesabı için Claude Code yalnız izin verilen klasörlerde açılır. \(folder.lastPathComponent) bunlardan biri değil. Hesabın Güvenlik sekmesinden değiştirebilirsin."))
                return
            }
        }
        do {
            try SystemActions.openClaudeCodeInTerminal(for: profile, paths: paths, in: folder, arguments: Toolbox(paths: paths).mcpArguments())
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
        if let folder, !profile.allowsFolder(folder) {
            let name = (folder as NSString).lastPathComponent
            notice = Notice(kind: .warning, message: String(localized: "\(profile.name) hesabı için Claude Code yalnız izin verilen klasörlerde açılır. \(name) bunlardan biri değil. Hesabın Güvenlik sekmesinden değiştirebilirsin."))
            return
        }
        do {
            try SystemActions.openClaudeCodeInTerminal(
                for: profile,
                paths: paths,
                in: folder.map { URL(fileURLWithPath: $0, isDirectory: true) },
                arguments: ["--resume", session.id] + Toolbox(paths: paths).mcpArguments()
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

    /// Removes the profile from Lanes. Its data folder stays on disk and its
    /// clone goes to the Trash. Adding
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
            let folderStays = FileManager.default.fileExists(atPath: paths.profileDirectory(for: profile.id).path)
            notice = Notice(kind: .info, message: folderStays
                ? String(localized: "\(profile.name) kaldırıldı. Klasörü Lanes > Profiles altında duruyor, Claude kopyası Çöp Sepeti'nde.")
                : String(localized: "\(profile.name) kaldırıldı. Claude kopyası Çöp Sepeti'nde."))
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
        }
    }

    /// Quits the account's Claude, waits up to 10 seconds for it to close,
    /// then removes the account. Returns false, with a notice, when it is
    /// still open, so no Claude is left running on a removed account.
    func quitAndRemoveProfile(_ profile: Profile) async -> Bool {
        quit(profile)
        for _ in 0..<20 where isRunning(profile) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            refreshInstances()
        }
        guard !isRunning(profile) else {
            notice = Notice(kind: .warning, message: String(localized: "\(profile.name) kapanmadığı için kaldırılmadı. Claude'u kapatıp yeniden dene."))
            return false
        }
        removeProfile(profile)
        return true
    }

    /// Moves rows of the sidebar's account list, which shows only the
    /// accounts that are not archived.
    func moveProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        var active = library.activeProfiles
        active.move(fromOffsets: source, toOffset: destination)
        library.reorderActive(active.map(\.id))
        save()
    }

    /// Puts an account in the archive or takes it out. An archived account
    /// keeps its sign-in and data; it only leaves the lists and ⌘1-9.
    func setArchived(_ profile: Profile, _ archived: Bool) {
        do {
            try library.setArchived(profile.id, archived)
            save()
            Log.app.info("\(archived ? "Archived" : "Restored", privacy: .public) an account")
        } catch {
            notice = Notice(kind: .error, message: error.localizedDescription)
        }
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
        await applyLayout(of: scene, to: profiles)
    }

    // MARK: Scene layout

    /// Saves where each open account of the scene has its Claude window.
    /// Saves where the scene's windows are now. Returns a line for the
    /// editor sheet to show, since a notice would sit behind the sheet.
    @discardableResult
    func saveLayout(of sceneID: SceneID) -> String {
        guard var scene = library.scene(withID: sceneID) else { return "" }
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            return String(localized: "Pencere yerleşimi için Lanes'e Erişilebilirlik izni ver, sonra yeniden kaydet.")
        }
        refreshInstances()
        var frames: [String: SceneWindowFrame] = [:]
        for profile in scene.profiles(in: library) {
            guard let pid = instance(for: profile)?.pid,
                  let window = AccessibilityWindow.main(of: pid),
                  !window.isMinimized, !window.isFullScreen,
                  let frame = window.frame else { continue }
            frames[profile.id.rawValue] = SceneWindowFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
        }
        guard !frames.isEmpty else {
            return String(localized: "\(scene.name) sahnesinde açık pencere yok. Önce sahnenin hesaplarını aç.")
        }
        scene.windowFrames = frames
        updateScene(scene)
        Log.instances.info("Saved a scene layout with \(frames.count) windows")
        return String(localized: "Yerleşim kaydedildi.")
    }

    func forgetLayout(of sceneID: SceneID) {
        guard var scene = library.scene(withID: sceneID) else { return }
        scene.windowFrames = [:]
        updateScene(scene)
    }

    /// Puts each account's window where the scene saved it. Windows that
    /// take a moment to appear are waited for, up to a few seconds.
    private func applyLayout(of scene: ProfileScene, to profiles: [Profile]) async {
        guard !scene.windowFrames.isEmpty, AccessibilityPermission.isGranted else { return }
        for profile in profiles {
            guard let saved = scene.windowFrame(for: profile.id) else { continue }
            let frame = CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
            for _ in 0..<20 {
                refreshInstances()
                if let pid = instance(for: profile)?.pid, let window = AccessibilityWindow.main(of: pid), !window.isFullScreen {
                    window.setFrame(frame)
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
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
        case .nextAccount: return String(localized: "Sonraki açık hesap")
        case .previousAccount: return String(localized: "Önceki açık hesap")
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
        // The Faz 0 clone check keeps its own folder there; it is Lanes', not
        // a removed account's.
        return OrphanProfileFolders.find(folderNames: names, library: library)
            .filter { $0 != ValidationModel.cloneTestProfile.id.rawValue }
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
            SpotlightIndex.update(library.activeProfiles)
            if let setAside {
                notice = Notice(kind: .warning, message: String(localized: "Okunamayan hesap listesi \(setAside.lastPathComponent) adıyla aynı klasörde saklandı."))
            }
        } catch {
            Log.app.error("Save failed: \(error.localizedDescription)")
            notice = Notice(kind: .error, message: String(localized: "Hesap listesi kaydedilemedi: \(error.localizedDescription)"))
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

    func takeLinks() async {
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
    func giveLinksBackToClaude() async {
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
            // No Lanes account has been in front: the link goes to Claude.app.
            if let claude {
                NSWorkspace.shared.open([link.url], withApplicationAt: claude.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "Claude uygulamasına iletildi.")), at: 0)
            } else {
                receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "Hedef hesap yok, iletilmedi.")), at: 0)
            }
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
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: openWithClaudeInstead(link, missed: profile) ?? String(localized: "\(profile.name) açılamadı, iletilmedi."), target: profile.id), at: 0)
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
            Notifier.post(.linkRouted, body: String(localized: "\(kind): \(profile.name)"))
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: String(localized: "\(profile.name) hesabına iletildi."), target: profile.id), at: 0)
        } catch {
            Log.app.error("Link routing failed: \(error.localizedDescription)")
            notice = Notice(kind: .warning, message: String(localized: "Bağlantı \(profile.name) hesabına iletilemedi: \(error.localizedDescription)"))
            receivedLinks.insert(ReceivedLink(kind: kind, receivedAt: Date(), outcome: openWithClaudeInstead(link, missed: profile) ?? String(localized: "İletilemedi: \(error.localizedDescription)"), target: profile.id), at: 0)
        }
    }

    /// A link the chosen account could not take still opens, in Claude
    /// itself, so the click is never lost. Returns the outcome line, or nil
    /// when Claude is missing.
    private func openWithClaudeInstead(_ link: ClaudeLink, missed profile: Profile) -> String? {
        guard let claude else { return nil }
        NSWorkspace.shared.open([link.url], withApplicationAt: claude.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        return String(localized: "Claude uygulamasına iletildi (\(profile.name) hesabına iletilemedi).")
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
