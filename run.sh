#!/bin/bash
# Build ClaudePet and assemble it into a launchable .app bundle.
#
# SwiftPM produces a bare executable; macOS needs a bundle for LSUIElement (no
# Dock icon), for SMAppService (launch at login), and for notifications to carry
# an app identity. This script is the bundling step.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="build/ClaudePet.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --product ClaudePet
BIN="$(swift build -c "$CONFIG" --product ClaudePet --show-bin-path)/ClaudePet"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudePet"
cp Sources/ClaudePet/Support/Info.plist "$APP/Contents/Info.plist"

# SwiftPM emits resources as a sibling .bundle. Bundle.module looks for it next
# to the executable, so it has to travel into the .app — the hook installer
# reads the shim script out of it.
BUNDLE_DIR="$(dirname "$BIN")"
for bundle in "$BUNDLE_DIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/MacOS/"
done

# Ad-hoc signature. Enough for local use and for SMAppService to see a stable
# identity; not a distribution signature. --deep is required because the app now
# carries SwiftPM's nested resource bundle.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"

if [ "${1:-}" = "--no-launch" ]; then
  echo "==> built $APP"
  exit 0
fi

echo "==> launching"
pkill -f "ClaudePet.app/Contents/MacOS/ClaudePet" 2>/dev/null || true
open "$APP"
echo "Running. Menu bar icon is a small crab; click the pet for the session roster."
