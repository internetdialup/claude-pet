# How he knows

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

## About the usage percentages

While idle, Claw'd rotates encouragement with a status ticker: the model
answering, how many sessions are live, how long you have been coding today, and
the project and branch.

**The weekly and 5-hour usage lines will probably not appear.** Claude Code no
longer publishes rate-limit percentages to disk, and this app will not invent a
number it cannot measure. The code reads the usage cache and freshness-gates it,
so those lines light up on their own if the data ever comes back. An empty line
is the honest answer; a made-up percentage is not.

---

[← Back to the README](../README.md)
