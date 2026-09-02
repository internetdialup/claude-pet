import SwiftUI

/// Turns time + mood into a `CrabPose`, every frame.
///
/// All motion is a pure function of `(mood, elapsed)`, so the sprite cannot
/// drift out of sync with its state. Offsets are whole pixels: on a 32×32 grid a
/// half-pixel move just smears two rows and loses the pixel-art read.
public enum CrabAnimator {

    /// Deterministic pseudo-random in 0..<1, so blink timing is irregular but
    /// stable across frames (a real RNG would re-roll 60× a second).
    ///
    /// This is a hash, not one step of a linear congruential generator. The
    /// previous version was `(n * 1664525 + 1013904223) & 0x7FFFFFFF`, whose
    /// output moves by only ~0.0008 per increment of `n` — so consecutive seeds
    /// landed in the same bucket and a four-way choice could only ever reach two
    /// of its options. That silently narrowed the idle flourishes and the
    /// working props as well as the hover reactions. splitmix64's finaliser
    /// avalanches properly: one bit of input changes half the output bits.
    ///
    /// ## The salt registry
    ///
    /// Every dice gate in the app is `noise(cycle &* A &+ B)`. Two schedules
    /// sharing an `A` over the same domain fire together forever, which reads
    /// as one coincidence you can never explain. The registry lived inside
    /// `bubbleBurst` and had gone stale — it listed six of the eleven — so it
    /// lives here now, at the one function all of them pass through.
    ///
    /// Over a **cycle** domain:
    ///
    /// | salt | who |
    /// | --- | --- |
    /// | `7 &+ 3` | which idle flourish |
    /// | `13 &+ 5` | the working prop re-roll |
    /// | `17 &+ 7` | whether an idle cycle is a fun fact |
    /// | `17 &+ 11` | whether a fact showing drops the shades — 17 shared by addend |
    /// | `17 &+ 13` | whether the shades land with a ding — same family |
    /// | `19 &+ 13` | the bubble shimmer |
    /// | `23 &+ 19` | whether an informational cycle is a tip, not a fact |
    /// | `29 &+ 11` | the cooking heat cascade |
    /// | `41 &+ 17` | the disco tint |
    /// | `43 &+ 11` | the idle mug |
    /// | `53 &+ 7` | the floor bug |
    /// | `59 &+ 7` | the petting hearts' column |
    /// | `59 &+ 11` | the sleep zZz's column — 59 shared by addend, same domain |
    /// | `61 &+ 3` | the stargazer |
    /// | `67 &+ 5` | the near-done glow |
    /// | `71 &+ 29 &+ slot` | the bubble bursts |
    /// | `73 &+ 5` | the patch of sun |
    /// | `79 &+ 23` | whether a silent working beat carries a fact |
    /// | `83 &+ 13` | the shell glint |
    /// | `89 &+ 11` | whether an idle flourish plays at all |
    ///
    /// Over other domains, where a collision with the above is impossible
    /// because the input is not a cycle: `37 &+ 11`, `91 &+ 17` and `53 &+ 29`
    /// (matrix rain, per column), `31 &+ 7` and `53 &+ 11` (the sizzle, per
    /// shot), `43 &+ 13` (idle chatter, per seed).
    ///
    /// | `97 &+ n` | the COSTUME EFFECTS, one addend each (11 = the shuriken) |
    ///
    /// **Free:** none. 97 is the last multiplier and the costumes share it by
    /// addend, the way `71 &+ 29 &+ slot` shares one across the bubble bursts.
    /// A tenth costume effect takes the next addend, not a new multiplier.
    static func noise(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        return Double(x >> 11) / Double(1 << 53)
    }

    /// A blink roughly every 5s (±1.5s), lasting 140ms.
    private static func blink(at t: Double, period: Double = 5.0) -> Double {
        let cycle = Int(floor(t / period))
        let jitter = (noise(cycle) - 0.5) * 3.0
        let start = Double(cycle) * period + period * 0.5 + jitter
        let dt = t - start
        return (dt >= 0 && dt <= 0.14) ? 1 : 0
    }

    /// Occasional one-pixel eye dart, held briefly then released.
    private static func gaze(at t: Double) -> (Int, Int) {
        let cycle = Int(floor(t / 3.0))
        let hold = t - Double(cycle) * 3.0
        guard hold > 0.2, hold < 2.0 else { return (0, 0) }
        let roll = noise(cycle)
        if roll < 0.34 { return (-1, 0) }
        if roll < 0.68 { return (1, 0) }
        return (0, 1)
    }

    /// The little unprompted things he does while waiting. Scheduled rather
    /// than random per frame, so each one plays through instead of stuttering.
    enum Flourish: String, CaseIterable {
        case jump, wave, wiggle, stretch, lookAround, scuttle, kickflip, varialFlip,
             cruise,
             // Appended, never inserted — the dice index into `allCases`.
             ollie

        /// The two skate tricks, so the line he shouts after one does not have
        /// to name them individually.
        /// Everything he does on a board. Two are tricks and one is a cruise,
        /// which is why this is not called `skateTricks` — he shouts after all
        /// three, and "Do a Kickflip!" lands funnier over a roll-away than it
        /// does over an actual kickflip.
        static let skateBeats: Set<Flourish> = [.kickflip, .varialFlip, .cruise, .ollie]

        var duration: Double {
            switch self {
            case .kickflip, .varialFlip: 2.8
            // Longer than the flips on purpose: the whole point of this one
            // is the hang, and hang needs clock to hang in.
            case .ollie: 3.2
            case .cruise: 2.6
            case .jump: 0.9
            case .wave: 1.8
            case .wiggle: 1.0
            case .stretch: 1.6
            case .lookAround: 2.0
            case .scuttle: 1.2
            }
        }
    }

    /// One slow breath, and the length of `sleeping`'s README clip.
    ///
    /// Named rather than written down twice, so the clip is exactly one breath
    /// and closes seamlessly. It used to be a 4.0s clip over a 6.98s cycle —
    /// 57% of a breath, so the GIF did not loop, it jumped.
    ///
    /// Five seconds rather than seven: seven is slower than anything that
    /// breathes and reads as stopped.
    static let breathPeriod = 5.0

    /// The ollie's air window inside its own 0…1 progress: the crouch ends at
    /// `ollieAirStart`, the stomp begins at `ollieAirStart + ollieAirSpan`.
    /// Shared with the drip-feed sampler's variant maps, which shade and
    /// re-arc the trick strictly INSIDE this window — one copy of the
    /// numbers, so the variants cannot drift from the flourish they dress.
    static let ollieAirStart = 0.12
    static let ollieAirSpan = 0.76

    /// One flourish per window, on dice, with a quiet stretch after it.
    private static let flourishPeriod = 7.0

    /// Which flourish is playing, and how far into it we are (0…1).
    ///
    /// The dice used to pick *which* and nothing gated *whether*, so he
    /// jumped, waved, stretched or scuttled every seven seconds, forever, on
    /// a metronome. Two things fell out of that, and one line fixes both.
    ///
    /// `noise(3)` is 0.113, which selects `allCases[0]` — jump — so cycle 0
    /// was **always** a jump, and it was already at progress 0 at t == 0.
    /// That put idle in breach of the frozen sentinel: `pose(mood: .idle,
    /// t: 0)` came back with `squash = 1`, a crouching crab, and
    /// `nothingFiresAtTimeZero` could not see it because it checks props,
    /// heat and glyphs rather than the body. Worse, `GifRenderer` samples
    /// every still at t = 0.4, which for idle is jump-progress 0.44 — so
    /// `still-idle.png`, the marketing still of him *at rest*, was a crab
    /// five pixels in the air.
    ///
    /// Excluding cycle 0 fixes both. The 0.7 chance is the separate half:
    /// 72% of cycles fire, gaps go irregular (7s, 14s, 7s, 21s…, longest 35s
    /// over 600 cycles) and the quiet stretches rise from 80% to 86%.
    /// "He should move sometimes, and be still most of the time."
    static func flourish(at t: Double) -> (Flourish, Double)? {
        let cycle = Int(floor(t / flourishPeriod))
        guard cycle > 0, noise(cycle &* 89 &+ 11) < 0.7 else { return nil }
        let since = t - Double(cycle) * flourishPeriod
        let all = Flourish.allCases
        let choice = all[Int(noise(cycle &* 7 &+ 3) * Double(all.count)) % all.count]
        guard since < choice.duration else { return nil }
        return (choice, since / choice.duration)
    }

    /// When the next SKATE TRICK lands, in mood-clock seconds, or nil if none
    /// is scheduled inside the horizon.
    ///
    /// Asks `flourish(at:)` rather than restating its dice. The schedule is
    /// already written down once; a second copy here would agree with it right
    /// up until somebody changed one of them, and the symptom would be him
    /// shouting about a trick he did not do.
    static func nextSkateTrickLanding(after t: Double, horizon: Double = 900) -> Double? {
        let first = max(1, Int(floor(t / flourishPeriod)))
        for cycle in first...(first + Int(horizon / flourishPeriod)) {
            let start = Double(cycle) * flourishPeriod
            guard let (kind, _) = flourish(at: start + 0.01),
                  Flourish.skateBeats.contains(kind)
            else { continue }
            let landed = start + kind.duration
            if landed > t { return landed }
        }
        return nil
    }

    /// The first cycle that actually fires, as an instant. `idle`'s README
    /// clip starts here: the clip is six seconds and the flourish period is
    /// seven, so a clip anchored at zero would now contain nothing but
    /// breathing.
    static let firstFlourishAt: Double = {
        for cycle in 1...64 where noise(cycle &* 89 &+ 11) < 0.7 {
            return Double(cycle) * flourishPeriod
        }
        return flourishPeriod
    }()

    /// The thinking spell's prop: sparkles first, then the Claude star, in
    /// strict 20s alternation — dice would be degenerate here (MoodClock
    /// rebases t on every entry, so cycle-0 dice is a constant), and the
    /// alternation guarantees the star actually appears in a long think
    /// while keeping every committed thinking clip (all < 20s) byte-stable.
    static func thinkingProp(at t: Double, spell: Double = 20) -> CrabPose.Prop {
        Int(floor(t / spell)) % 2 == 0 ? .sparkles : .star
    }

    /// A prop for the current work spell. Re-rolled every `spell` seconds so a
    /// long task does not stare at the same terminal window for ten minutes.
    static func workingProp(at t: Double, spell: Double = 20) -> CrabPose.Prop {
        let cycle = Int(floor(t / spell))
        let options = CrabPose.Prop.working
        return options[Int(noise(cycle &* 13 &+ 5) * Double(options.count)) % options.count]
    }

    /// Eases the 20-second prop re-roll: the outgoing prop dissolves over the
    /// spell's last 0.35s and the incoming one dissolves in over the next
    /// spell's first 0.35s — he puts one down, then picks the next up. Pure in
    /// `t`, so it flows through the offline renderers unchanged; the first
    /// spell never fades in (there is nothing before it to put down).
    private static let propFade = 0.35

    static func applyPropDissolve(at t: Double, spell: Double = 20,
                                  roll: ((Double) -> CrabPose.Prop)? = nil,
                                  to pose: inout CrabPose) {
        let pick = roll ?? { workingProp(at: $0, spell: spell) }
        let cycle = Int(floor(t / spell))
        let within = t - Double(cycle) * spell
        let current = pick(t)

        if cycle > 0, within < propFade {
            let previous = pick((Double(cycle) - 0.5) * spell)
            if previous != current {
                pose.propVisibility = Ease.smoothstep(within / propFade)
            }
        } else if within > spell - propFade {
            let next = pick((Double(cycle) + 1.5) * spell)
            if next != current {
                pose.propVisibility = Ease.smoothstep((spell - within) / propFade)
            }
        }
    }

    public static func pose(mood: PetMood, t: Double) -> CrabPose {
        pose(mood: mood, t: t, flourishes: true)
    }

    /// Where the bug is during an idle spell, or nil. Rarely, on dice, a
    /// two-pixel bug scuttles across the floor over six seconds — direction
    /// alternating by cycle, entering and leaving off-grid so there is no
    /// pop at either edge. Never in the first cycle.
    static func bugPosition(idleT t: Double) -> Int? {
        let cycle = Int(floor(t / 90))
        guard cycle > 0, noise(cycle &* 53 &+ 7) < 0.3 else { return nil }
        let since = t - Double(cycle) * 90
        guard since < 6 else { return nil }
        let progress = since / 6
        let x = -3.0 + progress * 37.0
        let column = cycle % 2 == 0 ? Int(x.rounded()) : 31 - Int(x.rounded())
        return column >= -2 && column <= 33 ? column : nil
    }

