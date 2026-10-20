#!/usr/bin/env bash
# Opens ONLY the personal signed copy. Never changes permissions or keychain settings.
set -euo pipefail
APP="/Users/dellcbyerllc/projects/purge-app/build/dev/Build/Products/Debug/Purge.app"
EXECUTABLE="$APP/Contents/MacOS/Purge"
REQUIREMENT='=identifier "io.getpurge.app" and certificate leaf = H"1FDC8F78848AE0D55DC04F9F854DED710B3AA2D6"'

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "The personal copy is not built. Run scripts/dev-run.sh from the Purge repo." >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict -R "$REQUIREMENT" "$APP"

# Do not accidentally activate an already-running foreign copy with the same app ID.
while IFS= read -r pid; do
  [[ -n "$pid" ]] || continue
  other="$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)"
  if [[ -n "$other" && "$other" != "$EXECUTABLE" ]]; then
    echo "Another Purge process is open at $other. Quit it before opening your copy." >&2
    exit 1
  fi
done < <(/usr/bin/pgrep -x Purge || true)

/usr/bin/open -a "$APP"
