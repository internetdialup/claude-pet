# Changelog

All notable changes to Claude Pet, for people who use it.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **📖 Fun facts finish their sentence now.** A scrolling fact always
  completes one full read before real news can replace it. After that, news
  takes over right away. Busy sessions used to cut facts off mid-word every
  ten seconds or so, and idle facts died even faster. Both paths are fixed.
- **😎 The deal-with-it drop.** About half the time a fun fact shows up, the
  shades fall from above and land on his face. Sometimes the landing gets a
  little sparkle and a ding. It varies on purpose, so keep watching.
- **🎉 The triple-poke party actually fires.** Three deliberate pokes now
  count even at human speed. The old version needed machine-gun clicking,
  and the roster panel was eating your second click anyway. The panel now
  waits three quarters of a second before opening, so a poke combo never
  flashes it.
- **🍤 Double-poke feeds him.** Two quick pokes on an idle crab's body and he
  pulls out the shrimp. One poke still opens the roster, three still party.
- **🌠 A shooting star, sometimes.** During a late-night stargaze there is a
  chance a streak crosses the sky, and he follows it with his eyes. Most
  nights it stays rare. That is the point.
- **🛹✨ The golden board.** About one skate trick in fifty rides a gold deck,
  and he has special lines saved for it.
- **💛 The long-pet thank-you.** Hold the pet for ten full seconds and the
  hearts surge, with a line he saves for exactly this.
- **🛹 More skating overall.** The idle rotation now leans harder into the
  board: tricks come up about twice as often as before.
- **🖼️ A release banner.** The release pages open with a masthead now:
  Claw'd mid-ollie beside the name, rendered from the same rig as everything
  else and checked byte-for-byte like the rest of the committed art.

- **😾 Wake him up and he lets you know about it.** Click a sleeping crab and
  one claw stretches out from under the covers with a zzz still rising. Then
  his eyes open, annoyed, at you. He stays up about ninety seconds, and if
  you leave him alone he drifts back to sleep. Real work still keeps him up
  the full fifteen minutes, and a session that needs you still beats
  everything. Daytime naps are quieter too: one z every other breath, while
  the deep 10pm to 6am sleep keeps its double density.

- **🛹 He ollies.** The big floating one, straight off the sticker. He pops,
  the nose kicks up, and he hangs there with his balance arms riding the
  float and the board glued to his feet. Nothing spins. The tilt is the whole
  trick, and he shouts after landing it like every other skate beat. That
  makes ten idle moves and eighteen props.

### Fixed

- **🍤 An honest accounting of the sleeping snack.** The click-a-sleeping-crab
  shrimp easter egg never worked. Not once, from the day it shipped: the
  click's own wake-up stir changed his mood before the sleeping check could
  run. The rude awakening owns that click now, and the shrimp found a new
  home on the double-poke (see above).

- **🦀 The menu bar crab is visible again.** Three separate bugs were hiding
  him. The icon was drawn at 12×7.5 points, smaller than a period; it now
  stands at a proper size, with a test that refuses specks. A stale
  remembered position could strand the icon in a dead stretch of the bar; the
  position is now forgotten on every launch. And the app's old bundle
  identifier turned out to be cursed on macOS 26. The window server refused
  to place any status item created under it, verified with minimal probe apps
  across reboots. The app now ships as `com.internetdialup.clawd`. Your
  settings are untouched because the preferences file keeps its old name. If
  "Open at login" was on, flip it once more.

## [1.6.0] — 2026-08-30

### Added

- **👋 He introduces himself, once.** The first time he ever appears on a
  desktop he hops, waves, and says who he is. First pet only. A second one you
  summoned on purpose has nothing to introduce.
- **🛹 He skates.** A kickflip, a varial flip, and a cruise where he holds his
  line while the ground streaks past underneath. He squints through the pop,
  opens his eyes for the rotation, and shouts when he lands one.
- **💤 He talks in his sleep, and keeps a tally of it.** He always had lines
  for sleeping; the app just never showed them. Now he mutters through about
  one nap cycle in four without stirring, and some of those are fun facts.
  Each fact bumps a 🐑 count in the session roster, hidden until it's off
  zero. The zZz's come twice as often between 10pm and 6am.
