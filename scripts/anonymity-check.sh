#!/bin/bash
# The identity gate.
#
# This repository is pseudonymous. Nothing tracked, nothing in the history
# after the amnesty commit, nothing in the committed media and nothing in the
# shipped bundle may carry the operator's name, email or home path. This
# script is the one place those rules are checked, so CI, make-dmg.sh and a
# human at the shell all run the same test.
#
# Modes (combine freely; --all runs every mode that applies):
#   --history          authors, committers and trailers since the amnesty commit
#   --tree             tracked files: no /Users/<account> outside the fixtures,
#                      plus any local patterns from .anonymity-patterns
#   --media            docs/media: no text chunks in PNGs, no editor tags in GIFs
#   --bundle <.app>    the whole bundle: ad-hoc signature, no host paths, no
#                      build paths, no reachable resource-bundle fatalError
#
# THE AMNESTY COMMIT. Thirty-seven merge commits at or before 72fdb17 were made
# with the GitHub web Merge button while the account's display name was not
# the pseudonym; GitHub stamps that name as the author of the merge commit it
# creates. They are a known, accepted leak: the repository had already been
# forked, so a rewrite would have been damage limitation at the cost of every
# clone, and the operator declined it. History since 72fdb17 must be clean, and
# a committer of "GitHub" fails on purpose — it is the fingerprint of the web
# Merge button. Merge locally with `git merge --no-ff` and push.
#
# IDENTITY WORDS ARE NEVER WRITTEN HERE. Commit 5be80da removed a comment that
# named the operator's machine from the previous version of this check — the
# check itself had become the leak. Local runs read extra patterns, one per
# line, from `.anonymity-patterns` (gitignored, never tracked). CI has no such
# file and runs the structural checks only.
set -uo pipefail
cd "$(dirname "$0")/.."

AMNESTY=72fdb17
PSEUDONYM=internetdialup
# Account names that are fabricated fixtures or the CI runner, never a person.
ALLOWED_ACCOUNTS='dev|x|runner'

fail=0
say() { printf '%s\n' "$*"; }
bad() { say "  ✗ $*"; fail=1; }
ok()  { say "  ✓ $*"; }

check_history() {
  say "history — authors, committers, trailers"
  local range="$AMNESTY..HEAD"
  if ! git merge-base --is-ancestor "$AMNESTY" HEAD 2>/dev/null; then
    range="HEAD"
    say "  (amnesty commit $AMNESTY not reachable from HEAD; checking the whole history)"
  fi
  local rows
  rows="$(git log --format='%h%x09%an%x09%cn' "$range")"
  local offenders
  offenders="$(printf '%s\n' "$rows" | awk -F'\t' -v p="$PSEUDONYM" '$2 != p || $3 != p { print }' || true)"
  if [ -n "$offenders" ]; then
    bad "commits since $AMNESTY with an author or committer that is not $PSEUDONYM:"
    printf '%s\n' "$offenders" | sed 's/^/      /'
    say "    (a committer of GitHub means the web Merge button — merge locally instead)"
  else
    ok "every commit since $AMNESTY is authored and committed by $PSEUDONYM"
  fi
  local trailers
  trailers="$(git log --format='%h%x09%B%x00' "$range" | tr '\0' '\n' | grep -iE '^[0-9a-f]{7,}'$'\t''|Co-Authored-By:' | grep -iB1 'Co-Authored-By:' | grep -E '^[0-9a-f]{7,}'$'\t' | cut -f1 || true)"
  if [ -n "$trailers" ]; then
    bad "commits carrying a Co-Authored-By trailer:"
    printf '%s\n' "$trailers" | sed 's/^/      /'
  else
    ok "no Co-Authored-By trailers since $AMNESTY"
  fi
}

