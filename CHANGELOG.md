# Changelog

All notable changes to Claude Pet, for people who use it. The engineering *why*
behind each change lives in [`docs/ctx-orientation.md`](docs/ctx-orientation.md),
which is a different document for a different audience.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-08-06

### Added

- **🔥 Cooking.** When Claude is really going, Claw'd catches fire. Triggered by
  8+ tool calls in a minute, or by live subagents — the on-disk signature of an
  `ultracode` fan-out. The threshold is measured, not guessed: an ordinary
  session runs a median of 4 tool calls a minute (p90 of 7), a fanned-out
  workflow a median of 22.
- **👀 Nudging.** When a plan is written and Claude is waiting on your approval,
  he holds out a clipboard and leans in. Detected exactly — an `ExitPlanMode`
  call with no answer yet.
- **Playful hover reactions.** Wink, little jump, wave, or wiggle, picked once
  per hover so it holds while you stay. He stirs even when asleep.
- **Click to poke.** He squashes down, then the roster opens as before. Dragging
  suppresses it.
- **Rainbow mode** 🎉🪄 — poke him three times quickly.
- **A real flame.** The fire is now an upward burst with sparks, replacing three
  flat bars, and he wears a determined expression while it burns.
- **A `plan` prop and a `glasses` prop**, and the `paper` ink behind them.
- Idle status ticker now also reports **live session count**, **hours coded
  today**, and the **project and branch**.

### Fixed

- **Randomness was barely random.** `noise()` was one step of a linear
  congruential generator, whose output moves ~0.0008 per increment — so
  consecutive seeds landed in the same bucket and a four-way choice could only
  ever reach two of its options. This had been quietly narrowing the idle
  flourishes and the working props as well. Replaced with a proper hash.
- **The nudging face broke.** `.wide` eyes draw a row taller while an oscillating
  tilt shifted each eye a pixel the *other* way, landing them two rows apart.
- **The hook installer could destroy `settings.json`** — an unparseable file
  parsed to an empty dictionary and was written back containing only hooks.
- **Hook events could be lost**: the shim wrote non-atomically while the pet
  deleted anything it failed to parse.
- **All feed I/O ran on the main actor**, so a 2 MB transcript read blocked the
  UI. Now on the feed queue.
- **Ten spurious alerts at launch** from replaying each session's tail.
- The sprite re-rendered at display rate forever, including asleep.
- `subagentCount` had never been populated — the event that fills it existed and
  was consumed, but nothing ever emitted it.

### Changed

- The app icon is now Claw'd **without** the flame, sitting larger on the plate.
- README rebuilt as a tour, one segment per state, each naming its real trigger.

## [1.0.0] — 2026-08-06

First public release.

### Added

- **Claw'd on your desktop.** A floating, draggable pet that mirrors whichever
  Claude Code session is busiest. Follows you across Spaces, survives other apps
  going fullscreen, and snaps to the screen edge when you let go of him.
- **Six moods**, each driven by real session state: idle, thinking, working,
  done, needs-you, and asleep.
- **A speech bubble** showing the current task — the in-progress todo's label
  when there is one, otherwise the running tool, otherwise the session title.
- **Eleven props** drawn from Claw'd's official art: a scrolling terminal, hard
  hat and tools, a server rack, a phone, rocket flame, glasses, a balloon,
  sparkles, a green check, an exclamation, and sleeping z's.
- **Idle personality.** When Claude is between tasks he cheers you on, and
  occasionally scrolls a status ticker instead.
- **Status ticker**: the model answering, how many sessions are live, how long
  you have been coding today, and the focused project and branch.
- **Unprompted flourishes** — he jumps, waves, wiggles, stretches, looks around,
  and scuttles on his own every few seconds.
- **Hover to greet him.** He startles, looks up at you, and waves. Even asleep.
- **Session roster.** Click him for every live session with its status, and pin
  him to one you care about.
- **Menu bar controls**: size, sounds, notifications, launch at login, session
  pinning, and hook installation.
- **Optional Claude Code hooks** for sub-100ms reactions and permission-prompt
  alerts. Installing them is user-initiated, shows the exact change first, and
  backs up `settings.json` before writing.
- **Sound and notifications** when a session finishes or needs you.

### Notes

- The app is **ad-hoc signed, not notarized** — see the README for the one-time
  Gatekeeper step. This is deliberate: notarizing would publish the author's
  legal name and Apple Team ID in every copy.
- The **weekly and 5-hour usage lines are usually absent.** Claude Code stopped
  publishing rate-limit percentages to disk, and the pet will not invent a number
  it cannot measure. Those lines appear on their own if the data returns.
- Reads your Claude Code data **read-only**, never over the network. The only
  write to anything Claude owns is the hook installer, and only when you ask.

[1.1.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.1.0
[1.0.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.0.0
