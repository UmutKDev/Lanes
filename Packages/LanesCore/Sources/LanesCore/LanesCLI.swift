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
    public static let version = 1

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

        [ -f "$MAP" ] || die "Hesap haritası yok. Lanes'i bir kez aç." 2

        # Prints "id<TAB>name<TAB>configDir" for a name, ID or list number.
        find_account() {
            want=$1
            lower_want=$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')
            while IFS="$TAB" read -r kind id number name config; do
                [ "$kind" = "A" ] || continue
                lower_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
                if [ "$id" = "$want" ] || [ "$number" = "$want" ] || [ "$lower_name" = "$lower_want" ]; then
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

        # Sets FOUND ("id<TAB>name<TAB>config") and REASON for the current folder.
        resolve_here() {
            FOUND=""
            REASON=""
            dir=$(pwd -P)
            while :; do
                if [ -f "$dir/\#(folderFileName)" ]; then
                    IFS= read -r want < "$dir/\#(folderFileName)" || true
                    want=$(printf '%s' "$want" | tr -d '\r')
                    FOUND=$(find_account "$want") || die "$dir/\#(folderFileName) dosyasındaki \"$want\" hesabı Lanes'te yok."
                    REASON="$dir/\#(folderFileName)"
                    return 0
                fi
                [ "$dir" = "/" ] && break
                dir=$(dirname "$dir")
            done
            here=$(pwd -P)
            best=""
            best_id=""
            while IFS="$TAB" read -r kind id folder rest; do
                [ "$kind" = "L" ] || continue
                case "$here/" in
                    "$folder"/*)
                        if [ ${#folder} -gt ${#best} ]; then
                            best=$folder
                            best_id=$id
                        fi
                        ;;
                esac
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
            id=$1
            here=$(pwd -P)
            any=0
            while IFS="$TAB" read -r kind pid folder rest; do
                [ "$kind" = "P" ] && [ "$pid" = "$id" ] || continue
                any=1
                case "$here/" in
                    "$folder"/*) return 0 ;;
                esac
            done < "$MAP"
            [ "$any" = 0 ]
        }

        list_accounts() {
            while IFS="$TAB" read -r kind id number name config; do
                [ "$kind" = "A" ] && printf '%s\t%s\n' "$number" "$name"
            done < "$MAP"
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
                exec claude "$@"
                ;;
            which)
                pick
                printf '%s (%s)\n' "$NAME" "$REASON"
                ;;
            use)
                [ -n "$1" ] || die "Bir hesap adı yaz: lanes use HESAP"
                FOUND=$(find_account "$1") || die "\"$1\" adında bir hesap yok. Hesaplar için: lanes list"
                NAME=$(printf '%s' "$FOUND" | cut -f2)
                printf '%s\n' "$NAME" > "\#(folderFileName)" || die "\#(folderFileName) yazılamadı."
                printf 'Bu klasör artık %s hesabında. (%s/\#(folderFileName))\n' "$NAME" "$(pwd)"
                ;;
            list)
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