- **🧠 He knows seventy-six things, and says them while he waits.** Fun facts
  across computer science, CS 101, Claude, AI, prompt engineering and vibe
  coding, plus sixteen tips about the tool you're holding. Every line was
  checked against the installed build instead of the docs, which caught six
  wrong ones. Two were commands the live documentation still lists and no
  build actually has. Facts show up during work too, in beats his own chatter
  had already decided to spend in silence.
- **⚡ Every costume gets a movement of its own.** Only the ninja's ribbons and
  the Matrix rain moved before; the other seven were paint. Now Frankenstein
  throws sparks at his bolts. Snow falls on Arctic White. A light sweeps
  across Retro Black, a tail swishes on Tiger, a column scans on Gundam,
  speed lines flank Sonic, a marquee chases on Arcade, and a shuriken spins
  across the ninja's airspace and is gone. None of them can cover an open eye.
- **🧟 Two more costumes, and two more props.** Frankenstein is green with a
  stitch line and two iron bolts at the temples, since a crab has no neck to
  put them on. Arcade is a cabinet: black shell, phosphor eyes and mouth lit
  from inside, a two-colour marquee below. The joystick joins the working
  props, and the shades became their own prop instead of a recolour of the
  reading glasses.
- **☀️ Light catches him, and sometimes he stands in it.** A diagonal glint
  crosses his shell every couple of idle minutes. It repaints only shell, so
  it never touches a costume or his face. In daylight, roughly every
  twenty-eight minutes, a pool of light lands on the floor and he shuts his
  eyes and stands in it for fourteen seconds. One envelope drives the pool,
  the gold on his shell, and his eyes easing closed, so it reads as one
  moment.
- **🟡 Gold breathes around him while a plan waits on you.** A soft ring
  swells for 2.6 seconds every eighteen. It doesn't start right away: he
  leans, bobs and holds the plan out on his own first, and the light only
  joins if that didn't get your attention. It gives up after three minutes of
  being ignored.
- **🧭 A second pet you can actually park.** Drag one crab near the other and
  it eases into one of six spots around him. The pull grows as you get
  closer, no snapping when you let go. None of the distances are typed in:
  each is the closest the two can stand with both speech bubbles still clear.
- **🎬 The secret menu can show you the rare things.** Shift+click and press
  K, and the menu now has an Effects section beside the moods. Each one
  bypasses the clock and the dice that normally gate it. That matters because
  some effects were unreachable on demand: you can't wait out a patch of sun
  at one in the morning.

### Changed

- **⏰ He stays up for fifteen minutes after the last thing that interested
  him.** Close your last session and he used to be asleep within two seconds,
  and nothing you did would reset it. Poking a sleeping crab woke him for a
  second, then straight back to snoring. A poke, a hold, a drag, or resting
  the pointer on him now all buy the same fifteen minutes. His sleeping
  breath got fixed too: two pixels of movement, eased, over five seconds.
- **🤹 He is still most of the time now.** A flourish used to fire every seven
  seconds, forever, like a metronome. Nothing decided whether one played,
  only which. Now about seven cycles in ten fire and the gaps go irregular.
  The near-done glow got the same treatment: it was 240 consecutive pulses
  across a ten-minute sprint, and is now one 2.2-second breath every forty
  seconds or so.
- **💞 Petting reads as affection now.** Held down, he used to produce a heart
  every 0.8 seconds forever. Thirty-eight hearts in a half-minute is a
  fountain, not a feeling. Now two hearts greet the purr, then one every four
  seconds. And letting go no longer deletes the hearts still climbing; they
  finish on their own clock.
- **☕ The things you could not name got redrawn.** The balloon read as a
  lollipop and meant nothing, so it's a mug now, and it means he's been idle
  a while. The hard hat's wrench and screwdriver looked like two grey rods,
  so he carries a single hammer instead. All props are drawn in inks a
  costume can't repaint, which is why the mug stays white on the ninja. The
  ninja's own shell went near-black; the old grey read as "standing in
  shadow".
