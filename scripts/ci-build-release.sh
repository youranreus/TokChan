#!/usr/bin/env bash
# Import credentials only for this build; never persist them in the checkout.
set +x
set -euo pipefail
original_umask=$(umask)
umask 077

for name in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD SPARKLE_PUBLIC_ED_KEY; do
  [[ -n "${!name:-}" ]] || { echo "Missing required release value: $name" >&2; exit 1; }
done
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid APPLE_TEAM_ID' >&2; exit 1; }
[[ "$APPLE_SIGNING_IDENTITY" == "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]] || {
  echo 'APPLE_SIGNING_IDENTITY must be a Developer ID Application identity for APPLE_TEAM_ID' >&2
  exit 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
credential_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/tokchan-signing.XXXXXX")
export APPLE_KEYCHAIN_PATH="$credential_dir/signing.keychain-db"
export APPLE_NOTARY_PROFILE=tokchan-release
keychain_password=$(openssl rand -hex 32)
keychain_created=false
search_list_changed=false
original_keychains=()

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if $search_list_changed; then
    security list-keychains -d user -s "${original_keychains[@]}" || status=1
  fi
  if $keychain_created; then
    security delete-keychain "$APPLE_KEYCHAIN_PATH" || status=1
  fi
  rm -rf -- "$credential_dir" || status=1
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Preserve the runner search list (including paths containing spaces).
security list-keychains -d user > "$credential_dir/keychains.txt"
while IFS= read -r path; do
  original_keychains+=("$path")
done < <(python3 - "$credential_dir/keychains.txt" <<'PY'
import shlex
import sys
from pathlib import Path
for value in shlex.split(Path(sys.argv[1]).read_text()):
    print(value)
PY
)
[[ ${#original_keychains[@]} -gt 0 ]] || { echo 'Cannot read original keychain search list' >&2; exit 1; }

# Use strict decoding, and never print credential material.
python3 - "$credential_dir/certificate.p12" <<'PY'
import base64
import os
import sys
from pathlib import Path
try:
    data = base64.b64decode(''.join(os.environ['APPLE_CERTIFICATE_P12_BASE64'].split()), validate=True)
    if not data:
        raise ValueError()
except (ValueError, base64.binascii.Error):
    raise SystemExit('APPLE_CERTIFICATE_P12_BASE64 must contain a valid base64 P12 file')
Path(sys.argv[1]).write_bytes(data)
PY
security create-keychain -p "$keychain_password" "$APPLE_KEYCHAIN_PATH"
keychain_created=true
security set-keychain-settings -lut 21600 "$APPLE_KEYCHAIN_PATH"
security unlock-keychain -p "$keychain_password" "$APPLE_KEYCHAIN_PATH"
security import "$credential_dir/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -k "$APPLE_KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" \
  "$APPLE_KEYCHAIN_PATH" >/dev/null
search_list_changed=true
security list-keychains -d user -s "$APPLE_KEYCHAIN_PATH" "${original_keychains[@]}"
rm -f -- "$credential_dir/certificate.p12"
xcrun notarytool store-credentials "$APPLE_NOTARY_PROFILE" \
  --keychain "$APPLE_KEYCHAIN_PATH" --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" >/dev/null
unset APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_APP_SPECIFIC_PASSWORD APPLE_ID keychain_password

# Keep credential files private without restricting distributed bundle resources.
umask "$original_umask"
"$script_dir/build-release.sh" --notarize
