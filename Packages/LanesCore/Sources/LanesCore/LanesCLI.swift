import Foundation

/// The `lanes` command line tool: a small POSIX shell script Lanes writes to
/// `~/.local/bin/lanes`, plus an account map it reads. The map holds only
/// names, IDs and folder paths, never anything from inside an account.
public enum LanesCLI {
    /// The account map's name in Lanes's folder.
    public static let mapFileName = "cli-accounts.tsv"
    /// The file a project folder names its account in.
    public static let folderFileName = ".lanes"
    /// Bumped whenever the script changes, so Lanes rewrites an older copy.
    public static let version = 3

    /// One line per fact, tab separated:
    /// `A id number name configDir` (configDir "-" for Claude's own),
    /// `L id folder` for a linked folder, `P id folder` for an allowed one,
    /// `H id file` for the "Bitti Haberi" settings file Claude Code gets
    /// with `--settings`. Archived accounts are left out.
    public static func map(library: ProfileLibrary, paths: ProfilePaths, hookSettings: [ProfileID: String] = [:]) -> String {
        var lines = [L("# Lanes hesap haritası. Lanes yazar, elle değiştirme.", "# Lanes account map. Written by Lanes; don’t edit it by hand.")]
        for (index, profile) in library.activeProfiles.enumerated() {
            let config = paths.claudeCodeConfigDirectory(for: profile)?.path ?? "-"
            lines.append(["A", profile.id.rawValue, String(index + 1), clean(profile.name), clean(config)].joined(separator: "\t"))
            for folder in profile.linkedFolders {
                lines.append(["L", profile.id.rawValue, clean(trimmed(folder))].joined(separator: "\t"))
            }
            for folder in profile.allowedFolders {
                lines.append(["P", profile.id.rawValue, clean(trimmed(folder))].joined(separator: "\t"))
            }
            if let file = hookSettings[profile.id] {
                lines.append(["H", profile.id.rawValue, clean(file)].joined(separator: "\t"))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Tabs and line breaks would split a line, so they become spaces.
    static func clean(_ value: String) -> String {
        value.map { $0 == "\t" || $0.isNewline ? " " : String($0) }.joined()
    }

    /// Folders are compared as plain prefixes, so a trailing slash goes.
    static func trimmed(_ folder: String) -> String {
        var folder = folder
        while folder.count > 1 && folder.hasSuffix("/") {
            folder.removeLast()
        }
        return folder
    }

    /// Whether a file holds a script this Lanes wrote, of any version, so
    /// Lanes never overwrites someone else's `lanes` command.
    public static func isOurs(_ contents: String) -> Bool {
        contents.contains(marker)
    }

    /// Whether the file is this version of the script in `language`. A
    /// script from an older Lanes, or written in the other language, is
    /// not current, so Lanes rewrites it.
    public static func isCurrent(_ contents: String, language: CoreLanguage = .current) -> Bool {
        contents.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0 == markerLine(language: language) }
    }

    static let marker = "# lanes-cli-version"

    /// `# lanes-cli-version 3 en`. Older scripts have no language at the end;
    /// `isOurs` still knows them by the marker.
    static func markerLine(language: CoreLanguage) -> String {
        "\(marker) \(version) \(language.rawValue)"
    }

    /// The script, its messages and help in `language`. POSIX sh, so it
    /// runs the same from zsh, bash or fish. `lanes help` prints lines 6 to
    /// 11, so the header keeps the same number of lines in both languages.
    public static func script(language: CoreLanguage = .current) -> String {
        func t(_ turkish: String, _ english: String) -> String {
            language.text(turkish, english)
        }
        let header = t(
            """
            # Lanes komut satırı aracı. Lanes yazar ve günceller; elle yapılan
            # değişiklikler bir sonraki güncellemede gider.
            #
            #   lanes claude [claude argümanları]   Bu klasörün hesabıyla Claude Code
            #   lanes -a HESAP claude ...           Belirli bir hesapla Claude Code
            #   lanes which                         Bu klasör hangi hesapta, neden
            #   lanes use HESAP                     Bu klasörü bir hesaba bağla (.lanes)
            #   lanes list                          Hesaplar
            #   lanes open HESAP                    Hesabın Claude uygulamasını aç
            """,
            """
            # The Lanes command line tool. Lanes writes and updates it; changes
            # made by hand are lost at the next update.
            #
            #   lanes claude [claude arguments]     Claude Code with this folder's account
            #   lanes -a ACCOUNT claude ...         Claude Code with a specific account
            #   lanes which                         Which account this folder uses, and why
            #   lanes use ACCOUNT                   Link this folder to an account (.lanes)
            #   lanes list                          Accounts
            #   lanes open ACCOUNT                  Open the account's Claude app
            """
        )
        let file = folderFileName
        let noMap = t("Hesap haritası yok. Lanes'i bir kez aç.", "No account map found. Open Lanes once.")
        let missingInFile = t(#"$file dosyasındaki \"$want\" hesabı Lanes'te yok."#, #"The account \"$want\" in $file isn't in Lanes."#)
        let linkedFolder = t("bağlı klasör", "linked folder")
        let needName = t("-a için bir hesap adı yaz.", "Enter an account name after -a.")
        func noAccount(_ variable: String) -> String {
            t(#"\"\#(variable)\" adında bir hesap yok. Hesaplar için: lanes list"#, #"There's no account named \"\#(variable)\". To see accounts: lanes list"#)
        }
        let notLinked = t(
            #"Bu klasör bir hesaba bağlı değil. \"lanes use HESAP\" ile bağla ya da \"lanes -a HESAP claude\" kullan."#,
            #"This folder isn't linked to an account. Link it with \"lanes use ACCOUNT\" or use \"lanes -a ACCOUNT claude\"."#
        )
        let notAllowed = t(
            "$NAME hesabı için Claude Code yalnız izin verilen klasörlerde açılır. Lanes'te hesabın Güvenlik sekmesine bak.",
            "For the $NAME account, Claude Code opens only in allowed folders. See the account's Security tab in Lanes."
        )
        let noClaude = t("Claude Code bulunamadı. Lanes'in Kurulum sayfasından kurabilirsin.", "Claude Code wasn't found. You can install it from the Setup page in Lanes.")
        // Single-quoted printf formats: no apostrophes in these two.
        let usingFormat = t(#"lanes: %s hesabıyla (%s)\n"#, #"lanes: using the %s account (%s)\n"#)
        let nowUsesFormat = t(#"Bu klasör artık %s hesabında. (%s/\#(file))\n"#, #"This folder now uses the %s account. (%s/\#(file))\n"#)
        let useNeedsName = t("Bir hesap adı yaz: lanes use HESAP", "Enter an account name: lanes use ACCOUNT")
        let isLink = t(
            "\(file) bir kısayol (symlink); Lanes onun gösterdiği dosyaya yazmaz. Önce sil.",
            "\(file) is a symbolic link; Lanes doesn't write to the file it points to. Delete it first."
        )
        let notWritten = t("\(file) yazılamadı.", "Couldn't write \(file).")
        let unknownCommand = t("Bilinmeyen komut: $command. Yardım için: lanes help", "Unknown command: $command. For help: lanes help")
        return #"""
        #!/bin/sh
        \#(markerLine(language: language))
        \#(header)

        MAP="$HOME/Library/Application Support/Lanes/\#(mapFileName)"
        TAB=$(printf '\t')

        die() { printf 'lanes: %s\n' "$1" >&2; exit "${2:-1}"; }
        # Text from a folder's .lanes file is shown without control
        # characters, so a file in a cloned repository cannot drive the
        # terminal.
        plain() { printf '%s' "$1" | tr -d '[:cntrl:]'; }

        need_map() {
            [ -f "$MAP" ] || die "\#(noMap)" 2
        }

        # Prints "id<TAB>name<TAB>configDir" for a name, ID or list number.
        # With "strict" as the second argument a list number does not count,
        # which is how .lanes files are read: numbers change with the order.
        find_account() {
            want=$1
            lower_want=$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')
            while IFS="$TAB" read -r kind id number name config; do
                [ "$kind" = "A" ] || continue
                lower_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
                by_number=0
                [ "$2" != "strict" ] && [ "$number" = "$want" ] && by_number=1
                if [ "$id" = "$want" ] || [ "$by_number" = 1 ] || [ "$lower_name" = "$lower_want" ]; then
                    printf '%s\t%s\t%s\n' "$id" "$name" "$config"
                    return 0
                fi
            done < "$MAP"
            return 1
        }

        account_by_id() {
            while IFS="$TAB" read -r kind id number name config; do
                if [ "$kind" = "A" ] && [ "$id" = "$1" ]; then
                    printf '%s\t%s\t%s\n' "$id" "$name" "$config"
                    return 0
                fi
            done < "$MAP"
            return 1
        }

        HERE_P=$(pwd -P)
        HERE_L=$(pwd -L 2>/dev/null || pwd)

        # Whether the current folder is $1 or inside it, by its real path or
        # by the path it was reached through.
        inside() {
            [ "$1" = "/" ] && return 0
            case "$HERE_P/" in "$1"/*) return 0 ;; esac
            case "$HERE_L/" in "$1"/*) return 0 ;; esac
            return 1
        }

        # Sets FOUND ("id<TAB>name<TAB>config") and REASON for the current folder.
        resolve_here() {
            FOUND=""
            REASON=""
            dir=$HERE_P
            while :; do
                file="$dir/\#(folderFileName)"
                if [ -f "$file" ] && [ ! -L "$file" ]; then
                    IFS= read -r want < "$file" || true
                    want=$(plain "$want")
                    FOUND=$(find_account "$want" strict) || die "\#(missingInFile)"
                    REASON="$file"
                    return 0
                fi
                [ "$dir" = "/" ] && break
                dir=$(dirname "$dir")
            done
            best=""
            best_id=""
            while IFS="$TAB" read -r kind id folder rest; do
                [ "$kind" = "L" ] || continue
                if inside "$folder" && [ ${#folder} -gt ${#best} ]; then
                    best=$folder
                    best_id=$id
                fi
            done < "$MAP"
            if [ -n "$best_id" ]; then
                FOUND=$(account_by_id "$best_id") || return 1
                REASON="\#(linkedFolder) $best"
                return 0
            fi
            return 1
        }

        # Whether the account may run Claude Code here (Güvenlik sekmesi).
        allowed_here() {
            any=0
            while IFS="$TAB" read -r kind pid folder rest; do
                [ "$kind" = "P" ] && [ "$pid" = "$1" ] || continue
                any=1
                inside "$folder" && return 0
            done < "$MAP"
            [ "$any" = 0 ]
        }

        list_accounts() {
            while IFS="$TAB" read -r kind id number name config; do
                [ "$kind" = "A" ] || continue
                printf '%s\t%s\n' "$number" "$name"
            done < "$MAP"
            return 0
        }

        ACCOUNT=""
        if [ "$1" = "-a" ] || [ "$1" = "--hesap" ] || [ "$1" = "--account" ]; then
            [ -n "$2" ] || die "\#(needName)"
            ACCOUNT=$2
            shift 2
        fi

        command=${1:-help}
        [ $# -gt 0 ] && shift

        pick() {
            need_map
            if [ -n "$ACCOUNT" ]; then
                FOUND=$(find_account "$ACCOUNT") || die "\#(noAccount("$ACCOUNT"))"
                REASON="-a $ACCOUNT"
            elif ! resolve_here; then
                die "\#(notLinked)"
            fi
            ID=$(printf '%s' "$FOUND" | cut -f1)
            NAME=$(printf '%s' "$FOUND" | cut -f2)
            CONFIG=$(printf '%s' "$FOUND" | cut -f3)
        }

        case "$command" in
            claude)
                pick
                allowed_here "$ID" || die "\#(notAllowed)"
                export PATH="$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH"
                if [ "$CONFIG" = "-" ]; then
                    unset CLAUDE_CONFIG_DIR
                else
                    mkdir -p "$CONFIG"
                    export CLAUDE_CONFIG_DIR="$CONFIG"
                fi
                command -v claude >/dev/null 2>&1 || die "\#(noClaude)"
                printf '\#(usingFormat)' "$(plain "$NAME")" "$(plain "$REASON")" >&2
                HOOKS=$(awk -F "$TAB" -v id="$ID" '$1 == "H" && $2 == id { print $3; exit }' "$MAP")
                if [ -n "$HOOKS" ] && [ -f "$HOOKS" ]; then
                    exec claude --settings "$HOOKS" "$@"
                fi
                exec claude "$@"
                ;;
            which)
                pick
                printf '%s (%s)\n' "$(plain "$NAME")" "$(plain "$REASON")"
                ;;
            use)
                need_map
                [ -n "$1" ] || die "\#(useNeedsName)"
                FOUND=$(find_account "$1") || die "\#(noAccount("$1"))"
                ID=$(printf '%s' "$FOUND" | cut -f1)
                NAME=$(printf '%s' "$FOUND" | cut -f2)
                [ -L "\#(folderFileName)" ] && die "\#(isLink)"
                # The ID stays right when the account is renamed; the name
                # on the next line is only for people reading the file.
                printf '%s\n# %s\n' "$ID" "$NAME" > "\#(folderFileName)" || die "\#(notWritten)"
                printf '\#(nowUsesFormat)' "$NAME" "$(pwd)"
                ;;
            list)
                need_map
                list_accounts
                ;;
            open)
                if [ -n "$1" ]; then ACCOUNT=$1; fi
                pick
                /usr/bin/open "lanes://open?account=$ID"
                ;;
            help|-h|--help)
                sed -n '6,11p' "$0" | sed 's/^# \{0,1\}//'
                ;;
            *)
                die "\#(unknownCommand)"
                ;;
        esac
        """#
    }
}
