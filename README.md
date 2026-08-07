<div align="center">
  <img src="docs/media/icon-1024.png" width="120" alt="Claude Pet">
  <h1>Claude Pet 🦀</h1>
  <p><strong>Claw'd lives on your desktop and shows you what Claude Code is doing.</strong></p>
  <img src="docs/media/desktop.gif" width="640" alt="Claw'd running on the desktop beside another desktop pet">
  <p><em>Claw'd on the desktop, reporting a live session — next to a friend.</em></p>
</div>

## What it is

Claude Code tells you what it is doing inside the terminal. The moment you switch
to a browser, a design tool, or another repo, that goes dark — and if you run
several sessions at once, it was never visible in the first place.

Claude Pet puts it back where you can see it. Claw'd sits on the desktop, always
on top, and reflects your sessions continuously: what tool is running, what task
is in progress, which one just finished, and which one is stuck waiting on you.
No window to check, no tab to switch to. You just glance at him.



He floats above your windows near the dock, follows you across Spaces, and can be
dragged anywhere. When Claude is reasoning he thinks. When a tool is running he
works at a little terminal. When a session finishes he throws his arms up. When
one needs your permission, he waves and chirps. The current task rides in a
speech bubble above his head.

He watches **every** running Claude Code session — the crab mirrors whichever one
is busiest, and clicking him opens a roster of all of them so you can pin one.

| | | |
| :---: | :---: | :---: |
| <img src="docs/media/idle.gif" width="150"> | <img src="docs/media/thinking.gif" width="150"> | <img src="docs/media/working.gif" width="150"> |
| **Idle** — cheers you on between tasks | **Thinking** — Claude is reasoning | **Working** — a tool is running |
| <img src="docs/media/done.gif" width="150"> | <img src="docs/media/needsAttention.gif" width="150"> | <img src="docs/media/sleeping.gif" width="150"> |
| **Done** — a turn finished | **Needs you** — waiting on a prompt | **Asleep** — nothing running |

<img src="docs/media/hover.gif" width="150" align="left" hspace="12">

**Hover him and he says hello.** He startles, looks up at you, and waves — even
when he is asleep. Every few seconds while idle he does something unprompted on
his own: a jump, a stretch, a wiggle, a look around the desktop.

<br clear="left">

## Installing

Download **`ClaudePet-1.0.0.dmg`** from
[Releases](https://github.com/internetdialup/claude-pet/releases), open it, and
drag Claw'd to Applications.

> **First launch shows "unidentified developer".** This is expected. The app is
> ad-hoc signed and deliberately **not** notarized — notarizing would publish the
> author's legal name and Apple Team ID inside every copy. To open it:
>
> **Right-click the app → Open → Open.** Once only.
>
> Or, if you prefer the terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/ClaudePet.app
> ```
>
> If you would rather not run someone else's binary at all — completely fair —
> [build it yourself](#building-it-yourself). It takes about thirty seconds.

**Claw'd has no Dock icon.** He lives in the menu bar: click the little crab
there for size, sounds, notifications, **Launch at login**, session pinning, and
hook installation. He reappears wherever you last dragged him, on whichever
display you left him on.

## Building it yourself

```bash
git clone https://github.com/internetdialup/claude-pet.git
cd claude-pet
./run.sh
```

That builds the executable, assembles `build/ClaudePet.app`, ad-hoc signs it, and
launches it. Requires macOS 14+ and a Swift 6 toolchain (Xcode 16 or newer).

```bash
swift build --product ClaudePet    # the Build Target from AGENT.md
swift test                          # unit tests; synthetic fixtures, never touches ~/.claude/
./scripts/make-icon.sh              # regenerate the app icon from the sprite rig
./scripts/make-dmg.sh               # build the installer
```

Three offline modes are useful when working on it:

```bash
.build/debug/ClaudePet --render-sheet out.png   # contact sheet of every mood and prop
.build/debug/ClaudePet --render-gif docs/media  # the GIFs above
.build/debug/ClaudePet --probe                  # print the PetState from your real sessions
```

## How it knows

Claude Code already writes everything needed, and the pet only reads it:

| Source | What it gives |
| :--- | :--- |
| `~/.claude/sessions/<pid>.json` | Live session registry. The filename is the PID, so liveness is `kill(pid,0)` **plus** a `procStart` match to guard PID reuse. |
| `~/.claude/projects/<encoded-cwd>/<id>.jsonl` | The transcript. `tool_use` blocks give the running tool and its description; `thinking` blocks and `stop_reason` give the rest. Also the model and git branch. |
| `~/.claude/tasks/<id>/*.json` | Todos. The in-progress item's `activeForm` is already phrased for a human, so it wins the bubble. |
| Hooks (optional) | `PreToolUse` / `PostToolUse` / `Stop` / `Notification` for sub-100ms reactions, and the only way to see a permission prompt. |

Filesystem watching is the ground truth; hooks are a latency optimisation on top.
That ordering is deliberate — hooks are blind to sessions that started before
they were installed, so the pet has to be correct without them.

### About the usage percentages

While idle, Claw'd rotates encouragement with a status ticker: the model
answering, how many sessions are live, how long you have been coding today, and
the project and branch.

**The weekly and 5-hour usage lines will probably not appear.** Claude Code no
longer publishes rate-limit percentages to disk, and this app will not invent a
number it cannot measure. The code reads the usage cache and freshness-gates it,
so those lines light up on their own if the data ever comes back. An empty line
is the honest answer; a made-up percentage is not.

## What it will not do

`~/.claude/` is your live working data. The rules are in `Bamboo.md` §5 and §6:

- **Read-only** for everything Claude Code owns — sessions, transcripts, todos,
  settings. The pet writes in exactly two places, neither of which is Claude's
  data: its own event drop-directory `~/.claude/claude-pet-events/`, and the hook
  installer, which is user-initiated from the menu bar, shows you the exact
  change first, and copies `settings.json` to `settings.json.bak.<timestamp>`
  before writing.
- **Every read is a bounded tail.** Transcripts reach 85 MB; a full read is a
  hang, not a slow path.
- **No network. At all.** `Package.swift` has an empty `dependencies` array,
  which makes that checkable rather than promised. Nothing is uploaded, no
  telemetry, no analytics, no crash reporting.
- Tests never touch `~/.claude/`.

## The art

Claw'd is Anthropic's mascot. He is **drawn, not imported** — a parametric rig
rasterised into a 32×32 indexed buffer each frame
([`Sources/ClaudePet/View/`](Sources/ClaudePet/View/)). Flat colour, no outline,
no shading ramp, whole-pixel motion. He is not a sprite sheet, so a new pose is a
few numbers rather than a new asset, and the app icon is rendered from the same
rig so the two can never drift apart.

This project is unofficial and not affiliated with or endorsed by Anthropic. See
[LICENSE](LICENSE).

## Version history

See [CHANGELOG.md](CHANGELOG.md). Currently **v1.0.0**.

## Contributing

The repo follows Bamboo, a governance discipline for AI-assisted codebases. Start
at [`AGENT.md`](AGENT.md), then [`Bamboo.md`](Bamboo.md), then
[`docs/ctx-orientation.md`](docs/ctx-orientation.md) for why things are the way
they are. [`development/swift-development.md`](development/swift-development.md)
is the structural standard for the Swift itself.

Two rules worth knowing before you open a PR:

1. **Exit codes are the evidence.** "It builds" needs `swift build` exiting 0.
2. **Never read a transcript whole.** Bounded tails only.

MIT licensed.
