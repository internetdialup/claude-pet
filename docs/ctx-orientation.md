# Orientation Log — Claude Pet

---
**Document Metadata:**
- **Created:** 2026-08-06
- **Last Updated:** 2026-08-06
- **Document Version:** v0.1.2
- **Operational Freeze Tag:** `v0.1.2-clawd-personality`
---

The Knob log. Newest on top. Target 4 entries, hard max 6 (`Bamboo.md` §1).

## Knob: v0.1.2 — Personality, and a hardening pass before going public — Thursday, August 06, 2026

Two halves: giving Claw'd something to do between tasks, and making the repo safe to publish.

**Personality.** Idle was dead air showing a stale label — after a turn ended, `.turnEnded` cleared `tool` but left `activity` set, so the bubble displayed the last tool's description indefinitely. Clearing it created a genuine "no task" moment, which `vocab-shoutouts.swift` now fills with encouragement. The catalogue is keyed by occasion rather than being a flat array, and selection is *seeded* rather than random: the bubble is recomputed on a 2s timer, so `Bool.random()` would rewrite the sentence three times before anyone finished reading it. The first picker had a subtle flaw worth remembering — it filtered the avoided line out and then indexed modulo the *shortened* array, which with a sequential seed made one line permanently unreachable. Indexing the full list and stepping past a collision fixes it, and there is a test that asserts every line is reachable.

He also moves now: a scheduled flourish (jump, wave, wiggle, stretch, look-around, scuttle) roughly every 7s, authored as shapes over a normalised 0…1 progress rather than as frequencies, so each one plays through instead of stuttering. Hovering him is its own greeting — he startles, looks up at you, and waves, even when asleep. The prop vocabulary grew from one to eleven, taken from the official sticker set (hard hat and tools, servers, phone, rocket flame, balloon, glasses), randomised per work spell. Two art defects were caught on the contact sheet and nowhere else: the flame anchored off-frame and clipped to a single bar at x=0, and raised arms drawn flush against the body merged into the top corners and turned the whole silhouette into a cat.

The operator asked for arm and leg motion to slow down — at the original rates they flickered several times a second, which reads as agitation in peripheral vision. `needsAttention` stayed quick, because that is the one state that wants urgency.

**Hardening.** A four-dimension audit (memory, resources, concurrency, open-source safety) raised 27 claims; an adversarial refutation pass killed 13 of them, including several confident-sounding ones about unbounded `carry` growth, `@unchecked Sendable` unsoundness, and a leaked window — each refuted by someone actually compiling the code and measuring. That ratio is the argument for the verify step: over a third of plausible findings were wrong.

What survived and got fixed:

- **`settings.json` could be destroyed.** The installer parsed it with `?? [:]`, so a file that existed but failed to parse became an empty dictionary and was written back containing *only* hooks — silently discarding statusLine, theme, plugins and permissions. It now refuses and names the backup. A backup existing is not a licence to overwrite.
- **Hook events could be lost.** The shim wrote with `cat > file` (not atomic) while the pet deleted anything it could not parse, so a file caught mid-write was destroyed rather than retried. The shim now writes to a scratch name and `mv`s it into place, and the pet only reaps unparseable files once they are a minute old.
- **All feed I/O ran on the main actor.** The watcher delivered on a background queue and the handler immediately hopped to `@MainActor` *before* reading — so a 2 MB transcript read plus per-line JSON parsing blocked the UI. Reading now happens on the feed queue and only the resulting `[ActivityEvent]` crosses over; `FoldStore` exists to give the per-session readers an isolation that is not the main actor.
- **Ten spurious alerts at launch.** Priming replayed each session's tail, and the tail almost always ends in a finished turn, so the pet chirped and posted a notification for work that completed before it started.
- **The sprite rendered at display rate forever**, including asleep with zero sessions. It is whole pixels on a 32×32 grid; nothing it can express needs 120 Hz. The timeline is now paced per mood.
- **A test hardcoded the operator's username, machine name and home path** — about to be published to GitHub. Replaced with a synthetic path that still exercises the awkward cases (a ` - ` run collapsing to three dashes, a curly apostrophe).
- Docs were claiming things the code did not do: a `Tests/ClaudePetTests/Fixtures/` directory that never existed, a fixed test count, and "exactly one writer to `~/.claude/`" while `HookServer` created and drained its own directory there.