    /// The floor bug's clickable box, or nil when no bug is out.
    ///
    /// The bug is a transient overlay standing on cells the silhouette mask
    /// calls empty, so the pounce cannot ride the mask — it rides here, and
    /// the window asks only when the mask has already missed. Pure, and
    /// cheap: a floor, a hash, a compare. The geometry lives with the
    /// schedule that owns it rather than as four literals inlined in the
    /// click handler.
    static func bugZone(idleT t: Double) -> CellRect? {
        guard let column = bugPosition(idleT: t) else { return nil }
        return CellRect(x: column - 2, y: 26, w: 6, h: PixelBuffer.side - 26)
    }

    /// The balloon's rare idle float — the prop was dead vocabulary from the
    /// day it was drawn: listed, rendered in every strip, scheduled by
    /// nothing. Now it is the bug and the telescope's sibling: on dice, in
    /// a long idle, he holds a balloon for eight seconds. Never in the
    /// first cycle (frozen sentinel), eased both ways via the window.
    static func idleBalloon(idleT t: Double) -> Double? {
        let cycle = Int(floor(t / 150))
        guard cycle > 0, noise(cycle &* 43 &+ 11) < 0.25 else { return nil }
        let since = t - Double(cycle) * 150
        guard since < 8 else { return nil }
        return Ease.window(since, duration: 8, edge: 0.9)
    }

    /// The midnight stargazer's envelope and clock during an idle spell, in
    /// the small hours only. 12s of telescope, eased 0.8s at both ends.
    static func stargaze(idleT t: Double, hourOfDay: Int?) -> (amount: Double, phase: Double)? {
        guard let hourOfDay, hourOfDay >= 23 || hourOfDay <= 4 else { return nil }
        let cycle = Int(floor(t / 120))
        guard cycle > 0, noise(cycle &* 61 &+ 3) < 0.35 else { return nil }
        let since = t - Double(cycle) * 120
        guard since < 12 else { return nil }
        return (Ease.window(since, duration: 12, edge: 0.8), since)
    }

    /// The rare scheduled effects, each forced on for review.
    ///
    /// The animation picker could only ever select a MOOD, which quietly meant
    /// the things most worth reviewing were the things it could not show: an
    /// effect gated on the wall clock and a dice is not reachable by choosing
    /// `idle` and waiting. The patch of sun is the clearest case — it wants
    /// daylight and a 1-in-4 roll on a seven-minute cycle, so at one in the
    /// morning there is no sequence of clicks that produces it.
    ///
    /// A preview deliberately bypasses BOTH gates, the hour and the dice, and
    /// loops. That is the whole point of it: the schedule is what you are
    /// trying to see past.
    public enum PreviewEffect: String, CaseIterable, Sendable {
        case basking, glint, ting, hearts, beacon
        // The skate beats. A trick needs the idle mood AND a dice that lands
        // about every thirty seconds, so while any session is running there is
        // no sequence of clicks that produces one — which is the exact case
        // this menu's own note says it exists for.
        case kickflip, varial, cruise

        /// How long this effect takes to let go, so a review that ends looks
        /// like the effect ending rather than like a number changing. Zero for
        /// the two that release by finishing what is already in flight, and
        /// for the one that is exempt.
        nonisolated var releaseDuration: Double {
            switch self {
            case .basking: 2.0      // its window's own edge
            case .beacon: 1.3       // its window's own edge
            case .glint, .hearts, .ting: 0
            // The tricks release by finishing the pass already in flight.
            case .kickflip, .varial, .cruise: 0
            }
        }
    }

    /// A preview's identity and its own two-ended latch — the house shape that
    /// `hoverSince`/`hoverEndedAt` and `petSince`/`petEndedAt` already use.
    ///
    /// The effect and its epoch are bundled deliberately. An effect without an
    /// epoch, or an epoch without an effect, is exactly the half-state the
    /// two-clock bug lived in; bundling makes that unrepresentable rather than
    /// merely fixed.
    public struct PreviewLatch: Equatable, Sendable {
        public var effect: PreviewEffect
        /// Reference time the menu item was chosen.
        public var since: Double
        /// Reference time it was dismissed, while the release plays out.
        public var endedAt: Double?

        public init(effect: PreviewEffect, since: Double, endedAt: Double? = nil) {
            self.effect = effect
            self.since = since
            self.endedAt = endedAt
        }

        nonisolated func frame(at time: Double) -> PreviewFrame {
            PreviewFrame(effect: effect,
                         t: max(0, time - since),
                         endedT: endedAt.map { max(0, $0 - since) })
        }
    }

    /// One preview's clock, resolved ONCE per frame and handed to every
    /// consumer of it.
    ///
    /// Deriving it twice is the whole bug this replaces: the floor pool rode
    /// the raw wall clock and the warm on his shell rode the mood clock, so
    /// they sat `epoch mod 18` apart and about a third of the time exactly one
    /// of the two was on screen — a gold crab standing on bare floor, or a
    /// pool of light under a cold one.
    public struct PreviewFrame: Equatable, Sendable {
        public var effect: PreviewEffect
        /// Seconds since it was chosen. Its own t=0, which is the single fact
        /// that makes every branch ease in from nothing instead of joining
        /// mid-cycle — and the reason the latch needs no attack envelope.
        public var t: Double
        /// `t` at the instant it was deselected, or nil while it is held.
        public var endedT: Double?

        public init(effect: PreviewEffect, t: Double, endedT: Double? = nil) {
            self.effect = effect
            self.t = t
            self.endedT = endedT
        }

        /// The exit. 1 while held. The latch owns nothing else: each branch's
        /// own envelope is already zero at t=0, so an attack on top would be
        /// easing something that is not there yet.
        var release: Double {
            guard let endedT else { return 1 }
            let duration = effect.releaseDuration
            guard duration > 0 else { return t > endedT ? 0 : 1 }
            return 1 - Ease.smoothstep((t - endedT) / duration)
        }
    }

    /// The basking envelope for a preview, release included.
    ///
    /// One function of one argument, so the floor pool, the warm on his shell
    /// and his shut eyes cannot diverge in clock *or* in arithmetic — the same
    /// "one envelope, three consumers" contract the scheduled version states.
    nonisolated static func previewBasking(_ frame: PreviewFrame) -> Double {
        guard frame.effect == .basking else { return 0 }
        let loop = frame.t.truncatingRemainder(dividingBy: 18)
        return Ease.window(loop, duration: 14, edge: 2.0) * frame.release
    }

    /// Forces one effect on, on its own looping clock. Every branch mirrors the
    /// scheduled version's SHAPE — same envelope, same durations — so what the
    /// picker shows is what actually ships, minus the waiting.
    nonisolated static func applyPreview(_ frame: PreviewFrame, to pose: inout CrabPose) {
        switch frame.effect {
        case .kickflip, .varial, .cruise:
            // Looped, with a beat of rest between passes so it reads as the
            // trick repeating rather than as one long stutter — and so the
            // landing, which is the part worth reviewing, is legible each time.
            let kind: Flourish = switch frame.effect {
            case .kickflip: .kickflip
            case .varial: .varialFlip
            default: .cruise
            }
            // The REST BEAT COMES FIRST, and that is the frozen sentinel rather
            // than a stylistic choice: `nothingIsMidFlightInAPreviewsFirstFrame`
            // requires a preview's t=0 to be indistinguishable from no preview
            // at all. Starting the loop at the top of the trick put him already
            // crouched on a board in the first frame, which is exactly the
            // mid-flight opening that guard exists to forbid.
            let rest = 0.8
            let since = frame.t.truncatingRemainder(dividingBy: kind.duration + rest)
            guard since >= rest else { return }
            apply(kind, progress: (since - rest) / kind.duration, t: frame.t, to: &pose)

        case .basking:
            let amount = previewBasking(frame)
            guard amount > 0.001 else { return }
            pose.sunPatch = amount
            pose.sunPatchPhase = frame.t.truncatingRemainder(dividingBy: 18)
            // Gated on the release too, so the face comes back before the
            // light has fully gone rather than after it. `applyPetting` uses
            // the same 0.5 for the same reason. A blink is exempt from no-snap.
            if amount > 0.55, frame.release >= 0.5 {
                pose.blink = 1
                pose.mouth = .smile
            }

        case .glint:
            // 1.6s of travel every four seconds, rather than every 2.5 minutes.
            // The `until` contract rather than an envelope: a pass already
            // travelling when you let go finishes, and no new one starts. Its
            // exit is off-shell by geometry, which is the defence `glintPass`
            // already claims — and its entrance is too, now that travel starts
            // at its own u=0 instead of wherever the wall clock was.
            let passStart = (frame.t / 4).rounded(.down) * 4
            if let endedT = frame.endedT, passStart > endedT { return }
            let since = frame.t - passStart
            pose.glint = since < 1.6 ? since / 1.6 : nil

        case .ting:
            // The wink's own 1.5s cycle, without needing a hover.
            //
            // Deliberately NOT eased at either end, and that is a decision
            // rather than an oversight: a wink and a twinkle both snap in
            // nature, which is the exemption `Ease`'s header and
            // `drawWinkGlint` already grant. Winking on the first frame after
            // you pick it is immediate feedback, which is the thing the
            // beacon's rest had to be shortened to get.
            guard frame.endedT == nil else { return }
            let cycle = frame.t.truncatingRemainder(dividingBy: 1.5)
            pose.winkEye = cycle < 0.22 ? .right : .none
            pose.winkGlint = cycle >= 0.22 && cycle < 0.40
            pose.mouth = .smile
            pose.blink = 0

        case .hearts:
            // A twenty-second hold on repeat: the opening pair, then the
            // refrain, which is the part worth judging. The wrap is silent —
            // the last birth is at 17.20 and it is finished by 18.50 — so one
            // loop of context is enough to carry a release.
            let loop = 20.0
            if let endedT = frame.endedT {
                guard frame.t - endedT < heartLife else { return }
                let base = (endedT / loop).rounded(.down) * loop
                pose.heartsElapsed = frame.t - base
                pose.heartsUntil = endedT - base
            } else {
                pose.heartsElapsed = frame.t.truncatingRemainder(dividingBy: loop)
            }
            // The face rides the same 0.35s attack the real hold does
            // (`Ease.amount`'s default), so selecting this does not slam his
            // eyes shut in the first frame. A blink is exempt from no-snap;
            // arriving already blinking is not a blink, it is a jump cut.
            let purr = Ease.smoothstep(frame.t / 0.35) * frame.release
            if purr >= 0.5 {
                pose.blink = 1
                pose.mouth = .smile
            }

        case .beacon:
            break       // composition layer; `PetRootView` draws it
        }
    }

    /// How far a glint has travelled across his shell, or nil. Idle only, on
    /// dice, 1.6 seconds of it about once every two and a half idle minutes.
    ///
    /// Idle rather than any mood, for the reason `thinkingProp`'s doc already
    /// gives: `MoodClock` rebases `t` on entry, so a cycle-0 dice roll in a
    /// short-lived mood is a constant, not a dice. Duty cycle 1.1%.
    static func shellGlint(idleT t: Double) -> Double? {
        let cycle = Int(floor(t / 60))
        guard cycle > 0, noise(cycle &* 83 &+ 13) < 0.4 else { return nil }
        let since = t - Double(cycle) * 60
        guard since < 1.6 else { return nil }
        return since / 1.6
    }

    /// The afternoon's light, and how far into its pass across the floor we
    /// are. Daylight only, and rarely — 14 seconds of it, eased two seconds at
    /// each end.
    ///
    /// The hour gate is doing two jobs. It is the obvious one, that light in
    /// the room happens in the daytime, and it is a **second independent lock
    /// on the frozen sentinel**: offline renderers pass no hour at all, so
    /// this cannot reach a committed asset even if its dice were to fire at
    /// cycle zero. `stargaze` earned the same lock for the same reason, and
    /// the two windows do not overlap — 8-17 against 23-04 — so the telescope
    /// and the sun can never want the same spell.
    ///
    /// Duty cycle: 0.25 × 14/420, about 3.3% of daylight idling, or one
    /// sighting every 28 minutes of it. Deliberately rarer than the bug (one
    /// per five idle minutes) because it is very much bigger on screen.
    static func sunPatch(idleT t: Double, hourOfDay: Int?) -> (amount: Double, phase: Double)? {
        guard let hourOfDay, hourOfDay >= 8, hourOfDay <= 17 else { return nil }
        let cycle = Int(floor(t / 420))
        guard cycle > 0, noise(cycle &* 73 &+ 5) < 0.25 else { return nil }
        let since = t - Double(cycle) * 420
        guard since < 14 else { return nil }
        return (Ease.window(since, duration: 14, edge: 2.0), since)
    }

