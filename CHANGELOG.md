# Changelog

All notable changes to Claude Pet, for people who use it. The engineering *why*
behind each change lives in [`docs/ctx-orientation.md`](docs/ctx-orientation.md),
which is a different document for a different audience.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.0.0
