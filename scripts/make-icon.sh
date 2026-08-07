#!/bin/bash
# Regenerate the app icon from the sprite rig.
#
# The icon is drawn by the app itself (--render-icon) so it can never drift from
# the character it depicts. The resulting AppIcon.icns is committed, so this only
# needs running when Claw'd's proportions or the palette change.
#
# Uses only iconutil and sips, both shipped with macOS — this repo has no
# package-manager dependencies and the tooling should not add one.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/icon"
DEST="Sources/ClaudePet/Resources/AppIcon.icns"

echo "==> building the renderer"
swift build --product ClaudePet >/dev/null
BIN="$(swift build --product ClaudePet --show-bin-path)/ClaudePet"

echo "==> rendering iconset"
rm -rf "$OUT"
mkdir -p "$OUT"
"$BIN" --render-icon "$OUT"

echo "==> packing $DEST"
iconutil --convert icns "$OUT/AppIcon.iconset" --output "$DEST"

echo "==> done"
echo "    $DEST         ($(du -h "$DEST" | cut -f1))"
echo "    $OUT/icon-1024.png       (review this one by eye)"
echo "    $OUT/dmg-background.png"
