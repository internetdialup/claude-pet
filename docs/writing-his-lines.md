# Writing his lines

Everything Claw'd says lives in **two files**. No strings scattered through
the codebase, no localisation framework, no config format to learn:

| | File | Holds |
| :---: | :--- | :--- |
| 💬 | [`Support/vocab.swift`](Sources/ClaudePet/Support/vocab.swift) | What he says in the **speech bubble** |
| 🔔 | [`Support/notification-nudge.swift`](Sources/ClaudePet/Support/notification-nudge.swift) | What the **macOS banners** say |

Both are the same shape (an exhaustive `switch` returning `[String]`), so
learning one teaches the other. Edit the arrays, run `./run.sh`, and he says
your words instead.

| | Occasion | When he says it | Ships with |
| :---: | :--- | :--- | :--- |
| 💬 | `.idle` | Sessions are live but Claude is between tasks | *"Let's build something awesome!"* · *"Ooo that's a spicy idea 🌶️"* |
| 💭 | `.thinking` | Reasoning, no tool running | *"Thinking it through"* · *"Give me a second"* |
| ⚙️ | `.working` | A tool is in flight | *"On it"* · *"This is the fun part"* |
| 🔥 | `.cooking` | Going hard: rapid calls, or a subagent fan-out | *"Absolutely cooking 🔥"* · *"Do not disturb"* |
| 👀 | `.planReady` | A plan is up and he wants your verdict | *"Plan's ready 👀"* · *"Shall we?"* |
| ✅ | `.finished` | A turn just ended | *"Nailed it"* · *"That's a wrap 🎬"* · *"Chef's kiss"* |
| ‼️ | `.needsYou` | Claude is blocked on you, usually a permission prompt | *"Psst — I need you"* · *"One quick question"* |
| 😴 | `.sleeping` | Nothing is running at all | *"zzz…"* · *"Resting my claws"* |

## 🥇 What wins, when several could apply

This is the one thing worth reading before you edit, because otherwise it looks
like your lines are being ignored:

| | Precedence | Example |
| :---: | :--- | :--- |
| 1️⃣ | A **rule** matching the current task | `git commit …` → *"Committing the good stuff 📦"* |
| 2️⃣ | The **real task text**, whenever there is one | *"Running the test suite"* |
| 3️⃣ | The **state's lines** | *"This is the fun part"* |

Rank 2️⃣ is deliberate: while Claude is actually running something, the bubble
shows what it is running. A pet that hides *"Running the test suite"* behind a
joke is a worse pet. So your `.working` and `.cooking` lines fill the **gaps
between tools** rather than replacing anything useful, and `.sleeping` speaks
only occasionally. A sleeping pet that talks constantly is not asleep.

## ✏️ Editing lines

Find the occasion, change the strings. That is the whole job:

```swift
// 💬 Between tasks. Encouragement, mostly.
case .idle: [
    "Let's build something awesome!",
    "Now we're cooking with crisco 🍳",
    "your line here",          // ← add as many as you like
]
```

## 🎯 Custom sentences for particular work

Rules let him say something specific when the task matches a pattern. The first
match wins, so put the specific ones first:

```swift
public static let rules: [VocabRule] = [
    VocabRule(#"\btest(s|ing)?\b"#, [
        "Writing tests, the good kind 🧪",
        "Red, green, refactor",
    ]),
    VocabRule(#"\bdeploy\b"#, ["Shipping it 🚀"]),   // ← yours here
]
```

| | Ships with | Fires on |
| :---: | :--- | :--- |
| 🧪 | tests | `test`, `tests`, `testing` |
| 📦 | commits | `commit`, `git` |
| 🔍 | debugging | `fix`, `bug`, `debug` |
| 📝 | docs | `README`, `doc`, `docs`, `document` |

Patterns are case-insensitive regular expressions. **A pattern that doesn't
compile is skipped, not fatal**. A typo in your vocabulary should never take
the pet down.

## ➕ Adding a whole new occasion

Add a `case` to `ShoutoutOccasion` and **the build will fail until you give it
lines**. That is deliberate: `lines(for:)` is a `switch` rather than a dictionary, so
the compiler catches a half-added occasion instead of Claw'd silently saying
nothing at runtime.

## 📏 Two rules worth knowing

| | |
| :--- | :--- |
| **Keep it short** | The bubble cuts off at **28 characters**. It caps at 210pt, and 28 is what fits, measured by rendering a ruler through the real bubble. A test enforces it, with a short allowlist of existing lines that run one or two over: a renderer deciding a sentence is a character too wide is not a reason to rewrite someone's voice. |
| **Emoji are welcome** | They render fine, but count each as **two** characters, since they draw about twice as wide. 🍳 🌶️ 🎬 all ship by default. |
| **He deals a deck** | Lines are dealt like a shuffled deck: every line is used once before any repeats, and the shuffle is reseeded each pass. A plain random pick would show one line four times and another never. |

<div align="center">
  <img src="media/bubbles.png" width="440" alt="One speech bubble per state, each with its own fill colour and glyph">
</div>

<p align="center"><em>One bubble per state. The fill, the glyph and the text all
come from the two files above.</em></p>

## 🔔 What the banners say

Same idea, second file. `notification-nudge.swift` holds the title and body for
each banner, and Claw'd's own icon rides along with it:

| | Event | Fires when | Default |
| :---: | :--- | :--- | :---: |
| ✅ | `.finished` | A turn ends while you are looking elsewhere | **on** |
| ‼️ | `.needsYou` | Claude is blocked on you | **on** |
| 👀 | `.planReady` | A plan is waiting for approval | **on** |
| 🔥 | `.cooking` | A session starts really going | **off** |

> [!IMPORTANT]
> **Banners do not fire in the downloadable build, and cannot.** macOS only
> delivers notifications to apps with a stable code-signing identity, and Claw'd
> is deliberately ad-hoc signed, because a Developer ID signature would publish the
> author's legal name and Apple Team ID inside every copy. An ad-hoc signature's
> hash changes on every build, so the app is never registered with Notification
> Center at all. It is not denied; it never appears in System Settings ▸
> Notifications for you to switch on.
>
> Measured on a real install: the released `.dmg` copied into `/Applications`,
> quarantine cleared, launched from there: zero entries under
> `com.apple.ncprefs.plist`, where 93 other apps were listed.
>
> The menu rows say so rather than showing a tick that does nothing. Building
> from source does not help: `run.sh` ad-hoc signs too. The copy below is live
> and tested, and ships for whoever signs their own build.

`.cooking` ships off because it fires often; turn it on from the menu bar under
**Notify when cooking 🔥**. All four respect the master **Notifications** toggle.

Banner copy has a tighter budget than the bubble: **titles under 40 characters,
bodies under 80**, because macOS truncates. The session name is appended for
you, so don't repeat it. A test enforces both limits.

Selection is driven by a **seed, never `random()`**. The bubble is recomputed on
a timer, so a real RNG would rewrite the sentence out from under you mid-read.

---

[← Back to the README](../README.md)
