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
}

/// Calls back whenever an app starts or quits, so the instance list stays
/// current without polling.
@MainActor
final class RunningInstanceMonitor {
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
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
    }
}
