import AppKit
import LanesCore

/// Makes a copy of Claude.app with its own Finder icon. On APFS the copy is a
/// clone, so it takes almost no disk space. Anthropic's signature is left as
/// is; Faz 0 checks whether macOS still accepts it.
enum CloneMaker {
    struct Result {
        var bundleURL: URL
        var copySeconds: Double
        var iconApplied: Bool
    }

    enum Failure: LocalizedError {
        case outsideClonesFolder

        var errorDescription: String? {
            String(localized: "Lanes yalnız kendi klon klasörüne yazar.")
        }
    }

    static func makeClone(of claudeApp: URL, at destination: URL, icon: NSImage?, paths: ProfilePaths) throws -> Result {
        let clonesPath = InstanceMatcher.normalize(paths.clonesDirectory.path) + "/"
        guard InstanceMatcher.normalize(destination.path).hasPrefix(clonesPath), destination.pathExtension == "app" else {
            throw Failure.outsideClonesFolder
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.clonesDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let start = Date()
        try fileManager.copyItem(at: claudeApp, to: destination)
        let copySeconds = Date().timeIntervalSince(start)
        var iconApplied = false
        if let icon {
            iconApplied = NSWorkspace.shared.setIcon(icon, forFile: destination.path, options: [])
        }
        return Result(bundleURL: destination, copySeconds: copySeconds, iconApplied: iconApplied)
    }

    static func removeClone(at bundle: URL, paths: ProfilePaths) throws {
        let clonesPath = InstanceMatcher.normalize(paths.clonesDirectory.path) + "/"
        guard InstanceMatcher.normalize(bundle.path).hasPrefix(clonesPath) else {
            throw Failure.outsideClonesFolder
        }
        try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
    }
}

/// Draws a profile's monogram as an app icon.
enum MonogramIcon {
    static func image(for profile: Profile, size: CGFloat = 512) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
            let path = NSBezierPath(roundedRect: inset, xRadius: size * 0.18, yRadius: size * 0.18)
            profile.color.nsColor.setFill()
            path.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.4, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let text = NSAttributedString(string: profile.monogram, attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
            return true
        }
    }
}
