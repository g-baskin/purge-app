#!/usr/bin/env bash
#
# Builds Purge for everyday use on your own Mac and opens it. Every build keeps
# the same signature, so macOS keeps Purge's permissions (like Full Disk Access).
#
# One-time setup first:  scripts/dev-signing-setup.sh
#
# Usage:  scripts/dev-run.sh             build and (re)open Purge
#         scripts/dev-run.sh --no-open   build only
#
# The app is built into build/dev. Use only this copy: macOS keeps one set of
# permissions per app, so another copy (a download, an older build) takes them
# over whenever it's opened.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/dev"
APP="$DERIVED/Build/Products/Debug/Purge.app"
EXECUTABLE="$APP/Contents/MacOS/Purge"

open_app=1
case "${1:-}" in
  --no-open) open_app=0 ;;
  "") ;;
  *)
    echo "usage: $0 [--no-open]" >&2
    exit 2
    ;;
esac

# Fails in seconds, before a long build, if the one-time setup isn't done.
"$ROOT/scripts/dev-sign.sh" --check

echo "Building Purge..."
# Built with a throwaway signature first, then signed properly below.
xcodebuild -project "$ROOT/purge.xcodeproj" -scheme purge -configuration Debug \
  -derivedDataPath "$DERIVED" -quiet \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build

echo "Signing..."
"$ROOT/scripts/dev-sign.sh" "$APP"

if [[ "$open_app" -eq 0 ]]; then
  echo "Built and signed: $APP"
  exit 0
fi

# Another copy is the user's to quit, not this script's.
for pid in $(pgrep -x Purge || true); do
  other="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  if [[ -n "$other" && "$other" != "$EXECUTABLE" ]]; then
    echo "Another copy of Purge is open from ${other%/Contents/MacOS/Purge}." >&2
    echo "Quit it, then open this one: open \"$APP\"" >&2
    exit 1
  fi
done

# Reopen so the new build is the one running.
this_build_pids() {
  local pid
  for pid in $(pgrep -x Purge || true); do
    if [[ "$(ps -o comm= -p "$pid" 2>/dev/null)" == "$EXECUTABLE" ]]; then
      echo "$pid"
    fi
  done
}
for pid in $(this_build_pids); do
  kill "$pid" 2>/dev/null || true
done
for _ in {1..50}; do # wait up to 5 seconds for it to quit
  [[ -z "$(this_build_pids)" ]] && break
  sleep 0.1
done

open "$APP"
echo "Opened $APP"
