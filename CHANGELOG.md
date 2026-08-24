# Changelog

All notable changes to Claude Pet, for people who use it.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.1] — 2026-08-24

### Fixed

- **🔌 He notices the sessions you start while he's running.** The big one. He
  watches each session's transcript, but Claude Code writes the session's
  registry entry a second or two *before* that transcript exists — so he
  reached for a file that wasn't there yet, gave up, and never tried again.
  Every session you started while he was already on the desktop was invisible
  to him for its whole life: no title, no tool, no mood, just idle. Relaunching
  him "fixed" it only because by then the file existed. He now waits for it.
- **📋 The near-done glow and the cooking card work again.** The same problem
  wearing a different hat: your todo folder is created by the first TodoWrite,
  so he watched the folder *above* it — which tells him the folder was created
  and then nothing ever again. He heard about your todos exactly once per
  session, while it was still empty, which quietly took the 80% glow and the
  quarter-crossing milestones with it.
- **🖱️ Double-clicks and repeat parties stop cutting themselves short.** Poking
  him twice queued two timers, and the first one ended the second poke's
  reaction two-thirds of the way through — so every double-click finished with
  a visible jolt. A second triple-poke party died the same way, mid-rainbow.
- **🎬 Green-screen plates line up with the titled cuts again.** Hiding the
  titles removed them from the layout instead of just making them invisible, so
  the plate's Claw'd sat ten rows higher than the master's. Keyed footage would
  have drifted against its own titles.
- **🟩 The vertical reel's pixels are square again.** At the 9:16 resting size
  every fourth column of him was an eighth wider than its neighbours — on a
  character whose whole look is square pixels, in the shot the vertical camera
  holds most of the time.
- **🏗️ It builds on a stock toolchain again.** An expression the newer Swift
  resolves and the older one rejects had been failing every automated build
  since 1.5.0 went out.

### Changed

- **👀 He bobs like he means the question.** The two states where he's waiting
  on *you* were the easiest to miss: a plan awaiting your verdict moved a
  single pixel every three and a half seconds, and the urgent one flickered
  rather than bounced. Both now travel further and land on every pixel on the
  way, so a question reads from across the room.

## [1.5.0] — 2026-08-21

### Added

- **🔊 An 8-bit soundboard.** He speaks now: a cute rising squeal when
  you poke him (three pokes climb into the party), a squeak-squeak on
  the bug catch, a low purr when petting begins, a sparkle run on
  costume changes, a fwoosh when a cook ignites, and a proper chiptune
  fanfare when an epic lands — the done bell stands down for it. The
  attention chirp and done chime got 8-bit voices too, and an optional
  per-service blip (C-E-G-B for npm, GitHub, Linear, deploys) lives
  behind "Service sound blips" in the menu. Every sound is synthesised
  in memory — still zero binary assets — and everything hushes during
  films, now enforced in one place.
- **⭐ A star for the thinking spell.** During long thinking stretches the
  sparkles now trade shifts with an 8-bit Claude star — a nine-cell
  sunburst in flame and gold, the same mark the reel's sting wears.
- **🌈 The rainbow, hammered home.** The triple-poke party throws real
  confetti now — six flecks tumbling through the trapezoid — the rainbow
  drags a chromatic afterimage behind him as he moves, and the epic bow
  fires a flat eight-ray sweep behind the glow. Mix and match, all three.
- **🎈 A balloon worth waiting for.** On a long idle, once in a while, he
  floats a balloon for a few seconds. Rare on purpose — never in the
  first stretch, so a fresh launch stays calm.

### Changed

- **🦀 The menu bar gets the actual crab.** The icon was a freehand
  drawing — an oval body, two stick eye-stalks, two oval claws — that
  shared nothing with the character on your desktop. It is drawn from
  the real sprite now, cropped so he fills the bar, with his eyes and
  smile punched through the shell the way a stencil reads a face.
- **👆 The roster admits it is clickable.** The session rows gave no
  feedback at all: nothing lit under the pointer, nothing moved when
  you pressed, so a list of sessions you can pin read as a list of
  labels. Rows now light on hover and answer on press, and the "Unpin"
  line got the same treatment.