- **🔋 A pet nobody is looking at stops drawing.** He used to tick at full
  rate with the display asleep. Now he drops to one frame a second whenever
  nobody can see him, and that beats every other rate rule. It only changes
  how often he draws, never what he looks like.
- **📦 Getting him onto a current Mac.** The headline install step used to be
  right-click → Open, which macOS 15 removed. So anyone on Sequoia was
  following an instruction that no longer exists. The `xattr -dr
  com.apple.quarantine` command leads now, with System Settings → Privacy &
  Security as the UI route. The right-click shortcut is still listed, marked
  as macOS 14 only. The install section now states macOS 14+ on Apple
  silicon, no Intel build. LICENSE went back to plain MIT so GitHub stops
  reporting "Other", and the trademark note moved to NOTICE.md unchanged.

### Fixed

- **🎲 The same line stops coming round twice in a row.** His lines are dealt
  like a deck of cards, but that only works if the deck advances one card per
  draw. None of the five places that asked him for a line did that. Measured
  on the shipped code: one idle line in ten was an immediate repeat, and one
  working burst in three. Bursts also rewrote themselves mid-read every
  fourteen seconds. All fixed.
- **🏷️ A joke stops talking over the thing you were actually doing.** Thirteen
  patterns could replace a session's label with a themed line, and seven of
  them matched the wrong things. "Make the header prettier" and "Add a user
  profile page" both got claimed by unrelated rules, while "builds" was
  missed entirely. A false match doesn't just mistime a joke. It deletes the
  one string on screen that said what was happening.
- **🐾 Two pets stop swallowing each other's drags.** His clickable area
  covers every pose he can hold: 410 cells, where the resting crab only draws
  264. Alone, that generosity costs nothing. Next to a sibling, a press meant
  for the other pet could land in this one's invisible halo and go nowhere.
  In company he now answers to exactly the cells he draws.
- **💬 The bubble stops taking the tail off a 29-character line.** The length
  ceiling was computed with the wrong character width. A ruler rendered
  through the actual bubble says 28 characters fit and 29 clip. "I'm hungry
  for something new!" is exactly 29, and it had been losing its exclamation
  mark for as long as the guard existed.
- **🔭 His eyes stop teleporting when the telescope comes out.** The stargazer
  snapped his gaze upward the moment its envelope crossed a threshold, and
  that snap landed inside his ordinary glance window 81 times out of 244
  across a simulated day. The look now eases along the envelope, so one
  two-pixel jump becomes two one-pixel steps.
- **🔏 Building him yourself no longer hands you a quietly unsigned app.**
  When signing failed, `run.sh` used to carry on, launch the app and print
  "Running". An unsigned Claw'd works fine right up until Open at Login or a
  notification needs a stable identity. The culprit is this repo living in
  iCloud Drive, which re-stamps the file attributes codesign rejects moments
  after they're cleared. Clearing, signing and verifying are now one retried
  unit, and the script exits non-zero when the signature isn't real.

## [1.5.1] — 2026-08-24

### Fixed

- **🔌 He notices the sessions you start while he's running.** The big one. He
  watches each session's transcript, but Claude Code writes the session's
  registry entry a second or two *before* that transcript exists. So he reached
  for a file that wasn't there yet, gave up, and never tried again. Every
  session you started while he was already on the desktop stayed invisible for
  its whole life. No title, no tool, no mood, just idle. Relaunching him
  "fixed" it only because by then the file existed. He now waits for it.
- **📋 The near-done glow and the cooking card work again.** The same bug
  wearing a different hat. Your todo folder is created by the first TodoWrite,
  so he watched the folder *above* it. That watch tells him the folder was
  created, and then nothing ever again. He heard about your todos exactly once
  per session, while the list was still empty. That quietly took the 80% glow
  and the quarter-crossing milestones with it.
- **🖱️ Double-clicks and repeat parties stop cutting themselves short.** Poking
  him twice queued two timers. The first one ended the second poke's reaction
  two-thirds of the way through, so every double-click finished with a visible
  jolt. A second triple-poke party died the same way, mid-rainbow.
