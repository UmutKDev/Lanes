#!/bin/bash
# Builds "Lanes for Safari" (the LanesForSafari scheme: a small sandboxed app
# that only carries the Lanes Safari extension) for the Mac App Store and,
# with LANES_UPLOAD=1, uploads it to App Store Connect. Lanes itself is not
# built here: it stays outside the store (see docs/app-store.md).
#
# Needs:
#   - Xcode 27 and XcodeGen (brew install xcodegen).
#   - An App Store Connect API key with the Admin role (Users and Access >
#     Integrations > Team Keys), so Xcode can make the store profiles and sign
#     with Apple's cloud-managed distribution certificate:
#       ASC_KEY_ID       the key's ID
#       ASC_ISSUER_ID    the issuer ID shown above the key list
#       ASC_KEY_FILE     path to the downloaded AuthKey_<ID>.p8
#   - The app record in App Store Connect, bundle ID com.umutkdev.LanesForSafari.
#
# The build number is the commit count, the same as Lanes releases, so every
# upload from a newer commit is accepted. Without LANES_UPLOAD=1 the signed
# .pkg is only exported into build/app-store/<version>-<build>/.
set -euo pipefail

fail() {
  echo "app-store: $*" >&2
  exit 1
}

step() {
  echo
  echo "==> $*"
}

[ "$(uname -s)" = Darwin ] || fail "yalnız macOS'ta çalışır."
root=$(git rev-parse --show-toplevel)
cd "$root"

xcode_major=$(xcodebuild -version | awk 'NR == 1 { split($2, v, "."); print v[1] }')
[ "${xcode_major:-0}" -ge 27 ] || fail "Xcode 27 gerekli, seçili olan: $(xcodebuild -version | head -1)"
command -v xcodegen >/dev/null || fail "XcodeGen gerekli: brew install xcodegen"

for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_FILE; do
  [ -n "${!name:-}" ] || fail "$name gerekli."
done
[ -s "$ASC_KEY_FILE" ] || fail "ASC_KEY_FILE boş ya da yok: $ASC_KEY_FILE"

[ "$(git rev-parse --is-shallow-repository)" = false ] || fail "sığ klon: önce git fetch --unshallow"
[ -z "$(git status --porcelain)" ] || fail "kaydedilmemiş değişiklik var, mağaza sürümü yalnız temiz bir commit'ten çıkar."

version=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
build=$(git rev-list --count HEAD)
[ -n "$version" ] || fail "project.yml'de MARKETING_VERSION bulunamadı."

out="build/app-store/$version-$build"
rm -rf "$out"
mkdir -p "$out"
archive="$out/LanesForSafari.xcarchive"
auth=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$(cd "$(dirname "$ASC_KEY_FILE")" && pwd)/$(basename "$ASC_KEY_FILE")"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

step "Proje oluşturuluyor"
xcodegen generate

step "Lanes for Safari $version ($build) arşivleniyor"
xcodebuild \
  -project Lanes.xcodeproj \
  -scheme LanesForSafari \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  -derivedDataPath "$out/dd" \
  "${auth[@]}" \
  CURRENT_PROJECT_VERSION="$build" \
  archive

destination=export
[ "${LANES_UPLOAD:-}" = 1 ] && destination=upload
options="$out/ExportOptions.plist"
cat >"$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>TN6A8RCVKP</string>
	<key>destination</key>
	<string>$destination</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST

if [ "$destination" = upload ]; then
  step "App Store Connect'e yükleniyor"
else
  step "Mağaza paketi hazırlanıyor (yüklemek için LANES_UPLOAD=1)"
fi
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$options" \
  -exportPath "$out/export" \
  "${auth[@]}"

# Xcode registers every app it builds with LaunchServices, and Safari would
# then list this build's extension next to the installed one.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
while IFS= read -r -d '' copy; do
  "$lsregister" -u "$copy" >/dev/null 2>&1 || true
done < <(find "$out" -name 'Lanes for Safari.app' -type d -prune -print0 2>/dev/null)
rm -rf "$out/dd"

step "Hazır"
if [ "$destination" = upload ]; then
  echo "Lanes for Safari $version ($build) App Store Connect'e yüklendi. İşlenmesi birkaç dakika sürer, sonra TestFlight ve sürüm sayfasında görünür."
else
  ls "$out/export"
fi
