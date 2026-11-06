#!/bin/bash
# Saves the App Store Connect API key the App Store workflow
# (.github/workflows/app-store.yml) needs into the GitHub repository. Run it
# once, and again only when the key changes:
#
#   scripts/setup-app-store-secrets.sh
#
# Needs gh signed in (gh auth status) and, before you start, a Team API key
# with the Admin role: App Store Connect > Users and Access > Integrations >
# App Store Connect API > Team Keys > "+". Download the AuthKey_<ID>.p8 file
# (Apple lets you download it only once) and note the Issuer ID shown above
# the key list.
set -euo pipefail

repo=UmutKDev/Lanes

fail() {
  echo "kurulum: $*" >&2
  exit 1
}

command -v gh >/dev/null || fail "gh gerekli: brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh oturumu yok: gh auth login"

read -r -p "AuthKey_....p8 dosyası (sürükleyip bırakabilirsin): " p8
p8=${p8%"${p8##*[![:space:]]}"}
p8=${p8//\\ / }
p8=${p8#\'}; p8=${p8%\'}
[ -f "$p8" ] || fail "dosya yok: $p8"
grep -q "BEGIN PRIVATE KEY" "$p8" || fail "bu bir App Store Connect API anahtarı değil: $p8"

# AuthKey_ABC123DEF4.p8 carries the key ID in its name.
key_id=$(basename "$p8" | sed -nE 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/p')
if [ -z "$key_id" ]; then
  read -r -p "Anahtar kimliği (Key ID): " key_id
fi
read -r -p "Issuer ID (anahtar listesinin üstünde): " issuer_id
[ -n "$key_id" ] && [ -n "$issuer_id" ] || fail "Key ID ve Issuer ID gerekli."

echo "GitHub'a kaydediliyor ($repo)..."
printf '%s' "$key_id" | gh secret set ASC_KEY_ID --repo "$repo"
printf '%s' "$issuer_id" | gh secret set ASC_ISSUER_ID --repo "$repo"
gh secret set ASC_KEY_P8 --repo "$repo" <"$p8"
echo "Tamam. Actions > App Store > Run workflow ile Lanes for Safari derlenip App Store Connect'e yüklenir."
