# Crash hardening: a handoff to the parent project

> **Status, 2026-08-28: every shared finding below is already fixed in this
> tree, and this document is kept as the record of the audit rather than as a
> list of work.** Each site now carries a comment naming the bug it used to
> have, so the fix cannot be quietly undone by someone who never read this:
>
> | # | Where it was | What stands there now |
> |:--|:--|:--|
> | 1 | `Window/PetWindow.swift` | The chain no longer ends in a subscript; `:399` and `:453` document the two old endings. |
> | 3 | `Support/HookInstaller.swift:150` | Resolved through `Support/ResourceBundle.swift`, never `Bundle.module`. |
> | 5 | `View/CrabView.swift:1811` | `age(of:at:)` clamps with `max(0, …)`, so no age can run backwards into a negative index. |
> | 6 | `App/AppDelegate.swift:34` | The raise is documented and guarded — it does not return nil, so it cannot be `?`-ed away. |
> | 7 | `App/main.swift:75` | `Probe.clampedDuration` parses the argument; `nan` and `inf` no longer survive the `?? 3`. |
>
> Finding 2 was parent-only and its line is gone. Findings 4 and 8 are
> octo-only and belong to the fork.
>
> The *mechanisms* below are still worth reading. They are the reason each fix
> looks the way it does, and they generalise past this repo — which is why the
> document survives its own checklist.

## 1. What this is

