#!/bin/bash
# Builds a Developer ID signed, notarized Lanes DMG: archive, export, notarize
# and staple the app, then put it in a DMG and notarize and staple that too.
# Every step is checked before the next one starts, so a DMG only appears when
# macOS would open it without a warning.
#
# Needs, once per Mac:
#   - Xcode 27. Xcode 26 builds leave out the macOS 27 menu bar code.
#   - A "Developer ID Application" certificate for LANES_TEAM_ID in the login
#     keychain.
#   - notarytool credentials saved under a keychain profile:
#       xcrun notarytool store-credentials lanes-notary
#
# Usage: LANES_TEAM_ID=ABCDE12345 make release
# LANES_NOTARY_PROFILE picks another profile name (default lanes-notary).
set -euo pipefail

fail() {
  echo "release: $*" >&2
  exit 1
}

step() {
  echo
  echo "==> $*"
}

team="${LANES_TEAM_ID:-}"
profile="${LANES_NOTARY_PROFILE:-lanes-notary}"

[ "$(uname -s)" = Darwin ] || fail "yalnız macOS'ta çalışır."
[ -n "$team" ] || fail "LANES_TEAM_ID gerekli, örnek: LANES_TEAM_ID=ABCDE12345 make release"

root=$(git rev-parse --show-toplevel)
cd "$root"

# Release builds come only from Xcode 27, see the comment at the top.
xcode_major=$(xcodebuild -version | awk 'NR == 1 { split($2, v, "."); print v[1] }')
[ "${xcode_major:-0}" -ge 27 ] || fail "Xcode 27 gerekli, seçili olan: $(xcodebuild -version | head -1)"

command -v xcodegen >/dev/null || fail "XcodeGen gerekli: brew install xcodegen"

# The build number comes from the commit count, so it has to be the whole
# history and a commit that exists elsewhere too.
[ "$(git rev-parse --is-shallow-repository)" = false ] || fail "sığ klon: önce git fetch --unshallow"
[ -z "$(git status --porcelain)" ] || fail "kaydedilmemiş değişiklik var, sürüm yalnız temiz bir commit'ten çıkar."

# The first valid Developer ID Application identity whose name ends in
# "(TEAM)". The DMG is signed by its SHA-1, which stays unambiguous when the
# keychain also holds an expired certificate with the same name.
identity=$(security find-identity -v -p codesigning \
  | awk -v team="($team)\"" '/"Developer ID Application: / && index($0, team) { print $2; exit }')
[ -n "$identity" ] || fail "Anahtar Zinciri'nde $team için Developer ID Application sertifikası yok."

version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
build=$(git rev-list --count HEAD)
commit=$(git rev-parse --short=12 HEAD)
[ -n "$version" ] || fail "project.yml'de MARKETING_VERSION bulunamadı."

out="build/release/$version-$build"
archive="$out/Lanes.xcarchive"
export_dir="$out/export"
app="$export_dir/Lanes.app"
dmg="$out/Lanes-$version-$build.dmg"
rm -rf "$out"
mkdir -p "$out"

echo "Lanes $version ($build), commit $commit, ekip $team"

# Submits a file, waits for Apple's answer and prints the log when it is not
# "Accepted". notarytool exits 0 for a rejected submission, so the status is
# read from its JSON output.
notarize() {
  local file=$1 result="$out/notarytool.json" status id
  xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --output-format json >"$result"
  status=$(plutil -extract status raw -o - "$result" 2>/dev/null || true)
  id=$(plutil -extract id raw -o - "$result" 2>/dev/null || true)
  if [ "$status" != Accepted ]; then
    cat "$result" >&2
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
    fail "onay taraması reddetti: $file (durum: ${status:-bilinmiyor})"
  fi
  echo "Onay taraması kabul etti ($id)."
}

step "Proje oluşturuluyor"
xcodegen generate

step "Arşivleniyor"
xcodebuild \
  -project Lanes.xcodeproj \
  -scheme Lanes \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  LANES_TEAM_ID="$team" \
  CURRENT_PROJECT_VERSION="$build" \
  archive

step "Developer ID ile dışa aktarılıyor"
options="$out/ExportOptions.plist"
cp Config/ExportOptions.plist "$options"
/usr/libexec/PlistBuddy -c "Add :teamID string $team" "$options"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" -exportOptionsPlist "$options"
[ -d "$app" ] || fail "dışa aktarılan uygulama bulunamadı: $app"

step "İmza denetleniyor"
codesign --verify --deep --strict --verbose=2 "$app"
details=$(codesign -dvv "$app" 2>&1)
printf '%s\n' "$details" | grep -q "^Authority=Developer ID Application: " || fail "uygulama Developer ID ile imzalanmamış."
printf '%s\n' "$details" | grep -q "^TeamIdentifier=$team$" || fail "uygulamanın ekip kimliği $team değil."
printf '%s\n' "$details" | grep -q "flags=.*runtime" || fail "hardened runtime açık değil, onay taraması reddeder."
plist="$app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$build" ] || fail "CFBundleVersion $build değil."
[ "$(/usr/libexec/PlistBuddy -c 'Print :LanesGitCommit' "$plist")" = "$commit" ] || fail "LanesGitCommit $commit değil."
[ "$(/usr/libexec/PlistBuddy -c 'Print :LanesGitTreeDirty' "$plist")" = false ] || fail "derleme kirli çalışma ağacından yapılmış."

step "Uygulama onay taramasına gönderiliyor"
zip="$out/Lanes.zip"
ditto -c -k --keepParent "$app" "$zip"
notarize "$zip"
rm -f "$zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app" 2>&1 | tee "$out/spctl-app.txt"
grep -q "source=Notarized Developer ID" "$out/spctl-app.txt" || fail "spctl uygulamayı Notarized Developer ID olarak kabul etmedi."

step "DMG hazırlanıyor"
staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Lanes.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Lanes" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg"

step "DMG onay taramasına gönderiliyor"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" 2>&1 | tee "$out/spctl-dmg.txt"
grep -q "source=Notarized Developer ID" "$out/spctl-dmg.txt" || fail "spctl DMG'yi Notarized Developer ID olarak kabul etmedi."

step "Hazır"
shasum -a 256 "$dmg"
echo "$dmg"