- **🎬 Green-screen plates line up with the titled cuts again.** Hiding the
  titles was supposed to make them invisible. It actually removed them from the
  layout, so the plate's Claw'd sat ten rows higher than the master's. Keyed
  footage would have drifted against its own titles.
- **🟩 The vertical reel's pixels are square again.** At the 9:16 resting size,
  every fourth column of him was an eighth wider than its neighbours. That's on
  a character whose whole look is square pixels, in the shot the vertical
  camera holds most of the time.
- **🏗️ It builds on a stock toolchain again.** The newer Swift resolves an
  expression the older one rejects. That expression had been failing every
  automated build since 1.5.0 went out.

### Changed

- **👀 He bobs like he means the question.** The two states where he's waiting
  on *you* were the easiest to miss. A plan awaiting your verdict moved a
  single pixel every three and a half seconds, and the urgent one didn't bounce
  at all, it flickered. Both now travel further and land on every pixel on the
  way, so a question reads from across the room.

## [1.5.0] — 2026-08-21

### Added

- **🔊 An 8-bit soundboard.** He speaks now. A cute rising squeal when you poke
  him (three pokes climb into the party), a squeak-squeak on the bug catch, and
  a low purr when petting begins. A sparkle run on costume changes, a fwoosh
  when a cook ignites, and a proper chiptune fanfare when an epic lands. The
  done bell stands down for the fanfare. The attention chirp and done chime got
  8-bit voices too. There's also an optional per-service blip (C-E-G-B for npm,
  GitHub, Linear, deploys) behind "Service sound blips" in the menu. Every
  sound is synthesised in memory, so still zero binary assets. Everything
  hushes during films, and that hush is now enforced in one place.
- **⭐ A star for the thinking spell.** During long thinking stretches, the
  sparkles now trade shifts with an 8-bit Claude star. It's a nine-cell
  sunburst in flame and gold, the same mark the reel's sting wears.
- **🌈 The rainbow, hammered home.** The triple-poke party throws real confetti
  now, six flecks tumbling through the trapezoid. The rainbow drags a chromatic
  afterimage behind him as he moves. And the epic bow fires a flat eight-ray
  sweep behind the glow. Mix and match, all three.
- **🎈 A balloon worth waiting for.** On a long idle, once in a while, he
  floats a balloon for a few seconds. It's rare on purpose. It never shows in
  the first stretch, so a fresh launch stays calm.

### Changed

- **🦀 The menu bar gets the actual crab.** The icon was a freehand drawing: an
  oval body, two stick eye-stalks, two oval claws. It shared nothing with the
  character on your desktop. It's drawn from the real sprite now, cropped so he
  fills the bar, with his eyes and smile punched through the shell the way a
  stencil reads a face.
- **👆 The roster admits it is clickable.** The session rows gave no feedback
  at all. Nothing lit under the pointer and nothing moved when you pressed, so
  a list of sessions you can pin read as a list of labels. Rows now light on
  hover and answer on press. The "Unpin" line got the same treatment.
- **🖱️ He only takes the clicks that are his.** The mouse used to treat his
  whole 32×32 square as him. So the empty sky over his head, the floor under
  his feet, the window's corners and the gaps between his legs all swallowed
  clicks meant for whatever was behind him. Those clicks opened the roster on
  the way, too. Now the click zone is his actual silhouette, widened just
  enough to cover the bob he does while breathing. Everything else passes
  straight through to the app underneath. Hovering and petting tightened with
  it: he stirs when the pointer is actually touching him, and his airspace no
  longer counts. The stomach is still the only drag handle, and the floor bug
  is still pounceable while it's out.
- **🟩 The Matrix goes full terminal.** The code used to be six one-pixel
  columns dripping at a single speed, drawn under his face, so his eyes erased
  chunks of it. Now it falls down his whole shell. Every column has its own
  speed and streak length, running through a bright head, a phosphor body and a
  dim tail, with varying-width code-lines scrolling underneath. The shell is
  darker so the code carries. His eyes are brighter than any of it, so he keeps
  his face.
