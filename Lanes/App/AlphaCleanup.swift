import AppKit
import LanesCore

/// Removes what the test builds before 1.0 left behind, once. Folders that
/// may hold a signed-in Claude go to the Trash, never straight to deletion,
/// and nothing inside an account folder is read: only whether it exists.
@MainActor
enum AlphaCleanup {
    /// Raise when a later release adds a step; every step must be safe to
    /// run again.
    static let version = 1

    /// The folder name the test builds used under Clones and Profiles.
    private static let testFolderName = "faz0-clone-test"
    /// The setting that showed the test builds' check pages.
    private static let retiredDefaults = ["showsDeveloperPages"]
    /// Results and reports the test builds wrote to the Diagnostics folder.
    private static let retiredDiagnostics = ["validation-results.json", "faz0-results.json", "faz0-report.md"]
    /// Copies of those results that were moved aside as unreadable.
    private static let retiredDiagnosticsPrefixes = ["validation-results-unreadable-", "faz0-results-unreadable-"]

    /// Runs the cleanup unless it already finished. A step that has to wait,
    /// because the test clone is open or the Trash refused, leaves the flag
    /// unset so the next launch tries again.
    static func runIfNeeded(paths: ProfilePaths, instances: [RunningInstance]) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Preferences.Key.alphaCleanupVersion) < version else { return }
        var finished = trashTestFolders(paths: paths, instances: instances)
        if !removeRetiredDiagnostics(in: paths.diagnosticsDirectory) {
            finished = false
        }
        for key in retiredDefaults {
            defaults.removeObject(forKey: key)
        }
        if finished {
            defaults.set(version, forKey: Preferences.Key.alphaCleanupVersion)
        }
    }

    /// Moves the test clone and its account folder to the Trash, unless the
    /// clone is running. Returns false when something was left for later.
    private static func trashTestFolders(paths: ProfilePaths, instances: [RunningInstance]) -> Bool {
        let cloneFolder = paths.clonesDirectory.appendingPathComponent(testFolderName, isDirectory: true)
        let dataFolder = paths.root
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(testFolderName, isDirectory: true)
        let fileManager = FileManager.default
        let folders = [cloneFolder, dataFolder].filter { fileManager.fileExists(atPath: $0.path) }
        guard !folders.isEmpty else { return true }
        // The clone running, or any Claude using the test folder, keeps both
        // folders in place until it quits.
        guard !isInUse(cloneFolder: cloneFolder, dataFolder: dataFolder, instances: instances) else {
            Log.app.info("Alpha cleanup waits: the test clone is open")
            return false
        }
        var finished = true
        for folder in folders {
            do {
                try fileManager.trashItem(at: folder, resultingItemURL: nil)
            } catch {
                Log.app.error("Alpha cleanup could not trash a test folder: \(error.localizedDescription, privacy: .public)")
                finished = false
            }
        }
        return finished
    }

    private static func isInUse(cloneFolder: URL, dataFolder: URL, instances: [RunningInstance]) -> Bool {
        let clonePrefix = InstanceMatcher.normalize(cloneFolder.path) + "/"
        let dataPrefix = InstanceMatcher.normalize(dataFolder.path) + "/"
        let usedByInstance = instances.contains { instance in
            instance.applicationBundlePath.hasPrefix(clonePrefix)
                || (instance.userDataDirectory.map { ($0 + "/").hasPrefix(dataPrefix) } ?? false)
        }
        if usedByInstance { return true }
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let bundle = app.bundleURL?.path else { return false }
            return InstanceMatcher.normalize(bundle).hasPrefix(clonePrefix)
        }
    }

    /// Deletes the test builds' results and reports. Returns false when one
    /// could not be deleted.
    private static func removeRetiredDiagnostics(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let retired = names.filter { name in
            retiredDiagnostics.contains(name) || retiredDiagnosticsPrefixes.contains { name.hasPrefix($0) }
        }
        var finished = true
        for name in retired {
            do {
                try fileManager.removeItem(at: directory.appendingPathComponent(name, isDirectory: false))
            } catch {
                Log.app.error("Alpha cleanup could not delete an old report: \(error.localizedDescription, privacy: .public)")
                finished = false
            }
        }
        return finished
    }
}
