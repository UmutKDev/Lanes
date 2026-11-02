#!/bin/bash
# Uploads the Chrome/Edge store ZIP to Microsoft Edge Add-ons and sends it to
# review, with the Edge Add-ons REST API (v1.1). Edge then updates everyone
# who installed Lanes from the store once the review passes.
#
#   scripts/edge-upload.sh <zip> [notes]
#
# Needs EDGE_CLIENT_ID, EDGE_API_KEY and EDGE_PRODUCT_ID (Partner Center >
# Microsoft Edge > Publish API, and the GUID on the extension's overview page).
#
# Exit codes: 0 sent to review, 3 Edge refused because a submission is still
# in review (nothing is lost, run again later), anything else is an error.
set -euo pipefail

zip=${1:?usage: edge-upload.sh <zip> [notes]}
notes=${2:-"Lanes update."}
: "${EDGE_CLIENT_ID:?}" "${EDGE_API_KEY:?}" "${EDGE_PRODUCT_ID:?}"
[ -s "$zip" ] || { echo "edge: ZIP yok: $zip" >&2; exit 1; }

api="https://api.addons.microsoftedge.microsoft.com/v1/products/$EDGE_PRODUCT_ID"
auth=(-H "Authorization: ApiKey $EDGE_API_KEY" -H "X-ClientID: $EDGE_CLIENT_ID")
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT

json_field() {
  python3 -c 'import json, sys; v = json.load(sys.stdin).get(sys.argv[1]); print("" if v is None else v)' "$1"
}

# POSTs and prints the operation ID from the Location header.
start() {
  local code
  code=$(curl -sS -o /dev/null -D "$headers" -w '%{http_code}' "${auth[@]}" -X POST "$@")
  if [ "$code" != 202 ]; then
    echo "edge: beklenmeyen yanıt $code" >&2
    cat "$headers" >&2
    exit 1
  fi
  awk 'tolower($1) == "location:" { gsub(/\r/, ""); n = split($2, p, "/"); print p[n] }' "$headers"
}

# Polls an operation until it leaves InProgress and prints its JSON.
wait_for() {
  local url=$1 body status
  for _ in $(seq 1 60); do
    body=$(curl -sS "${auth[@]}" "$url")
    status=$(printf '%s' "$body" | json_field status)
    if [ "$status" != InProgress ] && [ -n "$status" ]; then
      printf '%s' "$body"
      return
    fi
    sleep 5
  done
  echo "edge: işlem 5 dakikada bitmedi: $url" >&2
  exit 1
}

echo "Edge'e paket yükleniyor: $(basename "$zip")"
op=$(start -H "Content-Type: application/zip" --data-binary "@$zip" "$api/submissions/draft/package")
[ -n "$op" ] || { echo "edge: işlem kimliği gelmedi." >&2; exit 1; }
result=$(wait_for "$api/submissions/draft/package/operations/$op")
if [ "$(printf '%s' "$result" | json_field status)" != Succeeded ]; then
  echo "edge: paket yüklenemedi:" >&2
  printf '%s\n' "$result" >&2
  exit 1
fi
echo "$(printf '%s' "$result" | json_field message)"

echo "İncelemeye gönderiliyor"
payload=$(python3 -c 'import json, sys; print(json.dumps({"notes": sys.argv[1]}))' "$notes")
op=$(start -H "Content-Type: application/json" -d "$payload" "$api/submissions")
result=$(wait_for "$api/submissions/operations/$op")
status=$(printf '%s' "$result" | json_field status)
code=$(printf '%s' "$result" | json_field errorCode)
if [ "$status" = Succeeded ]; then
  echo "$(printf '%s' "$result" | json_field message)"
  exit 0
fi
printf '%s\n' "$result" >&2
[ "$code" = InProgressSubmission ] && exit 3
exit 1
