#!/usr/bin/env bash
#
# Finishes a local build of Purge so macOS keeps its permissions:
#   1. Gives it a very high build number, so the built-in updater never swaps it
#      for the original author's release, which has a different signature.
#   2. Signs it with your private Purge certificate (see dev-signing-setup.sh),
#      so macOS sees every build as the same app.
# Used by dev-run.sh and dev-test.sh.
#
# Usage:  scripts/dev-sign.sh path/to/Purge.app
#         scripts/dev-sign.sh --check      only check the certificate is ready
set -euo pipefail

IDENTITY="Purge Local Development"
KEYCHAIN="$HOME/Library/Keychains/purge-dev-signing.keychain-db"
SERVICE="io.getpurge.dev-signing"
# Higher than any release's build number, so the updater never offers one.
LOCAL_BUILD_NUMBER="99999"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path/to/Purge.app | --check" >&2
  exit 2
fi

if [[ ! -f "$KEYCHAIN" ]] ||
  ! keychain_password="$(security find-generic-password -s "$SERVICE" -a "$USER" -w 2>/dev/null)"; then
  echo "Set up signing first: scripts/dev-signing-setup.sh" >&2
  exit 1
fi
security unlock-keychain -p "$keychain_password" "$KEYCHAIN"

# codesign only uses a certificate macOS accepts for signing code.
fingerprint=""
while IFS= read -r line; do
  if [[ "$line" == *"\"$IDENTITY\""* ]]; then
    fingerprint="$(awk '{print $2}' <<<"$line")"
    break
  fi
done < <(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null || true)
if [[ ! "$fingerprint" =~ ^[0-9A-F]{40}$ ]]; then
  echo "macOS doesn't accept the Purge signing certificate yet. Run: scripts/dev-signing-setup.sh" >&2
  exit 1
fi

if [[ "$1" == "--check" ]]; then
  exit 0
fi

APP="$1"
if [[ ! -f "$APP/Contents/Info.plist" ]]; then
  echo "No app at $APP" >&2
  exit 1
fi

plutil -replace CFBundleVersion -string "$LOCAL_BUILD_NUMBER" "$APP/Contents/Info.plist"

# codesign only finds certificates in keychains on your keychain list, so this
# one goes on the list just while signing, then the list is put back as it was.
# Left on the list, a locked keychain can make other apps ask you to unlock it.
original_list=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"
  line="${line%\"}"
  if [[ -n "$line" ]]; then
    original_list+=("$line")
  fi
done < <(security list-keychains -d user)

already_listed=0
for listed in ${original_list[@]+"${original_list[@]}"}; do
  if [[ "$listed" == "$KEYCHAIN" ]]; then
    already_listed=1
  fi
done

restore_list() {
  if [[ ${#original_list[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${original_list[@]}" ||
      echo "Couldn't restore your keychain list. Check it in Keychain Access." >&2
  fi
}
if [[ "$already_listed" -eq 0 ]]; then
  trap restore_list EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  security list-keychains -d user -s "$KEYCHAIN" ${original_list[@]+"${original_list[@]}"}
fi

sign() {
  codesign --force --sign "$fingerprint" --keychain "$KEYCHAIN" --timestamp=none \
    --preserve-metadata=identifier,entitlements "$1"
}
# Inside out: what a bundle contains is signed before the bundle that seals it.
sign_bundle() {
  local bundle="$1"
  local nested
  for nested in "$bundle"/Contents/Frameworks/* "$bundle"/Contents/PlugIns/*; do
    case "$nested" in
      *.appex | *.xctest) sign_bundle "$nested" ;;
      *) sign "$nested" ;;
    esac
  done
  sign "$bundle"
}
shopt -s nullglob
sign_bundle "$APP"
codesign --verify --deep --strict "$APP"

# What macOS matches permissions against. It must name the certificate, not
# this one build's fingerprint (a "cdhash"), or permissions would reset again.
requirement="$(codesign -d -r- "$APP" 2>&1)"
if [[ "$requirement" == *cdhash* || "$requirement" != *certificate* ]]; then
  echo "Signing didn't take, so macOS would ask for permissions again:" >&2
  echo "$requirement" >&2
  exit 1
fi
