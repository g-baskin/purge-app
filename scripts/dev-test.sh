#!/usr/bin/env bash
#
# Runs Purge's tests on a build signed the same way as your everyday copy
# (dev-run.sh). The tests open Purge, and an unsigned copy would make macOS ask
# for permissions again; this one shares your copy's permissions instead.
#
# Usage:  scripts/dev-test.sh                  run every test
#         scripts/dev-test.sh -only-testing:PurgeTests/RestoreServiceTests
# Extra arguments go to xcodebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/test"
APP="$DERIVED/Build/Products/Debug/Purge.app"
settings=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)

# Fails in seconds, before a long build, if the one-time setup isn't done.
"$ROOT/scripts/dev-sign.sh" --check

echo "Building Purge and its tests..."
xcodebuild -project "$ROOT/purge.xcodeproj" -scheme purge -configuration Debug \
  -derivedDataPath "$DERIVED" -quiet "${settings[@]}" build-for-testing

echo "Signing..."
"$ROOT/scripts/dev-sign.sh" "$APP"

echo "Testing..."
xcodebuild -project "$ROOT/purge.xcodeproj" -scheme purge -configuration Debug \
  -derivedDataPath "$DERIVED" "${settings[@]}" test-without-building ${1+"$@"}
