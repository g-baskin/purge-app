#!/usr/bin/env bash
#
# One-time setup for building Purge on your own Mac: makes a private certificate
# that signs your local builds, so macOS keeps Purge's permissions (like Full
# Disk Access) from one build to the next.
#
# Why: macOS remembers a permission by the app's signature. Without a
# certificate, every build gets a throwaway ("ad hoc") signature, so each new
# build looks like a different app and has to be allowed again.
#
# What it adds:
#   ~/Library/Keychains/purge-dev-signing.keychain-db   holds the certificate and its key
#   a "Purge local signing" password in your login keychain, which unlocks it
#   a trust setting for your account only, accepting the certificate for
#     signing code and nothing else (macOS asks for your password to allow it)
# Anything that can use the certificate could sign code that claims Purge's
# permissions, so it is never exported and stays on this Mac.
#
# Usage:  scripts/dev-signing-setup.sh            set up (safe to run again)
#         scripts/dev-signing-setup.sh --remove   undo everything it added
set -euo pipefail

IDENTITY="Purge Local Development"
KEYCHAIN="$HOME/Library/Keychains/purge-dev-signing.keychain-db"
SERVICE="io.getpurge.dev-signing"
# LibreSSL, which ships with macOS: its .p12 files import cleanly into keychains.
OPENSSL=/usr/bin/openssl

has_password() {
  security find-generic-password -s "$SERVICE" -a "$USER" >/dev/null 2>&1
}

# Whether macOS accepts the certificate for signing code. codesign won't use it until it does.
is_trusted() {
  local identities
  [[ -f "$KEYCHAIN" ]] || return 1
  identities="$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null)" || return 1
  [[ "$identities" == *"\"$IDENTITY\""* ]]
}

has_trust_setting() {
  local settings
  settings="$(security dump-trust-settings 2>/dev/null || true)"
  [[ "$settings" == *"$IDENTITY"* ]]
}

# Changing which certificates are trusted always needs your password.
trust_certificate() {
  echo "macOS will ask for your password to trust the new certificate for signing code."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$1"
}

remove_setup() {
  if [[ -f "$KEYCHAIN" ]] && has_trust_setting; then
    local pem
    pem="$(mktemp)"
    if security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" >"$pem" 2>/dev/null && [[ -s "$pem" ]]; then
      echo "macOS will ask for your password to remove the trust setting."
      security remove-trusted-cert "$pem" || echo "The trust setting couldn't be removed." >&2
    fi
    rm -f "$pem"
  fi
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || rm -f "$KEYCHAIN"
  security delete-generic-password -s "$SERVICE" -a "$USER" >/dev/null 2>&1 || true
}

finish() {
  if ! is_trusted; then
    echo "macOS didn't accept the certificate. Run this script again to retry." >&2
    exit 1
  fi
  echo "Done. Build and open Purge with: scripts/dev-run.sh"
  echo "macOS will ask for Full Disk Access once more. After that, new builds keep it."
}

case "${1:-}" in
  --remove)
    remove_setup
    echo "Removed the Purge signing certificate."
    exit 0
    ;;
  "") ;;
  *)
    echo "usage: $0 [--remove]" >&2
    exit 2
    ;;
esac

umask 077
work="$(mktemp -d)"
created=0
started=0
cleanup() {
  rm -rf "$work"
  # A half-made keychain would block the next attempt, so start clean instead.
  if [[ "$started" -eq 1 && "$created" -eq 0 ]]; then
    remove_setup
  fi
}
trap cleanup EXIT

if [[ -f "$KEYCHAIN" ]] && has_password; then
  if is_trusted; then
    echo "Already set up. Build and open Purge with: scripts/dev-run.sh"
    exit 0
  fi
  # Made earlier, but the password prompt was cancelled or never shown.
  security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" >"$work/cert.pem"
  trust_certificate "$work/cert.pem"
  finish
  exit 0
fi
if [[ -f "$KEYCHAIN" ]] || has_password; then
  echo "An earlier setup didn't finish. Run '$0 --remove', then run this again." >&2
  exit 1
fi

started=1

# `create-keychain` also adds the new keychain to your search list. The list is
# put back right after: a locked keychain on it can make other apps ask you to
# unlock it. dev-sign.sh adds it back only while it signs.
search_list=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"
  line="${line%\"}"
  if [[ -n "$line" ]]; then
    search_list+=("$line")
  fi
done < <(security list-keychains -d user)

keychain_password="$("$OPENSSL" rand -hex 24)"
p12_password="$("$OPENSSL" rand -hex 24)"

cat >"$work/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

if ! "$OPENSSL" req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 \
  -config "$work/cert.cnf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>"$work/openssl.log"; then
  cat "$work/openssl.log" >&2
  exit 1
fi
"$OPENSSL" pkcs12 -export -name "$IDENTITY" -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/identity.p12" -passout "pass:$p12_password"

security create-keychain -p "$keychain_password" "$KEYCHAIN"
if [[ ${#search_list[@]} -gt 0 ]]; then
  security list-keychains -d user -s "${search_list[@]}"
fi
security set-keychain-settings "$KEYCHAIN" # no automatic locking while you're logged in
security unlock-keychain -p "$keychain_password" "$KEYCHAIN"
security import "$work/identity.p12" -k "$KEYCHAIN" -P "$p12_password" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without asking for a password on every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$KEYCHAIN" >/dev/null
security add-generic-password -s "$SERVICE" -a "$USER" -l "Purge local signing" \
  -j "Unlocks $KEYCHAIN for scripts/dev-run.sh" -w "$keychain_password"
# From here a failed step leaves a setup that running this again can finish.
created=1

trust_certificate "$work/cert.pem"
finish