    /// - Parameters:
    ///   - flourishes: when false the scheduled idle flourish is left off, so a
    ///     renderer can overlay one of its own choosing instead of whichever
    ///     one `flourish(at:)` happens to pick for that cycle.
    ///   - hourOfDay: the local hour, for the midnight stargazer. Offline
    ///     renderers pass nothing, so the telescope can never appear in a
    ///     committed asset by accident.
    static func pose(mood: PetMood, t: Double, flourishes: Bool,
                     hourOfDay: Int? = nil) -> CrabPose {
        var pose = CrabPose()
        pose.propPhase = t

        switch mood {
        case .idle:
            // A single-pixel breath. Anything larger reads as a bounce.
            pose.bob = sin(t * 1.6) > 0 ? 0 : 1
            pose.blink = blink(at: t)
            (pose.gazeX, pose.gazeY) = gaze(at: t)

            // His face shouldn't be a fixed grin — drop to flat now and then,
            // on a cycle unrelated to everything else so it feels incidental.
            if sin(t * 0.23) > 0.86 { pose.mouth = .flat }

            if flourishes, let (kind, progress) = flourish(at: t) {
                apply(kind, progress: progress, t: t, to: &pose)
            }

            // A second and a half of light across the shell. Not suppressed by
            // the sun or the telescope the way the bug and the balloon are —
            // it is a highlight ON him rather than a second thing to look at,
            // so it composes with either instead of competing.
            pose.glint = shellGlint(idleT: t)

            // Deep in the night, sometimes, the telescope comes out — and it
            // is evaluated FIRST because it owns the spell it appears in.
            //
            // All three ambient treats start on cycle boundaries and their
            // periods (90, 120, 150) share common multiples, so over a day
            // they begin on the same instant 57 times, three of them all
            // three at once. Most of those overlaps are harmless. Bug and
            // telescope is not: the bug puts his eyes on the floor and the
            // telescope puts them on the sky, and he cannot look at both.
            // De-phasing the schedules only takes 57 collisions to 40 —
            // with ~692 windows in a day the coincidence rate is intrinsic —
            // so the biggest, rarest, most composed moment simply wins.
            let gazing = stargaze(idleT: t, hourOfDay: hourOfDay)
            // …and in the afternoon, rarely, the light comes round instead.
            // The two cannot collide with each other — one wants 8-17 and the
            // other 23-04 — but either of them owns the spell it appears in,
            // for the same reason: he is absorbed in something, and a bug
            // arriving on top of it is clutter rather than life. Basking also
            // shuts his eyes, which a visitor he is supposed to be watching
            // would flatly contradict.
            let sun = sunPatch(idleT: t, hourOfDay: hourOfDay)

            if gazing == nil, sun == nil {
                if let float = idleBalloon(idleT: t) {
                    pose.prop = .mug
                    pose.propVisibility = float
                }

                // A visiting bug owns his attention: eyes drop to the floor
                // and follow it across.
                if let bug = bugPosition(idleT: t) {
                    pose.bugX = bug
                    pose.gazeX = bug < 14 ? -1 : (bug > 18 ? 1 : 0)
                    pose.gazeY = 1
                }
            }

            if let sun {
                pose.sunPatch = sun.amount
                pose.sunPatchPhase = sun.phase
                // One envelope, three consumers: the floor patch, the warm on
                // his shell in `composedTint`, and this — eyes easing shut on
                // a contented mouth.
                //
                // I tried the long-dead `Mouth.none` here, on the theory that
                // shut eyes are the one context where an absent mouth reads as
                // serenity rather than as a rendering fault. Rendered, it does
                // not: closed eyes AND no mouth leaves the face with no
                // information in it at all, and he reads as blank rather than
                // as blissful. He keeps the smile. `Mouth.none` stays unused,
                // which is the honest outcome — a slot with no use is better
                // than a use that looks broken.
                if sun.amount > 0.55 {
                    pose.blink = 1
                    pose.mouth = .smile
                }
            }

            if let gazing {
                pose.stargaze = gazing.amount
                pose.stargazePhase = gazing.phase
                // The gaze rides the envelope rather than a threshold. The
                // old `if amount > 0.4 { gazeY = -1 }` crossed at since ≈
                // 0.289, and because 120·cycle is divisible by three that
                // instant always fell inside `gaze()`'s live window — so
                // whenever the base roll had him looking DOWN, both eyes
                // jumped two rows in a single frame. Measured over a day of
                // idling: 81 of 244 firings, a third of them.
                // `moodMotionNeverTeleports` could not see it because it
                // checks only bob and lean and passes no hour, so the
                // telescope never came out in the test.
                let lead = Ease.smoothstep((gazing.amount - 0.25) / 0.45)
                pose.gazeY = Int((Double(pose.gazeY) + (-1 - Double(pose.gazeY)) * lead).rounded())
                pose.gazeX = Int((Double(pose.gazeX) + (1 - Double(pose.gazeX)) * lead).rounded())
                if gazing.amount > 0.4 { pose.mouth = .open }
            }

        case .thinking:
            pose.bob = sin(t * 3.0) > 0 ? 0 : 1
            pose.blink = blink(at: t, period: 3.2)
            // Eyes scanning side to side — the "working it out" tell.
            pose.gazeX = sin(t * 1.6) > 0 ? 1 : -1
            pose.mouth = .flat
            pose.prop = thinkingProp(at: t)
            applyPropDissolve(at: t, roll: { thinkingProp(at: $0) }, to: &pose)

        case .working:
            // Deliberately unhurried. At the original rates the arms and legs
            // flickered several times a second, which read as agitation and was
            // distracting in peripheral vision — the pet lives on the desktop
            // all day, so busy has to stay calm.
            pose.bob = sin(t * 2.2) > 0 ? 0 : 1
            pose.blink = blink(at: t, period: 4.0)
            pose.gazeY = 1                       // looking down at the work
            // Arms alternate like hands on a keyboard, about one beat a second.
            // Eased square: same rhythm as the old hard flip, no cliff.
            let beat = Ease.square(t * 2.6)
            pose.armLeft = 0.35 * beat
            pose.armRight = 0.35 * (1 - beat)
            pose.legPhase = t * 2.4
            pose.legAmplitude = 1
            pose.prop = workingProp(at: t)
            applyPropDissolve(at: t, to: &pose)

        case .cooking:
            // Head down, working fast, on fire. Quicker than `.working` but not
            // frantic — this is flow, not panic.
            pose.bob = sin(t * 3.4) > 0 ? 0 : 1
            pose.blink = blink(at: t, period: 5.0)
            pose.eyes = .determined
            pose.gazeY = 1
            pose.mouth = .flat
            let sprint = Ease.square(t * 4.2)
            pose.armLeft = 0.4 * sprint
            pose.armRight = 0.4 * (1 - sprint)
            pose.legPhase = t * 4
            pose.legAmplitude = 1
            pose.prop = .fire
            // Sometimes the heat gets into the shell: a banded cascade sweeps
            // up the body for a couple of seconds, on dice that skip more
            // cycles than they hit. Never in the first cycle — a frozen render
            // at t=0 must show a cool crab.
            let heatCycle = Int(floor(t / 8))
            if heatCycle > 0, noise(heatCycle &* 29 &+ 11) < 0.45 {
                let sinceCycle = t - Double(heatCycle) * 8
                pose.heat = Ease.window(sinceCycle, duration: 2.4, edge: 0.4)
                pose.heatPhase = sinceCycle / 1.2
            }

        case .nudging:
            // Expectant: leaning your way, eyes wide, one arm out holding the
            // plan, tapping a foot. Pointedly not the frantic wave of
            // `.needsAttention` — he is waiting, not alarmed.
            // Two pixels of travel around the rest line rather than a single
            // dip below it, and stepping through the middle pixel so it reads
            // as a bob rather than a blink. A question deserves to be seen:
            // one pixel, once every three and a half seconds, was a motion you
            // had to already be looking at to notice.
            pose.bob = Int((sin(t * 2.2) * 1.4).rounded())
            pose.lean = 1
            pose.eyes = .wide
            pose.blink = blink(at: t, period: 4.5)
            pose.gazeY = -1                       // looking up at you
            pose.mouth = .smile
            pose.armRight = 0.5                   // holding the plan out
            pose.armLeft = 0
            // No tilt. `.wide` already draws each eye a row taller and a row
            // higher; adding a tilt that shifts the two eyes in OPPOSITE
            // directions put them two rows apart, which reads as a broken face
            // rather than an inquisitive one. The lean carries the question.
            // One foot taps: a small, single-leg motion rather than a walk.
            // Gated trapezoid rather than a hard threshold — the tap keeps its
            // impatient duty cycle but lands and lifts instead of teleporting.
            pose.legPhase = .pi / 2
            pose.legAmplitude = Ease.gate(sin(t * 5), above: 0.4, soft: 0.25)
            pose.prop = .plan

        case .done:
            // Both arms up, holding the green check. One decaying hop.
            let hop = max(0, 1 - t / 1.2)
            // An arc, decaying, that touches every pixel it passes. The old
            // form jumped straight to -2 and back on a threshold, which is a
            // two-pixel snap — the one thing the rig is not allowed to do.
            pose.bob = -Int((max(0, sin(t * 5)) * 2 * hop).rounded())
            pose.armLeft = 1
            pose.armRight = 1
            pose.mouth = .open
            pose.prop = .check
            pose.blink = blink(at: t, period: 4.0)

        case .needsAttention:
            // Waving, bouncing, and shouting. Has to read across a room, so
            // this one stays quick — it is the only state that wants urgency.
            // Three pixels of lift, and it LANDS on every pixel on the way up
            // and down. The old form teleported between 0 and -2 on a hard
            // threshold: two pixels in one frame is a snap, and a snap that
            // fast reads as a flicker rather than a bounce — which is the
            // opposite of carrying across a room.
            pose.bob = -Int((((sin(t * 4.0) + 1) / 2) * 3).rounded())
            // Through upright, not across it: flipping -1 to 1 moved him two
            // pixels in a frame, so the "wave" was really a shudder.
            pose.lean = Int((sin(t * 3.2) * 1.4).rounded())
            // Eased, because `drawArm` quantises this to whole cells: a hard
            // flip between 0.7 and 1.0 moves the drawn reach from four cells to
            // six in a single frame, three times a second. The eased square
            // keeps the impatient duty cycle and lands on five on the way.
            let wave = Ease.square(t * 5.5)
            pose.armLeft = 0.7 + 0.3 * wave
            pose.armRight = 1.0 - 0.3 * wave
            pose.mouth = .open
            pose.prop = .bang

        case .sleeping:
            // A two-pixel breath, eased, so he HOLDS the top and the bottom
            // and steps through the middle — three depths on a grid with one
            // axis to spend. The old one-pixel square wave spent 85% of its
            // cycle on a single value, which is why `sleeping.gif` was 41
            // pixel-identical frames out of 48.
            //
            // Phase-shifted by a quarter turn so t=0 is the TOP of the breath
            // rather than halfway down it. That instant is not arbitrary: it
            // is where the sizzle's wake chapter opens, and t=0.4 is where
            // `still-sleeping.png` is sampled.
            pose.bob = Int((Ease.square(t * 2 * .pi / breathPeriod - .pi / 2,
                                        soft: 1.0) * 2).rounded())
            pose.blink = 1                        // eyes shut
            // Lids at the floor of the socket rather than across its middle:
            // "asleep, not switched off", costing no motion at all, and the
            // only thing carrying the read in the STILL where the breath
            // cannot help.
            //
            // This was a one-pixel head tilt until the operator reported it as
            // a broken eye, and they were right. A shut lid is one pixel tall,
            // so tilting the pair left two thin bars two rows apart — rendered
            // and measured at rows 13 and 15, a two-pixel gap on a
            // thirty-two-pixel sprite, in 100% of sleeping frames. Nothing
            // about that reads as a tipped head. Both lids drop together now.
            pose.lidsLowered = true
            pose.mouth = .flat
            // The zZz's ride the same clock as the breath, so a glyph is
            // released on an exhale rather than drifting against him. Denser
            // after dark; see `sleepZInterval`.
            pose.sleepZElapsed = t
            pose.sleepZInterval = sleepZInterval(hourOfDay: hourOfDay)
        }

        return pose
    }

