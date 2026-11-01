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
    public static let version = 2

    /// One line per fact, tab separated:
    /// `A id number name configDir` (configDir "-" for Claude's own),
    /// `L id folder` for a linked folder, `P id folder` for an allowed one.
    /// Archived accounts are left out.
    public static func map(library: ProfileLibrary, paths: ProfilePaths) -> String {
        var lines = ["# Lanes hesap haritası. Lanes yazar, elle değiştirme."]
        for (index, profile) in library.activeProfiles.enumerated() {
            let config = paths.claudeCodeConfigDirectory(for: profile)?.path ?? "-"
            lines.append(["A", profile.id.rawValue, String(index + 1), clean(profile.name), clean(config)].joined(separator: "\t"))
            for folder in profile.linkedFolders {
                lines.append(["L", profile.id.rawValue, clean(trimmed(folder))].joined(separator: "\t"))
            }
            for folder in profile.allowedFolders {
                lines.append(["P", profile.id.rawValue, clean(trimmed(folder))].joined(separator: "\t"))
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

    public static func isCurrent(_ contents: String) -> Bool {
        contents.contains("\(marker) \(version)")
    }

    static let marker = "# lanes-cli-version"

    /// The script. POSIX sh, so it runs the same from zsh, bash or fish.
    public static var script: String {
        #"""
        #!/bin/sh
        \#(marker) \#(version)
        # Lanes komut satırı aracı. Lanes yazar ve günceller; elle yapılan
        # değişiklikler bir sonraki güncellemede gider.
        #
        #   lanes claude [claude argümanları]   Bu klasörün hesabıyla Claude Code
        #   lanes -a HESAP claude ...           Belirli bir hesapla Claude Code
        #   lanes which                         Bu klasör hangi hesapta, neden
        #   lanes use HESAP                     Bu klasörü bir hesaba bağla (.lanes)
        #   lanes list                          Hesaplar
        #   lanes open HESAP                    Hesabın Claude uygulamasını aç

        MAP="$HOME/Library/Application Support/Lanes/\#(mapFileName)"
        TAB=$(printf '\t')

        die() { printf 'lanes: %s\n' "$1" >&2; exit "${2:-1}"; }
        # Text from a folder's .lanes file is shown without control
        # characters, so a file in a cloned repository cannot drive the
        # terminal.
        plain() { printf '%s' "$1" | tr -d '[:cntrl:]'; }

        need_map() {
            [ -f "$MAP" ] || die "Hesap haritası yok. Lanes'i bir kez aç." 2
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
                    FOUND=$(find_account "$want" strict) || die "$file dosyasındaki \"$want\" hesabı Lanes'te yok."
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
                REASON="bağlı klasör $best"
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
            [ -n "$2" ] || die "-a için bir hesap adı yaz."
            ACCOUNT=$2
            shift 2
        fi

        command=${1:-help}
        [ $# -gt 0 ] && shift

        pick() {
            need_map
            if [ -n "$ACCOUNT" ]; then
                FOUND=$(find_account "$ACCOUNT") || die "\"$ACCOUNT\" adında bir hesap yok. Hesaplar için: lanes list"
                REASON="-a $ACCOUNT"
            elif ! resolve_here; then
                die "Bu klasör bir hesaba bağlı değil. \"lanes use HESAP\" ile bağla ya da \"lanes -a HESAP claude\" kullan."
            fi
            ID=$(printf '%s' "$FOUND" | cut -f1)
            NAME=$(printf '%s' "$FOUND" | cut -f2)
            CONFIG=$(printf '%s' "$FOUND" | cut -f3)
        }

        case "$command" in
            claude)
                pick
                allowed_here "$ID" || die "$NAME hesabı için Claude Code yalnız izin verilen klasörlerde açılır. Lanes'te hesabın Güvenlik sekmesine bak."
                export PATH="$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH"
                if [ "$CONFIG" = "-" ]; then
                    unset CLAUDE_CONFIG_DIR
                else
                    mkdir -p "$CONFIG"
                    export CLAUDE_CONFIG_DIR="$CONFIG"
                fi
                command -v claude >/dev/null 2>&1 || die "Claude Code bulunamadı. Lanes'in Kurulum sayfasından kurabilirsin."
                printf 'lanes: %s hesabıyla (%s)\n' "$(plain "$NAME")" "$(plain "$REASON")" >&2
                exec claude "$@"
                ;;
            which)
                pick
                printf '%s (%s)\n' "$(plain "$NAME")" "$(plain "$REASON")"
                ;;
            use)
                need_map
                [ -n "$1" ] || die "Bir hesap adı yaz: lanes use HESAP"
                FOUND=$(find_account "$1") || die "\"$1\" adında bir hesap yok. Hesaplar için: lanes list"
                ID=$(printf '%s' "$FOUND" | cut -f1)
                NAME=$(printf '%s' "$FOUND" | cut -f2)
                [ -L "\#(folderFileName)" ] && die "\#(folderFileName) bir kısayol (symlink); Lanes onun gösterdiği dosyaya yazmaz. Önce sil."
                # The ID stays right when the account is renamed; the name
                # on the next line is only for people reading the file.
                printf '%s\n# %s\n' "$ID" "$NAME" > "\#(folderFileName)" || die "\#(folderFileName) yazılamadı."
                printf 'Bu klasör artık %s hesabında. (%s/\#(folderFileName))\n' "$NAME" "$(pwd)"
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
                die "Bilinmeyen komut: $command. Yardım için: lanes help"
                ;;
        esac
        """#
    }
}
