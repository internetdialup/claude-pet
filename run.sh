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

# Refuse to build over an iCloud sync duplicate.
#
# The repo lives in iCloud Drive, and when the file provider resolves a
# conflict it leaves a second copy beside the original named "Motion 2.swift".
# SwiftPM globs every .swift under Sources, so the copy is compiled too, and
# every type in it is declared twice. What you get is
#
#     error: invalid redeclaration of 'Ease'
#
# which names a symbol and not the cause, and sends you looking through a file
# that is perfectly fine. This is the same provider that re-stamps FinderInfo
# onto the bundle and breaks codesign further down; that one is retried, this
# one cannot be — a duplicate source is not a race, it is a file that has to go.
#
# Not deleted automatically. A duplicate is USUALLY a stale snapshot with
# nothing unique in it, and "usually" is not good enough to delete somebody's
# source with. Compare it against git and remove it yourself.
duplicates="$(find Sources Tests -name "* [0-9].swift" 2>/dev/null || true)"
if [ -n "$duplicates" ]; then
  echo "==> iCloud left duplicate sources behind. They will be compiled and"
  echo "    every type in them declared twice. Check each against git, then"
  echo "    delete it:"
  echo "$duplicates" | sed 's/^/      /'
  exit 1
fi

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

# Strip extended attributes, sign, and VERIFY — as one retried unit.
#
# codesign rejects a bundle carrying "resource fork, Finder information, or
# similar detritus", and this repo lives inside iCloud Drive, whose file
# provider stamps com.apple.FinderInfo and com.apple.fileprovider.fpfs#P back
# onto directories moments after they are cleared. So a single `xattr -cr`
# before signing is a race, and it is one this script used to lose silently:
# the failure printed three lines nobody reads and carried on to launch an
# UNSIGNED app, which works fine until launch-at-login or a notification
# quietly does not.
#
# com.apple.provenance is left alone deliberately — macOS manages it, it cannot
# be removed, and codesign does not object to it.
signed=""
for attempt in 1 2 3 4 5; do
  xattr -cr "$APP" 2>/dev/null || true
  if codesign --force --deep --sign - "$APP" 2>/dev/null \
     && codesign --verify --deep "$APP" 2>/dev/null; then
    signed="yes"
    [ "$attempt" -gt 1 ] && echo "==> signed on attempt $attempt (iCloud re-stamp)"
    break
  fi
done

if [ -z "$signed" ]; then
  echo "   codesign FAILED after five attempts — launch at login and"
  echo "   notifications may not work. Last error:"
  xattr -cr "$APP" 2>/dev/null || true
  codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/   /'
  echo "   Surviving attributes:"
  xattr -r "$APP" 2>/dev/null | grep -v provenance | sed 's/^/     /'
  exit 1
fi

if [ "${1:-}" = "--no-launch" ]; then
  echo "==> built $APP"
  exit 0
fi

echo "==> launching"

# Retire the running instance, WAIT for it to actually go, then retry the open.
#
# `open` fired straight after `pkill` races LaunchServices: it still has the
# dying process registered and answers -600, procNotFound. Measured, not
# theoretical — and under `set -e` that failure takes the whole script down
# after a clean build and a good signature, which reads as "the app is broken"
# when nothing is wrong but the timing. Two seconds later the same command
# works.
#
# Same lesson as the codesign block above, and it is the reason this is a loop
# rather than a `sleep 1`: one shot at a system service that needs a moment is
# a coin flip, and the fix is to keep asking until it answers.
pkill -f "ClaudePet.app/Contents/MacOS/ClaudePet" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -f "ClaudePet.app/Contents/MacOS/ClaudePet" >/dev/null 2>&1 || break
  sleep 0.2
done

launched=""
for attempt in 1 2 3; do
  if open "$APP" 2>/dev/null; then
    launched="yes"
    [ "$attempt" -gt 1 ] && echo "==> launched on attempt $attempt (LaunchServices race)"
    break
  fi
  sleep 1
done

if [ -z "$launched" ]; then
  echo "   open FAILED after three attempts. Last error:"
  open "$APP" 2>&1 | sed 's/^/   /'
  exit 1
fi

echo "Running. Menu bar icon is a small crab; click the pet for the session roster."
