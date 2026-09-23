# How he knows

Claude Code already writes everything needed, and the pet only reads it:

| Source | What it gives |
| :--- | :--- |
| `~/.claude/sessions/<pid>.json` | Live session registry. The filename is the PID, so liveness is `kill(pid,0)` **plus** a `procStart` match to guard PID reuse. Current Claude Code also writes what the session is doing — busy, waiting on you, or idle — and its own version; the pet reads that first and falls back to the transcript on builds that don't. |
| `~/.claude/projects/<encoded-cwd>/<id>.jsonl` | The transcript. `tool_use` blocks give the running tool and its description; `thinking` blocks and `stop_reason` give the rest. Also the model and git branch. |
| `~/.claude/tasks/<id>/*.json` | Todos. The in-progress item's `activeForm` is already phrased for a human, so it wins the bubble. Current Claude Code builds no longer write this folder; there the bubble shows the tool Claude is running instead. |
| Hooks (optional) | `PreToolUse` / `PostToolUse` / `Stop` / `Notification` for sub-100ms reactions, and — on Claude Code builds that don't publish a status — the only way to see a permission prompt. Each event lands as one JSON file — the hook's whole payload, tool input and output included — in `~/.claude/claude-pet-events/`, read and deleted on the spot; files over 256 KB are deleted unread. |

Filesystem watching is the ground truth, and hooks only make him faster. Hooks
can't see sessions that started before they were installed, so the pet has to
be correct without them.

## About the usage percentages

While idle, Claw'd rotates encouragement with a status ticker: the model
answering, how many sessions are live, how long you have been coding today, and
the project and branch.

**The weekly and 5-hour usage lines will probably not appear.** Claude Code
doesn't write them to disk: it hands rate limits to a `statusLine` command, if
you install one, and the usage cache the pet reads is whatever that command
writes. Without one there is no number to show, and this app won't invent one.
It checks the cache's freshness, so the lines appear on their own if you do run
such a command.

## When Claude Code changes under him

Claude Code updates constantly — sixty-four releases separated the command-line
and desktop builds on one machine this month, and the pet read every one of
them. So a new version number means nothing on its own, and he never checks
one.

What he watches is the *shape* of what gets written. If a live session's
registry file stops decoding, or its transcript stops producing records he
recognises, he stops guessing and says so: a puzzled pose, and a bubble that
names the version — *This Claw'd doesn't understand Claude Code 2.1.x yet*. The
menu says what broke and offers **Check for updates…**. The moment the format
reads again, he goes back to normal.

The thresholds were set against 53,000 real transcript lines from nine Claude
Code versions, so a healthy session can't trip them — only a format that has
actually changed.

---

[← Back to the README](../README.md)
