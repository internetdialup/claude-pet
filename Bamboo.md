# Bamboo.md — Claude Pet Operating Spec - v0.2.0

---
**Document Metadata:**
- **Created:** 2026-08-06
- **Last Updated:** 2026-08-06
- **Document Version:** v0.2.0
- **Operational Freeze Tag:** `v0.1.2-clawd-personality`
---

This repo is governed by Bamboo. Canon lives in `../bamboo-private`; this file is the **local** operating spec — the subset that binds work in `claude-pet`.

Ethos: **Physics over Liturgy.** If a rule cannot reduce to a file path, a script exit code, or a resource ceiling, it is not a rule here.

## 1. The 3-Concept Canon

- **Knob ⭐** — the unit of change. Every Knob earns a dated narrative entry in `docs/ctx-orientation.md`, newest on top. Log the *why*, not the diff. In this stack a Knob is a version bump of the `ClaudePet` product (see `development/swift-development.md`).
- **PLTRF 🏗️** — Preventative Long-Term Repo Fragmentation. One canonical home per concept. Broken links, orphans, and duplicate homes are **build failures**, enforced by `.github/workflows/pltrf-check.yml`.
- **Tiering ❄️** — Hot / Warm / Cold / Ice. The hot Knob log targets 4 entries, hard max 6.

## 2. Repo Contract

| File | Role |
| :--- | :--- |
| `README.md` | Human overview — what the pet is and how to run it |
| `AGENT.md` | Vendor-neutral cold-start router; carries `## Session Identity` |
| `CLAUDE.md` | Vendor overlay, sits on top of `AGENT.md`, never overrides it |
| `Bamboo.md` | This file — the local operating spec |
| `docs/ctx-orientation.md` | The Knob log |
| `docs/repo-organization.md` | The folder map |
| `behavior/ctx-rules.md` | Reasoning and context rules |
| `development/swift-development.md` | The Swift structural standard |
| `REPORTING_TEMPLATE.md` | Structural verification reporting format |
| `.github/workflows/pltrf-check.yml` | The CI gate |

## 3. Mandatory Rules

- **Session Identity** — `AGENT.md` MUST open with a `## Session Identity` block naming the Build Target. CI fails without it.
- **Anti-Sycophancy** — blind agreement is forbidden. Verify by running the code and reading the file. Verification means producing evidence, not performing confidence.
- **Durability Honesty** — a claim of "recorded/persisted/installed" MUST name the exact absolute path.
- **Numerical Grounding** — no stated metric unless a checked-in runnable command computes that exact number. "Reads the tail in ~2ms" requires a test that prints it.
- **Chain of Custody** — any doc edit bumps its header version and its 📜 footer changelog row in the same commit.
- **Persona Layer** — no persona or callsign text in inherited canon.

## 4. The Knob Loop

1. Do the work.
2. Write a dated Knob entry in `docs/ctx-orientation.md`, newest on top, with the *why* plus a bullet list of every changed file.
3. Bump header + footer version on every touched doc.
4. Update `docs/repo-organization.md` in the same commit if files were added or renamed.
5. Never commit `.env`, tokens, or any captured `~/.claude` transcript content.

## 5. The One Permitted Write to `~/.claude/` (Redline)

This app observes the user's live Claude Code state. The redline:

- **Read-only** for `~/.claude/sessions/`, `~/.claude/projects/`, `~/.claude/tasks/`.
- **Never read a transcript whole.** Transcripts reach 85 MB. Every read is a bounded tail. A code path that reads a full transcript is a defect, not a slow path.
- **Exactly one writer to Claude's own data**: the hook installer in `Sources/ClaudePet/Support/HookInstaller.swift`. The pet also creates and drains its own event directory, `~/.claude/claude-pet-events/`, which holds no Claude Code state — it lives under `~/.claude/` only because that is where the hook shim can reliably find it. It MUST (a) be user-initiated from the menubar, (b) show the exact JSON diff before writing, (c) copy `~/.claude/settings.json` to `~/.claude/settings.json.bak.<epoch>` first, (d) merge only the `hooks` key. A silent write to `settings.json` is a governance violation.
- **Tests never touch `~/.claude/`.** Fixtures are synthetic JSONL strings built inside the test files themselves, written to `FileManager.temporaryDirectory`.
- **The pet never blocks Claude.** `Sources/ClaudePet/Resources/claude-pet-hook.sh` always exits 0, even when the pet is not running.

## 6. Privacy Constraint

Transcript content is the user's private work. The pet renders it on the user's own screen and nowhere else. No network egress, no telemetry, no analytics, no crash reporting. `Package.swift` declares zero remote dependencies, which makes this verifiable rather than promised.

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v0.2.0 | 2026-08-06 | `v0.1.2-clawd-personality` | **Hot** | Redline clarified: the pet's own event directory is not Claude state; fixtures are synthetic, not a Fixtures/ folder. |
| v0.1.0 | 2026-08-06 | `v0.1.0-claude-pet-genesis` | **Hot** | Genesis. Local operating spec with the `~/.claude` redline and privacy constraint. |