    /// The playful things he does when you put the pointer on him.
    public enum Greeting: CaseIterable {
        case wave, wink, hop, wiggle
    }

    /// Which reaction a given seed selects. Exposed so the renderers can show
    /// each variant rather than whichever one a seed happens to pick.
    public static func greeting(forSeed seed: Int) -> Greeting {
        let variants = Greeting.allCases
        return variants[Int(noise(seed) * Double(variants.count)) % variants.count]
    }

    /// He notices you.
    ///
    /// Layered on top of whatever mood pose was already computed, so hovering a
    /// working Claw'd still shows his prop — he just looks up from it. Even
    /// asleep he stirs, which is the whole charm of poking a pet.
    ///
    /// - Parameters:
    ///   - elapsed: seconds since the pointer arrived.
    ///   - seed: picks the variant. Comes from the hover's start time, so it is
    ///     chosen once per hover — `Double.random` here would re-roll the
    ///     reaction 20-30 times a second.
    ///   - amount: the reaction envelope, 0…1. Rises when the pointer arrives
    ///     and falls after it leaves, so the greeting eases out through the
    ///     same shapes it eased in through instead of vanishing in one frame.
    ///     Continuous channels scale by it; discrete flips gate at 0.4.
    ///   - variant: names the reaction outright, for callers that want a
    ///     PARTICULAR one rather than whichever the seed lands on. `nil` keeps
    ///     the seed's answer, which is what hovering wants.
    ///
    ///     The alternative was searching for a seed that happens to resolve to
    ///     the wanted variant — `GifRenderer` does exactly that, five hundred
    ///     iterations of it, and that search is the reason this parameter
    ///     exists. Asking for `.wave` should not require solving for `.wave`.
    public static func applyGreeting(elapsed: Double, seed: Int = 0,
                                     amount: Double = 1,
                                     variant: Greeting? = nil,
                                     to pose: inout CrabPose) {
        guard amount > 0.001 else { return }
        let greeting = variant ?? greeting(forSeed: seed)
        let engaged = amount >= 0.4

        // A startled hop on arrival, common to every variant — he noticed you.
        if elapsed < 0.30 {
            pose.bob -= Int((3 * amount).rounded())
            pose.squash = 0
        } else if elapsed < 0.42 {
            pose.squash = engaged ? 1 : pose.squash
            pose.bob += engaged ? 1 : 0
        }

        if engaged {
            pose.asleepOverride = true  // eyes open even in the sleeping pose
            pose.gazeX = 0
            pose.gazeY = -1             // looking up, out of the screen at you
        }

        switch greeting {
        case .wave:
            if engaged {
                pose.blink = 0
                pose.mouth = .open
            }
            pose.armRight = max(pose.armRight, (0.55 + (sin(elapsed * 8) > 0 ? 0.25 : 0)) * amount)

        case .wink:
            // Routed through `winkEye` rather than `blink`, which
            // `asleepOverride` vetoes.
            if engaged {
                pose.mouth = .smile
                pose.blink = 0
                // A wink is a brief shut, not a held one. The first version used
                // `sin(elapsed * 2.2) > -0.3`, which keeps the eye closed for
                // about three quarters of every cycle — that does not read as a
                // wink, it reads as an eye that is stuck.
                let cycle = elapsed.truncatingRemainder(dividingBy: 1.5)
                pose.winkEye = cycle < 0.22 ? .right : .none
                // …and the wink tings as it OPENS. No schedule of its own: it
                // rides the cycle the wink already computes, on the far side
                // of the shut.
                pose.winkGlint = cycle >= 0.22 && cycle < 0.40
                // No tilt here. Tilt offsets the two eyes by a pixel in opposite
                // directions, and against a one-row shut eye that misalignment
                // is exactly what made the wink look wonky.
                pose.tilt = 0
            }
            pose.armRight = max(pose.armRight, 0.35 * amount)

        case .hop:
            if engaged {
                pose.mouth = .open
                pose.blink = 0
            }
            // A repeating little bounce for as long as you stay.
            let bounce = abs(sin(elapsed * 4))
            pose.bob -= Int((bounce * 3 * amount).rounded())
            pose.squash = (bounce < 0.15 && engaged) ? 1 : pose.squash
            pose.legAmplitude = max(pose.legAmplitude, 1.2 * amount)
            pose.legPhase = .pi / 2

        case .wiggle:
            if engaged {
                pose.mouth = .smile
                pose.blink = 0
                pose.lean += sin(elapsed * 9) > 0 ? -1 : 1
            }
            pose.armLeft = max(pose.armLeft, 0.3 * amount)
            pose.armRight = max(pose.armRight, 0.3 * amount)
        }
    }

    /// A heart's whole life: `Ease.pulse`'s attack + hold + decay.
    static let heartLife = 1.30

    /// Two hearts greet the purr, then one every four seconds.
    private static let heartOpening = [0.30, 1.20]
    private static let heartRefrainStart = 5.20
    private static let heartRefrain = 4.00

    /// How visible a heart is `age` seconds after its birth.
    ///
    /// `Ease.pulse` rather than a linear fade because it is **zero outside
    /// its own window**, at both ends. The old heart used `1 - age/1.6`,
    /// which is 1 at age zero — every cell appeared in one frame — and was
    /// then deleted by a bounds guard at 0.25 visibility. It had an ease at
    /// neither end.
    static func heartVisibility(age: Double) -> Double {
        Ease.pulse(age, attack: 0.15, hold: 0.25, decay: 0.90)
    }

    /// Which row a heart of this age sits on. One row per 0.20s from the
    /// crown at y=8, so a whole life is six rows and the last one is y=2 —
    /// the envelope closes with two rows of grid still to spare. The old rate
    /// asked for 8.7 rows of travel out of seven rows of airspace, and that
    /// mismatch is what forced the bounds guard that did the deleting.
    static func heartRow(age: Double) -> Int { 8 - Int(age / 0.20) }

    /// Which hearts are in the air `elapsed` seconds into a hold, as
    /// (ordinal, birth) pairs. The ordinal is permanent and unbounded — it
    /// picks the column and the dissolve, so it must not recycle.
    ///
    /// The old table was three onsets on a 2.4s modulo: a heart every 0.8s,
    /// forever, thirty-eight of them in a half-minute hold. It was the only
    /// sprite overlay in the app with no gate of any kind, which is exactly
    /// why it read as constant rather than as affection.
    ///
    /// The rarity here is spacing, not chance, and that is deliberate.
    /// Petting is something you choose to do; a dice that answers a
    /// three-second hold with nothing at all punishes the one interaction
    /// the operator goes looking for. Dice belong on the things that happen
    /// *to* you — the bug, the balloon, the telescope. So the first two
    /// hearts are guaranteed and land inside a second and a half, and the
    /// refrain that follows is what stops a long hold being a fountain:
    /// 1s → 1 heart, 3s → 2, 10s → 4, 30s → 9.
    /// `until` is when the hold ended, if it has: no heart is born after it,
    /// but the ones already climbing are still returned until they finish.
    static func heartSpawns(elapsed: Double, until: Double? = nil) -> [(ordinal: Int, born: Double)] {
        let lastBirth = min(elapsed, until ?? elapsed)
        var spawns: [(ordinal: Int, born: Double)] = []
        for (index, born) in heartOpening.enumerated() where born < lastBirth {
            spawns.append((index, born))
        }
        if lastBirth > heartRefrainStart {
            let beats = Int((lastBirth - heartRefrainStart) / heartRefrain)
            for beat in 0...beats {
                spawns.append((heartOpening.count + beat,
                               heartRefrainStart + Double(beat) * heartRefrain))
            }
        }
        // Only the ones still in the air; the rest have finished dissolving.
        return spawns.filter { elapsed - $0.born < heartLife }
    }

    // MARK: - Sleep

    /// How long one zZz lives, birth to gone.
    ///
    /// Short, and the shortness is load-bearing. `sleeping.gif` is exactly one
    /// breath long and has to LOOP: `theSleepingClipIsOneWholeBreath` renders
    /// t=0 and t=breathPeriod and demands the two be pixel-identical. A glyph
    /// still in the air when the clip ends is a seam, so a zZz must be born
    /// and gone inside a single breath — life plus its birth offset has to
    /// clear the interval, at BOTH densities.
    ///
    /// The first attempt ran 3s on a 2.5s spacing and broke that test, which
    /// is how the constraint was found rather than assumed.
    static let sleepZLife = 2.00

    /// Where a zZz sits `age` seconds after it left him.
    ///
    /// Slower than the hearts'. Hearts are excitement and should climb; this
    /// is breathing, and a glyph that hurries reads as steam.
    ///
    /// Five rows of travel, 8 down to 3 — deliberately NOT out of the frame.
    /// An earlier version ran 9 to 0 and the glyph was still solid when it met
    /// the top edge, so every zZz ended as a half-drawn fragment sliced by the
    /// sprite boundary. It runs out of life before it runs out of sky.
    static func sleepZRow(age: Double) -> Int { 8 - Int(age / 0.34) }

    /// Seconds between zZz's, by the clock on the wall.
    ///
    /// One every OTHER breath by day, two a breath after dark — the operator's
    /// tamagotchi ruling: a daytime nap is light dozing, and its z's should
    /// whisper. All three values are whole multiples or divisions of
    /// `breathPeriod`, so a glyph is always released on the same phase of the
    /// breath rather than drifting against the body it came from.
    ///
    /// **22:00–06:00**, the hours the operator asked for, and the same shape
    /// `stargaze` (23–04) and `sunPatch` (08–17) already use.
    ///
    /// `nil` — every offline render — pins the RENDER density: one z per
    /// breath, the density every committed byte of `sleeping.gif` was
    /// compared at. It stopped meaning "daytime" the day live-day backed off
    /// to whispering; it means "the clock the renderers do not have", and if
    /// it ever tracks the live day again the committed media re-densifies on
    /// its next regeneration, which is the one thing a byte-compared asset
    /// cannot survive.
    static func sleepZInterval(hourOfDay: Int?) -> Double {
        guard let hourOfDay else { return breathPeriod }
        if hourOfDay >= 22 || hourOfDay < 6 { return breathPeriod / 2 }
        return breathPeriod * 2
    }

    /// How far into its interval a zZz is released, as a fraction.
    ///
    /// Not zero, for two reasons that happen to want the same number. The
    /// frozen sentinel forbids anything mid-flight at t=0, where
    /// `still-sleeping.png` and the sizzle's wake chapter are both sampled.
    /// And the loop needs the glyph dead before the interval ends —
    /// `0.16 * interval + sleepZLife` clears both 5.0 and 2.5 with room.
    private static let sleepZOnset = 0.16

    /// Which zZz's are in the air at mood-clock time `t`, as (ordinal, birth)
    /// pairs. The ordinal is permanent and picks the column and the shape, so
    /// it must not recycle — the same contract `heartSpawns` keeps.
    static func sleepZSpawns(t: Double, interval: Double) -> [(ordinal: Int, born: Double)] {
        guard t > 0, interval > 0 else { return [] }
        let onset = interval * sleepZOnset
        let newest = Int(floor((t - onset) / interval))
        guard newest >= 0 else { return [] }
        let oldest = max(0, newest - Int((sleepZLife / interval).rounded(.up)))
        return (oldest...newest)
            .map { (ordinal: $0, born: onset + Double($0) * interval) }
            .filter { $0.born <= t && t - $0.born < sleepZLife }
    }

    /// Being petted: eyes ease shut, a purr wiggle, and hearts. Applied after
    /// the greeting so a hold wins over a hover — you cannot pet him and be
    /// waved at simultaneously.
    public static func applyPetting(elapsed: Double, amount: Double,
                                    until: Double? = nil, to pose: inout CrabPose) {
        // The hearts run on the latch, NOT on the purr envelope, and they are
        // written before the envelope guard on purpose. A heart born just
        // before you let go still has a life to finish, and the envelope is
        // closed 0.45s after the release — gating the hearts on it deleted
        // every one in the air in a single frame.
        if let until {
            if elapsed - until < heartLife {
                pose.heartsElapsed = elapsed
                pose.heartsUntil = until
            }
        } else {
            pose.heartsElapsed = elapsed
        }

        guard amount > 0.001 else { return }
        if amount >= 0.5 {
            pose.blink = 1
            pose.asleepOverride = false
            pose.winkEye = .none
            pose.mouth = .smile
            pose.lean += Ease.square(elapsed * 2.5) > 0.5 ? 1 : -1
        }
        pose.armLeft = max(pose.armLeft, 0.2 * amount)
        pose.armRight = max(pose.armRight, 0.2 * amount)
    }

