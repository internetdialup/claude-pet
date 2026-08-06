# AGENT.md - v0.2.0

---
**Document Metadata:**
- **Created:** 2026-08-06
- **Last Updated:** 2026-08-06
- **Document Version:** v0.2.0
- **Operational Freeze Tag:** `v0.1.2-clawd-personality`
---

You are an agent. This file is the cold-start router for **Claude Pet**.

## Session Identity

- **Callsign:** none
- **Workspace:** the root of the `claude-pet` checkout — the directory containing `Bamboo.md` and `AGENT.md`.
- **Who am I here:** an agent building a native macOS SwiftUI desktop pet that renders live Claude Code session activity.
- **Build Target:** `swift build --product ClaudePet` (macOS 14+, arm64). State the build target before claiming any compile result.
- **Branches:** `main` is public and ships with debug UI compiled out; `debug/preview-tools` keeps the mood-preview submenu always on.
- **Litmus:** if asked "what's your name?", answer that you are operating on the Claude Pet repo under Bamboo governance. If this session's cwd is not the workspace above, surface it before acting.

Order of operations on first contact:

## 0. Verify Workspace

Step zero: confirm the working directory is the repo root — it contains `Bamboo.md` and `AGENT.md`. If not, stop and surface it.

## 1. Read the policy source

Read `Bamboo.md` for the repo contract, document roles, and mandatory rules.

## 2. Read behavior/

`behavior/ctx-rules.md` carries the reasoning and context rules. Load it when you hit a term or constraint you do not recognize.

## 3. Read docs/ctx-orientation.md

Read `docs/ctx-orientation.md` for current state and the most recent structural changes (the Knob log, newest on top).

## 4. Read development/swift-development.md before touching Swift

`development/swift-development.md` defines what counts as a Knob in this stack and what structural verification means here. Do not edit `Sources/` without it.

## 5. Read docs/repo-organization.md before adding or renaming files

`docs/repo-organization.md` is the folder map. It updates in the **same commit** as any file addition or rename. No orphan pointers.

## 6. Narrate compression when it happens

When you compress your context window — or notice you are approaching the limit — say so. State which orientation log you will re-read (`docs/ctx-orientation.md`) and which active Knob reconstitutes the working state. Then actually read it.

## 7. Pre-Flight Push Plan Mandate

Before any `git push`, present a Push Execution Plan and obtain explicit approval: target repo, payload classification, and a compliance verdict confirming no secrets or `~/.claude` transcript contents are included in the payload.

## 8. Durability Honesty

This app reads and (optionally) writes the user's real Claude Code configuration. Any claim that something was "persisted," "installed," or "backed up" MUST name the exact absolute file path it landed in. No path, no claim.

## 9. Read-Only By Default

`~/.claude/` is the user's live working data. Only one code path in this repo may write to anything Claude Code owns — the gated hook installer described in `Bamboo.md` §5. The pet's own event drop-directory is the single exception, and it holds no Claude state. Tests never touch `~/.claude/` at all.

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v0.2.0 | 2026-08-06 | `v0.1.2-clawd-personality` | **Hot** | Added the branch map to Session Identity. |
| v0.1.0 | 2026-08-06 | `v0.1.0-claude-pet-genesis` | **Hot** | Genesis. Forked cold-start router for the Claude Pet Swift project. |
