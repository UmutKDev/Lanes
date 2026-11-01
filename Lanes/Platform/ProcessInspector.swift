import AppKit
import Darwin
import LanesCore

/// Reads another process's command line with the `KERN_PROCARGS2` sysctl.
/// macOS allows this for the user's own processes without any permission.
enum ProcessInspector {
    static func arguments(of pid: pid_t) -> ProcessArguments? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argumentMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argumentMax, &size, nil, 0) == 0, argumentMax > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(argumentMax))
        var argumentsMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var length = buffer.count
        let result = buffer.withUnsafeMutableBytes { raw in
            sysctl(&argumentsMib, 3, raw.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return nil }
        return ProcessArguments.parse(procargs2: Array(buffer.prefix(length)))
    }
}

/// Finds the running Claude Desktop instances and works out which profile each
/// one belongs to.
enum RunningInstanceScanner {
    static func scan(knownBundles: [String], library: ProfileLibrary, paths: ProfilePaths) -> [RunningInstance] {
        let known = Set(knownBundles.map(InstanceMatcher.normalize))
        return NSWorkspace.shared.runningApplications.compactMap { app -> RunningInstance? in
            let bundlePath = app.bundleURL.map { InstanceMatcher.normalize($0.path) }
            let isClaude = app.bundleIdentifier == ClaudeInstallation.bundleIdentifier
            let isKnownBundle = bundlePath.map { known.contains($0) } ?? false
            guard isClaude || isKnownBundle else { return nil }
            guard let arguments = ProcessInspector.arguments(of: app.processIdentifier) else { return nil }
            return InstanceMatcher.instance(
                pid: app.processIdentifier,
                arguments: arguments,
                knownBundles: knownBundles + [bundlePath].compactMap { $0 },
                library: library,
                paths: paths
            )
        }
        .sorted { $0.pid < $1.pid }
    }

    /// The `--user-data-dir` of every running app's main process, Claude
    /// or not, so a copy of Claude Lanes doesn't know still counts. Only
    /// the command line is read, never the environment. A leading `~/` is
    /// expanded, in case a launcher passed it unexpanded.
    static func userDataDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard let arguments = ProcessInspector.arguments(of: app.processIdentifier),
                  !arguments.isHelperProcess,
                  let directory = arguments.userDataDirectory else { return nil }
            let expanded = directory.hasPrefix("~/") ? home + "/" + directory.dropFirst(2) : directory
            return InstanceMatcher.normalize(expanded)
        }
    }
}

/// Calls back whenever an app starts or quits, so the instance list stays
/// current without polling.
@MainActor
final class RunningInstanceMonitor {
    var onChange: (() -> Void)?
    /// Called first for every app that starts, before `onChange`, so a
    /// clone opened outside Lanes can be caught while it is still running.
    var onLaunch: ((NSRunningApplication) -> Void)?
    private var observers: [NSObjectProtocol] = []
    /// Exit watchers for running instances. A clone kept out of the Dock is
    /// an agent app, and NSWorkspace does not report agents quitting.
    private var exitSources: [pid_t: DispatchSourceProcess] = [:]

    /// Watches these processes, and only these, for exit.
    func watchExits(of pids: Set<pid_t>) {
        for (pid, source) in exitSources where !pids.contains(pid) {
            source.cancel()
            exitSources[pid] = nil
        }
        for pid in pids where exitSources[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.exitSources[pid]?.cancel()
                    self?.exitSources[pid] = nil
                    self?.onChange?()
                }
            }
            exitSources[pid] = source
            source.resume()
        }
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let launched = name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    if launched, let app {
                        self?.onLaunch?(app)
                    }
                    self?.onChange?()
                }
            }
            observers.append(token)
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        watchExits(of: [])
    }
}
