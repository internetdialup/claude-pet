import AppKit
import SwiftUI

/// One pet on the desktop: his model, his window, his input wiring, his
/// visibility latches, and his own film watch. Everything that must exist
/// twice when a second pet is summoned lives here; everything genuinely
/// global — the coordinator, the menu bar, the roster popover, alerts, the
/// demo — stays in `AppDelegate`.
///
/// Instances are PERSISTENT across window rebuilds: a pixel-size change calls
/// `rebuildWindow()`, never replaces the instance — replacing it would reset
/// the film detector (≈10s of re-agreement, flashing the pet over a live
/// film) and lose the visibility latches.
@MainActor
final class PetInstance {
    /// 0 is the original pet; 1 the summoned second. Drives pref keys and
    /// state-slot selection.
    let slot: Int

    let model = PetViewModel()
    private(set) var controller: PetWindowController?

    /// Opens the global roster anchored to this pet's window.
    var onRosterRequested: (() -> Void)?
    /// Opens the secret animation-testing menu anchored to this pet's window.
    /// Summoned by Shift+click, then K — see `SecretMenuGate`.
    var onSecretMenuRequested: (() -> Void)?
    /// The operator did something deliberate to him. The app forwards it to the
    /// coordinator, which is the only thing that owns the wake window.
    ///
    /// A closure rather than a coordinator reference, on purpose — everything
    /// genuinely global stays in `AppDelegate` (see this class's own doc), and
    /// handing a per-pet object the global reducer is how a second pet
    /// eventually calls `setSlots`.
    var onStir: (() -> Void)?

    /// How long a pointer must rest on him before it counts as attention.
    ///
    /// A pointer crossing him on its way to the Dock must not buy fifteen
    /// minutes. Long enough to exclude a transit, short enough that "he
    /// noticed you" still feels causal.
    static let hoverStirDwell: TimeInterval = 1.2

    /// How long the rude wake holds the coordinator's stir back — exactly
    /// `rudeWakeArmRise + rudeWakeHold`, so the mood flips (and the zzz's cut)
    /// at the instant phase C begins: he stretches and glares from inside the
    /// sleeping pose, and only then gets up. The 0.4s mood crossfade and the
    /// envelope's 0.5s release land together.
    static let rudeWakeStirDelay: TimeInterval = 1.2

    /// A poke train: consecutive clicks with gaps at most this far apart.
    /// ONE constant serves double duty as the roster's settle delay, and the
    /// two must never diverge: the roster opens exactly when a train has
    /// provably ended, so by construction no counted poke can ever meet an
    /// open popover — whose transient dismissal monitor EATS the click, which
    /// is half of why the triple-poke party "never fired". (The other half:
    /// `NSEvent.clickCount` only accumulates inside the OS double-click
    /// interval, and a human poking deliberately at ~0.6s gaps reads as
    /// 1, 1, 1.) 0.75s sits above the deliberate cadence and below feeling
    /// broken — the squash and squeal still answer every press instantly;
    /// only the panel waits for the beat after.
    nonisolated static let pokeGap: TimeInterval = 0.75

    /// How many pokes the train ending at `now` contains, counting `now`.
    /// `times` are the previous poke instants, ascending; a gap wider than
    /// `gap` anywhere breaks the train. Pure, so the party's arithmetic is
    /// testable without a window — the `hoverCountsAsStir` pattern.
    nonisolated static func pokeVerdict(times: [Date], now: Date,
                                        gap: TimeInterval = pokeGap) -> Int {
        var count = 1
        var edge = now
        for time in times.reversed() {
            guard edge.timeIntervalSince(time) <= gap, time <= edge else { break }
            count += 1
            edge = time
        }
        return count
    }

    /// What an awake, non-shift, non-bug click does — the poke ladder:
    /// one poke opens the roster (after the settle beat), two feeds him,
    /// three throws the party. Double-poke rather than dice for the snack,
    /// per the house's own doctrine: dice are for the things that happen TO
    /// you; feeding him is something you DO, and a deliberate snack attempt
    /// answered by a roster panel would punish the one interaction sought.
    enum ClickAction: Equatable { case party, snack, pokeThenRoster }
    nonisolated static func clickAction(verdict: Int, mood: PetMood,
                                        onBody: Bool, snackBusy: Bool) -> ClickAction {
        if verdict >= 3 { return .party }
        if verdict == 2, mood == .idle, onBody, !snackBusy { return .snack }
        return .pokeThenRoster
    }

    /// Whether a hover that started at `startedAt` still counts as attention
    /// when its dwell timer fires at `queuedFor`.
    ///
    /// Both halves are load-bearing, and the second is easy to miss:
    /// `hoverStartedAt` deliberately SURVIVES the release so the greeting can
    /// ease out from where it was, and only clears 0.6s later. So a pointer
    /// that crossed him in 0.3s still carries the same stamp when the 1.2s
    /// timer fires — without the `endedAt == nil` half, every transit across
    /// him would buy a wake window, which is the exact thing the dwell exists
    /// to prevent.
    ///
    /// Pure and static so the policy is testable without a timer, the way
    /// `idleChatterShows` and `bubbleBurst` already are.
    nonisolated static func hoverCountsAsStir(startedAt: Date?, endedAt: Date?,
                                              queuedFor: Date) -> Bool {
        startedAt == queuedFor && endedAt == nil
    }
    /// The other pet's window frame, for snap de-stacking. Wired by the app,
    /// which is the only thing that knows about siblings.
    var siblingFrame: (() -> CGRect?)?

    /// Whether another pet is on the desk.
    ///
    /// The only thing that decides how generous his clickable silhouette is
    /// allowed to be. Alone, he accepts the union of every pose he can hold, so
    /// a poke lands even mid-bounce and the spare cells cost nothing but
    /// desktop. In company that same band sits over his neighbour and swallows
    /// presses meant for him — see `CrabHitMask.resting`.
    ///
    /// Set by the app, which is the only thing that knows about siblings, and
    /// applied live: pet one must not have to be rebuilt because pet two
    /// arrived.
    var hasCompany = false {
        didSet {
            guard hasCompany != oldValue else { return }
            controller?.updateHitMask(CrabHitMask.mask(sharingDesk: hasCompany))
        }
    }

