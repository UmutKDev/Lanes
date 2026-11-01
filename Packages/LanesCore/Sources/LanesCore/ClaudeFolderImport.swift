import Foundation

/// "Mevcut Claude klasörünü içe aktar": the rules for taking a Claude data
/// folder that another launcher made (such as an AppleScript applet running
/// `open -n Claude.app --args --user-data-dir=…`) into Lanes as a new
/// account. Pure logic, so it is tested on Linux. Lanes only checks whether
/// a few names exist inside a folder; it never lists or opens anything in it.
public enum ClaudeFolderImport {
    /// Every Chromium data folder has it, so it alone proves nothing.
    public static let requiredMarker = "Local State"
    /// Names only Claude's data folder has.
    public static let claudeMarkers = ["claude-code-sessions", "claude-code", "claude-code-spare", "claude_desktop_config.json"]

    /// Whether a folder looks like Claude Desktop data: it has `Local State`
    /// and either a Claude-only marker or a name starting with "Claude".
    /// That keeps Chrome, Slack and VS Code folders out.
    ///
    /// - Parameter exists: Whether a name exists directly inside the folder.
    public static func looksLikeClaudeData(name: String, exists: (String) -> Bool) -> Bool {
        guard exists(requiredMarker) else { return false }
        return name.lowercased().hasPrefix("claude") || claudeMarkers.contains(where: exists)
    }

    /// Why a folder cannot be imported.
    public enum Refusal: Equatable, Sendable {
        /// The plain Claude app's own folder, or something inside it.
        case plainClaudeFolder
        /// `~/.claude` or something inside it.
        case claudeCodeFolder
        /// Lanes's own folder or something inside it.
        case insideLanes
        /// A folder holding one of the above, such as Application Support.
        case containsProtectedFolder
        /// An account's data folder already.
        case usedByAccount(ProfileID)
        /// A running app was started with this folder, or one inside or above it.
        case inUse
        case notAFolder
        case symbolicLink
        case otherVolume

        public var message: String {
            switch self {
            case .plainClaudeFolder: L("Bu, Claude uygulamasının kendi klasörü.", "This is the Claude app’s own folder.")
            case .claudeCodeFolder: L("Bu, Claude Code’un klasörü.", "This is Claude Code’s folder.")
            case .insideLanes: L("Bu klasör zaten Lanes’te.", "This folder is already in Lanes.")
            case .containsProtectedFolder: L("Bu klasör başka Claude klasörlerini içeriyor.", "This folder holds other Claude folders.")
            case .usedByAccount: L("Bu klasörü bir hesap kullanıyor.", "An account already uses this folder.")
            case .inUse: L("Önce bu klasörü kullanan Claude’u kapat.", "Quit the Claude using this folder first.")
            case .notAFolder: L("Bu bir klasör değil.", "This isn’t a folder.")
            case .symbolicLink: L("Sembolik bağlantı aktarılamaz.", "Symbolic links can’t be imported.")
            case .otherVolume: L("Klasör başka bir diskte. Önce Mac’e taşı.", "Folder is on another disk. Move it to this Mac first.")
            }
        }
    }

    /// Why `path` cannot be imported, or nil when it can. Paths are compared
    /// without case, as APFS does by default, so `claude` is `Claude`.
    public static func refusal(for path: String, paths: ProfilePaths, library: ProfileLibrary, userDataDirectories: [String]) -> Refusal? {
        let target = comparable(path)
        let plain = comparable(paths.claudeDesktopDefaultDataDirectory.path)
        let claudeCode = comparable(paths.claudeCodeDefaultConfigDirectory.path)
        let lanes = comparable(paths.root.path)

        if isSameOrInside(target, plain) { return .plainClaudeFolder }
        for profile in library.profiles where !profile.isDefault {
            if isSameOrInside(target, comparable(paths.effectiveDesktopDataDirectory(for: profile).path)) {
                return .usedByAccount(profile.id)
            }
        }
        if isSameOrInside(target, claudeCode) { return .claudeCodeFolder }
        if isSameOrInside(target, lanes) { return .insideLanes }
        let protected = [plain, claudeCode, lanes]
            + library.profiles.map { comparable(paths.effectiveDesktopDataDirectory(for: $0).path) }
        if protected.contains(where: { isInside($0, target) }) { return .containsProtectedFolder }
        if isInUse(path: path, userDataDirectories: userDataDirectories) { return .inUse }
        return nil
    }

    public static func refusal(for path: String, paths: ProfilePaths, library: ProfileLibrary, instances: [RunningInstance]) -> Refusal? {
        refusal(for: path, paths: paths, library: library, userDataDirectories: instances.compactMap(\.userDataDirectory))
    }

    /// Whether a running app uses `path`: started with it as
    /// `--user-data-dir`, or with a folder inside or above it.
    public static func isInUse(path: String, userDataDirectories: [String]) -> Bool {
        let target = comparable(path)
        return userDataDirectories.contains { directory in
            let used = comparable(directory)
            return isSameOrInside(used, target) || isInside(target, used)
        }
    }

    public static func isInUse(path: String, instances: [RunningInstance]) -> Bool {
        isInUse(path: path, userDataDirectories: instances.compactMap(\.userDataDirectory))
    }

    /// A folder that may be offered in the list.
    public struct Candidate: Equatable, Sendable {
        public var name: String
        public var path: String
        /// Listed but not selectable until that Claude quits.
        public var inUse: Bool
    }

