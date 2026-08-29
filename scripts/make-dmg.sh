#!/bin/bash
# Build the distributable disk image.
#
# Uses only hdiutil, sips and SetFile/osascript — all shipped with macOS. This
# repo has no package-manager dependencies and the release tooling should not
# introduce one (no create-dmg, no Homebrew).
#
# The app inside is **ad-hoc signed and not notarized**, deliberately: a
# Developer ID signature publishes the signer's legal name and Apple Team ID in
# every copy. See README "Installing" for the Gatekeeper step users need.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/ClaudePet/Support/Info.plist)"
APP="build/ClaudePet.app"
VOLUME="Claude Pet"
STAGE="build/dmg-stage"
DMG="build/ClaudePet-${VERSION}.dmg"
SCRATCH="build/ClaudePet-rw.dmg"

[ -d "$APP" ] || { echo "error: $APP not found — run ./run.sh --no-launch first" >&2; exit 1; }

echo "==> staging v${VERSION}"
rm -rf "$STAGE" "$DMG" "$SCRATCH"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Window background and volume icon, both produced by --render-icon.
if [ -f build/icon/dmg-background.png ]; then
  cp build/icon/dmg-background.png "$STAGE/.background/bg.png"
fi
# The volume icon is NOT staged: hdiutil create -srcfolder drops
# .VolumeIcon.icns. It has to be written into the mounted volume, and the
# custom-icon bit set on the mount point itself. Done after attach, below.

echo "==> creating writable image"
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
  -format UDRW -ov "$SCRATCH" >/dev/null

MOUNT_DIR="/Volumes/$VOLUME"
hdiutil attach "$SCRATCH" -mountpoint "$MOUNT_DIR" -nobrowse -noautoopen >/dev/null


# Layout is best-effort. Driving Finder needs macOS Automation permission, which
# is not grantable from a script — if it is denied the DMG is still perfectly
# usable, just unstyled, so a failure here must not fail the build.
echo "==> applying window layout (best-effort)"
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 840, 560}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        try
            set background picture of opts to file ".background:bg.png"
        end try
        set position of item "ClaudePet.app" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then
  echo "    layout applied"
else
  echo "    Finder automation unavailable — shipping an unstyled (but working) DMG"
fi

# Volume icon goes on LAST. Finder's layout pass rewrites the volume root, and
# writing the icon before it means the file does not survive.
if [ -f Sources/ClaudePet/Resources/AppIcon.icns ]; then
  cp Sources/ClaudePet/Resources/AppIcon.icns "$MOUNT_DIR/.VolumeIcon.icns"
  SetFile -a C "$MOUNT_DIR" 2>/dev/null || echo "    (could not set the volume icon bit)"
fi

sync
echo "==> volume contents before compressing"
ls -a "$MOUNT_DIR" | sed 's/^/    /'
hdiutil detach "$MOUNT_DIR" >/dev/null

echo "==> compressing"
hdiutil convert "$SCRATCH" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$SCRATCH"
rm -rf "$STAGE"

# Ad-hoc only. Never a Developer ID identity here — see the header.
codesign --force --sign - "$DMG" 2>/dev/null || echo "    (dmg signature skipped)"

echo "==> built $DMG ($(du -h "$DMG" | cut -f1))"
echo
echo "Anonymity check 1/2 — signature must be adhoc with no TeamIdentifier:"
codesign -dv "$APP" 2>&1 | grep -Ei "Signature|TeamIdentifier|Authority" || echo "  (no signing authority recorded)"

# Anonymity check 2/2 — the one that was missing, and that a shipped release
# needed.
#
# v1.0.0 through v1.2.0 all passed the signature check above while carrying the
# author's home path 67-77 times inside the Mach-O: SwiftPM writes it as an
# N_OSO debug stab per object file, plus the Bundle.module fallback literal. On
# a stock macOS install that path is /Users/<account>/, and the account name is
# usually a real name — so the binary published the identity that skipping
# notarization was meant to protect.
#
# Two traps this check is written around:
#   - `strings` MISSES it. The path here contained a curly apostrophe — a
#     machine name with a non-ASCII character in it — which splits the run
#     and hides the match. Use grep on the raw bytes.
#   - The compressed .dmg shows nothing; the payload only appears once mounted.
#     So this inspects $APP's binary directly, before compression.
echo
echo "Anonymity check 2/2 — no build-host paths baked into the binary:"
MACHO="$APP/Contents/MacOS/ClaudePet"
LEAKS="$(LC_ALL=C grep -oa "/Users/[A-Za-z0-9_.-]*" "$MACHO" | sort -u | grep -v "^/Users/dev$" || true)"
if [ -n "$LEAKS" ]; then
  echo "  ✗ FAIL — the following host paths are inside the shipped binary:"
  printf '      %s\n' $LEAKS
  echo "    Do NOT publish this build. Rebuild via ./run.sh, which sets"
  echo "    --scratch-path outside \$HOME and -Xswiftc -gnone."
  exit 1
fi
echo "  ✓ clean (only the fabricated /Users/dev demo strings remain)"

# Portability check 3/3 — the gap the anonymity fix hid.
#
# run.sh builds under /tmp to keep the build path out of $HOME. Correct for
# anonymity — and its side effect is that SwiftPM's Bundle.module fallback
# literal becomes /tmp/… instead of /Users/…, so the check above goes quiet
# about it. A binary carrying its build directory resolves resources on
# exactly one Mac in the world: the one that compiled it. v1.x of the fork
# shipped three releases that died on every machine but that one, from the
# menu row the app exists to perform. Same technique as above: raw bytes,
# against the .app's binary before compression.
echo
echo "Portability check 3/3 — no build-machine paths, no fatalError resource accessor:"
BUILDPATHS="$(LC_ALL=C grep -oa "/tmp/claude-pet-build[A-Za-z0-9_./-]*" "$MACHO" | sort -u || true)"
if [ -n "$BUILDPATHS" ]; then
  echo "  ✗ FAIL — the binary names a build directory that exists on this machine only:"
  printf '      %s\n' $BUILDPATHS
  echo "    Resources resolved through it die on every other Mac."
  exit 1
fi
if LC_ALL=C grep -qa "could not load resource bundle" "$MACHO"; then
  echo "  ✗ FAIL — SwiftPM's resource-bundle fatalError is reachable."
  echo "    Something resolves resources through Bundle.module; route it"
  echo "    through ResourceBundle.resolved instead."
  exit 1
fi
echo "  ✓ clean (resources resolve relative to the app, on any machine)"
