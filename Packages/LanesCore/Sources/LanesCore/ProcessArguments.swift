import Foundation

/// A process's command line, read from the `KERN_PROCARGS2` sysctl.
///
/// That buffer is laid out as: a 32-bit `argc`, the executable path ending in
/// NUL, NUL padding, `argc` NUL-terminated arguments (starting with argv[0]),
/// then the environment as NUL-terminated `KEY=VALUE` strings. macOS only
/// returns the environment for the user's own processes; Lanes never reads it.
public struct ProcessArguments: Equatable, Sendable {
    public var executablePath: String
    /// The full argv, including argv[0].
    public var arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }

    /// Parses a `KERN_PROCARGS2` buffer. Returns `nil` when the buffer is too
    /// short or malformed.
    public static func parse(procargs2 buffer: [UInt8]) -> ProcessArguments? {
        guard buffer.count >= 4 else { return nil }
        // macOS on both Apple silicon and Intel is little-endian.
        let argc = Int(Int32(bitPattern:
            UInt32(buffer[0])
            | UInt32(buffer[1]) << 8
            | UInt32(buffer[2]) << 16
            | UInt32(buffer[3]) << 24
        ))
        guard argc >= 0 else { return nil }

        var index = 4
        guard let executablePath = readCString(buffer, from: &index) else { return nil }
        while index < buffer.count, buffer[index] == 0 {
            index += 1
        }

        var arguments: [String] = []
        arguments.reserveCapacity(argc)
        while arguments.count < argc {
            guard let argument = readCString(buffer, from: &index) else { break }
            arguments.append(argument)
        }
        guard arguments.count == argc else { return nil }
        return ProcessArguments(executablePath: executablePath, arguments: arguments)
    }

    private static func readCString(_ buffer: [UInt8], from index: inout Int) -> String? {
        guard index < buffer.count else { return nil }
        guard let end = buffer[index...].firstIndex(of: 0) else { return nil }
        let string = String(decoding: buffer[index..<end], as: UTF8.self)
        index = end + 1
        return string
    }

    /// The value of `--user-data-dir`, in either `--flag=value` or
    /// `--flag value` form. The last one wins, as in Chromium.
    public var userDataDirectory: String? {
        let flag = LaunchPlanner.userDataDirectoryFlag
        var result: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix(flag + "=") {
                result = String(argument.dropFirst(flag.count + 1))
            } else if argument == flag, index + 1 < arguments.count {
                result = arguments[index + 1]
                index += 1
            }
            index += 1
        }
        return result
    }

    /// Electron's GPU, renderer, network and utility helpers carry `--type=`.
    /// Only the main process has none.
    public var isHelperProcess: Bool {
        arguments.dropFirst().contains(where: { $0.hasPrefix("--type=") })
    }

    /// The `.app` bundle the executable belongs to, if any.
    public var applicationBundlePath: String? {
        let marker = ".app/Contents/MacOS/"
        guard let range = executablePath.range(of: marker, options: .backwards) else { return nil }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
}

/// A running Claude Desktop main process that Lanes knows about.
public struct RunningInstance: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var applicationBundlePath: String
    /// `nil` when the instance was started without `--user-data-dir`, which
    /// means it uses Claude's own folder.
    public var userDataDirectory: String?
    /// The profile this instance belongs to, when one matches.
    public var profileID: ProfileID?
    /// A Lanes clone started without its account's folder, from Finder,
    /// Spotlight or the Dock. It runs on the main account's data, so it
    /// belongs to no profile and Lanes warns about it (Faz 0.5.2).
    public var isStrayClone: Bool

    public var id: Int32 { pid }

    public init(pid: Int32, applicationBundlePath: String, userDataDirectory: String?, profileID: ProfileID?, isStrayClone: Bool = false) {
        self.pid = pid
        self.applicationBundlePath = applicationBundlePath
        self.userDataDirectory = userDataDirectory
        self.profileID = profileID
        self.isStrayClone = isStrayClone
    }
}

/// Matches running processes to profiles by the data folder they were started
/// with. This is what lets Lanes show which accounts are open, even when the
/// user started Claude some other way.
public enum InstanceMatcher {
    /// Builds a `RunningInstance` for a Claude main process, or returns `nil`
    /// for helpers and for processes that aren't Claude.
    ///
    /// - Parameter knownBundles: Paths of Claude.app and every clone.
    public static func instance(
        pid: Int32,
        arguments: ProcessArguments,
        knownBundles: [String],
        library: ProfileLibrary,
        paths: ProfilePaths
    ) -> RunningInstance? {
        guard !arguments.isHelperProcess, let bundle = arguments.applicationBundlePath else { return nil }
        let normalizedBundle = normalize(bundle)
        guard knownBundles.map(normalize).contains(normalizedBundle) else { return nil }

        let dataDirectory = arguments.userDataDirectory
        let isStrayClone = dataDirectory == nil && paths.isClonePath(normalizedBundle)
        let profile = isStrayClone ? nil : matchingProfile(userDataDirectory: dataDirectory, library: library, paths: paths)
        return RunningInstance(
            pid: pid,
            applicationBundlePath: normalizedBundle,
            userDataDirectory: dataDirectory.map(normalize),
            profileID: profile?.id,
            isStrayClone: isStrayClone
        )
    }

    public static func matchingProfile(userDataDirectory: String?, library: ProfileLibrary, paths: ProfilePaths) -> Profile? {
        let target = normalize(userDataDirectory ?? paths.claudeDesktopDefaultDataDirectory.path)
        return library.profiles.first { profile in
            normalize(paths.effectiveDesktopDataDirectory(for: profile).path) == target
        }
    }

    /// Standardizes a path so that `a/b/`, `a/./b` and `a/b` compare equal.
    public static func normalize(_ path: String) -> String {
        var standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        while standardized.count > 1, standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }
}
