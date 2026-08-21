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
        case jump, wave, wiggle, stretch, lookAround, scuttle

        var duration: Double {
            switch self {
            case .jump: 0.9
            case .wave: 1.8
            case .wiggle: 1.0
            case .stretch: 1.6
            case .lookAround: 2.0
            case .scuttle: 1.2
            }
        }
    }

    /// One flourish per window, with a quiet stretch after it.
    private static let flourishPeriod = 7.0

    /// Which flourish is playing, and how far into it we are (0…1).
    static func flourish(at t: Double) -> (Flourish, Double)? {
        let cycle = Int(floor(t / flourishPeriod))
        let since = t - Double(cycle) * flourishPeriod
        let all = Flourish.allCases
        let choice = all[Int(noise(cycle &* 7 &+ 3) * Double(all.count)) % all.count]
        guard since < choice.duration else { return nil }
        return (choice, since / choice.duration)
    }

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

            if let float = idleBalloon(idleT: t) {
                pose.prop = .balloon
                pose.propVisibility = float
            }

            // A visiting bug owns his attention: eyes drop to the floor and
            // follow it across.
            if let bug = bugPosition(idleT: t) {
                pose.bugX = bug
                pose.gazeX = bug < 14 ? -1 : (bug > 18 ? 1 : 0)
                pose.gazeY = 1
            }

            // And deep in the night, sometimes, the telescope comes out.
            if let gazing = stargaze(idleT: t, hourOfDay: hourOfDay) {
                pose.stargaze = gazing.amount
                pose.stargazePhase = gazing.phase
                if gazing.amount > 0.4 {
                    pose.gazeY = -1
                    pose.gazeX = 1
                    pose.mouth = .open
                }
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
            pose.bob = sin(t * 1.8) > 0 ? 0 : 1
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
            pose.bob = (sin(t * 5) > 0.3 && hop > 0) ? -2 : 0
            pose.armLeft = 1
            pose.armRight = 1
            pose.mouth = .open
            pose.prop = .check
            pose.blink = blink(at: t, period: 4.0)

        case .needsAttention:
            // Waving, bouncing, and shouting. Has to read across a room, so
            // this one stays quick — it is the only state that wants urgency.
            pose.bob = sin(t * 4.0) > 0 ? -2 : 0
            pose.lean = sin(t * 3.2) > 0 ? -1 : 1
            pose.armLeft = 0.7 + (sin(t * 5.5) > 0 ? 0.3 : 0)
            pose.armRight = 1.0 - (sin(t * 5.5) > 0 ? 0.3 : 0)
            pose.mouth = .open
            pose.prop = .bang

        case .sleeping:
            pose.bob = sin(t * 0.9) > 0 ? 0 : 1   // slow breathing
            pose.blink = 1                        // eyes shut
            pose.mouth = .flat
            pose.prop = .zzz
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
    public static func applyGreeting(elapsed: Double, seed: Int = 0,
                                     amount: Double = 1, to pose: inout CrabPose) {
        guard amount > 0.001 else { return }
        let greeting = greeting(forSeed: seed)
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

    /// Being petted: eyes ease shut, a purr wiggle, and hearts. Applied after
    /// the greeting so a hold wins over a hover — you cannot pet him and be
    /// waved at simultaneously.
    public static func applyPetting(elapsed: Double, amount: Double, to pose: inout CrabPose) {
        guard amount > 0.001 else { return }
        if amount >= 0.5 {
            pose.blink = 1
            pose.asleepOverride = false
            pose.winkEye = .none
            pose.mouth = .smile
            pose.lean += Ease.square(elapsed * 2.5) > 0.5 ? 1 : -1
            pose.heartsElapsed = elapsed
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

        for start in [3.5, 7.0] {
            let hop = t - start
            if hop >= 0, hop < 1.2, sin(hop * 5) > 0.3 {
                pose.bob = min(pose.bob, -2)
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
                clickedAt: Double? = nil,
                rainbowSince: Double? = nil,
                petSince: Double? = nil,
                petEndedAt: Double? = nil,
                pouncedAt: Double? = nil,
                snackSince: Double? = nil,
                completedAt: Double? = nil,
                badgeShownAt: Double? = nil,
                badgeEndedAt: Double? = nil,
                serviceGlyph: ServiceGlyph? = nil,
                serviceGlyphShownAt: Double? = nil,
                serviceGlyphEndedAt: Double? = nil,
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
        self.clickedAt = clickedAt
        self.rainbowSince = rainbowSince
        self.petSince = petSince
        self.petEndedAt = petEndedAt
        self.pouncedAt = pouncedAt
        self.snackSince = snackSince
        self.completedAt = completedAt
        self.badgeShownAt = badgeShownAt
        self.badgeEndedAt = badgeEndedAt
        self.serviceGlyph = serviceGlyph
        self.serviceGlyphShownAt = serviceGlyphShownAt
        self.serviceGlyphEndedAt = serviceGlyphEndedAt
        self.frozenTime = frozenTime
        self.flashScale = flashScale
        self.moodClock = moodClock
        self.costumeClock = costumeClock
    }

    /// How long the party lasts.
    public static let rainbowDuration = 4.0

    /// How long each pose holds during the party.
    static let rainbowPoseInterval = 0.8

    /// The pose to strike at a moment in the party, or nil when not partying.
    ///
    /// Cycling the colour alone reads as a recolour; cycling the pose too reads
    /// as a celebration.
    static func rainbowMood(elapsed: Double) -> PetMood? {
        guard elapsed >= 0, elapsed < rainbowDuration else { return nil }
        let order = PetMood.allCases
        let step = Int(elapsed / rainbowPoseInterval) % order.count
        return order[step]
    }

    /// The occasional disco during a long cook: one slow trip round the wheel
    /// at half saturation, pose untouched — he keeps working, head down, while
    /// the lights happen to him. Dice-gated to roughly one flash per few
    /// minutes of continuous cooking, never in the first cycle.
    static func discoTint(cookingT t: Double) -> Color? {
        let cycle = Int(floor(t / 45))
        guard cycle > 0, CrabAnimator.noise(cycle &* 41 &+ 17) < 0.22 else { return nil }
        let since = t - Double(cycle) * 45
        guard since < 5 else { return nil }
        let amount = Ease.window(since, duration: 5, edge: 0.7)
        guard amount > 0.01 else { return nil }
        return SpriteTint.towards(SpriteTint.rgb(hue: since / 5, saturation: 0.5, brightness: 0.92),
                                  amount: amount)
    }

    /// The near-done glow: once the todo list is ≥80% complete, a soft white
    /// pulse every 2.5s while he cooks — the sprint is almost home.
    static func nearDoneTint(cookingT t: Double, fraction: Double?) -> Color? {
        guard let fraction, fraction >= 0.8 else { return nil }
        let pulse = Ease.smoothstep(0.5 + 0.5 * sin(t * 2 * .pi / 2.5))
        let amount = 0.35 * pulse
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
    static func epicTint(doneT t: Double) -> Color? {
        let envelope = Ease.window(t, duration: 10, edge: 0.6)
        guard envelope > 0.001 else { return nil }
        let hue = (t / 5).truncatingRemainder(dividingBy: 1)
        return SpriteTint.towards(SpriteTint.rgb(hue: hue, saturation: 0.7, brightness: 0.95),
                                  amount: envelope)
    }

    // MARK: - The flashbang

    /// How fast the light arrives. Under the README GIF's 0.1s sampling step
    /// on purpose — see `celebrationFlashes`.
    static let flashAttack = 0.09

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
    static let celebrationFlashes: [(at: Double, hold: Double, decay: Double)] = [
        (at: 0.20, hold: 0.12, decay: 0.28),
        (at: 0.80, hold: 0.06, decay: 0.20),
    ]

    /// The epic's third tap, landing on the 1.2× transform's apex (`epicPeak`
    /// plateaus across [2.0, 2.6]) — the loudest moment in the app gets the
    /// longest hold. No tap at t≈0: the reel's `matchCutFlash` already whites
    /// the whole frame out across the cook→finale boundary, and the finale
    /// opens decaying from it. A sprite flash there is a white on a white.
    static let epicFlash = (at: 2.20, hold: 0.14, decay: 0.32)

    /// The loudest hit of the train at `t`. `max`, not a sum: two taps must
    /// never add to 2 and clip, so the 0…1 contract holds by construction
    /// rather than by the schedule happening not to overlap.
    private static func loudest(_ t: Double,
                                _ schedule: [(at: Double, hold: Double, decay: Double)]) -> Double {
        schedule.reduce(0) { best, tap in
            max(best, Ease.pulse(t - tap.at, attack: flashAttack,
                                 hold: tap.hold, decay: tap.decay))
        }
    }

    static func celebrationBlanch(doneT t: Double) -> Double {
        loudest(t, celebrationFlashes)
    }

    static func epicBlanch(doneT t: Double) -> Double {
        loudest(t, celebrationFlashes + [epicFlash])
    }

    /// The whiteness channel, composed. Deliberately NOT part of
    /// `composedTint`: a tint chooses a hue and reaches one ink, a blanch
    /// chooses how much light is hitting all of them. A flash expressed as a
    /// tint could only ever reach `.body`, which is exactly how the old one
    /// ended up as peach with black eyes in the middle of it.
    static func composedBlanch(mood: PetMood, t: Double,
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
    static func composedTint(mood: PetMood, t: Double, rainbowElapsed: Double?,
                             celebrating: Bool, epic: Bool = false,
                             taskFraction: Double?) -> Color? {
        if let rainbowElapsed, let party = rainbowTint(elapsed: rainbowElapsed) { return party }
        if mood == .done, celebrating, epic, let burst = epicTint(doneT: t) { return burst }
        if mood == .cooking {
            if let disco = discoTint(cookingT: t) { return disco }
            if let glow = nearDoneTint(cookingT: t, fraction: taskFraction) { return glow }
        }
        return nil
    }

    /// The body colour at a moment in the cycle, or nil when not partying.
    static func rainbowTint(elapsed: Double) -> Color? {
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
            let reacting = hoverSince != nil || clickedAt != nil || rainbowSince != nil
                || petSince != nil || pouncedAt != nil || snackSince != nil
            let interval = reacting ? 1.0 / 30 : frameInterval
            TimelineView(.periodic(from: Date(), by: interval)) { timeline in
                render(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func render(at time: Double) -> some View {
        // Live: rebase onto the mood so one-shot motion (the `done` hop) starts
        // at its own t=0. Frozen: the caller's time is already relative.
        var pose = currentPose(at: time)
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
                                         taskFraction: taskFraction)
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

    private func currentPose(at time: Double) -> CrabPose {
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
                                     hourOfDay: frozenTime == nil
                                         ? Calendar.current.component(.hour, from: Date())
                                         : nil)
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
        if let petSince, frozenTime == nil {
            CrabAnimator.applyPetting(elapsed: time - petSince,
                                      amount: Ease.amount(now: time,
                                                          since: petSince,
                                                          endedAt: petEndedAt),
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
