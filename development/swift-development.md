# Swift Development Specification 🦀 - v0.2.0

---
**Document Metadata:**
- **Created:** 2026-08-06
- **Last Updated:** 2026-08-06
- **Document Version:** v0.2.0
- **Operational Freeze Tag:** `v0.1.2-clawd-personality`
---

This document defines the structural discipline for Swift/SwiftUI projects governed by Bamboo. It prioritizes **Compiler Truth** and **Named Persistence** over narrative vibes. It was authored here because `development/swift-development.md` in the canon repo is a 0-byte placeholder.

## 1. The Swift 3-Concept Canon

### 1.1 The Target Knob
Every meaningful change to a product target, its public surface, or its persisted state MUST be logged as a Knob in `docs/ctx-orientation.md`.
- **Rule**: The entry names the target (`ClaudePet`) and every file whose module boundary moved.
- **Physics**: A change is not "done" until `swift build` exits 0 and `swift test` exits 0. A claim of "it compiles" without the exit code is liturgy.

### 1.2 Layer Stratification (View vs. State vs. Feed)
- **View Layer** (`Sources/ClaudePet/View/`, `Window/`) — SwiftUI and AppKit. Renders `PetState`. Owns no I/O.
- **State Layer** (`Sources/ClaudePet/Model/`) — value types only. `Codable`, `Sendable`, no imports beyond `Foundation`.
- **Feed Layer** (`Sources/ClaudePet/Feeds/`) — all filesystem and socket I/O. Emits `ActivityEvent` values.
- **Constraint**: dependencies point **inward** (View → Model ← Feeds). A View that opens a `FileHandle` is a layering violation. The Model layer importing SwiftUI is a layering violation.

### 1.3 Type PLTRF
- **One Home**: every file is named for its **principal type**. `PetState.swift` declares `PetState`. Two files declaring overlapping concepts is a duplicate home.
- **Companions**: a type that has no meaning apart from its principal may share the file — `CrabPose` beside `CrabRig`, `PetViewModel` beside `PetRootView`. A type that stands alone gets its own file; `ClaudeHome` was split out of `ClaudeSession.swift` for exactly this reason. The test is whether you would look for it under that filename.
- **Data catalogues** are named for their content rather than their type: `vocab-shoutouts.swift` declares `VocabShoutouts`. They hold no behaviour beyond selection, and the operator reads them by subject.
- **Assets have one home too**: a file that ships to the user lives on disk once and is loaded, never transcribed into a string literal. The hook shim is `Sources/ClaudePet/Resources/claude-pet-hook.sh`, read through `Bundle.module` — the file you can read in the repo is byte-for-byte the file that gets installed.
- **Renames**: renaming a type renames its file in the same commit, and the pointer in `docs/repo-organization.md` flips in that same commit.

---

## 2. Structural Verification (The Physics)

- **Build Target**: state it in the `AGENT.md` Session Identity block. Here: `swift build --product ClaudePet`.
- **Exit codes are the evidence**: `swift build 2>&1 | tail -20` and its exit status are the only acceptable proof of compilation. Screenshots prove rendering; they do not prove building.
- **Concurrency**: the package builds under Swift 6 strict concurrency. `@MainActor` isolation on UI types and `Sendable` on model types are structural claims the compiler checks — do not silence them with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment naming the invariant that makes it safe.
- **Warnings**: a new warning is a regression. `swift build 2>&1 | grep -c warning:` is the number.
- **Entitlements & Info.plist**: any capability claim (always-on-top, launch-at-login, notifications) names the exact key and the exact file — `Sources/ClaudePet/Support/Info.plist` (`LSUIElement`) or the `SMAppService` registration site.

---

## 3. Mandatory Hygiene

- **Naming**: types `UpperCamelCase`, members `lowerCamelCase`, no abbreviations that are not already in the domain (`PID`, `JSONL`, `URL` are fine).
- **Persistence claims name a store**: any "saved" claim names the exact `UserDefaults` suite and key (`com.internetdialup.claude-pet` / `pet.position`) or the absolute file path. "It persists" alone is not a report.
- **No remote dependencies**: `Package.swift` has an empty `dependencies` array. This is what makes the no-egress claim in `Bamboo.md` §6 verifiable instead of promised.
- **Bounded reads**: any file this app reads from `~/.claude/` may be arbitrarily large. Reads are seek-and-tail with an explicit byte budget, never `String(contentsOf:)`.
- **Timers stop**: every repeating animation timer or `DispatchSource` has a documented teardown path. A pet that burns CPU while asleep is a defect.

---

The compiler is structural. The exit code is the claim.

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v0.2.0 | 2026-08-06 | `v0.1.2-clawd-personality` | **Hot** | §1.3 amended: principal-type naming, companion types, data catalogues, and one-home-for-shipped-assets. |
| v0.1.0 | 2026-08-06 | `v0.1.0-claude-pet-genesis` | **Hot** | Genesis. Authored the Swift standard absent from canon; defined layer stratification and exit-code physics. |