**Structure for OSS.** Files are now named for their principal type (`DirectoryWatcher.swift` → `FileWatcher.swift`, `TranscriptTailer.swift` → `TranscriptFold.swift`, `PixelCanvas.swift` → `PixelBuffer.swift`), `ClaudeHome` was split out of `ClaudeSession.swift`, and the hook shim stopped existing twice — it was both a file and a Swift string literal, and is now only the file, shipped via `Bundle.module`. `development/swift-development.md` §1.3 was amended rather than quietly violated: it now permits companion types, names the data-catalogue exception that `vocab-shoutouts.swift` relies on, and requires that shipped assets live on disk once. The bundle identifier moved off the operator's legal name to the handle they publish under.

**Files changed:** `Sources/ClaudePet/Support/vocab-shoutouts.swift`, `Feeds/StatusTicker.swift`, `Model/ClaudeHome.swift`, `Resources/claude-pet-hook.sh` (new); `Feeds/{ActivityCoordinator,HookServer,TranscriptFold,FileWatcher}.swift`, `View/{CrabRig,CrabView,PixelBuffer,ThoughtBubble,PetRootView}.swift`, `Window/PetWindow.swift`, `App/{AppDelegate,MenuBarController,SpriteSheetRenderer}.swift`, `Support/{HookInstaller,Preferences,Palette}.swift`, `Model/{PetState,ClaudeSession,ActivityEvent}.swift`, `Package.swift`, `run.sh`; `Tests/ClaudePetTests/PersonalityTests.swift` (new) and the two existing suites; `LICENSE`, `.gitignore` (new); `README.md`, `Bamboo.md`, `CLAUDE.md`, `AGENT.md`, `development/swift-development.md`, `docs/repo-organization.md`.

## Knob: v0.1.1 — Claw'd likeness and the timezone liveness bug — Thursday, August 06, 2026

Two corrections, both found by looking at output rather than by reasoning about code.

**The sprite was the wrong character.** The first rig was an anatomical crab: elliptical shell, shading ramp, tapered pincers, a 1px outline, drawn on a 64×64 grid. It was a competent crab and not Claw'd at all. The operator supplied the official sticker art, and the difference is structural rather than cosmetic — Claw'd is a *rectangle*: flat colour with no shading and no outline, two black square eyes, thin nubs for arms, four stubby legs with a wide centre gap, on a coarse grid. Fine grids and soft edges are precisely what stop a copy from reading as the original. The rig was rebuilt on a 32×32 grid with flat inks, whole-pixel motion, and the prop vocabulary from the sticker set — sparkles while thinking, a little terminal window while a tool runs, the green check on completion. Two intermediate defects were caught on the contact sheet and fixed: raised arms drawn flush against the body merged into the top corners and turned the whole silhouette into a cat, so the raised segment now steps one pixel outward; and the `.open` mouth was a wide white slab that read as bared teeth, so it was narrowed.

**The pet reported zero sessions while ten were running.** `procStart` liveness was comparing *formatted strings*. Claude Code writes that field in UTC; `ps` and a default `DateFormatter` render local time. On a UTC−5 machine every live session was five hours "wrong" and therefore judged dead — the PID-reuse guard silently rejected everything it was meant to protect. The comparison is now between *instants*: parse the declared string in both UTC and local, take whichever lands nearer the kernel's recorded start, and accept within 1.5s. The lesson worth keeping is that the guard failed closed and looked like an empty desktop rather than an error, which is exactly the failure mode that a `--probe` mode exists to expose.

`--probe` was added for that reason: it starts the real coordinator against the real `~/.claude/`, prints the resulting `PetState`, and exits. It is how the pipeline is verified without needing a screenshot of a floating window. Its first successful run showed the bubble reading "Scaffolding repo and Bamboo harness" — this repo's own todo, observed from outside.

**The size control was wired to nothing.** The pet looked tiny, a `pixelSize` preference and a menu-bar submenu were added, and it changed nothing — because `PixelCanvasView` ended with a hardcoded `.frame(width: 32, height: 32)`. The sprite always rendered at 32 points and was then merely *centred* inside whatever larger frame the caller asked for, which also explains the large empty gap between the bubble and the character. A view that pins its own size silently discards its caller's layout, and the symptom was "the setting does nothing" rather than any error. The canvas now sets no frame of its own and fills what it is given.

Sizing itself was then calibrated against a reference the operator supplied — Claw'd should match the head of ChatGPT's desktop pet. Measured off that screenshot, using the bubble's known 200pt width as a ruler, the head is ≈86×64pt. Claw'd occupies 24 of 32 grid cells across and 16 down, so `pixelSize` 4 renders him at 96×64pt. That is the default; the menu now quotes the *character's* size rather than the sprite frame's, since the frame includes transparent margin and quoting it overstated how large he actually looks by a third.

