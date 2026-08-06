# CLAUDE.md — Vendor Overlay - v0.2.0

---
**Document Metadata:**
- **Created:** 2026-08-06
- **Last Updated:** 2026-08-06
- **Document Version:** v0.2.0
- **Operational Freeze Tag:** `v0.1.2-clawd-personality`
---

This overlay sits **on top of** `AGENT.md`. It never overrides it. Read `AGENT.md` first.

## Commits

- Commits are authored solely under the operator's name. **No `Co-Authored-By: Claude` trailers.**
- One Knob per commit where practical. The commit message summarizes; `docs/ctx-orientation.md` carries the *why*.

## Working style

- **Wayfinding before retrieval.** Read `docs/repo-organization.md` to find the home before grepping for the file.
- **Score before spending.** Rate a request on Impact / Complexity / Relevance before burning a large token budget on it.
- **Ghost-write the Knob.** When the operator describes a change conversationally, translate it into the Knob format without adding scope they did not ask for.

## Building and running

```bash
swift build --product ClaudePet    # the Build Target named in AGENT.md
swift test                          # fixtures only; never touches ~/.claude/
./run.sh                            # builds the .app bundle and launches it
```

Exit codes are the evidence (`development/swift-development.md` §2). Do not report "it builds" without one.

## The redline

This app reads the operator's live Claude Code data. Before writing any code that touches `~/.claude/`, re-read `Bamboo.md` §5. The short version: read-only for everything Claude Code owns, the user-initiated hook installer is the only writer to Claude's own state, every read is a bounded tail, and tests build synthetic fixtures in `FileManager.temporaryDirectory` rather than reading anything real.

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v0.2.0 | 2026-08-06 | `v0.1.2-clawd-personality` | **Hot** | Redline summary corrected to match Bamboo.md §5. |
| v0.1.0 | 2026-08-06 | `v0.1.0-claude-pet-genesis` | **Hot** | Genesis. Claude overlay with commit policy and the redline pointer. |