    /// The Shift+click-then-K state, plus the timer that hands borrowed key
    /// focus back when the operator arms the gate and then wanders off.
    private var secretGate = SecretMenuGate()
    /// This pet's draw counter for the bug-pounce line. See `LineCursor`.
    private var bugCursor = LineCursor()
    /// …and for the line he shouts after a skate beat.
    private var skateCursor = LineCursor()
    /// …and for the one introduction a fresh install ever gets.
    private var helloCursor = LineCursor()
    /// How long a skate line stays up. Exposed so the suite can check the
    /// longest line finishes scrolling inside it rather than restating 3.4.
    ///
    /// `nonisolated` for the reason `chatterInterval` and `plainColumns` are:
    /// it is a constant, not state, and the suite reads it from a synchronous
    /// nonisolated test. This class is `@MainActor`, so without the keyword the
    /// constant inherits an isolation it has no use for.
    nonisolated static let skateLineSeconds: TimeInterval = 3.4
    /// Cancels a scheduled skate line that the mood outran. A generation
    /// counter rather than a `Timer` handle, matching `fadeSeq`: the timer
    /// still fires, it just finds itself stale and does nothing.
    private var skateSeq = 0
    private var surfCursor = LineCursor()
    private var surfSeq = 0
    /// Longer than the skate window: three of the operator's surf lines are
    /// wider than the plain bubble, so they route to the marquee and have to
    /// finish SCROLLING, not merely appear. `surfLinesFitTheirWindow` pins
    /// that this is long enough for the longest of them.
    nonisolated static let surfLineSeconds: TimeInterval = 4.6
    /// The same generation trick for the hello, which schedules twice: once to
    /// begin after the window has settled, and once to clear itself afterwards.
    private var helloSeq = 0
    /// The poke train's memory — recent click instants, pruned to the last
    /// six. `pokeVerdict` reads it so three DELIBERATE pokes count even when
    /// the OS click counter reads them as three singles.
    private var pokeTimes: [Date] = []
    /// Every press bumps this, cancelling any pending roster open — a multi-
    /// poke never flashes the panel. The generation pattern, like `skateSeq`.
    private var rosterSeq = 0
    /// This pet's draw counter for the long-pet thank-you line.
    private var petCursor = LineCursor()

    /// How long after launch he waves.
    ///
    /// Not zero. The window is still arriving at t=0 — it fades in, and on a
    /// cold launch the whole app is still assembling — so a greeting fired
    /// immediately is one the person has not looked at yet. A beat of stillness
    /// first is what makes it read as him noticing you rather than as a loading
    /// animation.
    nonisolated static let helloDelay: TimeInterval = 1.2
    /// How long the wave holds before easing out. `Ease.amount` adds its own
    /// release on top, so he is in motion for a little longer than this.
    nonisolated static let helloWaveSeconds: TimeInterval = 2.0
    /// How long his introduction stays readable — longer than the wave on
    /// purpose, so the line can still be read once he has settled.
    nonisolated static let helloLineSeconds: TimeInterval = 3.6
    private var secretDisarmTimer: Timer?

    // MARK: - Visibility policy
    //
    // The three facts policy is decided from. `isVisible` is never read for
    // policy — a window faded out by the film watch reads as hidden, and one
    // menu click would then both surface him and corrupt the bookkeeping.

    private(set) var petHiddenByUser = false
    private var steppedAside = false
    /// The operator brought him back mid-film: an answer to THIS film,
    /// cleared when it ends.
    private var filmOverride = false
    /// The watch's current belief, cached because preference toggles need the
    /// answer now, not the next change.
    private(set) var filmPlaying = false
    private var filmWatch: FilmWatch?
    private var screenObserver: NSObjectProtocol?
    /// Display-sleep and window-occlusion watches. Nothing observed either
    /// before, so the timeline ticked at full rate with the screen off — the
    /// same waste `CrabView`'s frame-rate doc was written about, just from a
    /// direction nobody had checked.
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var displayAsleep = false
    private var windowCovered = false

    init(slot: Int) {
        self.slot = slot
    }