    /// The pounce after a bug is caught: crouch toward the floor, one hop, a
    /// check dissolving in and out. 1.4s, eased at both ends.
    public static func applyPounce(elapsed: Double, to pose: inout CrabPose) {
        let envelope = Ease.window(elapsed, duration: 1.4, edge: 0.25)
        guard envelope > 0.001 else { return }
        pose.gazeY = 1
        pose.mouth = .open
        if elapsed < 0.3 {
            pose.squash = 1                                  // the crouch
        } else if elapsed < 0.8 {
            pose.bob -= Int((sin((elapsed - 0.3) / 0.5 * .pi) * 3).rounded())
        } else {
            pose.squash = elapsed < 0.95 ? 1 : 0             // the landing
        }
        pose.prop = .check
        pose.propVisibility = min(pose.propVisibility, envelope)
    }

    /// The shrimp snack, 2.8s: he stirs, munches three beats, and settles. The
    /// shrimp itself is drawn by the rig off `snackElapsed`.
    public static func applySnack(elapsed: Double, to pose: inout CrabPose) {
        let envelope = Ease.window(elapsed, duration: 2.8, edge: 0.4)
        guard envelope > 0.001 else { return }
        pose.asleepOverride = true
        pose.snackElapsed = elapsed
        pose.gazeX = -1                                       // eyeing the shrimp
        // Munch: mouth flips on each bite beat, eased square between.
        let munching = elapsed > 0.7 && elapsed < 2.3
        pose.mouth = munching && Ease.square(elapsed * 2 * .pi) > 0.5 ? .open : .smile
        // One happy hop at the end.
        if elapsed > 2.3, elapsed < 2.55 {
            pose.bob -= 2
        }
    }

    /// The extended payoff after a cooking sprint lands (the game-design
    /// trick: the work is done, the reward runs longer). Layered over the
    /// normal done pose for ~10s under one master envelope — scale breathing
    /// about a pixel deep, and the done hop re-armed twice — then the
    /// envelope's tail cools everything back to a plain done before the mood
    /// decays away.
    public static func applyCelebration(t: Double, epic: Bool = false, to pose: inout CrabPose) {
        let envelope = Ease.window(t, duration: 10, edge: 0.6)
        guard envelope > 0.001 else { return }

        pose.scale = min(pose.scale, 1 - 0.04 * envelope * (0.5 + 0.5 * sin(t * 2.5)))

        // The two re-armed hops, on the same arc the base `.done` hop was
        // rewritten to use. They kept the old shape — a threshold that put him
        // two pixels off the floor in one frame and back the same way — which
        // is the snap the rest of the rig is not allowed. A floor-merge still,
        // so a poke or a greeting can deepen it.
        for start in [3.5, 7.0] {
            let hop = t - start
            if hop >= 0, hop < 1.2 {
                pose.bob = min(pose.bob, -Int((max(0, sin(hop * 5)) * 2).rounded()))
            }
        }

        if epic {
            // The transform: he grows a fifth through the crown rows and
            // settles back, eased at both ends. The overhead check dissolves
            // away for the peak — at 1.2x it renders as a mangled fragment
            // cropped by the grid's edge, and a missing prop reads better
            // than a broken one.
            let peak = Ease.window(t - 1.2, duration: 2.2, edge: 0.8)
            pose.scale *= 1 + 0.2 * peak
            pose.propVisibility = min(pose.propVisibility, 1 - peak)
        }
    }

    /// The peak of the epic transform at `t`, exposed for the tint composer
    /// and the tests — one envelope, two consumers.
    static func epicPeak(doneT t: Double) -> Double {
        Ease.window(t - 1.2, duration: 2.2, edge: 0.8)
    }

    /// The poke reaction: he squashes down, then springs back.
    ///
    /// - Parameter elapsed: seconds since the click.
    public static func applyClick(elapsed: Double, to pose: inout CrabPose) {
        guard elapsed >= 0, elapsed < clickDuration else { return }
        let progress = elapsed / clickDuration
        // Down fast, back slower — a spring, not a dip. Each leg of the ramp is
        // smoothstepped so the compression arrives and releases without a corner.
        let compression = progress < 0.35
            ? Ease.smoothstep(progress / 0.35)
            : Ease.smoothstep(max(0, 1 - (progress - 0.35) / 0.65))
        // Multiplicative, never assignment: a click mid-transform must dent
        // the current scale, not snap a 1.2x finale back to 1 in one frame.
        pose.scale *= 1 - 0.22 * compression
        pose.squash = compression > 0.5 ? 1 : 0
        pose.mouth = .open
    }

    public static let clickDuration = 0.34

    // MARK: - The rude awakening

    /// Phase A: one claw eases out while he is demonstrably still asleep.
    public static let rudeWakeArmRise = 0.5
    /// Phase B: eyes open, annoyed, at you — still in bed.
    public static let rudeWakeHold = 0.7
    /// Phase C: everything eases back out while the mood gets him up.
    public static let rudeWakeRelease = 0.5
    /// The whole sequence; the latch's clear-out waits a beat past this.
    public static let rudeWakeDuration = 1.7
    /// The instant the eyes snap open — the end of phase A, by construction.
    static let rudeWakeEyesOpenAt = 0.5

    /// The tamagotchi wake: poke a sleeping crab and he does not squeal and
    /// open the roster — he stretches one claw out from under the covers, a
    /// zzz still rising, and then opens his eyes ANNOYED at you.
    ///
    /// Three contracts, each carried by a mechanism rather than a hope:
    ///
    /// - **The z's survive phase A and B.** The coordinator's stir is
    ///   deferred by the caller, so the base pose stays `.sleeping` and keeps
    ///   its `sleepZElapsed` channel — this overlay deliberately never
    ///   touches it. Arm out WITH a zzz aloft is the operator's picture.
    /// - **The annoyed face is pre-seeded from t=0.** `.determined` eyes and
    ///   a `.flat` mouth are set through every phase — invisible while the
    ///   lids are shut, and it makes the mood blend's discrete midpoint
    ///   switch a no-op when the wake hands over to idle: both ends already
    ///   agree, so nothing swaps mid-crossfade.
    /// - **It closes itself.** One `Ease.pulse` envelope, zero at t ≤ 0 (the
    ///   frozen sentinel comes free) and back under 0.001 past 1.7s, so a
    ///   stale latch can strand nothing on his face.
    public static func applyRudeWake(elapsed: Double, to pose: inout CrabPose) {
        let amount = Ease.pulse(elapsed, attack: rudeWakeArmRise,
                                hold: rudeWakeHold, decay: rudeWakeRelease)
        guard amount > 0.001 else { return }
        // The claw, out at the poker — eased across drawArm's six-cell
        // quantisation, one cell per frame at 30fps. `max` so a live hover
        // greeting's wave composes instead of fighting.
        pose.armRight = max(pose.armRight, 0.75 * amount)
        pose.eyes = .determined
        pose.mouth = .flat
        if elapsed < rudeWakeEyesOpenAt {
            // Phase A: still asleep, and DEMONSTRABLY so — the pointer was on
            // him before the click, so a hover greeting may already have set
            // `asleepOverride`; the poke re-shuts the eyes. That one-frame
            // shut is a blink, the one snap the no-snap rule exempts.
            pose.asleepOverride = false
            pose.blink = 1
            pose.winkEye = .none
            pose.lidsLowered = true
        } else if amount >= 0.4 {
            // Phase B and most of C: eyes open, annoyed, up and at you.
            pose.asleepOverride = true
            pose.blink = 0
            pose.lidsLowered = false
            pose.gazeX = 0
            pose.gazeY = -1
            // A one-pixel startle on the instant the eyes open — the grid's
            // own quantum, explicitly allowed.
            if elapsed < rudeWakeEyesOpenAt + 0.12 { pose.bob -= 1 }
        }
    }

    // MARK: - The deal-with-it drop

    /// The fall, in seconds. At 30fps a 16-row smoothstep fall peaks at two
    /// rows per frame — the grid's own quantum, twice; if review calls it
    /// chunky the retreat is 0.7, never an easing change.
    public static let shadesDropDuration = 0.5
    /// One row of overshoot on touchdown, then settle — the sticker bounce.
    static let shadesOvershootBeat = 0.12
    /// The exit dissolve, matched to `propFade` so leaving reads like every
    /// other prop swap.
    public static let shadesFade = 0.35

    /// Rows still to fall at `elapsed`: −16 (the print's top line at row −4,
    /// fully off-sprite) easing to 0, a +1 overshoot beat, then rest.
    nonisolated static func shadesDropRows(elapsed: Double) -> Int {
        if elapsed < shadesDropDuration {
            let u = Ease.smoothstep(elapsed / shadesDropDuration)
            return -16 + Int((16 * u).rounded())
        }
        if elapsed < shadesDropDuration + shadesOvershootBeat { return 1 }
        return 0
    }

    /// A fun fact dropped the MLG shades on him.
    ///
    /// The pair falls OPAQUE from above — the fall is the whole gag, and a
    /// dissolving fall is neither a drop nor a dissolve — and leaves through
    /// the standard prop fade. Whatever the mood already had in the prop slot
    /// (the working terminal, the reading glasses, the idle mug) steps into
    /// the ghost channel and pixel-dissolves out for the fact's stay, then
    /// back in as the shades leave: `applyPropDissolve`'s own contract,
    /// borrowed whole. On a dinging showing, the four-point sparkle sits at
    /// the temple for the beat after touchdown.
    static func applyShadesDrop(elapsed: Double, endedElapsed: Double?,
                                ding: Bool, to pose: inout CrabPose) {
        guard elapsed >= 0 else { return }
        let exit = endedElapsed.map { Ease.clamp01(1 - $0 / shadesFade) } ?? 1
        guard exit > 0.001 else { return }
        let landed = Ease.clamp01(elapsed / shadesDropDuration)
        if pose.prop != .none, pose.prop != .shades {
            pose.ghostProp = pose.prop
            pose.ghostPropPhase = pose.propPhase
            pose.ghostPropVisibility = max(pose.ghostPropVisibility,
                                           min(pose.propVisibility,
                                               1 - min(landed, exit)))
        }
        pose.prop = .shades
        pose.propVisibility = exit
        pose.shadesDrop = shadesDropRows(elapsed: elapsed)
        if ding, endedElapsed == nil,
           elapsed >= shadesDropDuration, elapsed < shadesDropDuration + 0.3 {
            pose.shadesGlint = true
        }
    }

    /// The idle pose with `kind` overlaid, `t` seconds into the flourish.
    ///
    /// Past `kind.duration` the flourish is over and plain idle comes back, so a
    /// rendered loop can hold a beat of quiet before it repeats — which is what
    /// the live schedule does between windows.
    ///
    /// `t` is flourish-relative here where live it is absolute, so the
    /// oscillating ones start at a fixed phase rather than an arbitrary one.
    /// `jumpPose` has always made that trade.
    static func flourishPose(_ kind: Flourish, at t: Double) -> CrabPose {
        var pose = pose(mood: .idle, t: t, flourishes: false)
        if t < kind.duration {
            apply(kind, progress: t / kind.duration, t: t, to: &pose)
        }
        return pose
    }

    /// The jump at a given point in its arc, for the contact sheet.
    static func jumpPose(progress: Double) -> CrabPose {
        var pose = CrabPose()
        apply(.jump, progress: progress, t: progress * Flourish.jump.duration, to: &pose)
        return pose
    }