- **🖱️ He only takes the clicks that are his.** The mouse used to treat
  his whole 32×32 square as him — so the empty sky over his head, the
  floor under his feet, the window's corners and the gaps between his
  legs all swallowed clicks meant for whatever was behind him, and
  opened the roster on the way. Now the click zone is his actual
  silhouette, widened just enough to cover the bob he does while
  breathing. Everything else passes straight through to the app
  underneath. Hovering and petting tightened with it: he stirs when the
  pointer is touching him, not when it is somewhere in his airspace.
  The stomach is still the only drag handle, and the floor bug is still
  pounceable while it is out.
- **🟩 The Matrix goes full terminal.** The code used to be six
  one-pixel columns dripping at a single speed, drawn under his face so
  his eyes erased chunks of it. Now it falls down his whole shell —
  every column at its own speed and streak length, through a bright
  head, a phosphor body and a dim tail — with varying-width code-lines
  scrolling underneath it. The shell is darker so the code carries, and
  his eyes are brighter than any of it so he keeps his face.
- **💬 He speaks in bursts instead of wearing a banner.** The thought
  bubble used to sit on his head for the entire time he was working or
  cooking, its text merely swapping every fourteen seconds. Now a new
  task or tool shows immediately and holds, then he goes quiet and
  checks back in every half-minute or so. Alerts and plan-nudges are
  never silenced — they pulse instead, because being blocked on you is
  the one thing worth interrupting for. The menu-bar tooltip always
  shows the live task, even while he is quiet.
- **⚡ The white flash became a flashbang.** It used to be a peach wash
  held across the whole ten-second celebration — only 40% of the way to
  white, and only on his shell, so his eyes stayed black and a dark
  costume never lit at all. Now the whole sprite blanches to pure white,
  eyes and costume and heat bands together, in two hard hits inside the
  first second — bang, a beat of honest terracotta, secondary — with
  light spilling off him and, on an epic, the burst rings brightening on
  each hit. The other nine seconds stay calm, which is what makes the
  hits land. Honors the system Reduce Motion setting: he still
  celebrates with pose, hops and colour, just without the strobe.
- **🐯 The tiger goes orange.** Jungle Tiger trades green for actual tiger:
  orange coat, dark stripes, a cream belly patch, a darker mouth.
- **💥📟 Bang and phone, redrawn.** The alert bang wears an ember outline
  with a paper highlight and hops phase; the phone lights its screen and
  shows the alert dot, so the prop reads at a glance.
- **🗝️ The preview goes secret.** "Preview animation" left the menu bar —
  it was an art-review tool wearing a public hat. Shift+click the pet,
  then press K within three seconds: the animation-testing menu opens at
  the pet, Live hands control back to the live feed. Any other key, or
  just waiting, closes the gate quietly.

## [1.4.0] — 2026-08-12

### Added

- **👘 A wardrobe.** Seven costumes — Ninja, Retro Black, Matrix, Jungle
  Tiger, Arctic White, Gundam, Sonic — picked from the new menubar Costume
  submenu and remembered between launches. Costumes survive every mood and
  every prop; status effects always paint over them. The ninja trades the
  shell for shadow with a terracotta eye window, because a mask may frame
  the eyes but never cover them; the Matrix shell rains live green code
  down his back; the Gundam brings the RX-78 head home — V-fin, red crest,
  yellow cameras in a black visor recess, blue armor down the flanks; and
  the Sonic goes fast — blue shell, back-swept quills, tan muzzle, red
  sneakers over white socks.
- **🔥 Fire that heats the shell.** During a hard cook, a banded heat cascade
  sometimes sweeps up his body; when the todo list passes 80%, a soft white
  pulse says the sprint is almost home; and when a cooking sprint lands, the
  done state plays a ~10-second payoff — flash train, scale breathing, the hop
  re-armed twice — before cooling back down. Rarely, mid-cook, a five-second
  disco finds him. He keeps working through it.
