import Foundation

/// "Bitti Haberi": Claude Code tells Lanes when it finishes a reply or waits
/// for an approval, so Lanes can show a notification in the account's name.
///
/// Nothing is written into an account's own `settings.json`. Lanes keeps a
/// small settings file per account in its own folder and passes it with
/// `--settings` to the Claude Code sessions it starts (Terminal buttons,
/// Shortcuts, the `lanes` tool). Claude Code adds those hooks to the
/// account's own ones. Turning the feature off deletes Lanes's folder, and
/// the account's settings were never touched.
///
/// The hook reads nothing Claude Code sends it: its input is thrown away
/// unread. It writes one small file with the account ID, the event, the
/// terminal (tty), the terminal app's name and the project folder, all of
/// which come from the hook's own environment.
public enum ClaudeCodeHooks {
    /// What happened in a session.
    public enum Kind: String, CaseIterable, Sendable {
        /// Claude finished its reply (the `Stop` hook).
        case done
        /// Claude waits for a permission answer (the `Notification` hook,
        /// matched on `permission_prompt`).
        case waiting
    }

    /// Lanes's folder for the hook, under Lanes's Application Support.
    public static let folderName = "ClaudeCodeHooks"
    /// Where the hook drops its event files, inside that folder.
    public static let eventsFolderName = "Events"
    public static let scriptName = "lanes-hook"
    /// The first line of every event file, so an older or foreign file is
    /// skipped.
    public static let eventHeader = "lanes-event 1"
    /// An event file is a few short lines. Anything bigger is not ours.
    public static let maximumEventSize = 4096

    public static func settingsFileName(for id: ProfileID) -> String {
        "settings-\(id.rawValue).json"
    }

    /// The hook. POSIX sh, run as `/bin/sh lanes-hook ID KIND`.
    ///
    /// The file is written under a temporary name and renamed, so Lanes
    /// never reads half of one. Claude Code starts hooks without a
    /// controlling terminal, so the hook walks up to the first ancestor
    /// that has one, which is the session's.
    public static var script: String {
        #"""
        #!/bin/sh
        # Lanes "Bitti Haberi" kancası. Lanes yazar; elle değiştirme.
        # Claude Code'un gönderdiği veri okunmadan atılır.
        cat >/dev/null 2>&1
        case "$1" in *[!A-Za-z0-9-]*|"") exit 0 ;; esac
        case "$2" in done|waiting) ;; *) exit 0 ;; esac
        dir="$(dirname "$0")/Events"
        [ -d "$dir" ] || exit 0
        # Claude Code runs hooks without a terminal of their own, so the
        # first ancestor that has one (Claude Code itself) names it.
        pid=$$
        tty=""
        for _ in 1 2 3 4 5; do
            t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
            case "$t" in
                ""|"?"|"??") pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
                    case "$pid" in ""|0|1) break ;; esac ;;
                *) tty=$t; break ;;
            esac
        done
        tmp="$dir/.$$.tmp"
        printf '%s\n%s\n%s\n%s\n%s\n%s\n' "lanes-event 1" "$1" "$2" "$tty" "${TERM_PROGRAM:-}" "${CLAUDE_PROJECT_DIR:-$PWD}" > "$tmp" 2>/dev/null || exit 0
        mv -f "$tmp" "$dir/$(date +%s)-$$.event" 2>/dev/null
        exit 0
        """#
    }

    /// The settings Lanes passes with `--settings`: only hooks, for the
    /// chosen kinds. `scriptPath` is quoted for the shell Claude Code runs
    /// hook commands with.
    public static func settings(scriptPath: String, profileID: ProfileID, kinds: Set<Kind>) -> Data {
        func command(_ kind: Kind) -> [String: Any] {
            [
                "type": "command",
                "command": "/bin/sh \(ClaudeCodeCommand.shellQuoted(scriptPath)) \(ClaudeCodeCommand.shellQuoted(profileID.rawValue)) \(kind.rawValue)",
                "timeout": 10,
            ]
        }
        var hooks: [String: Any] = [:]
        if kinds.contains(.done) {
            hooks["Stop"] = [["hooks": [command(.done)]]]
        }
        if kinds.contains(.waiting) {
            hooks["Notification"] = [["matcher": "permission_prompt", "hooks": [command(.waiting)]]]
        }
        let object: [String: Any] = ["hooks": hooks]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    }

    /// One event from the hook.
    public struct Event: Equatable, Sendable {
        public var profileID: ProfileID
        public var kind: Kind
        /// `ttys003`, or nil when the session had no terminal.
        public var tty: String?
        /// The terminal app's `TERM_PROGRAM`, such as `Apple_Terminal`.
        public var terminalProgram: String?
        /// The project folder, when it is an absolute path.
        public var projectPath: String?

        public init(profileID: ProfileID, kind: Kind, tty: String? = nil, terminalProgram: String? = nil, projectPath: String? = nil) {
            self.profileID = profileID
            self.kind = kind
            self.tty = tty
            self.terminalProgram = terminalProgram
            self.projectPath = projectPath
        }

        /// Reads an event file. Every field is checked, because any program
        /// of this user could drop a file there.
        public init?(contents: String) {
            let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 6, lines[0] == ClaudeCodeHooks.eventHeader else { return nil }
            let id = lines[1]
            guard !id.isEmpty, id.count <= 64, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  let kind = Kind(rawValue: lines[2]) else { return nil }
            self.profileID = ProfileID(rawValue: id)
            self.kind = kind
            self.tty = Self.validTTY(lines[3])
            let program = lines[4]
            self.terminalProgram = !program.isEmpty && program.count <= 64
                && program.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) ? program : nil
            let path = lines[5]
            self.projectPath = path.hasPrefix("/") && path.count <= 4096 && !path.contains(where: { $0.isNewline || $0 == "\0" }) ? path : nil
        }

        /// `ttys` and digits only, so it can go into an AppleScript safely.
        static func validTTY(_ value: String) -> String? {
            let name = value.hasPrefix("/dev/") ? String(value.dropFirst(5)) : value
            guard name.hasPrefix("ttys"), name.count > 4, name.count <= 8,
                  name.dropFirst(4).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return name
        }
    }

    /// The terminal apps Lanes can bring forward, by `TERM_PROGRAM`.
    public static func terminalBundleIdentifier(for program: String?) -> String? {
        switch program {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "WezTerm": return "com.github.wez.wezterm"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "vscode": return "com.microsoft.VSCode"
        default: return nil
        }
    }

    /// Terminal apps whose being in front means the user is likely watching
    /// a session already.
    public static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "com.github.wez.wezterm", "dev.warp.Warp-Stable", "com.microsoft.VSCode",
        "net.kovidgoyal.kitty", "org.alacritty",
    ]
}
