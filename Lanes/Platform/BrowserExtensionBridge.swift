import AppKit
import Foundation
import LanesCore

/// Lanes's side of the Chrome and Edge extension (LanesChrome). Lanes puts a
/// native messaging host file into each installed Chrome-based browser, so
/// the extension can keep saved claude.ai sessions in the Keychain through
/// `lanes-browser-host`, and shares its account list (names, colors,
/// e-mails) so web accounts match their desktop twins. Only browsers whose
/// folder already exists get the file; a file another app wrote under the
/// same name is left alone.
enum BrowserExtensionBridge {
    struct BrowserState: Identifiable, Equatable {
        let browser: BrowserNativeHost.Browser
        let hostInstalled: Bool
        var id: String { browser.id }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Contents/MacOS/lanes-browser-host next to the Lanes binary.
    static var hostExecutable: URL? {
        guard let folder = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let url = folder.appendingPathComponent(BrowserNativeHost.executableName, isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// The unpacked extension inside Lanes.app, for "Load unpacked".
    static var extensionFolder: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { return nil }
        return url
    }

    /// Writes the list the host hands to the extension.
    static func publish(_ profiles: [Profile], identities: [ProfileID: BrowserNativeHost.Identity], paths: ProfilePaths) {
        let url = paths.root.appendingPathComponent(BrowserNativeHost.accountsFileName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            try BrowserNativeHost.accountList(profiles, identities: identities).write(to: url, options: .atomic)
        } catch {
            Log.app.error("Browser account list not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts the host file into every installed Chrome-based browser and keeps
    /// its path current when Lanes moves. Runs at launch.
    static func installHosts() {
        guard let executable = hostExecutable else { return }
        let contents = BrowserNativeHost.hostManifest(executable: executable)
        for browser in BrowserNativeHost.browsers where FileManager.default.fileExists(atPath: browser.dataFolder(home: home).path) {
            let file = browser.hostFile(home: home)
            switch BrowserNativeHost.hostFileState(try? Data(contentsOf: file), executable: executable) {
            case .current, .foreign:
                continue
            case .missing, .outdated:
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try contents.write(to: file, options: .atomic)
                    Log.app.info("Native host file written for \(browser.displayName, privacy: .public)")
                } catch {
                    Log.app.error("Native host file for \(browser.displayName, privacy: .public) not written: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Installed Chrome-based browsers and whether the host file is in place.
    static func states() -> [BrowserState] {
        let executable = hostExecutable
        return BrowserNativeHost.browsers
            .filter { FileManager.default.fileExists(atPath: $0.dataFolder(home: home).path) }
            .map { browser in
                let data = try? Data(contentsOf: browser.hostFile(home: home))
                let installed = executable.map { BrowserNativeHost.hostFileState(data, executable: $0) == .current } ?? false
                return BrowserState(browser: browser, hostInstalled: installed)
            }
    }

    /// Shows the unpacked extension in Finder and opens the browser's
    /// extensions page, where it is dropped or picked with "Load unpacked".
    static func revealForLoading(in browser: BrowserNativeHost.Browser) {
        if let folder = extensionFolder {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
        let page = browser.id.hasPrefix("edge") ? "edge://extensions" : "chrome://extensions"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", browser.displayName, page]
        try? process.run()
    }
}