- **🏆 The epic finale.** A cook that runs a full minute and lands earns the
  bigger payoff: the white flash, a warm glow blooming behind him under
  three expanding 8-bit rings, his whole body growing a fifth and settling
  back, and a rainbow sweeping the shell — all inside the same ten-second
  bow, easing back to a plain done before it fades. Short cooks keep the
  ordinary celebration.
- **🔖 Service glyphs.** He name-checks the service he's talking to: an
  8-bit npm cube while npm/yarn/pnpm/bun run, a GitHub mark while a push
  or PR is in flight, a Linear diamond during Linear tool calls, a deploy
  rocket for vercel/docker/fly — floating beside him AND badging his
  thought bubble, easing in with the work and lingering a few seconds
  past it. Original pixel marks, evocative not copied; recognition rides
  the real shell command, not the polite description.
- **📊 The cooking card.** With notifications on, a cook starting posts a
  macOS banner, and each quarter of the todo list crossed updates it in
  place — `▓▓▓▓░░░░ 50%` — silently, no re-chime. The done chime retires
  the card so a stale bar never sits under it.
- **⬛ Ground under his feet.** A soft 8-bit shadow block sits at his
  footline — 15% black, one and a half cells tall — so he stands on the
  desk instead of floating over it.
- **🥚 Four secrets.** A floor bug worth clicking, press-and-hold petting with
  rising hearts, a shrimp snack for whoever pokes a sleeping crab, and — in
  the small hours only — a telescope.
- **✨ Attention, eased.** The bubble sweeps an occasional light band and
  pulses a slow check when a plan awaits your verdict.
- **🎨 A vector bridge.** `--render-vectors` exports the base body and every
  prop as layered SVGs for design review. Code stays the source of truth.
- **🦀🦀 A second pet.** Summon him from the menu ("Second pet") and a
  second Claw'd joins the desk — following the busiest session the first
  isn't showing (or any session you pin him to), wearing his own costume,
  remembering his own spot, and getting everything the first has: petting,
  eggs, the badge, the film step-aside. Two windows, one app — never two
  processes, which would fight over the event feed. He parks beside his
  sibling, never under him, and dock-corner snaps de-stack. Maximum two;
  this is a desk, not a beach.
- **📌 Persistency.** A new menu toggle for how present he is. On (the
  default, and the classic posture) he floats above every window — still
  stepping aside for video. Off, he lives at normal window level: opening
  Finder or a browser covers him, nothing ever shuffles him forward, and
  you see him again when the windows move off.
- **🎬 He steps aside for films.** Fullscreen video on his display — Netflix,
  YouTube, whatever holds the screen awake — fades him out; the credits (or
  your escape key) bring him back. Deliberately film-only: a window covering
  the display AND that same app keeping the display awake, so a fullscreen
  editor or a slide deck never scares him off. Sound cues hush during films
  too. On by default; "Step aside for video" in the menu turns it off, and
  showing him mid-film keeps him up for the rest of it.
- **✅ The quiet done.** A finished task no longer leaves a lingering banner:
  the done pose plays its moment, then hands the signal to a small 8-bit
  checkbox parked beside his feet, bottom edge on his footline. It stays
  until new work consumes it — not until a clock does — and every three
  minutes it takes one soft golden breath to catch your eye. He stands in
  front of it when he leans over it. Completions older than half an hour
  don't resurrect on launch; recent ones greet you back.

### Changed

- **He's grabbed by the stomach.** The mouse knows exactly where he is —
  his sprite, nothing more: no invisible margin, no grabbable bubble. Only
  the torso moves him; claws, legs and crown still poke, pet and pounce.
  With two pets parked side by side, that's what keeps each one
  individually grabbable — and a poke never yanks him to the dock edge
  anymore.
- **Idle chatter goes intermittent.** For the first minute and a half of
  quiet he keeps you company as always; past that, roughly one cycle in
  three shows a line and the rest are calm. The status ticker keeps its
  share of the cycles that do show.
- **Nothing snaps anymore.** Mood changes cross-ease from the pose that was
  actually on screen; the hover greeting decays from wherever it had reached
  instead of vanishing; the 20-second prop re-roll puts one prop down and
  picks the next up through a pixel dissolve; the working arms are eased
  squares instead of square waves. The exemptions are single-pixel steps and
  blinks, which snap in nature.
