#!/bin/sh
# Builds the Chrome and Edge extension from the web files it shares with the
# Safari extension (LanesSafari/Resources) and the few files that differ
# (LanesChrome). No bundler: the files are copied as they are.
#
#   scripts/build-browser-extension.sh <out-folder>
#       An unpacked extension for "Load unpacked". Its manifest keeps the
#       development key, so the extension ID is always
#       gfddmgggahfmohadmaohjddpkhfnfaeg and Lanes's native host accepts it.
#       Xcode runs this to put the folder inside Lanes.app.
#
#   scripts/build-browser-extension.sh --store <zip-file>
#       The ZIP to upload to the Chrome Web Store and Edge Add-ons. The
#       stores give the extension their own ID, so the key is left out.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
store=false
if [ "${1:-}" = "--store" ]; then
    store=true
    shift
fi
target=${1:?usage: build-browser-extension.sh [--store] <out>}

if $store; then
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    folder="$work/LanesBrowser"
else
    folder=$target
fi

rm -rf "$folder"
mkdir -p "$folder"
# Shared web files, without Safari's manifest and texts.
(cd "$here/LanesSafari/Resources" && tar -cf - --exclude manifest.json --exclude _locales --exclude icons/icon-96.png --exclude icons/icon-256.png --exclude icons/icon-512.png --exclude icons/toolbar-19.png --exclude icons/toolbar-38.png .) | (cd "$folder" && tar -xf -)
# Chrome and Edge files on top.
(cd "$here/LanesChrome" && tar -cf - --exclude tools --exclude store --exclude '*.md' --exclude .DS_Store .) | (cd "$folder" && tar -xf -)

if $store; then
    python3 - "$folder/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path, encoding="utf-8"))
manifest.pop("key", None)
json.dump(manifest, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
    case $target in /*) out=$target ;; *) out=$(pwd)/$target ;; esac
    rm -f "$out"
    (cd "$folder" && zip -qrX "$out" . -x '.*')
    echo "$out"
else
    echo "$folder"
fi