Octo Pet is a fork of [Claude Pet](https://github.com/internetdialup/claude-pet). One round of
crash-hunting over the fork turned up seven findings, and six of them are in
code the fork inherited rather than code it wrote. This document exists because
those six are almost certainly still present upstream — and one of them is
strictly worse there, on a line this fork corrected and never sent back.

Read this if you work on **claude-pet**, or on any macOS SwiftPM app assembled
into a `.app` by a shell script. Every claim about claude-pet below carries a
`file:line` citation, checked against that tree; go and look rather than
believing this document. Nothing here is a patch. The two codebases have drifted
far enough that a diff would not apply, so each finding is written as a
*mechanism* — enough to recognise the shape somewhere else — followed by a
*recipe*, the seam to introduce and the per-call-site decision to make.

Two of the seven are, in plain terms, "a released build can die on a machine
that is not the one it was compiled on". Those are the ones to read first.

## 2. The findings table

| # | What traps | Trigger | Severity | Verdict |
|:--|:--|:--|:--|:--|
| 1 | `NSScreen.screens[0]` at the end of a screen lookup | No display attached: clamshell laptop with the external unplugged, or mid-reconfiguration | Crash on launch **and** on the display-change notification | **SHARED** — `Window/PetWindow.swift:186` |
| 2 | `NSScreen.main!` force unwrap | Same, on the first-launch parking path | Crash on launch | **PARENT-ONLY** — `Window/PetWindow.swift:215`; the fork removed its copy |
| 3 | `Bundle.module`'s generated accessor calls `fatalError` | Any machine that never compiled the project, the moment the resource is asked for | Crash in a shipped build, for every downloader | **SHARED** — `Support/HookInstaller.swift:150`, reached from the "Install Claude hooks…" menu row |
| 4 | Nothing — a missing packaging check | n/a | The gap that let #3 ship three times | **OCTO-ONLY** (the check). The gap it covers is **SHARED** |
| 5 | Negative array index from a mood age that ran backwards | A frame dated before the mood's own epoch | Crash while the pet is on fire | **SHARED** — `View/CrabView.swift:773` → `View/CrabRig.swift:736` |
| 6 | `UNUserNotificationCenter.current()` raises without a bundle identity | `swift run`, or the bare `.build/…` binary the README documents | Abort during launch, from source | **SHARED** — `App/AppDelegate.swift:51` and `:357` |
| 7 | An unclamped `Double(…)` duration argument | `--probe nan`, `--probe inf` | Silent no-op, or a process that never exits | **SHARED** — `App/main.swift:52` |
| 8 | The menu-bar off-bar detector answering "yes" with no displays | Display wake | Spends a once-per-launch warning | **OCTO-ONLY** — claude-pet has no off-bar detector |

Paths in the Verdict column are relative to `Sources/ClaudePet/` unless noted.

---

## 3. Per finding

### Finding 1 — the screen lookup that ends in a subscript

**SHARED.** `Sources/ClaudePet/Window/PetWindow.swift:179-187`.

```swift
static func screen(for rect: CGRect) -> NSScreen {
    …
    return nearest ?? NSScreen.main ?? NSScreen.screens[0]
}
```

**The mechanism.** That line reads as three fallbacks, each more total than the
last. None of them is total.

- `nearest` comes from `min(by:)` over `NSScreen.screens`. `min(by:)` on an
  empty collection returns nil. It is not a "no clear winner" nil; it is an
  "there was nothing to compare" nil, and it fires precisely when the list is
  empty.
- `NSScreen.main` is **documented to return nil**. The documented condition is
  the one being hit: no display is attached, or the value is being read from a
  context with no window on any screen. It is not a defensive optional. It is
  an API that genuinely has no answer sometimes, and this is that time.
- `NSScreen.screens` is **documented to be empty** when no display is attached.
  So the last fallback subscripts the exact array whose emptiness is what got
  us here. It does not misplace the window; it traps and takes the process.

"No display attached" is not exotic. Close a laptop lid with an external
connected and then unplug the external — there is a window of real time with
zero screens. macOS also passes through zero-screen states during
reconfiguration, on wake, and while a display goes to sleep.

In claude-pet this lookup is reached from four places, and two of them are worse
than the fork's were:

- `PetWindow.swift:194-196` — `currentVisibleFrame`, used by both paths below.
- `PetWindow.swift:206-226` — `restorePosition()`, the **launch** path (line 213
  and line 223). A launch with no display attached does not park the pet
  badly; it aborts.
- `PetWindow.swift:241-246` — `screenParametersChanged()`, the **live** path.
  Note the ordering: line 242 guards on `isUsable`, which returns false when
  `NSScreen.screens` is empty (correctly — nothing is reachable), so the guard
  *falls through* into `currentVisibleFrame` at 243. Unplugging the last
  display therefore routes straight into the subscript. This is the one that
  makes the finding a live crash rather than only a launch crash.
- `PetWindow.swift:164` — the drag-drop snap.

**The fix, as a recipe.**

1. **Make the rule a pure function over `[CGRect]`.** Move the
   containing-else-nearest decision out of the `NSScreen` read entirely:

   ```swift
   static func nearestScreenIndex(to rect: CGRect, among frames: [CGRect]) -> Int?
   ```

   Return an **index**, not a rectangle — an index is the one thing a function
   over plain geometry can hand back that still names a particular `NSScreen`.
   Read `NSScreen.screens` into a local first and index that local, so the
   index cannot be resolved against a list that changed underneath it. The
   payoff is section 5: "no displays" becomes `[]` in a unit test instead of
   hardware nobody owns.

2. **Let the lookup return `NSScreen?`.** Do not invent a synthetic screen to
   keep the signature total. A fabricated rectangle trades a loud crash for a
   pet placed silently somewhere that does not exist, and there is no right
   position when there is nowhere to put it.

3. **Decide per call site — and the default is "defer, don't guess".** With no
   display there is nothing to place onto and nobody watching it happen, and
   the display-change notification is the same one that will run the placement
   again. So most call sites should simply return. In claude-pet:
   - the drag drop (`:164`) — return; leave the window where the hand let go,
     and do not persist an origin resolved against nothing;
   - `screenParametersChanged` (`:241`) — return; the frame is still the best
     record of where the pet was.

4. **The one exception is launch.** Deferring at `restorePosition()` leaves an
   `LSUIElement` app with an unplaced, invisible window, no Dock icon to click
   and no way to ask for it back short of relaunching. That path must
   *remember* it still owes a placement. A one-field value type is enough:

   ```swift
   struct PlacementDebt: Equatable, Sendable {
       private(set) var isOwed = false
       mutating func attempted(placed: Bool) { isOwed = !placed }
   }
   ```

   Record the debt where a placement can come back empty-handed; clear it only
   when one actually lands — **not** by being read, or the display-change that
   still has no display would discharge it. Then have
   `screenParametersChanged()` settle the debt *before* it asks its usual
   question, because "did the window drift off screen" and "was it ever put on
   one" are different questions and the second one comes first.

5. **Check the reads you are keeping.** `isUsable` at `PetWindow.swift:230-236`
   is `NSScreen.screens.contains { … }`, which is false on an empty array —
   safe, and correctly so. Write that down next to it. It is the second
   `NSScreen.screens` read in the file and the first one was the crash; the
   next reader deserves to be told which is which instead of re-deriving it.

### Finding 2 — the force unwrap, which is worse here

**PARENT-ONLY.** `Sources/ClaudePet/Window/PetWindow.swift:215`.

```swift
let (edge, thickness) = DockMagnet.dockEdge(frame: (window.screen ?? NSScreen.main!).frame,
```

**The mechanism.** Same documented nil as above, with the optional chain spent
on the wrong operand. `window.screen` is itself documented to return nil when
the window is offscreen — so the `??` is doing real work, and everything it
catches lands on `NSScreen.main!`, which is the API that returns nil for the
very reason `window.screen` just did. The two nils are correlated, not
independent. This is on the first-launch parking path, inside the `else` branch
taken whenever there is no usable saved position — which is exactly the first
launch, and every launch after a monitor change.

The fork had this line and removed it, replacing it with a lookup that answers
`nil`. It kept a comment explaining why, and then — this is the instructive part
— the same file went on shipping finding 1 seventy lines above, because the
sentence "`NSScreen.main` is documented to return nil" was written down in one
place and not read in the other. If you fix only one of these two, fix this one
second and finding 1 first, since finding 1's optional lookup is what this line
should be calling anyway.

**The fix.** Once `screen(for:)` returns `NSScreen?`, this line has no reason to
exist: ask the lookup, and take the same "defer, don't guess" branch as the rest
of `restorePosition()`.

### Finding 3 — `Bundle.module` is a `fatalError` with a friendly name

**SHARED**, with a different resource at the far end.
`Sources/ClaudePet/Support/HookInstaller.swift:149-154`:

```swift
static func shimSource() throws -> String {
    guard let url = Bundle.module.url(forResource: "claude-pet-hook", withExtension: "sh") else {
        throw HookError.missingShim
    }
```

**The mechanism, and why the `guard` does not help.** The trap is not
`.url(forResource:)`. It is `Bundle.module` itself, before the `guard` is ever
evaluated. SwiftPM *generates* that accessor into the module, and it probes
exactly two locations:

1. `Bundle.main.bundleURL` + `/<Package>_<Target>.bundle`
2. an absolute path into the build directory of whichever machine compiled the
   binary

and calls `fatalError("could not load resource bundle: …")` when both miss.

Now look at probe 1 for an app. `Bundle.main.bundleURL` **is** `ClaudePet.app`
— not its `Contents/Resources`. So probe 1 looks for the resource bundle
*beside* the app's own contents, in the folder the `.app` is sitting in.
Meanwhile `run.sh:43-49` copies the bundle into `Contents/Resources`, which is
where it must go: `codesign` rejects a bundle nested under `Contents/MacOS` as
"bundle format unrecognized". **Probe 1 has therefore never matched a shipped
build, and cannot.** Probe 2 matches on exactly one machine in the world: the
one that ran the compiler.

The comment at `run.sh:43-45` states the opposite —

> that is where Bundle.module looks first (via Bundle.main.resourceURL)

— and that sentence is the whole defect. Two facts, each true, believed to be
one: `codesign`'s requirement really does force `Contents/Resources`, and the
generated accessor's search order really does start at `bundleURL`. They never
agreed. The fork carried the identical sentence and shipped three releases that
died because of it.

**Why this is invisible from the inside.** Probe 2 resolves on the build
machine. So the developer's own copy works — through the fallback path, silently
— and no other copy does. A build-machine-only success is the hardest class of
bug to see from where you are standing, because the machine that could see it is
the one machine that cannot.

**Reachability in claude-pet.** `shimSource()` is called from `install()`
(`HookInstaller.swift:95`), which is called from `promptAndInstall()`, wired to
the menu row at `App/MenuBarController.swift:151-152` — *"Install Claude
hooks…"*. That is not a corner of the app. It is the setup step the app exists
to perform. A downloaded build should be expected to die on it.

**The fix, as a recipe.** Resolve the bundle yourself and make "no bundle" a
*value*, not a trap:

```swift
enum ResourceBundle {
    static let resolved: Bundle? = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        .lazy
        .compactMap { $0?.appendingPathComponent("ClaudePet_ClaudePet.bundle") }
        .compactMap(Bundle.init(url:))
        .first
}
```

The order matters and is the reverse of the generated accessor's:

- `resourceURL` **first**, so an installed `.app` resolves through
  `Contents/Resources` — which is what makes that the right directory rather
  than merely the directory `codesign` tolerates;
- `bundleURL` **second**, so a bare `.build/<triple>/debug/ClaudePet` still
  finds its sibling `.bundle` while developing;
- resolved **once, lazily** — the filesystem does not move under a running app;
- and the result is `Bundle?`, so the failure has somewhere to go.

Then decide per call site what "no bundle" means. For a cosmetic resource the
answer is "do without it" — a decorative effect must never be able to end the
process. For claude-pet's hook shim the answer is different and already written:
`HookError.missingShim` exists, with a user-facing message telling them to
rebuild. It was simply unreachable, because the accessor died first. Making the
bundle optional is what finally connects that error to the condition it
describes.

Grep for `Bundle.module` across the tree; every occurrence is one of these.

### Finding 4 — the packaging check that would have caught finding 3

**OCTO-ONLY** as a check; the gap is **SHARED**.

claude-pet's `scripts/make-dmg.sh` runs two checks before a release
(`:101` and `:121`). The second greps the raw Mach-O for `/Users/` paths, and it
is a good check — it is why no home directory has gone out. It cannot catch
finding 3, for a reason worth stating plainly:

`run.sh:27` sets `SCRATCH="${SCRATCH:-/tmp/claude-pet-build}"` to keep the build
path out of `$HOME`. That is correct for anonymity. Its side effect is that the
`Bundle.module` fallback literal baked into the binary becomes `/tmp/…` instead
of `/Users/…`, and the `/Users` grep goes quiet. **The anonymity fix hid the
portability bug.** Both facts were sitting in every shipped binary the whole
time, findable from the outside with the tools already in that file, and nothing
was looking.

Two greps close it, using the same technique as the existing check — raw bytes
(not `strings`, which a UTF-8 machine name splits and hides), and against
`$APP`'s binary before compression, since a compressed `.dmg` shows nothing:

```bash
BUILDPATHS="$(LC_ALL=C grep -oa "/tmp/[A-Za-z0-9_./-]*" "$MACHO" | sort -u || true)"
[ -n "$BUILDPATHS" ] && fail "a build directory from THIS machine is inside the binary"

LC_ALL=C grep -qa "could not load resource bundle" "$MACHO" \
  && fail "SwiftPM's resource-bundle fatalError is reachable"
```

The first says "this binary expects a directory that exists on one Mac". The
second says "something in here resolves resources through the accessor that ends
in `fatalError`". Either one is a build that must not be published.

### Finding 5 — an age that runs backwards, and the subscript that kills for it

**SHARED.** The consumer is verbatim identical.

**The mechanism.** A mood's age is `frameTime − moodEpoch`, and nothing in
either codebase says it cannot be negative. It can, and the two codebases get
there by slightly different routes:

- The fork stamps the epoch from the *frame's own date*, and still went
  negative: dropping to a coarser render tier re-anchors a `.periodic`
  schedule, a periodic lattice snaps **down** rather than up, and the frame
  after a tier change can carry a date up to one whole coarse interval earlier
  than the frame that stamped the epoch.
- claude-pet is looser still, because **the epoch and the age are read off two
  different clocks.** `MoodClock.epoch(for:)` stamps
  `startedAt = Date.timeIntervalSinceReferenceDate`
  (`View/CrabView.swift:869`) — wall clock at the moment of the call. The age
  subtracts it from `timeline.date`, the *scheduled* entry of
  `TimelineView(.periodic(from: Date(), by: interval))`
  (`View/CrabView.swift:728`, consumed at `:754` and `:773`). A scheduled entry
  is by construction at or before the instant the frame actually renders.
  Nothing constrains their order, and no comment claims one.

That interval is re-anchored constantly in claude-pet: it is
`mood.style.frameInterval` (`View/CrabView.swift:714`), it changes on every mood
change, and it is overridden to `1/30` whenever the pet is reacting to the
pointer (`:726-727`). The coarsest tier is `1/6` s for `.sleeping`
(`Support/MoodStyle.swift:82`), so a lattice re-anchor can hand back a date up
to ~167 ms behind.

**Where it lands.** `View/CrabRig.swift:736`:

```swift
let frame = flameFrames[Int(phase * 6) % flameFrames.count]
```

`flameFrames` has three elements (`CrabRig.swift:698`). `phase` is
`pose.propPhase`, which is the mood age (`CrabView.swift:151`). **Swift's `%`
keeps the sign of the dividend**, so a phase of −0.20 selects −1 and −0.34
selects −2: roughly two thirds of the negative band is a killed process rather
than a wrong flame. The threshold is small — `phase ≤ −1/6` is enough — and
`.cooking` sets `pose.prop = .fire` unconditionally (`CrabView.swift:226`) at
whatever phase it is handed, so there is no second gate in the way.

**The tell that this is worth fixing at the seam.** claude-pet already knows
this hazard, in four places, and misses it at the one that produces the number:

- `View/CrabView.swift:638` — `rainbowMood(elapsed:)` guards `elapsed >= 0`
  before doing arithmetic of exactly this shape;
- `View/CrabView.swift:696` — `rainbowTint(elapsed:)`, the same guard;
- `View/CrabView.swift:465` — `applyClick(elapsed:)`, the same guard;
- `View/CrabRig.swift:249` — `drawHearts`, `guard elapsed > born, age >= 0`.

Four guards on four readers, and none on the number they all read.

**The fix, as a recipe.** Clamp **where the age is computed**, not at the
subscript. The subscript is a symptom; every reader of the phase shares one
number, and guarding the fire leaves the next reader to find it again.

```swift
func age(of mood: PetMood, at time: Double) -> Double {
    max(0, time - epoch(for: mood))
}
```

Three things to get right:

1. **It must still rebase.** `age` has to wrap the mutating `epoch`, not
   replace it. A clamp that quietly stopped committing mood flips would freeze
   every one-shot beat at the previous mood's clock — a worse bug than the one
   being fixed. Assert it: after a mood change, the new mood's age at the same
   instant is 0, and 1 one second later.
2. **Route every reader through it.** In claude-pet that is `CrabView.swift:754`
   and `:773`, both currently `time - moodEpoch`.
3. **Leave the subscript partial.** Do not also guard the fire. Its totality is
   now the seam's promise, and the test of that promise is the test of the seam
   (section 5). Two guards for one invariant is how the second one drifts.

While you are there, consider whether `epoch` should take the frame's time
rather than reading `Date()` — that removes the two-clock problem at the source
and leaves only the lattice one, which the clamp then covers.

### Finding 6 — the notification centre raises without a bundle identity

**SHARED**, verbatim. `Sources/ClaudePet/App/AppDelegate.swift:51` and `:357`.

**The mechanism.** `UNUserNotificationCenter.current()` does not return nil when
the process has no bundle identifier. It raises
`NSInternalInconsistencyException` ("bundleProxyForCurrentProcess is nil"), from
inside the class's own `dispatch_once`. So the process aborts with a stack
reading `_dispatch_once_callout` → `currentNotificationCenter` and nothing
whatsoever about what the app was doing or why it was not allowed to.

And a SwiftPM executable has no bundle identity. `swift run ClaudePet`, or the
bare `.build/debug/ClaudePet` the README documents for every offline renderer,
run with no argument: both fall past every `--render-*` guard in `App/main.swift`
into `app.run()` at `main.swift:63`, and `AppDelegate.swift:51` is the first
thing on that path to require an identity. Building from source and launching
what you built — the first thing a new contributor does — aborts during
`applicationDidFinishLaunching`.

The packaged app is unaffected: `run.sh` copies `Support/Info.plist` into
`Contents/`, so the identity is there and the centre answers normally. This only
ever bites the way people are told to build it, which is exactly why it survives
— nobody tests the path everybody uses first.

**The fix.** Look the centre up once, behind an identity check, and let the call
sites optional-chain:

```swift
@MainActor
private enum Notifier {
    static let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : .current()
}
```

Then `Notifier.center?.requestAuthorization(…)` and `Notifier.center?.add(…)`.
A run from source posts no banner instead of dying to raise one. Leave a comment
saying the check must not be "simplified" back out; it looks redundant from
inside a packaged build, which is the only place it looks redundant.

### Finding 7 — `Double` parses "nan" and "inf" perfectly happily

**SHARED** at the parse seam; the consequence differs.

`Sources/ClaudePet/App/main.swift:52`:

```swift
let seconds = arguments.count > index + 1 ? Double(arguments[index + 1]) ?? 3 : 3
```

**The mechanism.** `Double("nan")`, `Double("inf")` and `Double("1e30")` all
succeed. So the `?? 3` fallback — the whole point of which is "the operator
typed nonsense" — never fires for the three arguments most likely to be
nonsense. The `??` is only reached by strings `Double` cannot parse at all.

Downstream, `App/Probe.swift:15-16`:

```swift
let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
```

- `nan` — every comparison against NaN is false, so the loop body never runs and
  `--probe nan` exits immediately having probed nothing. It survives by luck,
  not by handling.
- `inf` / `1e30` — the deadline is unreachable and the loop never stops.

The fork's `--soak` took the same string into `max(1, Int(seconds * fps))` and
**trapped** on its first line, because the floor is applied *after* the
conversion and `Int(nan)` is a dead process rather than a large number to be
clamped. claude-pet has no `--soak`, so it gets a hang rather than a trap — but
the seam is identical and the next consumer added to it inherits whichever
failure it happens to produce.

**The fix.** Clamp where the string becomes a number, which is the only place
still holding both facts — what was typed, and whether anything was typed at
all:

```swift
func clampedDuration(_ text: String) -> Double? {
    guard let value = Double(text), value.isFinite, value > 0 else { return nil }
    return min(value, 3600)
}
```

An hour is longer than any probe anyone means and short of everything that
overflows on the way to a frame count. Each caller keeps its own default behind
`?? n`, which now actually fires.

### Finding 8 — a detector answering with nothing to measure

**OCTO-ONLY.** claude-pet's `App/MenuBarController.swift` creates its status
item and never asks whether the system has since pushed it off the bar, so there
is nothing here to port. Recorded only so the list is complete, and because the
*shape* generalises: `contains` on an empty array is `false`, which for a
predicate phrased as "is it still on some bar?" reads as a confident **no** when
the honest answer is "there are no bars, ask me later". If you add such a
detector, have the sample return `Bool?` and let "no displays" decline to
answer, rather than feeding a debounce a guess.

The same asymmetry applies to anything that announces at most once per launch: a
false positive during a display wake does not merely say something untrue, it
consumes the session's only chance to say something true later.

---

## 4. The four non-bugs

Every one of these was independently re-found by several passes of the same
audit over the fork, which is the tell that a reader over here will spend the
same time on them. All four have counterparts in claude-pet at the citations
below. They are safe. One of them is safe for a reason that can be removed by
accident.

**4.1 — `status[(seed / 3) % status.count]` — safe only because of the guard
directly above it.** `Sources/ClaudePet/Feeds/ActivityCoordinator.swift:604-605`.

```swift
if !status.isEmpty, seed % 3 == 2 {
    next = (status[(seed / 3) % status.count], true)
```

`seed` derives from a wall clock, so it can be negative if the clock is before
1970 — absurd, and settable. Swift's `%` keeps the dividend's sign, so a
negative `seed` yields `0`, `-1` or `-2` from `seed % 3` and **never `2`**: the
branch is simply not entered, and the subscript inside it cannot be reached with
a negative index. **`== 2` is load-bearing, not stylistic.** Loosen it to `!= 0`
— a plausible-looking change to the cadence — and `(seed / 3) % status.count`
goes live the same day. Write that where the guard is, not somewhere it can
drift from. `Support/vocab.swift:253` solves the same problem the other way,
with `let safe = seed & Int.max`; if the cadence ever needs to change, take that
route rather than widening the comparison.

**4.2 — `FileManager.default.urls(for:in:)[0]`.**
`Sources/ClaudePet/Support/SoundBank.swift:70` (caches) and
`Sources/ClaudePet/Support/HookInstaller.swift:17` (application support).

This reads like the `NSScreen.screens[0]` of finding 1 and is a different kind
of thing. It is a **path computation**, not a survey of attached hardware: for
these domains Foundation derives one URL from the process's own home directory
and answers whether or not anything exists at the far end — the `createDirectory`
on the next line is there precisely because it may not. `NSScreen.main` is
documented to return nil and `NSScreen.screens` documented to be empty; there is
no equivalent sentence for this call, because there is no equivalent condition.
A process that cannot name its own home has already lost.

**4.3 — `Int((size.height / cell).rounded(.up))`.**
`Sources/ClaudePet/View/Backdrop.swift:70-72`.

Safe only because of *where it is used*. A zero width makes `cell` zero,
`size.height / cell` infinite, and `Int(∞)` a trap — and `max(1, …)` runs
**after** the conversion and cannot rescue it. Every `Backdrop()` in claude-pet
sits under a fixed frame in the offline reel renderer
(`App/ReelRenderer.swift:151`, `:190`, `:227`, `:305`), reachable only behind
`--render-reel` and `--render-social`, so the size is never negotiated and never
zero. **Put one in a flexible container and this becomes live**: SwiftUI
proposes zero freely — an empty stack cell, a collapsed sidebar, a view laid out
before its parent has a size. If it ever ships outside the reel, guard the width
first.

**4.4 — the scrolling terminal's `lineWidths[(row + scroll) % lineWidths.count]`.**
`Sources/ClaudePet/View/CrabRig.swift:633-636`.

This looks exactly like finding 5's flame and is not one, for a reason worth
keeping: **the prop selector and the phase are the same number.** `.terminal` is
only ever chosen by `CrabView.workingProp(at:)`
(`Sources/ClaudePet/View/CrabView.swift:80-84`), off a hash of
`Int(floor(t / 20))`. Running that hash over the negative band — the
`noise` function at `CrabView.swift:20-26` is deterministic, so this is
arithmetic, not opinion — across the whole range a backward render lattice can
reach, `t ∈ [−40, 0)`, the selected prop is `.phone`. The nearest negative spell
that picks a terminal at all is `t ∈ [−260, −240)`: a four-minute jump backwards,
which no tier change or clock re-anchor produces. A negative `scroll` therefore
cannot arrive while this function is the one drawing. Decouple the two clocks
and it can.

(For the same reason, `workingProp` itself is safe: its index is
`Int(noise(…) * count) % count` and `noise` returns `0..<1`, so the dividend is
never negative.)

---

## 5. How to verify without the hardware

Almost all of this is testable on one Mac with one display.

**The `[CGRect]` seam is the whole trick.** Once the screen rule is a pure
function over an array of rectangles (finding 1, step 1), "no displays attached"
is `[]` in a unit test. Write at least:

- `nearestScreenIndex(to: anyRect, among: []) == nil` — the regression itself;
- one display, rect inside it → index 0; rect outside it → still index 0, by
  nearest-centre;
- two displays, a rect exactly between them → **the same index every time**.
  Ties must go to the earliest index, which is `NSScreen.screens` order and
  holds as long as the arrangement does. Without that rule the pet flickers
  across a seam and the menu opens on a different monitor each right-click.
- the same for whatever `isUsable`/reachability predicate you keep: empty array
  → false, and take the parking path rather than trapping.

**The mood age (finding 5) needs no window and no Metal.** Stamp an epoch, then
sweep the whole backward band a coarse tier can produce — the fork sweeps
−2.0 s to +6 s in 5 ms steps — and assert the age is never negative, that
forward of the epoch it is still exactly the elapsed time, and that a mood change
still rebases to zero *through* the clamp. Then apply the flame's own
arithmetic (`Int(phase * 6) % 3`) to what comes out and assert the result is in
`0..<3`. Deliberately do **not** test the subscript in isolation: it is meant to
stay partial, and this is the test of the promise that keeps it total.

**Finding 3 has a check anyone can run today, on the machine they are sitting
at.** A shipped app whose resource bundle resolves only via an absolute build
path will die the moment that path is absent — so make it absent:

```bash
./run.sh                      # build and assemble build/ClaudePet.app
rm -rf /tmp/claude-pet-build  # delete the scratch directory the fallback names
open build/ClaudePet.app      # then trigger the resource: "Install Claude hooks…"
```

If it dies, every downloader's copy dies too, because none of them ever had that
directory. This is the entire test, and it costs one command. It is also worth
copying the `.app` to another Mac and doing nothing but click that menu row —
but the `rm -rf` reproduces it locally and needs nobody else's hardware.

Add the two `make-dmg.sh` greps from finding 4 so a release cannot ship it
again, and note that they inspect the `.app`'s Mach-O *before* compression: the
compressed `.dmg` shows nothing until mounted.

**Finding 6 needs one command**: `swift run ClaudePet` with no arguments. It
should reach a run loop, not abort. That it currently aborts is the finding.

**Finding 7 needs three**: `--probe nan` (should run the default, not exit
instantly), `--probe inf` (should run the default, not hang), `--probe -5`
(should run the default).

**Concurrency, for completeness.** claude-pet has **13** `MainActor.assumeIsolated`
call sites; the fork has 18. All 13 were checked and **none is reachable off the
main actor**: seven are top-level statements in `App/main.swift` (`:9`, `:15`,
`:20`, `:25`, `:30`, `:39`, `:53`), which run on the main thread before the app
object exists; the other six are in `Window/PetWindow.swift` (`:324`, `:328`,
`:340`, `:349`, `:363`, `:377`) — AppKit mouse handlers, which AppKit delivers on
the main thread, plus one `Timer` closure scheduled from `mouseDown` onto the
main run loop. Every genuine background-to-main hop in the feeds uses
`Task { @MainActor in … }` instead (`Feeds/ActivityCoordinator.swift:154`,
`:158`, `:165`, `:247`, `:260`, `:273`, `:642`). This is the right split; it is
recorded here so the next audit does not re-derive it. The thing to watch is a
new `assumeIsolated` added inside a `DispatchQueue` block —
`Feeds/FileWatcher.swift` and `Feeds/HookServer.swift` both own queues.

---

## 6. What genuinely needs other hardware

These are unverified. They are listed so the list of "checked" above stays
honest, not because they are believed to be broken.

- **Notched Mac menu bar geometry.** The reserved strip is a per-screen height,
  and it is larger on a notched display than on the external monitors this was
  measured against. Anything that compares a window's frame to "the screen minus
  the menu bar" should read the height off *that* screen rather than carrying a
  constant. Needs a notched Mac to confirm the numbers.
- **Stage Manager.** It changes `visibleFrame` and window ordering in ways not
  exercised here at all. No finding above assumes anything about it, which is
  itself untested.
- **Real clamshell undock timing.** The zero-screen window is reasoned about
  from documentation — `NSScreen.main` documented nil, `NSScreen.screens`
  documented empty — and reproduced in tests as `[]`. How long the real window
  lasts, how many `NSApplication.didChangeScreenParametersNotification` fire
  during it, and whether any intermediate state reports one screen with a
  degenerate frame, all need an external display to pull.
- **Non-2× backing scale.** Anything taking a `displayScale` and turning it into
  pixel arithmetic is untested at 1× and at the fractional scales a scaled
  resolution produces.
- **Intel / x86_64 slices.** Everything above was reasoned about and run on
  Apple silicon. Nothing in these findings is architecture-specific in
  principle, and none of it has been confirmed on an Intel Mac.
