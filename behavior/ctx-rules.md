# Context Rules - v16.18

---
**Document Metadata:**
- **Created:** 2026-07-01
- **Last Updated:** 2026-07-01
- **Document Version:** v16.18
- **Operational Freeze Tag:** `v16.18-crucible-freeze-093`
---


This document defines the hard operational rules and structural constraints for the Bamboo framework. It prioritizes binary verification over narrative "liturgy."

## 1. The 3-Concept Cold-Start Rule

Every agent must internalize these three directives before execution:
1. **Read `AGENT.md`**: Follow the cold-start loading order without exception.
2. **Log Knobs**: Every meaningful change earns a dated narrative entry in the orientation log (`docs/memory-ctx/ctx-orientation.md` here; `docs/ctx-orientation.md` in forks).
3. **Don't Bloat**: Keep the lexicon lean. Use only the load-bearing terms (**Knob**, **PLTRF**, **Hot/Warm/Cold**).

## 2. Structural Verification (The Physics of Truth)

Bamboo replaces vague mandates with structural requirements to enforce **Anti-Sycophancy**—the explicit audit of operator assumptions to combat cognitive degradation and "Blind Agreement."

- **Rule**: Every claim regarding the system's state, existence, or change MUST reference a specific file path or shell output. 
- **Enforcement**: Claims that cannot be reduced to a file path or a script exit code are considered "Liturgy" and are subject to immediate rejection.
- **Verification**: Anti-Sycophancy is not a "tone." It is a link to a raw data file or a command result. If you cannot cite the path, do not make the claim.

## 3. Chain of Custody (Evidence Integrity)

AI Forensics relies on the integrity of the record.
- **Rule**: Every log, handoff, or state artifact that supports a forensic audit MUST be tamper-evident.
- **Mechanism**: Use append-only logs (e.g., `agent-bus.jsonl`), integrity hashes (SHA256), and git authorship to maintain a verifiable chain of custody.
- **Enforcement**: Evidence that cannot prove its origin or has been silently modified is rejected as "forged context."
- **Version Tracking (The Diff Rule / The Redline)**: Any change to a file or document MUST update its last-updated timestamp at both header and footer locations. Furthermore, if a document or compiled artifact publishes a version tag—or if its filename is trailed with a version number (e.g., `-v1.1.1.pdf`)—the version number MUST be incremented, and all stale files must be removed immediately. Rebuilding or modifying an artifact without synchronizing and bumping version numbers across headers, footers, and filenames is a critical compliance violation to prevent upstream context debt.

## 4. PLTRF (Preventative Long-Term Repo Fragmentation)

Maintaining repository structural integrity is a three-tiered discipline to preserve the repo's knowledge graph:
- **Filesystem Integrity**: The repository map (`docs/repo-organization.md`) must be 100% accurate, with zero orphaned or unmapped files.
- **Reference Integrity**: All cross-references, file pointers, and code symbols must resolve successfully. When a file is renamed or moved, all references must be updated inside the same Knob commit.
- **Knowledge Integrity**: Ensure "One Home" per concept. Duplicate concept definitions are forbidden to prevent semantic drift. 

All automatable aspects of PLTRF are enforced by CI (`pltrf-check.yml`), which fails the build on any broken pointer or duplicate concepts.

## 5. Knob Entry Format

Every Knob entry in the orientation log must contain:
1. **Date**: Full date (e.g., Saturday, June 13, 2026).
2. **Narrative**: 1-2 paragraphs of "Why" and "What."
3. **Cross-References**: Binary links to changed files or previous Knobs.
4. **Order**: Newest Knob on top. Four Knobs (active + last three) is the resting target; the hot log tolerates up to six before a batch-migrate of the oldest back down to four becomes mandatory. The CI gate warns at five or six and fails at seven.
5. **Rollover**: When per-Knob entries cross 5000 characters, spawn the next numbered summary (`ctx-ori-summary-2.md`, then `-3`, `-4`, `-5`) and keep the hot entries in the main log. Older entries migrate to the summary as cold storage.

## 6. Hot/Warm/Cold Tiering

- **Hot**: Active Knob and current directives. Stays in context.
- **Warm**: Recent history (last 3-5 Knobs). Summarized or moved to `ctx-ori-summary-*.md`.
- **Cold**: Archived history. Externalized to the repo; pulled only on demand.

## 7. Canonical Lexicon Definitions

### Knob
The unit of change in a project. One commit, version bump, or in-place change that moves the repo from one state to the next. Each Knob is documented by a ctx-orientation entry that records what changed and why. The entry describes the Knob. The Knob is the change itself, not the entry. A version bump with no state change behind it is a cosmetic Knob and should be logged as one.

### PLTRF (Preventative Long Term Repo Fragmentation)
The discipline of maintaining the structural integrity of the repository knowledge graph. It expands beyond a simple markdown link checker into a three-tiered governance layer spanning: (1) Filesystem Integrity (accurate folder mappings and no orphan files), (2) Reference Integrity (resolvable cross-references and atomic renames), and (3) Knowledge Integrity (avoiding semantic duplication and ensuring one canonical home per concept). All automatable aspects are checked at build time, but PLTRF is the wider human/agent discipline of preventing cognitive decay and self-contradicting specifications.

## 8. The Numerical Grounding Rule

To ensure the "Physics of Truth" is maintained, no repository document, specification, or report may state a quantitative compliance score, drift percentage, or system metric unless there is a runnable script checked into the repository that dynamically computes and outputs that exact number on demand. Any stated metrics not backed by an executable script are classified as "Liturgy" and are considered build-breaking defects.

---

Liturgy purged. Physics enforced.

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v16.18 | 2026-07-01 | `v16.18-crucible-freeze-093` | **Cold** | Enhanced Version Tracking rule with strict timestamp and filename requirements (The Redline). |
| v16.17 | 2026-07-01 | `v16.17-crucible-freeze-088` | **Cold** | Added Version Tracking (The Diff Rule). |
| v16.16 | 2026-07-01 | `v16.16-crucible-freeze-078` | **Cold** | Added Section 8 (Numerical Grounding Rule). |
| v16.14 | 2026-07-01 | `v16.14-crucible-freeze-076` | **Cold** | Archived historical retro and post-mortem logs. |