- **The console is in his claws.** The little code window sits in front of him
  like a held laptop — claw tips gripping the lid, eyes peering over it — and
  tracks his bob instead of hanging painted on the sky.

### Fixed

- **One pet, ever.** Launching the app while a copy is already running now
  quits the old copy instead of doubling him — the build you just launched
  is the one you meant.
- **Crash hardening, from the fork's crash hunt.** A launch or display
  unplug with no screen attached no longer aborts (the pet defers placement
  and settles the debt when a display arrives); "Install Claude hooks…"
  works on machines that didn't compile the app (resources resolve relative
  to the app, and two release checks now prove it); a clock that briefly
  runs backwards can no longer kill him mid-flame; building from source and
  running the bare binary reaches the desktop instead of aborting on the
  notification centre; and `--probe nan`/`inf` run the default instead of
  probing nothing or forever.
- **First click grabs him.** A press while another app was frontmost was
  swallowed as an activation click; dragging him needed a second try.
- **The bubble tail is no longer eaten by the sprite** in the overlap band —
  the live view gets the fix the reel renderer already had.

## [1.3.0] — 2026-08-08

### Added

- **🌊 A backdrop, and the features that had never been pictured.** Eleven new
  assets: the six idle flourishes (only one had ever been rendered on its own),
  the triple-poke party, the session roster, one bubble per state, and every prop
  in a strip. The README described all of them in text and showed none of them.
- **`--render-reel`** renders composed scenes — the hero, the roster, the bubbles
  and the props — entirely from code.
- **`--render-social`** renders the same 15 seconds in **two aspects** — 9:16 at
  1080×1920 for Reels and 16:9 at 1920×1080 for Threads — plus a cover still.
  Video rather than GIF because neither platform takes a GIF, and at those sizes
  a GIF would be enormous and stuck at 256 colours. Encoded with AVFoundation,
  which ships with macOS, so `Package.swift` keeps its empty dependency array.
  Both cuts share one clock and one beat list, so their timing cannot drift.
  It also writes **clean plates** in both aspects — the pet on the backdrop with
  no wordmark, tagline or URL, in a `clean` variant that keeps the speech bubble
  and a `bare` variant that drops it. Titles belong in the edit, not baked into
  the footage.

### Changed

- **The hero is rendered, not recorded.** It was the one committed asset that was
  a screen capture, which quietly falsified the promise that a diff in the media
  folder means the animation changed. It now renders offline from the demo
  script: reproducible, and structurally unable to capture a stray notification
  the way the old one did. It also shrank from 432 KB to 237 KB.
- The backdrop is **derived** from a wallpaper's hue and saturation, not copied
  from it — and deliberately much darker, because the sampled mid-tones sat
  within 1.02:1 of Claw'd's body colour and would have shimmered.
- **Sleep threshold 300s → 900s.** Measured over the local corpus: the median
  park between a finished turn and the next human prompt is 180s, and **40% of
  ordinary parks exceed 300s** — so a 5-minute nap fired during two-fifths of
  normal think-breaks. At 900s only 19% are longer, and those are real
  walk-aways. (This changes no shipped behaviour, since the old threshold could
  never fire either.)
- **`--probe` takes an optional duration**, e.g. `--probe 320`. The default 3s
  is shorter than every decay horizon, so it could not observe one.

### Fixed

