#!/bin/sh
# Claude Pet hook shim.
#
# Claude Code pipes the hook payload as JSON on stdin. This drops it into a
# directory the pet watches, and gets out of the way.
#
# Bamboo.md §5: the pet must never block Claude. Every failure mode here — no
# directory, no disk, no pet running — still exits 0.
DIR="$HOME/.claude/claude-pet-events"
mkdir -p "$DIR" 2>/dev/null

# The pet deletes each event as it consumes it. If the pet is NOT running, that
# never happens and this directory would grow forever. Prune occasionally rather
# than on every hook, so the common path stays a single write.
if [ $((RANDOM % 40)) -eq 0 ]; then
    find "$DIR" -type f -name '*.json' -mmin +10 -delete 2>/dev/null
fi

# Write to a scratch name, then rename into place. `mv` within one directory is
# atomic, so the pet never observes a half-written file — reading one and
# failing to parse it used to lose the event entirely.
STEM="$(date +%s)-$$-$RANDOM"
TMP="$DIR/.$STEM.partial"
FILE="$DIR/$STEM.json"
cat > "$TMP" 2>/dev/null && mv -f "$TMP" "$FILE" 2>/dev/null
rm -f "$TMP" 2>/dev/null
exit 0
