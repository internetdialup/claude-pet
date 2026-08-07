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
    private static func noise(_ n: Int) -> Double {
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
    enum Flourish: CaseIterable {
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

    /// A prop for the current work spell. Re-rolled every `spell` seconds so a
    /// long task does not stare at the same terminal window for ten minutes.
    static func workingProp(at t: Double, spell: Double = 20) -> CrabPose.Prop {
        let cycle = Int(floor(t / spell))
        let options = CrabPose.Prop.working
        return options[Int(noise(cycle &* 13 &+ 5) * Double(options.count)) % options.count]
    }

    public static func pose(mood: PetMood, t: Double) -> CrabPose {
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

            if let (kind, progress) = flourish(at: t) {
                apply(kind, progress: progress, t: t, to: &pose)
            }

        case .thinking:
            pose.bob = sin(t * 3.0) > 0 ? 0 : 1
            pose.blink = blink(at: t, period: 3.2)
            // Eyes scanning side to side — the "working it out" tell.
            pose.gazeX = sin(t * 1.6) > 0 ? 1 : -1
            pose.mouth = .flat
            pose.prop = .sparkles

        case .working:
            // Deliberately unhurried. At the original rates the arms and legs
            // flickered several times a second, which read as agitation and was
            // distracting in peripheral vision — the pet lives on the desktop
            // all day, so busy has to stay calm.
            pose.bob = sin(t * 2.2) > 0 ? 0 : 1
            pose.blink = blink(at: t, period: 4.0)
            pose.gazeY = 1                       // looking down at the work
            // Arms alternate like hands on a keyboard, about one beat a second.
            pose.armLeft = sin(t * 2.6) > 0 ? 0.35 : 0
            pose.armRight = sin(t * 2.6) > 0 ? 0 : 0.35
            pose.legPhase = t * 2.4
            pose.legAmplitude = 1
            pose.prop = workingProp(at: t)

        case .cooking:
            // Head down, working fast, on fire. Quicker than `.working` but not
            // frantic — this is flow, not panic.
            pose.bob = sin(t * 3.4) > 0 ? 0 : 1
            pose.blink = blink(at: t, period: 5.0)
            pose.eyes = .determined
            pose.gazeY = 1
            pose.mouth = .flat
            pose.armLeft = sin(t * 4.2) > 0 ? 0.4 : 0
            pose.armRight = sin(t * 4.2) > 0 ? 0 : 0.4
            pose.legPhase = t * 4
            pose.legAmplitude = 1
            pose.prop = .fire

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
            pose.legPhase = .pi / 2
            pose.legAmplitude = sin(t * 5) > 0.4 ? 1 : 0
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
    public static func applyGreeting(elapsed: Double, seed: Int = 0, to pose: inout CrabPose) {
        let greeting = greeting(forSeed: seed)

        // A startled hop on arrival, common to every variant — he noticed you.
        if elapsed < 0.30 {
            pose.bob -= 3
            pose.squash = 0
        } else if elapsed < 0.42 {
            pose.squash = 1
            pose.bob += 1
        }

        pose.asleepOverride = true      // eyes open even in the sleeping pose
        pose.gazeX = 0
        pose.gazeY = -1                 // looking up, out of the screen at you

        switch greeting {
        case .wave:
            pose.blink = 0
            pose.mouth = .open
            pose.armRight = max(pose.armRight, 0.55 + (sin(elapsed * 8) > 0 ? 0.25 : 0))

        case .wink:
            // Routed through `winkEye` rather than `blink`, which
            // `asleepOverride` vetoes.
            pose.mouth = .smile
            pose.blink = 0
            // A wink is a brief shut, not a held one. The first version used
            // `sin(elapsed * 2.2) > -0.3`, which keeps the eye closed for about
            // three quarters of every cycle — that does not read as a wink, it
            // reads as an eye that is stuck.
            let cycle = elapsed.truncatingRemainder(dividingBy: 1.5)
            pose.winkEye = cycle < 0.22 ? .right : .none
            // No tilt here. Tilt offsets the two eyes by a pixel in opposite
            // directions, and against a one-row shut eye that misalignment is
            // exactly what made the wink look wonky.
            pose.tilt = 0
            pose.armRight = max(pose.armRight, 0.35)

        case .hop:
            pose.mouth = .open
            pose.blink = 0
            // A repeating little bounce for as long as you stay.
            let bounce = abs(sin(elapsed * 4))
            pose.bob -= Int((bounce * 3).rounded())
            pose.squash = bounce < 0.15 ? 1 : 0
            pose.legAmplitude = 1.2
            pose.legPhase = .pi / 2

        case .wiggle:
            pose.mouth = .smile
            pose.blink = 0
            pose.lean += sin(elapsed * 9) > 0 ? -1 : 1
            pose.armLeft = max(pose.armLeft, 0.3)
            pose.armRight = max(pose.armRight, 0.3)
        }
    }

    /// The poke reaction: he squashes down, then springs back.
    ///
    /// - Parameter elapsed: seconds since the click.
    public static func applyClick(elapsed: Double, to pose: inout CrabPose) {
        guard elapsed >= 0, elapsed < clickDuration else { return }
        let progress = elapsed / clickDuration
        // Down fast, back slower — a spring, not a dip.
        let compression = progress < 0.35
            ? progress / 0.35
            : max(0, 1 - (progress - 0.35) / 0.65)
        pose.scale = 1 - 0.22 * compression
        pose.squash = compression > 0.5 ? 1 : 0
        pose.mouth = .open
    }

    public static let clickDuration = 0.34

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
    /// Reference-time instant the pointer arrived on him, or nil.
    public var hoverSince: Double?
    /// Reference-time instant he was last clicked, or nil.
    public var clickedAt: Double?
    /// Reference-time instant rainbow mode began, or nil. 🎉🪄
    public var rainbowSince: Double?
    /// Frozen time, for deterministic screenshots in the debug picker.
    public var frozenTime: Double?

    public init(mood: PetMood,
                hoverSince: Double? = nil,
                clickedAt: Double? = nil,
                rainbowSince: Double? = nil,
                frozenTime: Double? = nil) {
        self.mood = mood
        self.hoverSince = hoverSince
        self.clickedAt = clickedAt
        self.rainbowSince = rainbowSince
        self.frozenTime = frozenTime
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

    /// The body colour at a moment in the cycle, or nil when not partying.
    static func rainbowTint(elapsed: Double) -> Color? {
        guard elapsed >= 0, elapsed < rainbowDuration else { return nil }
        // Two full trips round the wheel, then out. Saturation stays under 1 so
        // he still reads as Claw'd wearing colours rather than a colour wheel.
        let hue = (elapsed / rainbowDuration * 2).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.72, brightness: 0.92)
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
            let reacting = hoverSince != nil || clickedAt != nil || rainbowSince != nil
            let interval = reacting ? 1.0 / 30 : frameInterval
            TimelineView(.periodic(from: Date(), by: interval)) { timeline in
                render(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func render(at time: Double) -> some View {
        // Live: rebase onto the mood so one-shot motion (the `done` hop) starts
        // at its own t=0. Frozen: the caller's time is already relative.
        PixelCanvasView(buffer: CrabRig.render(currentPose(at: time)),
                        bodyTint: rainbowSince.flatMap {
                            CrabView.rainbowTint(elapsed: time - $0)
                        })
            .drawingGroup()
    }

    private func currentPose(at time: Double) -> CrabPose {
        let t = frozenTime == nil ? time - moodEpoch : time

        // During the party the pose cycles too. `MoodClock` is deliberately
        // bypassed: it rebases time on every mood change, which at 0.8s per pose
        // would restart each one at t=0 and freeze the animation.
        if let rainbowSince, frozenTime == nil,
           let partyMood = CrabView.rainbowMood(elapsed: time - rainbowSince) {
            var pose = CrabAnimator.pose(mood: partyMood, t: time - rainbowSince)
            pose.mouth = .open
            return pose
        }

        var pose = CrabAnimator.pose(mood: mood, t: t)
        if let hoverSince, frozenTime == nil {
            // The hover's start instant doubles as the variant seed: chosen once
            // per hover, stable for its whole duration.
            CrabAnimator.applyGreeting(elapsed: time - hoverSince,
                                       seed: Int(hoverSince * 1000),
                                       to: &pose)
        }
        if let clickedAt, frozenTime == nil {
            CrabAnimator.applyClick(elapsed: time - clickedAt, to: &pose)
        }
        return pose
    }

    /// Set when the mood changes so transient animations replay from the start.
    private var moodEpoch: Double { MoodClock.shared.epoch(for: mood) }
}

/// Records when each mood was last entered, so `done` and `needsAttention`
/// replay their one-shot motion instead of joining mid-cycle.
@MainActor
final class MoodClock {
    static let shared = MoodClock()
    private var current: PetMood = .sleeping
    private var startedAt: Double = Date.timeIntervalSinceReferenceDate

    func epoch(for mood: PetMood) -> Double {
        if mood != current {
            current = mood
            startedAt = Date.timeIntervalSinceReferenceDate
        }
        return startedAt
    }
}
