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

# Build somewhere neutral, without debug info.
#
# Both halves are anonymity, not tidiness. SwiftPM bakes the absolute build path
# into the binary twice over: once per object file as an N_OSO debug stab, and
# once as the `Bundle.module` fallback literal. On a stock macOS install that
# path is /Users/<account>/... and the account name is usually a real name, so a
# default release build ships the author's identity inside every copy — which is
# the exact thing this project skips notarization to avoid.
#
# Measured on the v1.2.0 tree: default build 77 occurrences, --scratch-path
# alone 37 (the DWARF line tables survive), -gnone alone leaves the bundle
# literal. Both together: 0. `scripts/make-dmg.sh` asserts that zero.
# Must live OUTSIDE $HOME. A scratch path inside the repo still canonicalizes to
# /Users/<account>/... and would embed the very thing this is avoiding.
SCRATCH="${SCRATCH:-/tmp/claude-pet-build}"
BUILD=(swift build -c "$CONFIG" --product ClaudePet --scratch-path "$SCRATCH" -Xswiftc -gnone)

echo "==> ${BUILD[*]}"
"${BUILD[@]}"
BIN="$("${BUILD[@]}" --show-bin-path)/ClaudePet"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudePet"
cp Sources/ClaudePet/Support/Info.plist "$APP/Contents/Info.plist"
cp Sources/ClaudePet/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM emits resources as a sibling .bundle, which has to travel into the
# .app — the hook installer reads the shim script out of it. It goes in
# Contents/Resources: that is where Bundle.module looks first (via
# Bundle.main.resourceURL), and codesign rejects a bundle nested under
# Contents/MacOS as "bundle format unrecognized".
BUNDLE_DIR="$(dirname "$BIN")"
for bundle in "$BUNDLE_DIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# Strip extended attributes first. `cp -R` carries them over from the build
# directory, and codesign rejects a bundle with "resource fork, Finder
# information, or similar detritus".
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc signature. Enough for local use and for SMAppService to see a stable
# identity; not a distribution signature. --deep is required because the app
# carries SwiftPM's nested resource bundle.
if ! codesign --force --deep --sign - "$APP" 2>/dev/null; then
  echo "   codesign FAILED — launch at login and notifications may not work:"
  codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/   /'
fi

if [ "${1:-}" = "--no-launch" ]; then
  echo "==> built $APP"
  exit 0
fi

echo "==> launching"
pkill -f "ClaudePet.app/Contents/MacOS/ClaudePet" 2>/dev/null || true
open "$APP"
echo "Running. Menu bar icon is a small crab; click the pet for the session roster."