    /// Overlays a flourish onto the idle pose. `progress` runs 0…1 across the
    /// flourish's own duration, so each one is authored as a shape rather than
    /// as a frequency.
    private static func apply(_ kind: Flourish, progress: Double, t: Double, to pose: inout CrabPose) {
        switch kind {
        case .cruise:
            // He does not jump and he does not go anywhere. Every other skate
            // beat is him doing something to the board; this one is him simply
            // moving fast, which on a fixed camera means the GROUND moves and
            // he does not.
            pose.prop = .skateboardRoll
            pose.propVisibility = 1
            pose.propPhase = progress
            // Leaning into it, eyes forward. He is not watching anything leave
            // any more — he is the one travelling.
            if progress > 0.2 {
                pose.lean = 1
                pose.gazeX = 1
            }
            if progress > 0.4 { pose.mouth = .open }

        case .kickflip, .varialFlip:
            // Roll, pop, one full turn of the board, land it.
            //
            // Two tricks, one shape: the airtime and the pop are identical and
            // only the board differs, which is exactly right — a kickflip and
            // an impossible are the same jump with the deck doing something
            // else underneath you.
            //
            // The board is a WORN prop, which is the whole trick: worn props
            // travel with `bob`, so when he leaves the ground it goes with him.
            // A board that stayed on the floor while he jumped would not be a
            // kickflip, it would be him falling off.
            //
            // `propPhase` carries the turn, 0 to 1 across the airtime, and one
            // whole turn lands deck-down — which is what a kickflip IS, and why
            // the phase must reach exactly 1 rather than stopping short.
            pose.prop = kind == .kickflip ? .skateboard : .skateboardVarial
            pose.propVisibility = 1
            // Set on EVERY branch, never left to the caller. The idle pose he
            // is layered onto carries its own `propPhase` for its own prop, and
            // inheriting it renders the board at some arbitrary angle — which
            // is exactly what the first contact sheet showed: a flat deck while
            // rolling, then a sliver on the crouch, for no reason a viewer
            // could see.
            pose.propPhase = 0
            if progress < 0.15 {
                pose.squash = 1                       // load the pop
                pose.bob = 1
            } else if progress < 0.80 {
                let air = (progress - 0.15) / 0.65
                pose.bob = -Int((sin(air * .pi) * 9).rounded())
                pose.legAmplitude = 1.6               // legs tuck out of the way
                pose.legPhase = .pi / 2
                pose.blink = 0
                // The scrunch is the POP, not the whole trick. Held across the
                // entire airtime it stopped being an expression and became his
                // face — and it also hid the thing worth watching, since a crab
                // squinting through his own kickflip is not looking at it. He
                // screws his eyes up as he snaps the board, then opens them for
                // the rotation and the landing.
                if air < 0.25 { pose.eyes = .squint }  // >_< , off the stickers
                pose.mouth = .open
                pose.propPhase = air
            } else {
                pose.squash = 1                       // stomp it
                pose.bob = 1
                pose.mouth = .open
            }

        case .ollie:
            // The sticker ollie: a big floating one, nose high, board stuck to
            // his feet, arms riding the balance the whole way up and down.
            //
            // Same worn-prop trick as the flips — the board travels with `bob`
            // — but the arc is different on purpose. A flip's air is a sine:
            // up, over, down. This one flattens the top of that sine
            // (`pow 0.55`) so he spends most of the air NEAR the apex, which
            // is what "floating" is; the flips get through their air in the
            // time this one spends arriving at the top of it.
            //
            // The arms are the sticker's other half: not tucked like the jump,
            // but OUT, front arm high and back arm low, wobbling gently in
            // counterphase like he is surfing the hang. Eyes squint through
            // the pop, then open wide for the whole float — this trick is for
            // enjoying, not surviving.
            pose.prop = .skateboardOllie
            pose.propVisibility = 1
            pose.propPhase = 0
            if progress < Self.ollieAirStart {
                pose.squash = 1                       // load the pop
                pose.bob = 1
            } else if progress < Self.ollieAirStart + Self.ollieAirSpan {
                let air = (progress - Self.ollieAirStart) / Self.ollieAirSpan
                let hang = pow(sin(air * .pi), 0.55)  // flat-topped: the float
                pose.bob = -Int((hang * 10).rounded())
                pose.legAmplitude = 1.6
                pose.legPhase = .pi / 2
                pose.blink = 0
                pose.propPhase = air
                if air < 0.18 {
                    pose.eyes = .squint               // the snap
                } else {
                    // Balance arms, breathing in counterphase through the hang.
                    let sway = sin(t * 5)
                    pose.armRight = 0.7 + 0.25 * sway
                    pose.armLeft = 0.35 - 0.2 * sway
                    pose.gazeX = 1                    // eyes down the line
                }
                pose.mouth = .open
            } else {
                pose.squash = 1                       // stomp it flat
                pose.bob = 1
                pose.mouth = .open
            }

        case .jump:
            // Crouch, launch, arc, land heavy.
            if progress < 0.16 {
                pose.squash = 1                       // anticipation
                pose.bob = 1
            } else if progress < 0.82 {
                let air = (progress - 0.16) / 0.66    // 0…1 across the arc
                let height = sin(air * .pi) * 5
                pose.bob = -Int(height.rounded())
                pose.legAmplitude = 1.6               // legs tuck at the apex
                pose.legPhase = .pi / 2
                pose.armLeft = 0.4
                pose.armRight = 0.4
                pose.blink = 0
            } else {
                pose.squash = 1                       // landing
                pose.bob = 1
                pose.mouth = .open
            }

        case .wave:
            pose.armRight = 0.75 + (sin(t * 7) > 0 ? 0.25 : 0)
            pose.mouth = .open
            pose.gazeX = 1

        case .wiggle:
            pose.lean = sin(t * 7) > 0 ? -1 : 1
            pose.mouth = .smile

        case .stretch:
            // Reach up, hold, come down.
            let reach = sin(min(1, progress) * .pi)
            pose.armLeft = reach
            pose.armRight = reach
            pose.bob = reach > 0.6 ? -1 : 0
            pose.mouth = .flat

        case .lookAround:
            pose.gazeX = sin(t * 1.8) > 0 ? 1 : -1
            pose.gazeY = progress > 0.5 ? 1 : 0

        case .scuttle:
            // A couple of steps one way, then back.
            pose.legPhase = t * 6
            pose.legAmplitude = 1.4
            pose.lean = progress < 0.5 ? -1 : 1
        }
    }
}

/// Claw'd himself, animating continuously off the display link.
/// `@MainActor` written down rather than inferred — see the note on
/// `PetRootView`. The pure schedules (the tints, the flash bursts) are
/// `nonisolated` beneath it, because they are functions of a clock reading
/// and nothing else.
@MainActor
public struct CrabView: View {
    public var mood: PetMood
    /// The wardrobe. Costume changes cross-dissolve via `CostumeClock`.
    public var costume: Costume = .none
    /// A cooking sprint just landed — the done pose plays its extended payoff.
    public var celebrating: Bool = false
    /// …after cooking a while: the payoff is the full finale.
    public var epicCelebration: Bool = false
    /// The focused session's todo completion, for the near-done glow.
    public var taskFraction: Double?
    /// Reference-time instant the pointer arrived on him, or nil.
    public var hoverSince: Double?
    /// Reference-time instant the pointer left, while the greeting eases out.
    /// `hoverSince` stays set through the release so the envelope has both ends.
    public var hoverEndedAt: Double?
    /// Reference-time instant the first-run hello began, or nil.
    ///
    /// The same greeting the pointer gets, fired once on the very first launch
    /// so a new arrival is introduced to rather than merely rendered at. Its
    /// end is scheduled up front rather than waiting on a pointer leaving,
    /// which is the only way this differs from a hover.
    public var helloSince: Double?
    /// When that hello starts easing out. Set at the same moment as
    /// `helloSince`, because nothing else will come along to end it.
    public var helloEndedAt: Double?
    /// Reference-time instant he was last clicked, or nil.
    public var clickedAt: Double?
    /// Reference-time instant rainbow mode began, or nil. 🎉🪄
    public var rainbowSince: Double?
    /// Petting: press-and-hold without moving. Same two-ended envelope as hover.
    public var petSince: Double?
    public var petEndedAt: Double?
    /// Reference-time instant a floor bug was caught, or nil.
    public var pouncedAt: Double?
    /// Reference-time instant the sleeping-click snack began, or nil.
    public var snackSince: Double?
    /// Reference-time instant a sleeping crab was poked awake, or nil. The
    /// rude-wake sequence plays over the still-sleeping pose (the stir is
    /// deferred), then everything eases out as the mood gets him up.
    public var rudeWakeSince: Double?
    /// The deal-with-it latch: a flaired fact arrived / left. Two-ended like
    /// hover, plus whether this showing's landing dings, plus the rate flag —
    /// `shadesDropping` holds the 30fps reaction tier for the ~0.9s fall only
    /// (a forty-second worn fact must not cost idle its frame rate).
    public var shadesSince: Double?
    public var shadesEndedAt: Double?
    public var shadesDing: Bool = false
    public var shadesDropping: Bool = false
    /// The quiet completion badge. `completedAt` is the identity (nudge
    /// windows + the five-minute clock); the shown/ended pair is the
    /// appearance latch, so every entrance and exit — first show, early
    /// clear, focus switch, session death — goes through one eased envelope.
    public var completedAt: Double?
    public var badgeShownAt: Double?
    public var badgeEndedAt: Double?
    /// The service glyph — kind plus the shown/ended appearance latch, the
    /// badge's exact contract: every entrance, kind swap and exit goes
    /// through one eased envelope.
    public var serviceGlyph: ServiceGlyph?
    public var serviceGlyphShownAt: Double?
    public var serviceGlyphEndedAt: Double?
    /// Nobody can see him — the display is asleep, or his window is covered.
    /// Purely a frame-rate input; see `PetViewModel.unseen`.
    public var unseen: Bool = false
    /// One rare effect forced on for review, with its own epoch, or nil for
    /// the real schedules. Defaulted so every offline renderer, test and
    /// preview call is untouched — and a half-set latch is unrepresentable,
    /// so the failure mode of this plumbing is "no preview", never "a preview
    /// at the wrong time".
    public var previewLatch: CrabAnimator.PreviewLatch?
    /// Frozen time, for deterministic screenshots in the debug picker.
    public var frozenTime: Double?

    /// Scales the flashbang, for the system Reduce Motion setting: 1 normally,
    /// 0 when the operator has asked the machine to calm down.
    ///
    /// Injected rather than read here. The setting is a property of the running
    /// machine, and reading it inside a render path would make the sizzle's
    /// byte-determinism depend on the build machine's accessibility
    /// preferences. Only the live view supplies anything but the default.
    public var flashScale: Double = 1

    /// The view-state clocks. Per-model instances live — two pets must not
    /// rebase each other's epochs or cross-trigger costume dissolves — with
    /// `.shared` as the default so bare constructions (previews, frozen
    /// renders that never touch a clock) need no ceremony.
    public var moodClock: MoodClock = .shared
    public var costumeClock: CostumeClock = .shared

    public init(mood: PetMood,
                costume: Costume = .none,
                celebrating: Bool = false,
                epicCelebration: Bool = false,
                taskFraction: Double? = nil,
                hoverSince: Double? = nil,
                hoverEndedAt: Double? = nil,
                helloSince: Double? = nil,
                helloEndedAt: Double? = nil,
                clickedAt: Double? = nil,
                rainbowSince: Double? = nil,
                petSince: Double? = nil,
                petEndedAt: Double? = nil,
                pouncedAt: Double? = nil,
                snackSince: Double? = nil,
                rudeWakeSince: Double? = nil,
                shadesSince: Double? = nil,
                shadesEndedAt: Double? = nil,
                shadesDing: Bool = false,
                shadesDropping: Bool = false,
                completedAt: Double? = nil,
                badgeShownAt: Double? = nil,
                badgeEndedAt: Double? = nil,
                serviceGlyph: ServiceGlyph? = nil,
                serviceGlyphShownAt: Double? = nil,
                serviceGlyphEndedAt: Double? = nil,
                unseen: Bool = false,
                previewLatch: CrabAnimator.PreviewLatch? = nil,
                frozenTime: Double? = nil,
                flashScale: Double = 1,
                moodClock: MoodClock = .shared,
                costumeClock: CostumeClock = .shared) {
        self.mood = mood
        self.costume = costume
        self.celebrating = celebrating
        self.epicCelebration = epicCelebration
        self.taskFraction = taskFraction
        self.hoverSince = hoverSince
        self.hoverEndedAt = hoverEndedAt
        self.helloSince = helloSince
        self.helloEndedAt = helloEndedAt
        self.clickedAt = clickedAt
        self.rainbowSince = rainbowSince
        self.petSince = petSince
        self.petEndedAt = petEndedAt
        self.pouncedAt = pouncedAt
        self.snackSince = snackSince
        self.rudeWakeSince = rudeWakeSince
        self.shadesSince = shadesSince
        self.shadesEndedAt = shadesEndedAt
        self.shadesDing = shadesDing
        self.shadesDropping = shadesDropping
        self.completedAt = completedAt
        self.badgeShownAt = badgeShownAt
        self.badgeEndedAt = badgeEndedAt
        self.serviceGlyph = serviceGlyph
        self.serviceGlyphShownAt = serviceGlyphShownAt
        self.serviceGlyphEndedAt = serviceGlyphEndedAt
        self.unseen = unseen
        self.previewLatch = previewLatch
        self.frozenTime = frozenTime
        self.flashScale = flashScale
        self.moodClock = moodClock
        self.costumeClock = costumeClock
    }

