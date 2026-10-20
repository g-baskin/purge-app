#!/usr/bin/env bash
#
# Runs hosted tests with a separate bundle ID and URL scheme. They must NEVER
# register as the personal app or inherit its Full Disk Access identity.
# This path needs no private signing certificate or keychain changes.
#
# Usage:  scripts/dev-test.sh                  run every test
#         scripts/dev-test.sh -only-testing:PurgeTests/RestoreServiceTests
# Extra arguments go to xcodebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/test"
settings=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
  ENABLE_HARDENED_RUNTIME=NO
  PURGE_APP_BUNDLE_IDENTIFIER=io.getpurge.app.testhost
  PURGE_URL_SCHEME=purge-testhost
  "PURGE_APP_DISPLAY_NAME=Purge Tests")

echo "Building Purge and its tests..."
xcodebuild -project "$ROOT/purge.xcodeproj" -scheme purge -configuration Debug \
  -derivedDataPath "$DERIVED" -quiet "${settings[@]}" build-for-testing

# Native window fixtures and deadline-based tests share one NSApplication.
# Run test cases serially; concurrency exercised inside each test is unchanged.
echo "Testing..."
xcodebuild -project "$ROOT/purge.xcodeproj" -scheme purge -configuration Debug \
  -derivedDataPath "$DERIVED" "${settings[@]}" test-without-building \
  -parallel-testing-enabled NO ${1+"$@"}
