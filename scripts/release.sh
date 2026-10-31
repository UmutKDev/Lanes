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
#   - Sparkle's EdDSA private key in the login keychain, with its public half
#     in Config/Release.xcconfig (LANES_SPARKLE_PUBLIC_KEY). Sparkle's
#     generate_keys tool makes both.
#
# Usage: LANES_TEAM_ID=ABCDE12345 make release
# LANES_NOTARY_PROFILE picks another profile name (default lanes-notary).
# LANES_PUBLISH=1 also creates the GitHub release with the DMG and the update
# feed, using gh. Without it the script prints the command instead.
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
  -clonedSourcePackagesDirPath "$out/packages" \
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
# Without both, the released Lanes would never find its next update.
feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist" 2>/dev/null || true)
[ -n "$feed" ] || fail "SUFeedURL boş, Config/Release.xcconfig'te LANES_UPDATE_FEED_URL gerekli."
[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)" ] \
  || fail "SUPublicEDKey boş: Sparkle'ın generate_keys aracıyla anahtar üret, açık anahtarı Config/Release.xcconfig'te LANES_SPARKLE_PUBLIC_KEY'e yaz."

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
# hdiutil now and then writes a broken image; check it and try again once
# before it goes to notarization.
for attempt in 1 2; do
  hdiutil create -volname "Lanes" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
  if hdiutil verify "$dmg" >/dev/null 2>&1; then
    echo "DMG doğrulandı."
    break
  fi
  [[ $attempt == 2 ]] && fail "hdiutil bozuk bir DMG yazdı, iki denemede de."
  echo "DMG bozuk çıktı, yeniden hazırlanıyor."
done
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$dmg"

step "DMG onay taramasına gönderiliyor"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg" 2>&1 | tee "$out/spctl-dmg.txt"
grep -q "source=Notarized Developer ID" "$out/spctl-dmg.txt" || fail "spctl DMG'yi Notarized Developer ID olarak kabul etmedi."

step "Güncelleme kaydı hazırlanıyor"
# The feed points at .../OWNER/REPO/releases/latest/download/appcast.xml, so
# each release carries a feed that lists itself, downloaded from its own tag.
repo=$(printf '%s' "$feed" | sed -nE 's#^https://github.com/([^/]+/[^/]+)/releases/latest/download/appcast\.xml$#\1#p')
[ -n "$repo" ] || fail "SUFeedURL bir GitHub Releases adresi değil: $feed"
tag="v$version-$build"
updates="$out/updates"
mkdir -p "$updates"
cp "$dmg" "$updates/"
# Release notes for Sparkle's update window: the commit subjects since the
# previous release tag. generate_appcast picks the file up by the DMG's name.
previous=$(git describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null || true)
notes="$updates/$(basename "$dmg" .dmg).html"
{
  echo "<ul>"
  git log --no-merges --format='%s' ${previous:+"$previous..HEAD"} \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's#.*#<li>&</li>#'
  echo "</ul>"
} >"$notes"
generate_appcast="$out/packages/artifacts/sparkle/Sparkle/bin/generate_appcast"
[ -x "$generate_appcast" ] || fail "generate_appcast bulunamadı: $generate_appcast"
# Signs the DMG with the EdDSA key from the keychain and embeds the notes.
"$generate_appcast" --embed-release-notes --download-url-prefix "https://github.com/$repo/releases/download/$tag/" "$updates"
[ -f "$updates/appcast.xml" ] || fail "appcast.xml oluşmadı."

step "Hazır"
shasum -a 256 "$dmg"
echo "$dmg"
echo "$updates/appcast.xml"

publish=(gh release create "$tag" --repo "$repo" --title "Lanes $version ($build)" --notes "Commit $commit" "$updates/$(basename "$dmg")" "$updates/appcast.xml")
if [ "${LANES_PUBLISH:-}" = 1 ]; then
  step "GitHub'da yayınlanıyor"
  command -v gh >/dev/null || fail "gh gerekli: brew install gh"
  "${publish[@]}"
else
  echo
  echo "Yayınlamak için:"
  printf '%q ' "${publish[@]}"
  echo
fi