check_tree() {
  say "tree — tracked files"
  local hits
  hits="$(git grep -n -I -E '/Users/[A-Za-z0-9_.-]+' -- . ':!docs/internal' \
          | grep -vE "/Users/($ALLOWED_ACCOUNTS)([/\"' ]|\$)" || true)"
  if [ -n "$hits" ]; then
    bad "tracked files name a home directory that is not a fixture account:"
    printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/      /'
  else
    ok "no home paths outside the fixture accounts ($ALLOWED_ACCOUNTS)"
  fi
  if [ -f .anonymity-patterns ]; then
    if git ls-files --error-unmatch .anonymity-patterns >/dev/null 2>&1; then
      bad ".anonymity-patterns is TRACKED — it must stay local (see .gitignore)"
    fi
    local words
    words="$(git grep -n -i -I -f .anonymity-patterns -- . ':!docs/internal' || true)"
    if [ -n "$words" ]; then
      bad "tracked files match a local identity pattern:"
      printf '%s\n' "$words" | cut -c1-160 | sed 's/^/      /'
    else
      ok "no local identity pattern matches in tracked files"
    fi
  else
    say "  (no .anonymity-patterns file — structural checks only)"
  fi
}

check_media() {
  say "media — docs/media"
  local f n
  for f in docs/media/*.png; do
    [ -e "$f" ] || continue
    n="$(LC_ALL=C grep -c -a -E 'tEXt|iTXt|zTXt' "$f" || true)"
    [ "${n:-0}" -eq 0 ] || bad "$f carries a text chunk (tEXt/iTXt/zTXt) — re-export without metadata"
  done
  for f in docs/media/*.gif; do
    [ -e "$f" ] || continue
    n="$(LC_ALL=C grep -c -a -E 'Adobe|GIMP|Software|Author' "$f" || true)"
    [ "${n:-0}" -eq 0 ] || bad "$f carries an editor or author tag"
  done
  [ "$fail" -eq 0 ] && ok "no text chunks in PNGs, no editor tags in GIFs"
}

check_bundle() {
  local app="$1"
  say "bundle — $app"
  [ -d "$app" ] || { bad "$app not found"; return; }
  local macho="$app/Contents/MacOS/ClaudePet"
  [ -f "$macho" ] || { bad "$macho not found"; return; }

  # Ad-hoc only. A Developer ID signature publishes the signer's legal name
  # and Team ID in every copy.
  local sig
  sig="$(codesign -dv "$app" 2>&1 || true)"
  if printf '%s\n' "$sig" | grep -q '^Signature=adhoc$' \
     && printf '%s\n' "$sig" | grep -q '^TeamIdentifier=not set$'; then
    ok "signature is ad-hoc with no TeamIdentifier"
  else
    bad "signature is not an anonymous ad-hoc one:"
    printf '%s\n' "$sig" | grep -Ei 'Signature|TeamIdentifier|Authority' | sed 's/^/      /'
  fi

  # Home paths, in raw bytes over the WHOLE bundle — Info.plist, CodeResources
  # and the resource bundle included, not just the Mach-O. Raw bytes rather
  # than `strings`: a non-ASCII character in a path splits a `strings` run and
  # hides the match (that is how v1.0.0–v1.2.0 shipped a home path 67 times).
  local leaks
  leaks="$(LC_ALL=C grep -rao '/Users/[A-Za-z0-9_.-]*' "$app" | sed 's/^[^:]*://' | sort -u \
           | grep -vE "^/Users/($ALLOWED_ACCOUNTS)\$" || true)"
  if [ -n "$leaks" ]; then
    bad "host paths inside the bundle:"
    printf '%s\n' "$leaks" | sed 's/^/      /'
    say "    Rebuild via ./run.sh, which builds under /tmp with -Xswiftc -gnone."
  else
    ok "no host paths (only the fabricated fixture accounts remain)"
  fi

  # Build paths: a binary that names its build directory resolves resources on
  # exactly one Mac — the one that compiled it. Three releases died that way.
  local buildpaths
  buildpaths="$(LC_ALL=C grep -rao '/tmp/claude-pet-build[A-Za-z0-9_./-]*' "$app" | sed 's/^[^:]*://' | sort -u || true)"
  if [ -n "$buildpaths" ]; then
    bad "the bundle names a build directory that exists on this machine only:"
    printf '%s\n' "$buildpaths" | sed 's/^/      /'
  else
    ok "no build-machine paths"
  fi
  if LC_ALL=C grep -qa 'could not load resource bundle' "$macho"; then
    bad "SwiftPM's resource-bundle fatalError is reachable — route resources through ResourceBundle.resolved"
  else
    ok "no reachable resource-bundle fatalError"
  fi
}

[ $# -gt 0 ] || { say "usage: $0 [--history] [--tree] [--media] [--bundle <.app>] [--all]"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --history) check_history ;;
    --tree)    check_tree ;;
    --media)   check_media ;;
    --bundle)  shift; check_bundle "${1:?--bundle needs a path}" ;;
    --all)     check_history; check_tree; check_media; [ -d build/ClaudePet.app ] && check_bundle build/ClaudePet.app ;;
    *) say "unknown flag: $1"; exit 2 ;;
  esac
  shift
done

if [ "$fail" -ne 0 ]; then
  say
  say "ANONYMITY CHECK FAILED — do not publish."
  exit 1
fi
say
say "anonymity check passed"