Because a larger sprite implies a larger window, and a large transparent window would swallow desktop clicks, the host view now hit-tests: only the sprite band accepts the mouse and everything outside it is click-through.

**Files changed:**
- `Sources/ClaudePet/View/CrabRig.swift` — rewritten; Claw'd's blocky geometry, arm/leg/face parts, and the prop set.
- `Sources/ClaudePet/View/PixelCanvas.swift` — rewritten; 32×32 grid, flat ink slots, `stamp()` for glyph props, outline pass removed, and the self-imposed 32pt frame deleted.
- `Sources/ClaudePet/View/CrabView.swift` — whole-pixel animation curves per mood.
- `Sources/ClaudePet/Support/Palette.swift` — replaced the clay ramp with Claw'd's flat palette.
- `Sources/ClaudePet/View/ThoughtBubble.swift` — restyled to the sticker bubbles: flat fill, square corners, stepped pixel tail.
- `Sources/ClaudePet/Feeds/SessionRegistry.swift` — the liveness fix; `processStartEpoch` and `parseProcStart` replace string comparison.
- `Sources/ClaudePet/App/Probe.swift` — new; `--probe` prints live `PetState`.
- `Sources/ClaudePet/View/PetRootView.swift`, `Window/PetWindow.swift`, `App/AppDelegate.swift`, `App/MenuBarController.swift`, `Support/Preferences.swift` — size preference, window rebuild, click-through hit testing.
- `Tests/ClaudePetTests/SessionAndGeometryTests.swift` — regression test asserting UTC-written and locally-written `procStart` are both accepted.
- `README.md` — created.

## Knob: v0.1.0 — Claude Pet genesis — Thursday, August 06, 2026

The operator runs roughly ten concurrent Claude Code sessions and has no ambient signal for what any of them are doing — the state exists on disk but never reaches the eye. This Knob stands up a native macOS desktop pet, a crab, that renders that state continuously: it floats above the windows near the dock, blinks on an idle cycle, and animates according to whether Claude is thinking, running a tool, finished, or waiting on a permission prompt. The task title rides in a bubble above its head.

The design decision worth recording is *why the pet reads the filesystem rather than only listening to hooks*. Hooks are fast but they are also blind to any session that started before they were installed, and they vanish on restart. `~/.claude/sessions/<pid>.json` is a live registry — the filename is the PID, so liveness is `kill(pid,0)` plus a `procStart` match to guard against PID reuse — and the transcripts and `~/.claude/tasks/<sessionId>/*.json` carry the rest. Filesystem observation is therefore the ground truth and hooks are a latency optimization layered on top. That ordering is what makes the pet correct after a crash.

The second decision: transcripts reach 85 MB. Every read is a bounded tail. This is written into `Bamboo.md` §5 as a redline rather than left as a performance note, because a full read is not a slow path — it is a hang.

The third: this repo had no Swift standard to inherit. `development/swift-development.md` is a 0-byte placeholder in the canon repo, so it was authored here, modeled on the shape of the Unity standard — layer stratification (View → Model ← Feeds), exit codes as the only acceptable proof of compilation, and persistence claims that must name a `UserDefaults` key or an absolute path.

**Files changed:**
- `AGENT.md` — created; cold-start router with Session Identity naming the `swift build --product ClaudePet` target, plus the read-only default rule for `~/.claude/`.
- `Bamboo.md` — created; local operating spec. Carries the `~/.claude` redline (§5: one permitted writer, bounded reads, tests never touch it) and the no-egress privacy constraint (§6).
- `development/swift-development.md` — created; authored the Swift structural standard absent from canon.
- `docs/repo-organization.md` — created; folder map for the package and governance layer.
- `docs/ctx-orientation.md` — created; this log.
- `behavior/ctx-rules.md` — forked verbatim from `../bamboo-private`.
- `REPORTING_TEMPLATE.md` — forked verbatim from `../bamboo-private`.
- `.github/workflows/pltrf-check.yml` — forked from canon; `VALID_PREFIX` and `HOTLOG` retuned for this repo's top-level folders.
- `Package.swift`, `Sources/ClaudePet/**`, `Tests/ClaudePetTests/**` — the executable target scaffold.

---
### 📜 Document Changelog

| Version | Date | Freeze Tag | Memory Tier | Summary of Change |
| :--- | :--- | :--- | :--- | :--- |
| v0.1.2 | 2026-08-06 | `v0.1.2-clawd-personality` | **Hot** | Knob v0.1.2 — personality pass and pre-OSS hardening. |
| v0.1.0 | 2026-08-06 | `v0.1.0-claude-pet-genesis` | **Hot** | Genesis Knob. Project stood up under Bamboo governance. |