- **💬 He speaks in bursts instead of wearing a banner.** The thought bubble
  used to sit on his head the entire time he was working or cooking, its text
  merely swapping every fourteen seconds. Now a new task or tool shows
  immediately and holds. Then he goes quiet and checks back in every
  half-minute or so. Alerts and plan-nudges are never silenced. They pulse,
  because being blocked on you is the one thing worth interrupting for. The
  menu-bar tooltip always shows the live task, even while he's quiet.
- **⚡ The white flash became a flashbang.** It used to be a peach wash held
  across the whole ten-second celebration. It only reached 40% of the way to
  white, and it only touched his shell, so his eyes stayed black and a dark
  costume never lit at all. Now the whole sprite blanches to pure white: eyes,
  costume and heat bands together. Two hard hits land inside the first second.
  Bang, a beat of honest terracotta, then the secondary. Light spills off him,
  and on an epic the burst rings brighten on each hit. The other nine seconds
  stay calm, and that's what makes the hits land. It honors the system Reduce
  Motion setting: he still celebrates with pose, hops and colour, just without
  the strobe.
- **🐯 The tiger goes orange.** Jungle Tiger trades green for actual tiger
  colours: orange coat, dark stripes, a cream belly patch, a darker mouth.
- **💥📟 Bang and phone, redrawn.** The alert bang wears an ember outline with
  a paper highlight, and it hops phase. The phone lights its screen and shows
  the alert dot, so the prop reads at a glance.
- **🗝️ The preview goes secret.** "Preview animation" left the menu bar. It
  was an art-review tool wearing a public hat. Shift+click the pet, then press
  K within three seconds. The animation-testing menu opens at the pet, and Live
  hands control back to the live feed. Any other key, or just waiting, closes
  the gate quietly.

## [1.4.0] — 2026-08-12

### Added

- **👘 A wardrobe.** Seven costumes: Ninja, Retro Black, Matrix, Jungle Tiger,
  Arctic White, Gundam, Sonic. Pick one from the new menubar Costume submenu
  and he remembers it between launches. Costumes survive every mood and every
  prop, and status effects always paint over them. The ninja trades the shell
  for shadow with a terracotta eye window, because a mask may frame the eyes
  but never cover them. The Matrix shell rains live green code down his back.
  The Gundam brings the RX-78 head home: V-fin, red crest, yellow cameras in a
  black visor recess, blue armor down the flanks. And the Sonic goes fast, with
  a blue shell, back-swept quills, a tan muzzle, and red sneakers over white
  socks.
- **🔥 Fire that heats the shell.** During a hard cook, a banded heat cascade
  sometimes sweeps up his body. Once the todo list passes 80%, a soft white
  pulse says the sprint is almost home. And a cooking sprint that lands plays a
  ~10-second payoff in the done state: flash train, scale breathing, the hop
  re-armed twice, then it cools back down. Rarely, mid-cook, a five-second
  disco finds him. He keeps working through it.
- **🏆 The epic finale.** A cook that runs a full minute and lands earns the
  bigger payoff. The white flash, a warm glow blooming behind him under three
  expanding 8-bit rings, his whole body growing a fifth and settling back, and
  a rainbow sweeping the shell. All of it fits inside the same ten-second bow,
  easing back to a plain done before it fades. Short cooks keep the ordinary
  celebration.
- **🔖 Service glyphs.** He name-checks the service he's talking to. An 8-bit
  npm cube while npm/yarn/pnpm/bun run, a GitHub mark while a push or PR is in
  flight, a Linear diamond during Linear tool calls, and a deploy rocket for
  vercel/docker/fly. Each one floats beside him AND badges his thought bubble,
  easing in with the work and lingering a few seconds past it. The pixel marks
  are original, evocative without copying anyone. Recognition rides the real
  shell command, so a polite tool description can't fake it.
- **📊 The cooking card.** With notifications on, a cook starting posts a macOS
  banner. Each quarter of the todo list crossed updates it in place, silently
  and with no re-chime: `▓▓▓▓░░░░ 50%`. The done chime retires the card, so a
  stale bar never sits under it.