- **🐛 The pet no longer hangs on a finished task.**
  ([#2](https://github.com/internetdialup/claude-pet/issues/2), reported by
  TokyoSoyMRX.) Commit something, leave the tab open, and Claw'd would keep
  narrating the work forever — never settling to idle, never sleeping, the
  bubble frozen on whatever it last saw.

  Two independent causes. The pet's own workload poll ran every 2 seconds and
  emitted an event for **every** live session whether or not anything had
  changed, and the reducer advanced `lastActivity` on every event kind — so
  `now - lastActivity` never exceeded 2 seconds and every time-based threshold
  was arithmetically unreachable. That includes the 6-second `done → idle`
  decay, which means **it had never once fired in a shipped build**, and the
  300-second sleep threshold, which is why he never slept while a session was
  open. Underneath that, `.thinking` and `.working` had no decay path at all.

  The poll no longer counts as session activity, and the per-session decay now
  covers every mood that can strand rather than `.done` alone. Decay clears the
  tool, the task text and any pending approval alongside the mood — leaving any
  one of them set kept the words on screen after the pose relaxed.

- **A session title no longer masquerades as a live task.** The idle branch was
  gated on "no task", and a title counts as a task, so any *named* session — most
  of them — froze on its own title and never reached the status ticker.

- **The bubble truncates at 29 characters, not 46.** The docs and the test both
  said 46; the bubble caps at 210pt over a 6.62pt advance, which is 29. Five
  shipped lines are longer and are cut off on screen — including the one in the
  README hero, which is why it read *"Let's build something aweso…"*. The limit
  is corrected and enforced; the five lines are named rather than rewritten.
- **Deleted `hover.gif`**, which was byte-identical to `hover-hop.gif` and
  referenced nowhere.
- Two stale **v1.0.0** claims in the README, four versions out of date.

## [1.2.1] — 2026-08-07

### Fixed

- **🔒 Build-host paths are no longer baked into the binary.** A default SwiftPM
  release build writes the absolute build path into the executable once per
  object file as an `N_OSO` debug stab, plus once more as the `Bundle.module`
  fallback literal. On a stock macOS install that path starts `/Users/<account>/`,
  and the account name is usually a real name — so every published `.dmg`
  carried the author's identity, which is the exact thing this project skips
  notarization to avoid. `run.sh` now builds with `--scratch-path` outside
  `$HOME` and `-Xswiftc -gnone`; measured on this tree, that takes the count
  from 77 to zero.
- **The anonymity check now checks the binary.** `scripts/make-dmg.sh` verified
  the signature was ad-hoc with no Team ID — true, and passing, while the
  Mach-O was wide open. It now greps the raw bytes of the executable for host
  paths and **exits non-zero rather than shipping**. Two traps it is written
  around: `strings` misses a path containing a non-ASCII machine name, and the
  compressed `.dmg` reveals nothing until it is mounted.
- **Scrubbed a real notification banner from the README demo.** A macOS banner
  belonging to an unrelated session was captured into the recording and frozen
  into all 192 frames — naming a private project. `DemoMode` had correctly
  fabricated the roster; an OS notification landed on top of the sanitized
  capture. Historical copies were rewritten out of git history at the same time.

## [1.2.0] — 2026-08-06

### Added

- **🗣️ Every state can carry your words.** `vocab.swift` covered four of his
  eight states; now it covers all eight, so thinking, working, cooking and
  sleeping can all be written by you. The file states the precedence up front —
  a matching rule beats the real task text, which beats the state's lines —
  because otherwise it reads like your lines are being ignored when they are
  simply losing to *"Running the test suite"*, which is the more useful thing to
  show.
- **🔔 `notification-nudge.swift`.** The macOS banners now have their own
  editable file, the same shape as `vocab.swift`. Banners also carry Claw'd's
  icon, and two new ones join them: **plan waiting** (a plan can sit unnoticed
  for a long time) and **cooking started**, which ships **off** behind a menu-bar
  toggle because it fires often.
- **🎉 Party mode cycles poses.** Triple-click used to recolour him; now he walks
  the full set of states while the rainbow runs — sparkles, terminal, fire,
  clipboard — for four seconds, then goes back to reporting reality.

### Fixed

- **Clicking Claw'd no longer steals focus.** `canBecomeKey` was unconditionally
  true, so poking the pet pulled the caret out of whatever you were typing in.
  It is now true only while the roster popover is open, which is the one case
  that genuinely needs a key window.

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

[1.5.1]: https://github.com/internetdialup/claude-pet/releases/tag/v1.5.1
[1.5.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.5.0
[1.4.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.4.0
[1.3.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.3.0
[1.2.1]: https://github.com/internetdialup/claude-pet/releases/tag/v1.2.1
[1.2.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.2.0
[1.1.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.1.0
[1.0.0]: https://github.com/internetdialup/claude-pet/releases/tag/v1.0.0
