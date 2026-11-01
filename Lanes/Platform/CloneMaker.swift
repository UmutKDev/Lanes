import AppKit
import LanesCore

/// Makes a copy of Claude.app with its own Finder icon. On APFS the copy is a
/// clone, so it takes almost no disk space. Anthropic's signature is left as
/// is unless the clone has to be re-signed, as for hiding it from the Dock.
enum CloneMaker {
    enum Failure: LocalizedError {
        case outsideClonesFolder
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .outsideClonesFolder:
                return String(localized: "Lanes yalnız kendi klon klasörüne yazar.")
            case let .signingFailed(detail):
                return String(localized: "Dock'ta görünmeyen klon imzalanamadı: \(detail)")
            }
        }
    }

    /// Copies Claude.app next to a profile's clone under a hidden name. The
    /// copy is an APFS clone, so it is quick, but it still runs off the main
    /// thread. `install` then puts it in place.
    static func copyForRenewal(of claudeApp: URL, into folder: URL, paths: ProfilePaths) throws -> URL {
        guard paths.isClonePath(folder.appendingPathComponent("x.app").path) else {
            throw Failure.outsideClonesFolder
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".lanes-new-\(UUID().uuidString).app", isDirectory: true)
        try fileManager.copyItem(at: claudeApp, to: temporary)
        return temporary
    }

    /// Gives the fresh copy its icon and swaps it in for the old clone. The
    /// old one first steps aside under a hidden name and goes to the Trash
    /// only after the new one is in place; if the move fails it is put back,
    /// so a failed renewal never leaves the account without a clone.
    static func install(_ temporary: URL, as destination: URL, icon: NSImage?, paths: ProfilePaths) throws {
        guard paths.isClonePath(destination.path), paths.isClonePath(temporary.path) else {
            throw Failure.outsideClonesFolder
        }
        if let icon {
            _ = NSWorkspace.shared.setIcon(icon, forFile: temporary.path, options: [])
        }
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        let oldBundles = ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" && !$0.lastPathComponent.hasPrefix(".") }
        var setAside: [(original: URL, hidden: URL)] = []
        do {
            for old in oldBundles {
                let hidden = folder.appendingPathComponent(".lanes-old-\(UUID().uuidString).app", isDirectory: true)
                try fileManager.moveItem(at: old, to: hidden)
                setAside.append((original: old, hidden: hidden))
            }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            for item in setAside.reversed() {
                try? fileManager.moveItem(at: item.hidden, to: item.original)
            }
            throw error
        }
        // A copy the Trash refuses stays hidden; removeLeftovers tries again.
        for item in setAside {
            try? fileManager.trashItem(at: item.hidden, resultingItemURL: nil)
        }
    }

    /// Entitlements that belong to Anthropic's team. An app signed on this
    /// Mac can't carry them; macOS refuses to start it if it does.
    static let restrictedEntitlementPrefixes = [
        "com.apple.application-identifier",
        "com.apple.developer.",
        "keychain-access-groups",
    ]

    /// Keeps a clone out of the Dock and Cmd-Tab. Changing Info.plist breaks
    /// Anthropic's signature, so the bundle is signed again on this Mac:
    /// Anthropic's team entitlements go, and library validation is turned
    /// off so Claude's frameworks, still signed by Anthropic, load. The
    /// clone then asks for the keychain password once and shows no menus.
    static func hideFromDock(_ bundle: URL) throws {
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        guard var info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any] else {
            throw Failure.signingFailed("Info.plist")
        }
        info["LSUIElement"] = true
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL, options: .atomic)

        var entitlements: [String: Any] = [:]
        let current = try run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", bundle.path])
        if let start = current.range(of: "<?xml"),
           let data = String(current[start.lowerBound...]).data(using: .utf8),
           let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            entitlements = parsed
        }
        for key in entitlements.keys where restrictedEntitlementPrefixes.contains(where: { key.hasPrefix($0) }) {
            entitlements[key] = nil
        }
        entitlements["com.apple.security.cs.disable-library-validation"] = true

        let entitlementsURL = FileManager.default.temporaryDirectory.appendingPathComponent("lanes-entitlements-\(UUID().uuidString).plist")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: entitlementsURL)
        defer { try? FileManager.default.removeItem(at: entitlementsURL) }
        // Only the outer bundle is signed again; the frameworks and helpers
        // inside keep Anthropic's signature.
        _ = try run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--entitlements", entitlementsURL.path, bundle.path])
    }

    /// Runs a tool and returns what it printed, stdout and stderr together.
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure.signingFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    /// Hidden copies left by a renewal that stopped halfway. An old clone
    /// set aside goes to the Trash rather than being deleted.
    static func removeLeftovers(in folder: URL) {
        let fileManager = FileManager.default
        let items = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            if item.lastPathComponent.hasPrefix(".lanes-new-") {
                try? fileManager.removeItem(at: item)
            } else if item.lastPathComponent.hasPrefix(".lanes-old-") {
                try? fileManager.trashItem(at: item, resultingItemURL: nil)
            }
        }
    }

    /// A profile's clone bundle on disk, whatever name it has now.
    static func existingBundle(in folder: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension == "app" && !$0.lastPathComponent.hasPrefix(".") }
    }

    /// Explains a failed copy or swap in plain words. macOS's App Management
    /// setting can stop Lanes from changing an app bundle.
    static func explanation(for error: Error) -> String {
        let nsError = error as NSError
        let denied = [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code)
            || (nsError.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(nsError.code))
            || ((nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { $0.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains($0.code) } ?? false)
        if denied {
            return String(localized: "macOS klonu değiştirmeye izin vermedi. Sistem Ayarları > Gizlilik ve Güvenlik > Uygulama Yönetimi'nde Lanes'e izin verip yeniden dene.")
        }
        return error.localizedDescription
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