    /// Stops the watch and releases the window — a dismissed second pet must
    /// leave nothing ticking. The screen-parameters observer token is stored
    /// precisely so this can remove it.
    func teardown() {
        secretDisarmTimer?.invalidate()
        secretDisarmTimer = nil
        filmWatch?.stop()
        filmWatch = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        if let sleepObserver { workspace.removeObserver(sleepObserver) }
        if let wakeObserver { workspace.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
        controller?.close()
        controller = nil
    }

    // MARK: - Window

    /// Builds (or rebuilds, after a size change) the floating window. The
    /// window is recreated rather than resized because its size, content and
    /// click-through region all derive from `pixelSize`; the instance and its
    /// latches survive the swap.
    func rebuildWindow() {
        // Close, not just hide. `hide()` only orders the window out; the old
        // NSWindow and its SwiftUI host stayed alive and kept ticking their
        // TimelineView, so every size change added another animating ghost.
        controller?.close()

        let pixelSize = Preferences.shared.pixelSize
        let size = PetRootView.windowSize(pixelSize: pixelSize)
        // Only HE accepts clicks — his silhouette, not the square he is drawn
        // in. Everything else in the window is transparent and click-through,
        // so the desktop and whatever app is under him keep their own mouse.
        // Narrower once he has company: his halo would otherwise sit over the
        // other pet and eat presses meant for that pet's drag handle.
        let region = PetHitRegion(pixelSize: pixelSize,
                                  mask: CrabHitMask.mask(sharingDesk: hasCompany))

        let slot = self.slot
        let controller = PetWindowController(
            contentSize: size,
            hitRegion: region,
            // The torso is the drag handle; the rest of him pokes, pets and
            // pounces. Both rects come from the same pixelSize in the same
            // call, so they can never go stale against each other.
            dragRect: PetRootView.torsoFrame(pixelSize: pixelSize),
            rootView: PetRootView(model: model, pixelSize: pixelSize),
            loadPosition: { slot == 0 ? Preferences.shared.position : Preferences.shared.pet2Position },
            storePosition: { origin in
                if slot == 0 { Preferences.shared.position = origin }
                else { Preferences.shared.pet2Position = origin }
            },
            // A summoned second pet must not park exactly under the first and
            // look like a no-op: his default home sits one window further
            // along the dock edge.
            parkOffset: slot == 0 ? 0 : size.width + DockMagnet.gutter
        )
        controller.avoidingFrame = { [weak self] in self?.siblingFrame?() }
        // The bug stands on cells the silhouette calls empty, so it publishes
        // its own clickable box while it is out. Consulted only when the mask
        // has already missed, i.e. on clicks that were about to pass through.
        controller.liveZones = { [weak self] in
            guard let zone = self?.currentBugZone() else { return [] }
            return [zone]
        }
        wire(controller)
        controller.setPersistent(Preferences.shared.persistent)
        self.controller = controller
        if steppedAside {
            // A rebuild mid-film (or mid-fade) must not flash a full-alpha
            // pet over it; the eventual fade-in rises from here.
            controller.prepareSteppedAside()
        } else if !petHiddenByUser {
            controller.show()
        }
    }

    private func wire(_ controller: PetWindowController) {
        controller.onClick = { [weak self] clicks, location in
            guard let self else { return }
            // 🗝️ Shift+click is the arming half of the secret handshake, not
            // a poke: the window borrows key focus (the roster's dance) and
            // listens for a lone K. Modifier state is polled because it is
            // the one keyboard fact a focusless window can always read.
            // Checked before ANY stir so the handshake works on a sleeper too.
            if NSEvent.modifierFlags.contains(.shift) {
                self.onStir?()
                self.armSecretMenu()
                return
            }

            // 🌙 A click on a sleeping crab is a RUDE AWAKENING, not a roster
            // request — the roster stays a menu-bar away. Checked BEFORE any
            // stir, and that ordering is the whole fix: the stir chain is
            // synchronous all the way to `model.state`, so a stir on the line
            // above this check flips the mood to idle before the question is
            // asked — which is precisely how the old sleeping-snack branch
            // spent its entire shipped life unreachable.
            //
            // The stir is DEFERRED to the end of the annoyed beat, so the
            // sleeping pose — and the zzz mid-air — survive the claw coming
            // out and the eyes opening. No squeal (silence reads as him not
            // dignifying this), no roster (the poke is the wake; the NEXT
            // click, now awake, squashes and opens it as ever). A click
            // landing during the wake is swallowed: he is already being
            // woken, and a fast triple-poke on a sleeper gets a rude wake,
            // not a party — the party needs him awake, which is right.
            if self.model.state.mood == .sleeping {
                // Pokes during the wake still COUNT: a determined triple-poker
                // gets the party the moment he is up (checked in the deferred
                // stir below). Appended before every return in this branch, or
                // that promise silently never fires.
                self.pokeTimes.append(Date())
                self.pokeTimes = Array(self.pokeTimes.suffix(6))
                guard self.model.rudeWakeStartedAt == nil else { return }
                let wokenAt = Date()
                self.model.rudeWakeStartedAt = wokenAt
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.rudeWakeStirDelay) { [weak self] in
                    guard let self, self.model.rudeWakeStartedAt == wokenAt else { return }
                    self.onStir?()
                    // Three pokes since the wake began: he is up, and the
                    // party he owes them starts on his first waking breath.
                    if self.pokeTimes.filter({ $0 >= wokenAt }).count >= 3 {
                        self.startParty()
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.rudeWakeDuration + 0.1) { [weak self] in
                    guard let self, self.model.rudeWakeStartedAt == wokenAt else { return }
                    self.model.rudeWakeStartedAt = nil
                }
                return
            }

            // Any AWAKE click is contact. The paths below all return early,
            // so stirring here is the one place that catches every one of
            // them without repetition.
            self.onStir?()

            // Every press cancels any pending roster open — a multi-poke
            // never flashes the panel — and joins the train. The verdict is
            // the FRESHER of our own train and the OS click counter: the
            // counter keeps the machine-gun fast path, the train counts the
            // deliberate ~0.6s pokes the counter reads as singles.
            self.rosterSeq &+= 1
            let now = Date()
            let verdict = max(Self.pokeVerdict(times: self.pokeTimes, now: now), clicks)
            self.pokeTimes.append(now)
            self.pokeTimes = Array(self.pokeTimes.suffix(6))

            // 🐛 A click on the visiting floor bug is a pounce, not a roster
            // request. The bug's schedule is pure, so ask it where it is —
            // through THIS pet's clock; the shared one is nobody's clock now.
            // The pending roster is already cancelled above, and pounce
            // clicks keep counting toward the train — the party check has
            // always preceded the pounce.
            if let zone = self.currentBugZone(),
               let cell = self.gridCell(for: location), zone.contains(cell) {
                SoundBank.play(.pounce)
                let pouncedAt = Date()
                self.model.pouncedAt = pouncedAt
                // A draw counter, not the wall clock: two pounces minutes
                // apart jumped the seed by hundreds, which put the deck in an
                // unrelated pass and repeated the line about one time in four.
                self.say(self.bugCursor.advance(Vocab.lines(for: .bugCaught),
                                                id: "bugCaught"),
                         or: "Bug fixed", for: 2.4, mood: .done,
                         deliberate: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    guard let self, self.model.pouncedAt == pouncedAt else { return }
                    self.model.pouncedAt = nil
                }
                return
            }

            // The poke ladder: one opens the roster, two feeds him, three
            // throws the party. 🎉🍤📋
            let onBody = self.gridCell(for: location)
                .map { CrabHitMask.body[$0.x, $0.y] } ?? false
            switch Self.clickAction(verdict: verdict, mood: self.model.state.mood,
                                    onBody: onBody,
                                    snackBusy: self.model.snackStartedAt != nil) {
            case .party:
                // 🎉🪄 The squeal tops out, the rainbow latches, and the
                // roster stays shut — a party is not a roster request. The
                // train resets so a fourth poke starts fresh instead of
                // rebasing the party mid-plateau (a rebase restarts
                // `rainbowMood` at t=0, a pose jump no-snap forbids).
                SoundBank.play(.squeal(step: 3))
                self.startParty()
                self.pokeTimes.removeAll()
                let clickedAt = Date()
                self.model.clickedAt = clickedAt
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.clickDuration + 0.1) { [weak self] in
                    guard let self, self.model.clickedAt == clickedAt else { return }
                    self.model.clickedAt = nil
                }

            case .snack:
                // 🍤 The shrimp's comeback — the branch the autopsy found
                // stillborn on the sleeping click, resurrected piece for
                // piece on the double-poke, where feeding a crab you can see
                // is a thing you DO. The body-cell gate stays for the same
                // reason it always had: mouseUp location can drift a few
                // points off him.
                SoundBank.play(.squeal(step: 2))
                let snackAt = Date()
                self.model.snackStartedAt = snackAt
                self.model.clickedAt = snackAt        // the squash still answers
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.clickDuration + 0.1) { [weak self] in
                    guard let self, self.model.clickedAt == snackAt else { return }
                    self.model.clickedAt = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) { [weak self] in
                    guard let self, self.model.snackStartedAt == snackAt else { return }
                    self.model.snackStartedAt = nil
                }

            case .pokeThenRoster:
                // Squash and squeal instantly — the click always FEELS
                // answered — then the roster opens on the settle beat, when
                // the train has provably ended. The guard chain: a newer
                // press cancels (generation), a party that latched meanwhile
                // keeps the panel shut.
                SoundBank.play(.squeal(step: min(verdict, 3)))
                let clickedAt = Date()
                self.model.clickedAt = clickedAt
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.clickDuration + 0.1) { [weak self] in
                    guard let self, self.model.clickedAt == clickedAt else { return }
                    self.model.clickedAt = nil
                }
                let seq = self.rosterSeq
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pokeGap) { [weak self] in
                    guard let self, self.rosterSeq == seq,
                          self.model.rainbowStartedAt == nil else { return }
                    self.onRosterRequested?()
                }
            }
        }
        controller.onPetStart = { [weak self] in
            guard let self else { return }
            SoundBank.play(.purr)
            // The most deliberate gesture there is. Once per hold — `onPetEnd`
            // does not re-stir, because a second stamp inside one gesture buys
            // nothing against a fifteen-minute window.
            self.onStir?()
            let start = Date()
            self.model.pettingStartedAt = start
            self.model.pettingEndedAt = nil
            // 💛 The crescendo's thank-you: ten seconds of unbroken petting
            // earns three quick hearts (pure in `heartSpawns`) and one line.
            // Stamp-guarded like every timer here — release-then-regrab arms
            // a fresh ten-second clock, and an early release fires nothing.
            DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.longPetCrescendoAt + 0.15) { [weak self] in
                guard let self, self.model.pettingStartedAt == start,
                      self.model.pettingEndedAt == nil else { return }
                SoundBank.play(.shimmer)
                self.say(self.petCursor.advance(Vocab.lines(for: .longPet),
                                                id: "longPet"),
                         or: "Best. Human. Ever 💛", for: 2.4, mood: .done,
                         deliberate: true)
            }
        }
        controller.onPetEnd = { [weak self] in
            guard let self else { return }
            self.model.pettingEndedAt = Date()
            // A step-aside deferred to the hold gets its turn on release.
            self.stepAsideIfWanted()
            // Long enough to cover the purr's 0.45s release AND the life of a
            // heart born just before the release (1.3s). Clearing at 0.6s
            // re-introduced the very deletion `heartsUntil` exists to prevent:
            // the pose would stop being petted while hearts were still
            // climbing. The cost is that the view holds 30fps for two seconds
            // after a pet rather than for half of one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, let ended = self.model.pettingEndedAt,
                      Date().timeIntervalSince(ended) >= 1.95 else { return }
                self.model.pettingStartedAt = nil
                self.model.pettingEndedAt = nil
            }
        }
        controller.onHover = { [weak self] hovering in
            guard let self else { return }
            if hovering {
                let started = Date()
                self.model.hoverStartedAt = started
                self.model.hoverEndedAt = nil
                // A hover only counts once he has actually been rested on —
                // see `hoverCountsAsStir` for why both halves of that check
                // are needed.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverStirDwell) { [weak self] in
                    guard let self,
                          Self.hoverCountsAsStir(startedAt: self.model.hoverStartedAt,
                                                 endedAt: self.model.hoverEndedAt,
                                                 queuedFor: started)
                    else { return }
                    self.onStir?()
                }
            } else {
                // Keep the start time so the greeting eases out from where it
                // was, then clear both once the release has played so the view
                // drops back to its mood frame rate.
                self.model.hoverEndedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, let ended = self.model.hoverEndedAt,
                          Date().timeIntervalSince(ended) >= 0.55 else { return }
                    self.model.hoverStartedAt = nil
                    self.model.hoverEndedAt = nil
                }
            }
        }
        controller.onDragEnded = { [weak self] in
            // Moving him around the desk is contact too.
            self?.onStir?()
            // A step-aside deferred to a held crab gets its chance now, and
            // the watch re-reads a window that may have landed on another
            // display.
            self?.filmWatch?.reconsider()
            self?.stepAsideIfWanted()
        }
        controller.onKey = { [weak self] event in
            guard let self else { return false }
            switch self.secretGate.press(event.charactersIgnoringModifiers, at: Date()) {
            case .summon:
                // Hand the key back BEFORE the menu tracks: the menu runs its
                // own event loop and needs nothing from this window.
                self.disarmSecretMenu()
                self.onSecretMenuRequested?()
                return true
            case .disarm:
                // A wrong key closes the gate quietly — consumed, no beep.
                self.disarmSecretMenu()
                return true
            case .ignore:
                return false
            }
        }
    }

    // MARK: - The secret door

    /// Shift+click armed the gate: borrow key focus the way the roster does
    /// and listen for K. The timer is the wander-off path — an armed gate
    /// with no keypress must still hand the borrowed focus back.
    private func armSecretMenu() {
        secretGate.arm(at: Date())
        controller?.borrowKey()
        secretDisarmTimer?.invalidate()
        secretDisarmTimer = Timer.scheduledTimer(withTimeInterval: SecretMenuGate.armWindow,
                                                 repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.disarmSecretMenu() }
        }
    }

    private func disarmSecretMenu() {
        secretDisarmTimer?.invalidate()
        secretDisarmTimer = nil
        secretGate.disarm()
        controller?.returnKey()
    }

    // MARK: - State intake

    /// A fresh state from the coordinator: forward to the model and settle
    /// the latches that derive from it.
    func take(state: PetState) {
        // The glow's own t=0: latched on the epic edge, released when the
        // celebration ends (the envelope is long done by then).
        if state.epicCelebration, model.celebrationStartedAt == nil {
            model.celebrationStartedAt = Date()
            // Once per finale, on the edge — the fanfare replaces the done
            // chime for epics (handleAlert stands down; see its guard).
            SoundBank.play(.fanfare)
        } else if !state.celebrating, model.celebrationStartedAt != nil {
            model.celebrationStartedAt = nil
        }
        let wasIdle = model.state.mood == .idle
        model.state = state
        updateServiceGlyphLatches()
        updateBadgeLatches()
        updateKnowledgeLatches()
        if state.mood == .idle, !wasIdle {
            armIdleShouts()
        }
    }

    /// Arm the skate and surf shouts once the mood clock actually knows he is
    /// idle — which is NOT yet, at the moment the mood changes.
    ///
    /// **This raced, and the shouts lost every time.** Both arms guard on
    /// `moodClock.currentEpoch(for: .idle)`, which is deliberately
    /// non-mutating: it answers `mood == current ? startedAt : nil`. The
    /// clock's `current` is advanced only by the mutating `epoch(for:)`, and
    /// the only production caller of that is `age(of:at:)` from CrabView's
    /// render. The render is a SwiftUI body evaluation driven by the very
    /// `@Published` write two lines above, so it necessarily runs AFTER this
    /// returns. On the idle rising edge — the only edge that arms — the clock
    /// therefore still holds the previous mood, `currentEpoch` is nil, the
    /// guard fails, and both functions return having bumped a sequence number
    /// and scheduled nothing. Nothing re-armed either, because the only other
    /// arm site is inside the closure that never ran.
    ///
    /// So he has never once shouted about a trick he landed or a wave he
    /// rode, in any build. Retrying on the next runloop turn lets the render
    /// rebase the clock first; the attempt cap keeps a mood that never
    /// renders (a hidden window) from retrying forever.
    private func armIdleShouts(attempt: Int = 0) {
        guard model.state.mood == .idle else { return }
        guard model.moodClock.currentEpoch(for: .idle) != nil else {
            guard attempt < 4 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.armIdleShouts(attempt: attempt + 1)
            }
            return
        }
        armSkateLine()
        armSurfLine()
    }

    /// The deal-with-it latch: settled on the edges of "a flaired fact is on
    /// his head", the glyph latch's exact shape. Rising edge starts the drop
    /// (and holds the 30fps tier for the fall only); a text change while
    /// still flaired keeps the pair worn without a re-drop — one gag per
    /// stay, not per sentence; falling edge plays the standard prop fade.
    private func updateKnowledgeLatches() {
        let live = model.state.bubble != nil
            && model.state.bubbleTone == .knowledge
            && model.state.bubbleFlair != .none
        if live, model.shadesStartedAt == nil || model.shadesEndedAt != nil {
            let startedAt = Date()
            model.shadesStartedAt = startedAt
            model.shadesEndedAt = nil
            model.shadesDing = model.state.bubbleFlair == .shadesDing
            model.shadesDropping = true
            if model.shadesDing {
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.shadesDropDuration) { [weak self] in
                    guard let self, self.model.shadesStartedAt == startedAt,
                          self.model.shadesEndedAt == nil else { return }
                    SoundBank.play(.ding)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.shadesDropDuration + 0.4) { [weak self] in
                guard let self, self.model.shadesStartedAt == startedAt else { return }
                self.model.shadesDropping = false
            }
        } else if !live, model.shadesStartedAt != nil, model.shadesEndedAt == nil {
            let endedAt = Date()
            model.shadesEndedAt = endedAt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.model.shadesEndedAt == endedAt else { return }
                self.model.shadesStartedAt = nil
                self.model.shadesEndedAt = nil
                self.model.shadesDing = false
                self.model.shadesDropping = false
            }
        }
    }

    /// 🌊 The same arrangement as the skate shout, for the swell: meet the
    /// moment the wave carries him out, then say something about it.
    ///
    /// It asks the animator when that will be rather than timing it here,
    /// which is the whole reason `nextSurfEnd` exists — a timer that
    /// guessed could speak over a wave that never came.
    private func armSurfLine() {
        surfSeq &+= 1
        let seq = surfSeq
        guard model.state.mood == .idle,
              let epoch = model.moodClock.currentEpoch(for: .idle),
              let ends = CrabAnimator.nextSurfEnd(
                after: Date.timeIntervalSinceReferenceDate - epoch)
        else { return }

        let wait = epoch + ends - Date.timeIntervalSinceReferenceDate
        guard wait > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.surfSeq == seq else { return }
            // The clock is the authority on whether the ride happened, not
            // the timer: he may have been given work, or idle may have left
            // and come back on a new epoch.
            guard self.model.state.mood == .idle,
                  self.model.moodClock.currentEpoch(for: .idle) == epoch else { return }
            self.say(self.surfCursor.advance(Vocab.lines(for: .surf), id: "surf"),
                     or: "Aloha 🌴", for: PetInstance.surfLineSeconds, mood: .done)
            self.armSurfLine()        // and meet the next swell
        }
    }

    /// **One door for every spoken line, and it can say no.**
    ///
    /// Five places used to assign `model.transientBubble` directly, and none
    /// of them looked first. The bubble is a single slot with a queue of
    /// writers and no lock, so whatever spoke last won — which is how the
    /// operator came to watch a fun fact taken off the screen mid-thought.
    ///
    /// The rule is his: whatever is on screen finishes. A line that arrives
    /// into an occupied bubble is DROPPED, not queued — the skate and surf
    /// shouts are tied to a moment (a landing, a wave) and a shout that
    /// arrives late is worse than one that never comes. Both re-arm
    /// themselves for the next one regardless, so nothing gets stuck.
    ///
    /// Returns whether the line was actually said, for callers that care.
    @discardableResult
    private func say(_ line: @autoclosure () -> String?, or fallback: String,
                     for seconds: TimeInterval, mood: PetMood,
                     deliberate: Bool = false) -> Bool {
        guard Self.shouldSpeak(transientUntil: model.transientBubble?.until,
                               stateBubble: model.state.bubble,
                               tone: model.state.bubbleTone,
                               deliberate: deliberate,
                               now: Date())
        else { return false }
        // The line is DRAWN here, not by the caller, and that is the whole
        // reason for the autoclosure. `LineCursor.advance` is mutating: it
        // steps the deck's seed and writes it back unconditionally. Drawing
        // before asking meant a refused line still burned its place in the
        // pool — the sentence was consumed, never shown, and never came round
        // again. Now a refusal costs nothing.
        model.transientBubble = (line() ?? fallback,
                                 Date().addingTimeInterval(seconds), mood)
        return true
    }

    /// **The rule, as a pure function.** Lifted out of `say` so it can be
    /// tested without building a `PetInstance` — the same shape `pokeVerdict`
    /// and `clickAction` already use, and the reason this one needed lifting
    /// is that `say` is private and nothing in the suite could reach it.
    ///
    /// Two guards, and they are not the same guard:
    ///
    /// - A transient still being read always wins. Whatever is on screen
    ///   finishes; that is the operator's rule and it has no exceptions,
    ///   because two of his own lines fighting is the bug that started this.
    /// - A fact holding the face wins over AMBIENT lines only. The skate and
    ///   surf shouts arrive unbidden and can wait for the next trick. A poke
    ///   or a long pet cannot: the person did something with their hands and
    ///   is owed an answer, and the alternative is worse than an interrupted
    ///   fact — the chirp plays, the pose lands, and no words come, which
    ///   reads as the app being broken rather than as him being polite.
    nonisolated static func shouldSpeak(transientUntil: Date?,
                                        stateBubble: String?,
                                        tone: PetState.BubbleTone,
                                        deliberate: Bool,
                                        now: Date) -> Bool {
        if let until = transientUntil, until > now { return false }
        if deliberate { return true }
        if let showing = stateBubble, !showing.isEmpty, tone == .knowledge {
            return false
        }
        return true
    }

    /// 🎉🪄 The triple-poke party, latched with the guarded clear every latch
    /// in this file uses: a stale timer finds a newer stamp and does nothing.
    /// Shared by the awake poke ladder and the sleeper's deferred payoff.
    private func startParty() {
        let started = Date()
        model.rainbowStartedAt = started
        DispatchQueue.main.asyncAfter(deadline: .now() + CrabView.rainbowDuration) { [weak self] in
            guard let self, self.model.rainbowStartedAt == started else { return }
            self.model.rainbowStartedAt = nil
        }
    }

    /// Meet the next skate beat at the moment it lands.
    ///
    /// **Scheduled, not detected.** The flourish schedule is pure in the mood
    /// clock, so given when idle began the exact landing instant is knowable —
    /// there is nothing to poll for and no frame to miss. The alternative was
    /// watching the animation from the app layer, which would mean a callback
    /// out of a `TimelineView` body or a second clock kept beside the real one
    /// and hoped to agree with it.
    ///
    /// Through **`model.moodClock`**, never `MoodClock.shared`. Each pet owns
    /// its clock — `currentBugZone` above already says why, in the same words:
    /// the shared one is nobody's clock now. The first version of this read the
    /// shared instance, which with two pets on the desk is a clock neither of
    /// them renders from, and the line would have been scheduled against
    /// nothing.
    ///
    /// `currentEpoch(for:)` is the non-mutating question. Asking `epoch(for:)`
    /// would REBASE the clock — restarting the very animation this is trying to
    /// meet.
    private func armSkateLine() {
        skateSeq &+= 1
        let seq = skateSeq
        guard model.state.mood == .idle,
              let epoch = model.moodClock.currentEpoch(for: .idle),
              let landing = CrabAnimator.nextSkateTrickLanding(
                after: Date.timeIntervalSinceReferenceDate - epoch)
        else { return }

        let wait = epoch + landing - Date.timeIntervalSinceReferenceDate
        guard wait > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.skateSeq == seq else { return }
            // He may have been given work in the meantime, or the mood may have
            // left and come back on a new epoch. The clock is the authority on
            // whether the trick actually happened, not the timer.
            guard self.model.state.mood == .idle,
                  self.model.moodClock.currentEpoch(for: .idle) == epoch else { return }
            // 🛹✨ Golden landings get the reserved deck. `skateLandingIsGolden`
            // is the SAME derivation the pose used to paint the board, asked
            // at the same landing instant — so the shout can never call an
            // ordinary trick golden, or stay quiet about the jackpot.
            // 🎭 …and IN CHARACTER, when he is wearing one. A costume that
            // only recolours him is a paint job; one that changes what he
            // says is a character, which is what the operator asked for.
            // The golden deck still outranks it: the jackpot is the rarer
            // thing to have landed, and it should sound like it whatever he
            // has on. A costume with no voice of its own falls back to his,
            // rather than being handed a forced catchphrase.
            let worn = self.model.costume
            let inCharacter = Vocab.skateLines(for: worn)
            // Drawn lazily, inside `say`, so a shout that arrives while a
            // fact is being read costs the deck nothing.
            self.say(CrabAnimator.skateLandingIsGolden(at: landing)
                        ? self.skateCursor.advance(Vocab.lines(for: .goldenSkate),
                                                   id: "goldenSkate")
                        : inCharacter.isEmpty
                            ? self.skateCursor.advance(Vocab.lines(for: .kickflip),
                                                       id: "kickflip")
                            : self.skateCursor.advance(inCharacter,
                                                       id: "skate-\(worn.rawValue)"),
                     or: "Kowbunga 🤙!", for: PetInstance.skateLineSeconds,
                     mood: .done)
            self.armSkateLine()          // and meet the next one
        }
    }

    // MARK: - Hello

    /// He introduces himself, once, on the first launch ever.
    ///
    /// The DMG cannot carry motion — a Finder window's background is a colour
    /// or a single still, with nowhere to put a frame rate — so the first
    /// moving thing a new arrival sees is this. It is also the only moment they
    /// have no idea what the crab on their desktop is, which is why every line
    /// in the `.hello` pool names him.
    ///
    /// **Slot 0 only.** A second pet is summoned deliberately by someone who
    /// already knows what he is; being introduced to by your own sibling is not
    /// a first meeting.
    ///
    /// The reaction itself is `applyGreeting`'s `.wave` — the same one the
    /// pointer gets, asked for by name rather than by hunting a seed that
    /// happens to roll it.
    ///
    /// - Parameter force: play it regardless of the preference, for the secret
    ///   menu's row. Deliberately does NOT mark him greeted: replaying a
    ///   greeting should not be able to consume a first run that has not
    ///   happened yet.
    func sayHello(force: Bool = false) {
        guard slot == 0 else { return }
        if !force {
            guard !Preferences.shared.hasBeenGreeted else { return }
            Preferences.shared.hasBeenGreeted = true
        }

        helloSeq &+= 1
        let seq = helloSeq
        DispatchQueue.main.asyncAfter(deadline: .now() + PetInstance.helloDelay) { [weak self] in
            guard let self, self.helloSeq == seq else { return }
            let start = Date()
            self.model.helloStartedAt = start
            self.model.helloEndedAt = start.addingTimeInterval(PetInstance.helloWaveSeconds)
            // `.idle` styling, not `.done`: the same green bubble without the
            // checkmark. A greeting that opens with a tick reads as a
            // notification about something finishing.
            //
            // Through `say` like everything else, and `deliberate` because a
            // first-launch hello is not something to skip. This was the last
            // direct write to `transientBubble` — safe on the first-run path,
            // where nothing else has spoken yet, and not safe on the
            // secret-menu force path, which can fire at any moment including
            // over a fact mid-read. Saying "this one overrides" out loud is
            // better than saying it by not calling the function.
            self.say(self.helloCursor.advance(Vocab.lines(for: .hello), id: "hello"),
                     or: "Hi, I'm Claw'd 🦀", for: PetInstance.helloLineSeconds,
                     mood: .idle, deliberate: true)

            // Clear the pair once it has finished easing out. Not housekeeping:
            // `helloSince` is one of the flags that puts CrabView on the smooth
            // reaction frame rate, so leaving it set would hold the whole
            // session at that rate for a wave that ended seconds ago — an idle
            // pet costing an idle machine something, which is exactly what
            // `.sleeping`'s reduced rate exists to prevent.
            let settle = PetInstance.helloWaveSeconds + 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
                guard let self, self.helloSeq == seq else { return }
                self.model.helloStartedAt = nil
                self.model.helloEndedAt = nil
            }
        }
    }

    // MARK: - Films

    func startFilmWatch() {
        let film = FilmWatch(
            geometry: { [weak self] in
                // Re-read the controller every sample: `rebuildWindow`
                // replaces it wholesale, and a captured window is the one
                // that is wrong at the moment it matters.
                guard let window = self?.controller?.window,
                      let screen = PetWindowController.screen(for: window.frame)
                else { return nil }   // no display → no geometry → the detector surfaces him
                return FullScreenWatch.geometry(of: screen)
            },
            onChange: { [weak self] playing in self?.filmChanged(playing: playing) })
        film.start()
        filmWatch = film

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.filmWatch?.reconsider() }
        }

        // Display sleep is on the WORKSPACE centre, not the default one — a
        // notification posted to the wrong centre simply never arrives.
        let workspace = NSWorkspace.shared.notificationCenter
        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displayAsleep = true; self?.publishVisibility() }
        }
        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.displayAsleep = false; self?.publishVisibility() }
        }
        if let window = controller?.window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main) { [weak self] _ in
                // NOTHING is read out of the notification, and that is the
                // point. `occlusionState` is main-actor isolated and this
                // closure is `@Sendable`, so touching the window here is
                // illegal — Swift 6.1 says so and 6.3 does not, which is
                // exactly the kind of disagreement that reaches CI green
                // locally. Hop first, then re-read the window from `self`,
                // where reading it is legal on either toolchain.
                Task { @MainActor in
                    guard let self, let window = self.controller?.window else { return }
                    self.windowCovered = !window.occlusionState.contains(.visible)
                    self.publishVisibility()
                }
            }
        }
    }

    /// Hands the view the one fact it needs: can anyone see him right now.
    ///
    /// A rate input only. The pose stays a pure function of time; this decides
    /// how often it is asked for. A pet nobody is looking at should not be
    /// rebuilding a 1024-cell buffer twenty times a second.
    private func publishVisibility() {
        model.unseen = displayAsleep || windowCovered
    }

    private func filmChanged(playing: Bool) {
        filmPlaying = playing
        if playing {
            stepAsideIfWanted()
        } else {
            // The film's reason is withdrawn; so is the override it earned.
            filmOverride = false
            if steppedAside {
                steppedAside = false
                // Coming back is not a promise to appear — the operator's own
                // hide stands on its own.
                if !petHiddenByUser { controller?.fadeIn() }
            }
        }
    }

    func stepAsideIfWanted() {
        // A held crab is in the operator's hand twice over: mid-drag and
        // mid-pet both defer the fade, and the release re-runs this. Before
        // the torso-only handle, every press armed the drag and isDragging
        // covered a pet-hold for free; now the hold speaks for itself.
        guard filmPlaying, Preferences.shared.stepsAsideForVideo,
              !petHiddenByUser, !filmOverride, !steppedAside,
              controller?.isDragging != true,
              model.pettingStartedAt == nil || model.pettingEndedAt != nil else { return }
        steppedAside = true
        controller?.fadeOut()
    }

    /// The step-aside preference was switched off (or the operator wants him
    /// back): end an active step-aside now.
    func surfaceFromFilm() {
        guard steppedAside else { return }
        steppedAside = false
        if !petHiddenByUser { controller?.fadeIn() }
    }

    func applyPersistency() {
        controller?.setPersistent(Preferences.shared.persistent)
    }

    // MARK: - Interactions

    func toggleVisibility() {
        guard let controller else { return }
        if steppedAside {
            // Bringing him back mid-film is an answer to THIS film: he stays
            // up for the rest of it and the override dies with it.
            filmOverride = true
            steppedAside = false
            controller.fadeIn()
            return
        }
        petHiddenByUser.toggle()
        petHiddenByUser ? controller.hide() : controller.show()
    }

    /// The completion badge's appearance latches. Rules: the badge waits for
    /// the done pose to relax (the crossfade dissolves the big overhead check
    /// out while the foot badge dissolves in — never two checkmarks); a
    /// completion ending for any reason — new work, focus switch away,
    /// session death — eases out through one 0.45s envelope rather than
    /// vanishing; a focus switch between two live completions swaps identity
    /// without re-running the attack, so the badge never dips.
    private func updateBadgeLatches() {
        let state = model.state
        if let live = state.completedAt {
            guard state.mood != .done else { return }   // wait out the pose
            if model.badgeCompletionAt == nil || model.badgeEndedAt != nil {
                model.badgeCompletionAt = live
                model.badgeShownAt = Date()
                model.badgeEndedAt = nil
            } else if model.badgeCompletionAt != live {
                model.badgeCompletionAt = live
            }
        } else if model.badgeCompletionAt != nil, model.badgeEndedAt == nil {
            let ended = Date()
            model.badgeEndedAt = ended
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.model.badgeEndedAt == ended else { return }
                self.model.badgeCompletionAt = nil
                self.model.badgeShownAt = nil
                self.model.badgeEndedAt = nil
            }
        }
    }

    /// The service glyph's appearance latches, on the badge pattern: a new
    /// kind enters through a fresh attack; a kind CHANGE retires the old art
    /// first and re-latches once the retreat has played, so swaps dip
    /// through zero instead of popping new pixels at full visibility; state
    /// going quiet eases out.
    private func updateServiceGlyphLatches() {
        let live = model.state.serviceGlyph
        if let live {
            if model.serviceGlyphKind == nil
                || (model.serviceGlyphEndedAt != nil && model.serviceGlyphKind == live) {
                // First appearance, or the same kind returning mid-retreat:
                // fresh attack — with the family's own blip.
                SoundBank.play(.glyphBlip(live))
                model.serviceGlyphKind = live
                model.serviceGlyphShownAt = Date()
                model.serviceGlyphEndedAt = nil
            } else if model.serviceGlyphKind != live, model.serviceGlyphEndedAt == nil {
                // A different service took over: retire the old art, then
                // re-run this to bring the new one in from zero.
                let ended = Date()
                model.serviceGlyphEndedAt = ended
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, self.model.serviceGlyphEndedAt == ended else { return }
                    self.model.serviceGlyphKind = nil
                    self.model.serviceGlyphShownAt = nil
                    self.model.serviceGlyphEndedAt = nil
                    self.updateServiceGlyphLatches()
                }
            }
        } else if model.serviceGlyphKind != nil, model.serviceGlyphEndedAt == nil {
            let ended = Date()
            model.serviceGlyphEndedAt = ended
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.model.serviceGlyphEndedAt == ended else { return }
                self.model.serviceGlyphKind = nil
                self.model.serviceGlyphShownAt = nil
                self.model.serviceGlyphEndedAt = nil
            }
        }
    }

    /// The floor bug's clickable box right now, through THIS pet's idle clock
    /// — the shared one is nobody's clock now. Nil unless a bug is out.
    private func currentBugZone() -> CellRect? {
        guard model.state.mood == .idle,
              let epoch = model.moodClock.currentEpoch(for: .idle) else { return nil }
        return CrabAnimator.bugZone(idleT: Date.timeIntervalSinceReferenceDate - epoch)
    }

    /// This pet's click→cell mapping. The maths lives once, on `PetRootView`,
    /// where the window's hit test reads it too.
    private func gridCell(for location: CGPoint) -> (x: Int, y: Int)? {
        PetRootView.spriteCell(for: location, pixelSize: Preferences.shared.pixelSize)
    }
}