    /// The candidates among the names directly inside `folder` (Application
    /// Support): hidden names, folders that don't look like Claude data and
    /// refused folders are left out. Folders in use stay, marked.
    ///
    /// - Parameter exists: Whether a full path exists.
    public static func candidates(
        in folder: String,
        names: [String],
        paths: ProfilePaths,
        library: ProfileLibrary,
        userDataDirectories: [String],
        exists: (String) -> Bool
    ) -> [Candidate] {
        let base = InstanceMatcher.normalize(folder)
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { name in
            guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }
            let path = base + "/" + name
            let refusal = refusal(for: path, paths: paths, library: library, userDataDirectories: userDataDirectories)
            guard refusal == nil || refusal == .inUse else { return nil }
            guard looksLikeClaudeData(name: name, exists: { exists(path + "/" + $0) }) else { return nil }
            return Candidate(name: name, path: path, inUse: refusal == .inUse)
        }
    }

    /// The new account's name: the launcher's name without `.app` ("Claude
    /// Work"), else the folder's name without a leading "Claude-" or
    /// "Claude " ("Claude-Work" → "Work"). When nothing with a letter is
    /// left ("Claude-2"), the whole folder name.
    public static func suggestedName(folderName: String, launcherName: String?) -> String {
        if let launcherName {
            var name = launcherName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.lowercased().hasSuffix(".app") { name.removeLast(4) }
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        let folder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["claude-", "claude ", "claude_"] where folder.lowercased().hasPrefix(prefix) {
            let rest = folder.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.contains(where: \.isLetter) { return rest }
        }
        return folder
    }

    static func comparable(_ path: String) -> String {
        InstanceMatcher.normalize(path).lowercased()
    }

    static func isSameOrInside(_ path: String, _ folder: String) -> Bool {
        path == folder || isInside(path, folder)
    }

    /// Strictly below `folder`.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        path.hasPrefix(folder == "/" ? "/" : folder + "/") && path != folder
    }
}

/// Reads an old launcher's AppleScript, as decompiled text, to tell which
/// data folder it opened. Text matching only: Lanes never runs the script.
public enum LauncherScript {
    /// Whether the script opens Claude with `--user-data-dir` set to
    /// `folder`, written as an absolute path, `~/…`, `$HOME/…` or
    /// `${HOME}/…`, with spaces as they are, as `\ ` or as AppleScript's
    /// `\\ `. The path must end there, so `Claude-2` never matches
    /// `Claude-20`. Case is ignored, as APFS does.
    public static func pointsAt(script: String, folder: String, home: String) -> Bool {
        let text = script.lowercased()
        guard text.contains("claude.app") || text.contains("com.anthropic"),
              text.contains(LaunchPlanner.userDataDirectoryFlag) else { return false }

        let absolute = InstanceMatcher.normalize(folder)
        let homePath = InstanceMatcher.normalize(home)
        var spellings = [absolute]
        if homePath != "/", absolute.hasPrefix(homePath + "/") {
            let relative = String(absolute.dropFirst(homePath.count + 1))
            spellings += ["~/", "$HOME/", "${HOME}/"].map { $0 + relative }
        }
        let variants = spellings.flatMap { spelling in
            [spelling, spelling.replacingOccurrences(of: " ", with: "\\ "), spelling.replacingOccurrences(of: " ", with: "\\\\ ")]
        }
        return Set(variants).contains { contains(text, path: $0.lowercased(), isAbsolute: $0.hasPrefix("/")) }
    }

    private static func contains(_ text: String, path: String, isAbsolute: Bool) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: path, range: searchStart..<text.endIndex) {
            searchStart = text.index(after: range.lowerBound)
            if isAbsolute, range.lowerBound > text.startIndex {
                let before = text[text.index(before: range.lowerBound)]
                if before.isLetter || before.isNumber || before == "/" || before == "." { continue }
            }
            var end = range.upperBound
            if end < text.endIndex, text[end] == "/" { end = text.index(after: end) }
            if endsAtBoundary(text, end, closing: openingQuote(in: text, before: range.lowerBound)) { return true }
        }
        return false
    }

    /// The quote the path's argument opened with: `'`, `"` or AppleScript's
    /// `\"`, found by looking back to the start of the argument. Nil when
    /// the argument is not quoted.
    private static func openingQuote(in text: String, before index: String.Index) -> String? {
        var cursor = index
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            let character = text[previous]
            if character == " " || character == "\t" || character.isNewline { return nil }
            if character == "'" { return "'" }
            if character == "\"" {
                if previous > text.startIndex, text[text.index(before: previous)] == "\\" { return "\\\"" }
                return "\""
            }
            cursor = previous
        }
        return nil
    }

    /// A quoted path ends only at its closing quote, so a space inside the
    /// quotes (`Claude-2 Backup`) is still part of the path. An unquoted
    /// one also ends at whitespace or the end of the AppleScript string.
    private static func endsAtBoundary(_ text: String, _ index: String.Index, closing: String?) -> Bool {
        if let closing {
            return text[index...].hasPrefix(closing)
        }
        guard index < text.endIndex else { return true }
        let next = text[index]
        if next == "\"" || next == "'" || next == " " || next.isNewline || next == "\t" { return true }
        if next == "\\" {
            // `\"` closes a quoted path inside an AppleScript string.
            let after = text.index(after: index)
            return after < text.endIndex && text[after] == "\""
        }
        return false
    }
}