    // `nonisolated` on the two party constants and on `rainbowMood`,
    // `discoTint`, `nearDoneTint` and `rainbowTint` below.
    //
    // None of them touch view state. They are pure functions of a clock reading
    // and their arguments, and they were always written that way — the isolation
    // was never asked for. `CrabView` conforms to `View`, `View` is `@MainActor`,
    // and Swift 6.1 pushes that inference onto the type's static members too.
    // Swift 6.3 does not, so this compiled clean on the machine it was written on
    // and handed the CI runner — two minor versions back — twenty-one errors in
    // test code that never wanted a main actor, most of them inside `#expect`
    // expansions, which are synchronous and nonisolated.
    //
    // Saying `nonisolated` at the declaration is the honest fix rather than the
    // small one: a colour is not main-actor state, and the alternative was
    // pinning twenty-one assertions to the main actor to work around one wrong
    // inference. `epicTint` and `celebrationTint` are every bit as pure, but
    // their callers already sit on the main actor, so nothing put the question
    // to them; this changes only what the runner rejected.

    /// How long the party lasts.
    nonisolated public static let rainbowDuration = 4.0

    /// How long each pose holds during the party.
    nonisolated static let rainbowPoseInterval = 0.8

    /// The pose to strike at a moment in the party, or nil when not partying.
    ///
    /// Cycling the colour alone reads as a recolour; cycling the pose too reads
    /// as a celebration.
    nonisolated static func rainbowMood(elapsed: Double) -> PetMood? {
        guard elapsed >= 0, elapsed < rainbowDuration else { return nil }
        let order = PetMood.allCases
        let step = Int(elapsed / rainbowPoseInterval) % order.count
        return order[step]
    }

    /// The occasional disco during a long cook: one slow trip round the wheel
    /// at half saturation, pose untouched — he keeps working, head down, while
    /// the lights happen to him. Dice-gated to roughly one flash per few
    /// minutes of continuous cooking, never in the first cycle.
    nonisolated static func discoTint(cookingT t: Double) -> Color? {
        let cycle = Int(floor(t / 45))
        guard cycle > 0, CrabAnimator.noise(cycle &* 41 &+ 17) < 0.22 else { return nil }
        let since = t - Double(cycle) * 45
        guard since < 5 else { return nil }
        let amount = Ease.window(since, duration: 5, edge: 0.7)
        guard amount > 0.01 else { return nil }
        return SpriteTint.towards(SpriteTint.rgb(hue: since / 5, saturation: 0.5, brightness: 0.92),
                                  amount: amount)
    }

    /// The near-done glow: once the todo list is ≥80% complete, he takes a
    /// breath of white every forty seconds or so — the sprint is almost home.
    ///
    /// It used to be a 0.35 push toward white breathing every 2.5s with no
    /// dice at all, for the ENTIRE tail of every sprint above 80%. A
    /// ten-minute sprint was two hundred and forty consecutive pulses. That is
    /// the same signal `celebrationBlanch`'s doc was written to condemn — a
    /// partial push toward white over terracotta is a peach, and a peach held
    /// long enough is a washed-out monitor. There it was held for ten seconds;
    /// here it was held for minutes.
    ///
    /// It also snapped. `taskFraction` is quantised to 0.05 and moves live, so
    /// the instant a list crossed 0.8 this went from nil to `0.35 * pulse(t)`
    /// at whatever phase the sine happened to be at — worst case a jump
    /// straight to full amplitude in one frame, and the same in reverse when
    /// adding a task dropped the fraction back under. Now that it is dark 94%
    /// of the time, almost every crossing lands on exact zero with nothing to
    /// snap, and the worst survivor is bounded by the 0.28.
    nonisolated static func nearDoneTint(cookingT t: Double, fraction: Double?) -> Color? {
        guard let fraction, fraction >= 0.8 else { return nil }
        let cycle = Int(floor(t / 20))
        guard cycle > 0, CrabAnimator.noise(cycle &* 67 &+ 5) < 0.5 else { return nil }
        let since = t - Double(cycle) * 20
        guard since < 2.2 else { return nil }
        let amount = 0.28 * Ease.window(since, duration: 2.2, edge: 0.8)
        guard amount > 0.01 else { return nil }
        return SpriteTint.towards((r: 1, g: 1, b: 1), amount: amount)
    }

    /// The epic finale's tint: the rainbow burst under the 10s master envelope.
    ///
    /// The white light that used to ride on top of this lives in `epicBlanch`
    /// now, where it can reach the eyes and the costume instead of only the
    /// body — so what is left here is a plain hue lerp, and the rainbow stays
    /// saturated instead of washing to pastel twice a second.
    ///
    /// Deliberately non-nil across the whole window: it is what stops
    /// `composedTint` falling through into the plain-celebration branch
    /// mid-finale.
    nonisolated static func epicTint(doneT t: Double) -> Color? {
        let envelope = Ease.window(t, duration: 10, edge: 0.6)
        guard envelope > 0.001 else { return nil }
        let hue = (t / 5).truncatingRemainder(dividingBy: 1)
        return SpriteTint.towards(SpriteTint.rgb(hue: hue, saturation: 0.7, brightness: 0.95),
                                  amount: envelope)
    }

    // MARK: - The flashbang

    /// How fast the light arrives. Under the README GIF's 0.1s sampling step
    /// on purpose — see `celebrationFlashes`.
    nonisolated static let flashAttack = 0.09

    /// The flashbang: two detonations inside the first second, then nothing.
    ///
    /// Every tap peaks at **exactly 1.0**. Taps differ by duration and spacing,
    /// never by amplitude, because a partial push toward white over terracotta
    /// is a peach — and nine peach pulses dwelling across ten seconds is what
    /// this replaces. It read as a washed-out monitor because that is what a
    /// low-amplitude signal held for ten seconds is.
    ///
    /// The bang, 110ms of real terracotta, then a shorter secondary: the event
    /// spans 0.20→1.15, and the other nine seconds carry no flash at all.
    ///
    /// Starts sit on the 0.1s grid and `flashAttack < 0.10 < attack + hold`, so
    /// the README GIF — which samples the finale at 10fps — always lands
    /// strictly inside a plateau rather than on a flank. `flashesSurviveTenFps`
    /// pins all three halves of that invariant.
    nonisolated static let celebrationFlashes: [(at: Double, hold: Double, decay: Double)] = [
        (at: 0.20, hold: 0.12, decay: 0.28),
        (at: 0.80, hold: 0.06, decay: 0.20),
    ]

    /// The epic's third tap, landing on the 1.2× transform's apex (`epicPeak`
    /// plateaus across [2.0, 2.6]) — the loudest moment in the app gets the
    /// longest hold. No tap at t≈0: the reel's `matchCutFlash` already whites
    /// the whole frame out across the cook→finale boundary, and the finale
    /// opens decaying from it. A sprite flash there is a white on a white.
    nonisolated static let epicFlash = (at: 2.20, hold: 0.14, decay: 0.32)

    /// The loudest hit of the train at `t`. `max`, not a sum: two taps must
    /// never add to 2 and clip, so the 0…1 contract holds by construction
    /// rather than by the schedule happening not to overlap.
    nonisolated private static func loudest(_ t: Double,
                                _ schedule: [(at: Double, hold: Double, decay: Double)]) -> Double {
        schedule.reduce(0) { best, tap in
            max(best, Ease.pulse(t - tap.at, attack: flashAttack,
                                 hold: tap.hold, decay: tap.decay))
        }
    }

    nonisolated static func celebrationBlanch(doneT t: Double) -> Double {
        loudest(t, celebrationFlashes)
    }

    nonisolated static func epicBlanch(doneT t: Double) -> Double {
        loudest(t, celebrationFlashes + [epicFlash])
    }

    /// The whiteness channel, composed. Deliberately NOT part of
    /// `composedTint`: a tint chooses a hue and reaches one ink, a blanch
    /// chooses how much light is hitting all of them. A flash expressed as a
    /// tint could only ever reach `.body`, which is exactly how the old one
    /// ended up as peach with black eyes in the middle of it.
    nonisolated static func composedBlanch(mood: PetMood, t: Double,
                               celebrating: Bool, epic: Bool) -> Double {
        guard mood == .done, celebrating else { return 0 }
        return epic ? epicBlanch(doneT: t) : celebrationBlanch(doneT: t)
    }

    /// One place decides which tint owns the body, so two effects can never
    /// fight frame-by-frame: the user's party outranks the celebration, which
    /// outranks the disco, which outranks the near-done glow.
    ///
    /// The plain celebration has no tint of its own any more — between taps he
    /// is honest terracotta, and the colour event IS the bang.
    /// - Parameter hourOfDay: the local hour, for the afternoon's warm.
    ///   Defaulted so every existing caller and test compiles untouched, and
    ///   so offline renderers — which pass nothing — stay cold.
    nonisolated static func composedTint(mood: PetMood, t: Double, rainbowElapsed: Double?,
                             celebrating: Bool, epic: Bool = false,
                                         taskFraction: Double?, hourOfDay: Int? = nil,
                                         preview: CrabAnimator.PreviewFrame? = nil) -> Color? {
        // First, and it wins outright — the same rule `currentPose` states for
        // the pose. A preview exists to be seen past the schedules.
        if let preview {
            let amount = CrabAnimator.previewBasking(preview)
            guard amount > 0.001 else { return nil }
            return SpriteTint.towards(SpriteTint.goldRGB, amount: 0.26 * amount)
        }
        if let rainbowElapsed, let party = rainbowTint(elapsed: rainbowElapsed) { return party }
        if mood == .done, celebrating, epic, let burst = epicTint(doneT: t) { return burst }
        if mood == .cooking {
            if let disco = discoTint(cookingT: t) { return disco }
            if let glow = nearDoneTint(cookingT: t, fraction: taskFraction) { return glow }
        }
        if mood == .idle, let sun = CrabAnimator.sunPatch(idleT: t, hourOfDay: hourOfDay) {
            return SpriteTint.towards(SpriteTint.goldRGB, amount: 0.26 * sun.amount)
        }
        return nil
    }

    /// The body colour at a moment in the cycle, or nil when not partying.
    /// `nonisolated` for the reason given above `rainbowDuration`.
    nonisolated static func rainbowTint(elapsed: Double) -> Color? {
        guard elapsed >= 0, elapsed < rainbowDuration else { return nil }
        // Two full trips round the wheel, then out. Saturation stays under 1 so
        // he still reads as Claw'd wearing colours rather than a colour wheel.
        // The trapezoid mixes the party colour up from terracotta and back down
        // to it, so the tint has no seam at either end of the party.
        let hue = (elapsed / rainbowDuration * 2).truncatingRemainder(dividingBy: 1)
        let amount = Ease.window(elapsed, duration: rainbowDuration, edge: 0.4)
        return SpriteTint.towards(SpriteTint.rgb(hue: hue, saturation: 0.72, brightness: 0.92),
                                  amount: amount)
    }

    /// How often the sprite is rebuilt, per mood.
    ///
    /// The sprite is whole pixels on a 32×32 grid, so nothing it can express
    /// needs 120 Hz. Driving `.animation` unconditionally meant an idle machine
    /// with zero Claude sessions rebuilt a 1024-cell buffer, rescanned it into
    /// runs, and re-composited an offscreen layer every display frame, all
    /// night. These rates are chosen against each mood's fastest motion.
    private var frameInterval: Double { mood.style.frameInterval }

