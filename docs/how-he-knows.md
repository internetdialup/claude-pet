# How he knows

Claude Code already writes everything needed, and the pet only reads it:

| Source | What it gives |
| :--- | :--- |
| `~/.claude/sessions/<pid>.json` | Live session registry. The filename is the PID, so liveness is `kill(pid,0)` **plus** a `procStart` match to guard PID reuse. |
| `~/.claude/projects/<encoded-cwd>/<id>.jsonl` | The transcript. `tool_use` blocks give the running tool and its description; `thinking` blocks and `stop_reason` give the rest. Also the model and git branch. |
| `~/.claude/tasks/<id>/*.json` | Todos. The in-progress item's `activeForm` is already phrased for a human, so it wins the bubble. |
| Hooks (optional) | `PreToolUse` / `PostToolUse` / `Stop` / `Notification` for sub-100ms reactions, and the only way to see a permission prompt. |

Filesystem watching is the ground truth, and hooks only make him faster. Hooks
can't see sessions that started before they were installed, so the pet has to
be correct without them.

## About the usage percentages

While idle, Claw'd rotates encouragement with a status ticker: the model
answering, how many sessions are live, how long you have been coding today, and
the project and branch.

**The weekly and 5-hour usage lines will probably not appear.** Claude Code
stopped publishing rate-limit percentages to disk, and this app won't invent a
number it can't measure. It still reads the usage cache and checks its
freshness, so those lines come back on their own if the data ever does.

---

[← Back to the README](../README.md)
