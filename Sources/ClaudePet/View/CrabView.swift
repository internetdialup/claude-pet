import SwiftUI

/// Turns time + mood into a `CrabPose`, every frame.
///
/// All motion is a pure function of `(mood, elapsed)`, so the sprite cannot
/// drift out of sync with its state. Offsets are whole pixels: on a 32×32 grid a
/// half-pixel move just smears two rows and loses the pixel-art read.
public enum CrabAnimator {

    /// Deterministic pseudo-random in 0..<1, so blink timing is irregular but
    /// stable across frames (a real RNG would re-roll 60× a second).
    private static func noise(_ n: Int) -> Double {
        let x = Double((n &* 1_664_525 &+ 1_013_904_223) & 0x7FFF_FFFF)
        return x / Double(0x7FFF_FFFF)
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

    /// He notices you.
    ///
    /// Layered on top of whatever mood pose was already computed, so hovering a
    /// working Claw'd still shows his prop — he just looks up from it. Even
    /// asleep he stirs, which is the whole charm of poking a pet.
    ///
    /// - Parameter elapsed: seconds since the pointer arrived.
    public static func applyGreeting(elapsed: Double, to pose: inout CrabPose) {
        // A startled hop on arrival, then settle into looking at you.
        if elapsed < 0.30 {
            pose.bob -= 3
            pose.squash = 0
        } else if elapsed < 0.42 {
            pose.squash = 1
            pose.bob += 1
        }

        pose.asleepOverride = true      // eyes open even in the sleeping pose
        pose.blink = 0
        pose.gazeX = 0
        pose.gazeY = -1                 // looking up, out of the screen at you
        pose.mouth = .open

        // A small wave with the near arm, held for as long as you stay.
        pose.armRight = max(pose.armRight, 0.55 + (sin(elapsed * 8) > 0 ? 0.25 : 0))
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
    /// Reference-time instant the pointer arrived on him, or nil.
    public var hoverSince: Double?
    /// Frozen time, for deterministic screenshots in the debug picker.
    public var frozenTime: Double?

    public init(mood: PetMood, hoverSince: Double? = nil, frozenTime: Double? = nil) {
        self.mood = mood
        self.hoverSince = hoverSince
        self.frozenTime = frozenTime
    }

    /// How often the sprite is rebuilt, per mood.
    ///
    /// The sprite is whole pixels on a 32×32 grid, so nothing it can express
    /// needs 120 Hz. Driving `.animation` unconditionally meant an idle machine
    /// with zero Claude sessions rebuilt a 1024-cell buffer, rescanned it into
    /// runs, and re-composited an offscreen layer every display frame, all
    /// night. These rates are chosen against each mood's fastest motion.
    private var frameInterval: Double {
        switch mood {
        case .sleeping: 1.0 / 6      // a breath and drifting z's
        case .idle: 1.0 / 20         // blinks, gaze darts, occasional flourish
        case .thinking: 1.0 / 15
        case .working: 1.0 / 20      // typing arms and a scrolling terminal
        case .done, .needsAttention: 1.0 / 30   // one-shot motion, wants to pop
        }
    }

    public var body: some View {
        if let frozenTime {
            render(at: frozenTime)
        } else {
            // Hovering gets the smoother rate — that one is a direct response to
            // the pointer and needs to feel immediate.
            let interval = hoverSince == nil ? frameInterval : 1.0 / 30
            TimelineView(.periodic(from: Date(), by: interval)) { timeline in
                render(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func render(at time: Double) -> some View {
        // Live: rebase onto the mood so one-shot motion (the `done` hop) starts
        // at its own t=0. Frozen: the caller's time is already relative.
        PixelCanvasView(buffer: CrabRig.render(currentPose(at: time)))
            .drawingGroup()
    }

    private func currentPose(at time: Double) -> CrabPose {
        let t = frozenTime == nil ? time - moodEpoch : time
        var pose = CrabAnimator.pose(mood: mood, t: t)
        if let hoverSince, frozenTime == nil {
            CrabAnimator.applyGreeting(elapsed: time - hoverSince, to: &pose)
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