    public var body: some View {
        if let frozenTime {
            render(at: frozenTime)
        } else {
            // Hover and click get the smoother rate — both are direct responses
            // to the pointer and need to feel immediate. Leaving clicks on the
            // mood rate renders a 0.34s shrink as two frames in `.sleeping`.
            // `hoverSince` stays set through the greeting's ease-out, so the
            // release renders at the reaction rate too instead of at 6fps.
            //
            // `helloSince` belongs here for a sharper reason than the rest: the
            // first launch has no sessions, so the mood underneath the hello is
            // idle or asleep — and asleep renders at 6fps. Left out, the one
            // animation a new user is guaranteed to see would be the choppiest
            // thing the app ever draws.
            // `rudeWakeSince` for the same sharp reason as `helloSince`: the
            // mood underneath a rude wake is SLEEPING, which renders at 6fps —
            // and a 0.5s arm rise at 6fps is three frames of teleporting claw.
            let reacting = hoverSince != nil || clickedAt != nil || rainbowSince != nil
                || petSince != nil || pouncedAt != nil || snackSince != nil
                || helloSince != nil || rudeWakeSince != nil || shadesDropping
            let interval = CrabView.tickInterval(unseen: unseen, reacting: reacting,
                                                 mood: frameInterval)
            TimelineView(.periodic(from: Date(), by: interval)) { timeline in
                render(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// The local hour, for the two schedules that only happen at a particular
    /// time of day — the telescope and the patch of sun. **Nil whenever time
    /// is frozen**, which is what keeps both of them out of every offline
    /// render, every GIF and every sprite sheet, regardless of what their dice
    /// would have said.
    ///
    /// One definition, read by both the pose and the tint, so they cannot
    /// disagree about what time it is.
    /// How often to ask for a frame.
    ///
    /// Extracted and pure so the policy is testable — the same reason
    /// `hoverCountsAsStir` and `idleChatterShows` are statics rather than
    /// expressions buried in the thing they govern.
    ///
    /// **Unseen outranks reacting.** If the display is asleep or his window is
    /// covered there is nobody to react for, and a pet nobody is looking at
    /// should not be rebuilding a 1024-cell buffer twenty times a second. One
    /// frame a second is enough to notice the moment he is visible again, and
    /// unlike freezing time it keeps hover, the click latches, the badge and
    /// the glyph all honest in the meantime.
    nonisolated static func tickInterval(unseen: Bool, reacting: Bool, mood: Double) -> Double {
        if unseen { return 1.0 }
        return reacting ? 1.0 / 30 : mood
    }

    private var hourOfDay: Int? {
        frozenTime == nil ? LocalHour.current : nil
    }

    private func render(at time: Double) -> some View {
        // ONE derivation of the preview clock, handed to BOTH consumers.
        // Deriving it twice is what put the floor pool and the warm on his
        // shell `epoch mod 18` apart, so this line is the fix — not the
        // arithmetic further down.
        let preview = previewLatch?.frame(at: time)
        // Live: rebase onto the mood so one-shot motion (the `done` hop) starts
        // at its own t=0. Frozen: the caller's time is already relative.
        var pose = currentPose(at: time, preview: preview)
        var ghostCostume = Costume.none
        var costumeProgress = 1.0
        if frozenTime == nil {
            // Cross-ease mood changes from the last pose that was actually on
            // screen. Offline renderers never note a displayed pose, so the
            // blend can never engage there — parity by construction.
            if let (from, u) = moodClock.crossfade(at: time) {
                pose = CrabPose.blend(from: from, to: pose, u: u)
            }
            moodClock.note(displayed: pose)
            // Same contract for the wardrobe: live changes cross-dissolve,
            // frozen and offline renders wear the costume at full strength.
            costumeClock.note(costume)
            costumeProgress = costumeClock.progress(at: time)
            if costumeProgress < 1 { ghostCostume = costumeClock.previous }
        }
        let localT = frozenTime == nil ? moodClock.age(of: mood, at: time) : time
        let tint = CrabView.composedTint(mood: mood,
                                         t: localT,
                                         rainbowElapsed: frozenTime == nil
                                             ? rainbowSince.map { time - $0 } : nil,
                                         celebrating: celebrating,
                                         epic: epicCelebration,
                                         taskFraction: taskFraction,
                                         hourOfDay: hourOfDay,
                                         preview: preview)
        let blanch = CrabView.composedBlanch(mood: mood, t: localT,
                                             celebrating: celebrating,
                                             epic: epicCelebration) * flashScale
        return PixelCanvasView(buffer: CrabRig.render(pose,
                                                      costume: costume,
                                                      ghostCostume: ghostCostume,
                                                      costumeVisibility: costumeProgress),
                               bodyTint: tint,
                               inkOverrides: CostumeStyle.blendedOverrides(from: ghostCostume,
                                                                           to: costume,
                                                                           u: costumeProgress),
                               blanch: blanch)
            .drawingGroup()
    }

    private func currentPose(at time: Double, preview: CrabAnimator.PreviewFrame? = nil) -> CrabPose {
        let t = frozenTime == nil ? moodClock.age(of: mood, at: time) : time

        // During the party the pose cycles too. `MoodClock` is deliberately
        // bypassed: it rebases time on every mood change, which at 0.8s per pose
        // would restart each one at t=0 and freeze the animation.
        if let rainbowSince, frozenTime == nil,
           let partyMood = CrabView.rainbowMood(elapsed: time - rainbowSince) {
            var pose = CrabAnimator.pose(mood: partyMood, t: time - rainbowSince)
            pose.mouth = .open
            pose.confettiElapsed = time - rainbowSince
            return pose
        }

        var pose = CrabAnimator.pose(mood: mood, t: t, flourishes: true,
                                     hourOfDay: hourOfDay)
        if mood == .done, celebrating, frozenTime == nil {
            CrabAnimator.applyCelebration(t: t, epic: epicCelebration, to: &pose)
        }
        if let hoverSince, frozenTime == nil {
            // The hover's start instant doubles as the variant seed: chosen once
            // per hover, stable for its whole duration.
            CrabAnimator.applyGreeting(elapsed: time - hoverSince,
                                       seed: Int(hoverSince * 1000),
                                       amount: Ease.amount(now: time,
                                                           since: hoverSince,
                                                           endedAt: hoverEndedAt),
                                       to: &pose)
        }
        // The first-run hello. Deliberately AFTER the hover block, so someone
        // whose pointer is already on him during the greeting gets one coherent
        // reaction rather than two fighting over the same channels — and `.wave`
        // is named rather than rolled, because a hello that came out a wink
        // would not read as a hello.
        if let helloSince, frozenTime == nil {
            CrabAnimator.applyGreeting(elapsed: time - helloSince,
                                       amount: Ease.amount(now: time,
                                                           since: helloSince,
                                                           endedAt: helloEndedAt),
                                       variant: .wave,
                                       to: &pose)
        }
        if let petSince, frozenTime == nil {
            CrabAnimator.applyPetting(elapsed: time - petSince,
                                      amount: Ease.amount(now: time,
                                                          since: petSince,
                                                          endedAt: petEndedAt),
                                      until: petEndedAt.map { $0 - petSince },
                                      to: &pose)
        }
        if let clickedAt, frozenTime == nil {
            CrabAnimator.applyClick(elapsed: time - clickedAt, to: &pose)
        }
        if let pouncedAt, frozenTime == nil {
            CrabAnimator.applyPounce(elapsed: time - pouncedAt, to: &pose)
        }
        if let snackSince, frozenTime == nil {
            CrabAnimator.applySnack(elapsed: time - snackSince, to: &pose)
        }
        // AFTER the greeting on purpose: the pointer is on him when the click
        // lands, so a hover greeting is usually mid-flight — phase A vetoes
        // its opened eyes (still asleep while the claw comes out), and the
        // arms compose through `max`.
        if let rudeWakeSince, frozenTime == nil {
            CrabAnimator.applyRudeWake(elapsed: time - rudeWakeSince, to: &pose)
        }
        if let shadesSince, frozenTime == nil {
            CrabAnimator.applyShadesDrop(elapsed: time - shadesSince,
                                         endedElapsed: shadesEndedAt.map { time - $0 },
                                         ding: shadesDing, to: &pose)
        }
        if let completedAt, frozenTime == nil {
            // The foot badge: the appearance latch eased both ways, and
            // nothing else — the badge lives until new work consumes it, not
            // until a clock does. Written into the pose here so mood-blend
            // ghost snapshots carry it.
            pose.doneBadge = Ease.amount(now: time, since: badgeShownAt, endedAt: badgeEndedAt,
                                         attack: 0.5, release: 0.45)

            // The reminder: one eased breath through the badge every three
            // minutes — a shimmer, not a wave. Idle-only (a plan or a blocked
            // session outranks a reminder; a sleeping crab keeps the static
            // badge and none of the motion), and never in the first cycle.
            if mood == .idle, pose.doneBadge > 0.5 {
                pose.doneBadgePulse = CrabView.badgePulse(age: time - completedAt)
            }
        }
        if let serviceGlyph, frozenTime == nil {
            // The service glyph floats in on the same two-ended latch as the
            // badge; frozen renders never carry it by construction.
            pose.serviceGlyph = serviceGlyph
            pose.serviceGlyphVisibility = Ease.amount(now: time,
                                                      since: serviceGlyphShownAt,
                                                      endedAt: serviceGlyphEndedAt)
        }
        // A forced effect is applied LAST and wins outright. The whole point
        // of a preview is to see the thing regardless of what the schedules,
        // the hour and the dice would otherwise have decided — and `frozenTime`
        // is deliberately NOT consulted, because a frozen render is the other
        // review mode and previews are the live one.
        if let preview {
            CrabAnimator.applyPreview(preview, to: &pose)
        }

        return pose
    }

    /// The pulse envelope, pure in the badge's age: zero through the first
    /// three minutes, then one 2.4s swell at the top of every cycle.
    static func badgePulse(age: Double) -> Double {
        let cycle = Int(age / badgePulsePeriod)
        guard cycle >= 1 else { return 0 }
        return Ease.window(age - Double(cycle) * badgePulsePeriod,
                           duration: badgePulseDuration, edge: 1.0)
    }

    /// "Every 3 mins, etc, etc" — the operator's cadence for the completion
    /// reminder, and how long each breath takes.
    static let badgePulsePeriod = 180.0
    static let badgePulseDuration = 2.4

    /// Set when the mood changes so transient animations replay from the start.
}

/// Records when each mood was last entered, so `done` and `needsAttention`
/// replay their one-shot motion instead of joining mid-cycle — and snapshots
/// the last displayed pose at each change, so the new mood can cross-ease in
/// from exactly where the old one left him.
@MainActor
public final class MoodClock {
    public static let shared = MoodClock()
    public init() {}
    nonisolated static let blendDuration = 0.4

    private var current: PetMood = .sleeping
    private var startedAt: Double = Date.timeIntervalSinceReferenceDate
    private var lastDisplayed: CrabPose?
    private var blendFrom: CrabPose?
    private var blendStartedAt: Double = -.infinity

    func epoch(for mood: PetMood) -> Double {
        if mood != current {
            current = mood
            startedAt = Date.timeIntervalSinceReferenceDate
            // Snapshotting the *displayed* pose (not the previous mood's raw
            // pose) keeps a second mood change mid-blend continuous: the new
            // blend starts from whatever hybrid was actually on screen.
            blendFrom = lastDisplayed
            blendStartedAt = startedAt
        }
        return startedAt
    }

    /// The mood's age at `time`, clamped at zero — and this wrapper is where
    /// EVERY reader gets the number, not `time - epoch` by hand.
    ///
    /// The age can genuinely run backwards: the epoch is stamped off the wall
    /// clock at the moment of the call, while `time` is a `TimelineView`
    /// `.periodic` entry — a scheduled instant, by construction at or before
    /// the frame it renders, re-anchored on every mood change and every
    /// reaction fast-path flip. The coarsest tier (sleeping, 1/6s) can hand
    /// back a date ~167ms behind the epoch, and Swift's `%` keeps the sign of
    /// the dividend — so an unclamped age reached `flameFrames[-1]` and killed
    /// the process while the pet was on fire. Four readers already guarded
    /// their own arithmetic; this clamps the number they all read, and the
    /// downstream subscripts stay deliberately partial — their totality is
    /// this seam's promise, and two guards for one invariant is how the second
    /// one drifts.
    ///
    /// Still rebases: the clamp wraps the mutating `epoch`, never replaces it.
    /// A clamp that quietly stopped committing mood flips would freeze every
    /// one-shot beat at the previous mood's clock.
    func age(of mood: PetMood, at time: Double) -> Double {
        max(0, time - epoch(for: mood))
    }

    /// The epoch without the rebase side effect, for callers that only want to
    /// ask "how long has this mood been on screen" (nil when it is not current).
    func currentEpoch(for mood: PetMood) -> Double? {
        mood == current ? startedAt : nil
    }

    /// The live view reports each frame it drew; offline renderers never do.
    func note(displayed pose: CrabPose) { lastDisplayed = pose }

    /// The outgoing snapshot and eased progress while a blend is running.
    func crossfade(at time: Double) -> (from: CrabPose, u: Double)? {
        guard let blendFrom else { return nil }
        let progress = (time - blendStartedAt) / Self.blendDuration
        guard progress < 1 else { self.blendFrom = nil; return nil }
        guard progress > 0 else { return (blendFrom, 0) }
        return (blendFrom, Ease.smoothstep(progress))
    }
}