- **⬛ Ground under his feet.** A soft 8-bit shadow block sits at his footline,
  15% black and one and a half cells tall. He stands on the desk now, no more
  floating over it.
- **🥚 Four secrets.** A floor bug worth clicking, press-and-hold petting with
  rising hearts, a shrimp snack for whoever pokes a sleeping crab, and a
  telescope that only comes out in the small hours.
- **✨ Attention, eased.** The bubble sweeps an occasional light band, and it
  pulses a slow check when a plan awaits your verdict.
- **🦀🦀 A second pet.** Summon him from the menu ("Second pet") and a second
  Claw'd joins the desk. He follows the busiest session the first isn't
  showing, or any session you pin him to. He wears his own costume and
  remembers his own spot. He also gets everything the first has: petting, eggs,
  the badge, the film step-aside. Two windows, one app. Never two processes,
  which would fight over the event feed. He parks beside his sibling, never
  under him, and dock-corner snaps de-stack. Maximum two.
- **📌 Persistency.** A new menu toggle for how present he is. On (the default,
  and the classic posture), he floats above every window, still stepping aside
  for video. Off, he lives at normal window level. Opening Finder or a browser
  covers him, and nothing ever shuffles him forward. You see him again when the
  windows move off.
- **🎬 He steps aside for films.** Fullscreen video on his display fades him
  out. Netflix, YouTube, whatever holds the screen awake. The credits (or your
  escape key) bring him back. It's deliberately film-only: a window has to
  cover the display AND that same app has to be keeping the display awake. So a
  fullscreen editor or a slide deck never scares him off. Sound cues hush
  during films too. It's on by default, and "Step aside for video" in the menu
  turns it off. Showing him mid-film keeps him up for the rest of it.
- **✅ The quiet done.** A finished task no longer leaves a lingering banner.
  The done pose plays its moment, then hands the signal to a small 8-bit
  checkbox parked beside his feet, bottom edge on his footline. It stays until
  new work consumes it. No clock ever clears it. Every three minutes it takes
  one soft golden breath to catch your eye. He stands in front of it when he
  leans over it. Completions older than half an hour don't resurrect on launch.
  Recent ones greet you back.

### Changed

- **He's grabbed by the stomach.** The mouse knows exactly where he is: his
  sprite and nothing more. No invisible margin, no grabbable bubble. Only the
  torso moves him. Claws, legs and crown still poke, pet and pounce. With two
  pets parked side by side, that's what keeps each one individually grabbable.
  And a poke never yanks him to the dock edge anymore.
- **Idle chatter goes intermittent.** For the first minute and a half of quiet,
  he keeps you company as always. Past that, roughly one cycle in three shows a
  line and the rest are calm. The status ticker keeps its share of the cycles
  that do show.
- **Nothing snaps anymore.** Mood changes cross-ease from the pose that was
  actually on screen. The hover greeting decays from wherever it had reached,
  and no longer vanishes. The 20-second prop re-roll puts one prop down and
  picks the next up through a pixel dissolve. The working arms are eased
  squares now, no more square waves. The exemptions are single-pixel steps and
  blinks, which snap in nature.
- **The console is in his claws.** The little code window sits in front of him
  like a held laptop, claw tips gripping the lid and eyes peering over it. It
  tracks his bob now. It used to hang painted on the sky.

### Fixed

- **One pet, ever.** Launching the app while a copy is already running now
  quits the old copy, so he never doubles. The build you just launched is the
  one you meant.
- **Crash hardening, from the fork's crash hunt.** A launch or display unplug
  with no screen attached no longer aborts. The pet defers placement and
  settles the debt when a display arrives. "Install Claude hooks…" works on
  machines that didn't compile the app, because resources resolve relative to
  the app, and two release checks now prove it. A clock that briefly runs
  backwards can no longer kill him mid-flame. Building from source and running
  the bare binary reaches the desktop, where it used to abort on the
  notification centre. And `--probe nan`/`inf` run the default now. They used
  to probe nothing, or forever.
