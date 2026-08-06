# Claude Pet 🦀

Claw'd lives on your desktop and shows you what Claude Code is doing.

He floats above your windows near the dock, follows you across Spaces, and can be
dragged anywhere. When Claude is reasoning he looks around with sparkles overhead.
When a tool is running he types at a little terminal window. When a session
finishes he throws his arms up with a green check. When one needs your
permission, he waves and chirps. The current task rides in a speech bubble above
his head.

He watches **every** running Claude Code session — the crab mirrors whichever one
is busiest, and clicking him opens a roster of all of them so you can pin one.

## Running it

```bash
./run.sh
```

That builds the executable, assembles `build/ClaudePet.app`, ad-hoc signs it, and
launches it. There is no Dock icon — the control surface is the crab in the menu
bar: size, sounds, notifications, launch at login, session pinning, and hook
installation. A mood-preview submenu appears in debug builds only; the
`debug/preview-tools` branch keeps it on permanently.

```bash
swift build --product ClaudePet    # the Build Target from AGENT.md
swift test                          # unit tests; synthetic fixtures, never touches ~/.claude/
```

Two offline modes are useful when working on it:

```bash
.build/debug/ClaudePet --render-sheet out.png   # contact sheet of all six moods
.build/debug/ClaudePet --probe                  # print the PetState from your real sessions
```

## How it knows

Claude Code already writes everything needed, and the pet only reads it:

| Source | What it gives |
| :--- | :--- |
| `~/.claude/sessions/<pid>.json` | Live session registry. The filename is the PID, so liveness is `kill(pid,0)` **plus** a `procStart` match to guard PID reuse. |
| `~/.claude/projects/<encoded-cwd>/<id>.jsonl` | The transcript. `tool_use` blocks give the running tool and its description; `thinking` blocks and `stop_reason` give the rest. |
| `~/.claude/tasks/<id>/*.json` | Todos. The in-progress item's `activeForm` is already phrased for a human, so it wins the bubble. |
| Hooks (optional) | `PreToolUse` / `PostToolUse` / `Stop` / `Notification` for sub-100ms reactions, and the only way to see a permission prompt. |

Filesystem watching is the ground truth; hooks are a latency optimisation on top.
That ordering is deliberate — hooks are blind to sessions that started before
they were installed, so the pet has to be correct without them.

## What it will not do

`~/.claude/` is your live working data. The rules are in `Bamboo.md` §5 and §6,
and they are short:

- **Read-only** for everything Claude Code owns — sessions, transcripts, todos,
  settings. The pet writes in exactly two places, neither of which is Claude's
  data: its own event drop-directory `~/.claude/claude-pet-events/`, and the
  hook installer, which
  is user-initiated from the menu bar, shows you the exact change first, and
  copies `settings.json` to `settings.json.bak.<timestamp>` before writing.
- **Every read is a bounded tail.** Transcripts reach 85 MB; a full read is a
  hang, not a slow path.
- **No network.** `Package.swift` has an empty `dependencies` array, which makes
  that checkable rather than promised.
- Tests never touch `~/.claude/`.

## The art

Claw'd is drawn, not imported — a parametric rig rasterised into a 32×32 indexed
buffer each frame (`Sources/ClaudePet/View/`). Flat colour, no outline, no
shading ramp, whole-pixel motion. He is not a sprite sheet, so a new pose is a
few numbers rather than a new asset.

## Governance

The repo follows Bamboo. Start at `AGENT.md`, then `Bamboo.md`, then
`docs/ctx-orientation.md` for why things are the way they are.
