#!/bin/bash
# Saves the secrets the Release workflow (.github/workflows/release.yml)
# needs into the GitHub repository, from the Mac that makes releases today.
# Run it once, and again only when a certificate or password changes:
#
#   scripts/setup-release-secrets.sh
#
# Needs gh signed in (gh auth status) and, before you start:
#   1. The Developer ID certificate exported as a .p12 file: Keychain Access >
#      login > My Certificates > "Developer ID Application: ..." > right-click
#      > Export. Pick a password; the script asks for it.
#   2. An app-specific password for your Apple ID, made at
#      https://account.apple.com > Sign-In and Security > App-Specific
#      Passwords.
# The Sparkle key is read from the login keychain by Sparkle's own
# generate_keys tool (macOS asks to allow it once).
set -euo pipefail

repo=UmutKDev/Lanes
root=$(cd "$(dirname "$0")/.." && pwd)

fail() {
  echo "kurulum: $*" >&2
  exit 1
}

command -v gh >/dev/null || fail "gh gerekli: brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh oturumu yok: gh auth login"

read -r -p "Developer ID .p12 dosyası (sürükleyip bırakabilirsin): " p12
p12=${p12%"${p12##*[![:space:]]}"}
p12=${p12//\\ / }
p12=${p12#\'}; p12=${p12%\'}
[ -f "$p12" ] || fail "dosya yok: $p12"
read -r -s -p ".p12 parolası: " p12_password; echo
openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys -legacy 2>/dev/null | grep -q "Developer ID Application" \
  || openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys 2>/dev/null | grep -q "Developer ID Application" \
  || fail ".p12 açılamadı ya da içinde Developer ID Application sertifikası yok."

read -r -p "Apple ID e-postası: " apple_id
read -r -s -p "Uygulamaya özel parola (xxxx-xxxx-xxxx-xxxx): " notary_password; echo

# Sparkle comes with the Swift package, so generate_keys is in an earlier
# release build or in Xcode's DerivedData.
generate_keys=$(
  { ls -d "$root"/build/release/*/packages/artifacts/sparkle/Sparkle/bin/generate_keys \
      "$HOME"/Library/Developer/Xcode/DerivedData/Lanes-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys; } 2>/dev/null \
    | tail -1
)
[ -x "$generate_keys" ] || fail "Sparkle generate_keys bulunamadı. Önce Lanes'i bir kez Xcode'da derle (make build)."
key_file=$(mktemp)
trap 'rm -P "$key_file" 2>/dev/null || rm -f "$key_file"' EXIT
rm -f "$key_file"
"$generate_keys" -x "$key_file" >/dev/null
[ -s "$key_file" ] || fail "Sparkle özel anahtarı dışa aktarılamadı."

echo "GitHub'a kaydediliyor ($repo)..."
base64 -i "$p12" | gh secret set LANES_DEVELOPER_ID_P12 --repo "$repo"
printf '%s' "$p12_password" | gh secret set LANES_DEVELOPER_ID_P12_PASSWORD --repo "$repo"
printf '%s' "$apple_id" | gh secret set LANES_NOTARY_APPLE_ID --repo "$repo"
printf '%s' "$notary_password" | gh secret set LANES_NOTARY_PASSWORD --repo "$repo"
gh secret set LANES_SPARKLE_PRIVATE_KEY --repo "$repo" <"$key_file"

echo "Tamam. .p12 dosyasını artık silebilirsin."
echo "Sürüm için: https://github.com/$repo/actions/workflows/release.yml > Run workflow"