- **First click grabs him.** A press while another app was frontmost was
  swallowed as an activation click, so dragging him needed a second try.
- **The bubble tail is no longer eaten by the sprite** in the overlap band. The
  live view gets the fix the reel renderer already had.

## [1.3.0] — 2026-08-08

### Added

- **🌊 A backdrop, and the features that had never been pictured.** Eleven new
  assets: the six idle flourishes (only one had ever been rendered on its own),
  the triple-poke party, the session roster, one bubble per state, and every
  prop in a strip. The README described all of them in text and showed none of
  them.
- **`--render-reel`** renders composed scenes entirely from code: the hero, the
  roster, the bubbles and the props.
- **`--render-social`** renders the same 15 seconds in **two aspects**, plus a
  cover still: 9:16 at 1080×1920 for Reels and 16:9 at 1920×1080 for Threads.
  It's video because neither platform takes a GIF. At those sizes a GIF would
  be enormous and stuck at 256 colours anyway. Encoding is AVFoundation, which
  ships with macOS, so `Package.swift` keeps its empty dependency array. Both
  cuts share one clock and one beat list, so their timing cannot drift.
  It also writes **clean plates** in both aspects: the pet on the backdrop with
  no wordmark, tagline or URL. The `clean` variant keeps the speech bubble and
  the `bare` variant drops it. Titles belong in the edit, so none get baked
  into the footage.

### Changed

- **The hero is rendered offline now.** It was the one committed asset that was
  a screen capture. That quietly falsified the promise that a diff in the media
  folder means the animation changed. It now renders from the demo script,
  which makes it reproducible and structurally unable to capture a stray
  notification the way the old one did. It also shrank from 432 KB to 237 KB.
- The backdrop is **derived** from a wallpaper's hue and saturation. No pixels
  are copied from it. It's also deliberately much darker, because the sampled
  mid-tones sat within 1.02:1 of Claw'd's body colour and would have shimmered.
- **Sleep threshold 300s → 900s.** Measured over the local corpus, the median
  park between a finished turn and the next human prompt is 180s. **40% of
  ordinary parks exceed 300s**, so a 5-minute nap fired during two-fifths of
  normal think-breaks. At 900s only 19% are longer, and those are real
  walk-aways. (This changes no shipped behaviour, since the old threshold could
  never fire either.)
- **`--probe` takes an optional duration**, e.g. `--probe 320`. The default 3s
  is shorter than every decay horizon, so it could not observe one.

### Fixed

- **🐛 The pet no longer hangs on a finished task.**
  ([#2](https://github.com/internetdialup/claude-pet/issues/2), reported by
  TokyoSoyMRX.) Commit something, leave the tab open, and Claw'd would keep
  narrating the work forever. He never settled to idle and never slept. The
  bubble froze on whatever it last saw.

  Two independent causes. The pet's own workload poll ran every 2 seconds and
  emitted an event for **every** live session, whether or not anything had
  changed. The reducer advanced `lastActivity` on every event kind. So
  `now - lastActivity` never exceeded 2 seconds, and every time-based threshold
  was arithmetically unreachable. That includes the 6-second `done → idle`
  decay, which means **it had never once fired in a shipped build**. It also
  includes the 300-second sleep threshold, which is why he never slept while a
  session was open. Underneath that, `.thinking` and `.working` had no decay
  path at all.

  The poll no longer counts as session activity. The per-session decay now
  covers every mood that can strand, where before it covered `.done` alone.
  Decay clears the tool, the task text and any pending approval alongside the
  mood. Leaving any one of them set kept the words on screen after the pose
  relaxed.

- **A session title no longer masquerades as a live task.** The idle branch was
  gated on "no task", and a title counts as a task. So any *named* session
  (most of them) froze on its own title and never reached the status ticker.

- **The bubble truncates at 29 characters.** The docs and the test both said
  46. The real cap is 210pt over a 6.62pt advance, which is 29. Five shipped
  lines are longer and got cut off on screen, including the one in the README
  hero. That's why it read *"Let's build something aweso…"*. The limit is
  corrected and enforced. The five long lines are named, and left as they were.
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
