import Testing
import Foundation
@testable import ClaudePet

/// The flair dice: which fact showings drop the shades, dealt once on the
/// fact's own seed, coordinator-side — so the view rolls nothing and every
/// recompute of one showing agrees with itself.
@Suite("Shades flair")
struct ShadesFlairTests {

    /// About half the fact showings wear the shades; about a third of those
    /// land with the ding. Measured over enough seeds that the dice cannot
    /// hide, in both moods that allow it.
    @Test("The rates are the operator's: half shades, a third of those ding")
    func theRatesHold() {
        for mood in [PetMood.idle, .working] {
            var shades = 0, dings = 0
            let n = 20_000
            for seed in 0..<n {
                switch ActivityCoordinator.factFlair(seed: seed, mood: mood) {
                case .shades: shades += 1
                case .shadesDing: shades += 1; dings += 1
                case .none: break
                }
            }
            let shadeRate = Double(shades) / Double(n)
            let dingShare = Double(dings) / Double(max(1, shades))
            #expect(abs(shadeRate - 0.5) < 0.02,
                    "\(mood): shades on \(shadeRate) of showings, wanted ~half")
            #expect(abs(dingShare - 0.35) < 0.03,
                    "\(mood): \(dingShare) of shaded landings ding, wanted ~0.35")
        }
    }

    /// The moods that must never flair: cooking (the fire IS the signal),
    /// sleeping (shades over shut eyes), and everything urgent.
    @Test("Only idle and working facts may wear them")
    func theMoodGateHolds() {
        for mood in [PetMood.cooking, .sleeping, .thinking, .done,
                     .nudging, .needsAttention] {
            for seed in stride(from: 0, to: 5_000, by: 7) {
                #expect(ActivityCoordinator.factFlair(seed: seed, mood: mood) == .none,
                        "\(mood) flaired on seed \(seed)")
            }
        }
    }

    /// Shared-multiplier-distinct-addend at work: the shades die must not
    /// shadow the fact die on the same seeds, or half the informational
    /// cycles would be structurally shadeless.
    @Test("The shades die is independent of the fact die")
    func theDiceAreIndependent() {
        var informationalShaded = 0, informational = 0
        for seed in 0..<20_000 where ActivityCoordinator.informationalBeat(seed: seed) {
            informational += 1
            if ActivityCoordinator.factFlair(seed: seed, mood: .idle) != .none {
                informationalShaded += 1
            }
        }
        let rate = Double(informationalShaded) / Double(max(1, informational))
        #expect(abs(rate - 0.5) < 0.03,
                "shades correlate with the fact die: \(rate) among informational seeds")
    }
}

/// The MLG drop itself: a whole-pixel fall from off-sprite, an overshoot
/// beat, and a clean exit — pure in elapsed time, unreachable by any
/// committed render.
@Suite("Shades drop")
@MainActor
struct ShadesDropTests {

    /// The envelope, cell by cell: starts fully off-sprite (nothing pops in),
    /// falls monotonically at no more than two rows per 30fps frame — the
    /// grid's quantum, twice, which is the fall's stated budget — lands
    /// exactly at rest, overshoots exactly one row, settles.
    @Test("The fall is whole-pixel, monotone, and lands on the beat")
    func theFallIsHonest() {
        #expect(CrabAnimator.shadesDropRows(elapsed: 0) == -16,
                "the pair must start fully off-sprite — a visible pop-in is not a drop")
        var last = -16
        for step in stride(from: 0.0, through: CrabAnimator.shadesDropDuration, by: 1.0 / 30) {
            let rows = CrabAnimator.shadesDropRows(elapsed: step)
            #expect(rows >= last, "the fall reversed at \(step)s")
            #expect(rows - last <= 2, "the fall jumped \(rows - last) rows at \(step)s")
            last = rows
        }
        // Touchdown IS the overshoot: the pair lands one row low (+1) and
        // settles up to rest — a bounce goes past the mark, then home.
        #expect(CrabAnimator.shadesDropRows(elapsed: CrabAnimator.shadesDropDuration) == 1,
                "the overshoot beat is the sticker bounce — it must exist")
        #expect(CrabAnimator.shadesDropRows(elapsed: CrabAnimator.shadesDropDuration + 0.2) == 0)
        #expect(CrabAnimator.shadesDropRows(elapsed: 10) == 0)
    }

    /// The frozen sentinel, stated as a sweep: no schedule inside `pose()`
    /// ever reaches the shades. They exist only through the latch, so no
    /// committed still, GIF, or sheet can catch them.
    @Test("No pose schedule can reach the shades")
    func noScheduleReachesThem() {
        for mood in PetMood.allCases {
            for t in stride(from: 0.0, through: 8.0, by: 0.25) {
                let pose = CrabAnimator.pose(mood: mood, t: t, flourishes: true)
                #expect(pose.prop != .shades,
                        "\(mood) at \(t)s wore the shades with no latch")
                #expect(pose.shadesDrop == 0 && pose.shadesGlint == false,
                        "\(mood) at \(t)s carried drop channels with no latch")
            }
        }
    }

    /// The incumbent survives: whatever the mood had in the prop slot steps
    /// into the ghost channel for the stay and is untouched once the exit
    /// completes.
    @Test("The working prop steps aside and comes back")
    func theIncumbentSurvives() {
        var pose = CrabAnimator.pose(mood: .working, t: 3, flourishes: false)
        let incumbent = pose.prop
        #expect(incumbent != .none, "the working pose should carry a prop")

        var midFall = pose
        CrabAnimator.applyShadesDrop(elapsed: 0.25, endedElapsed: nil,
                                     ding: false, to: &midFall)
        #expect(midFall.prop == .shades)
        #expect(midFall.propVisibility == 1, "the pair falls OPAQUE — that is the gag")
        #expect(midFall.ghostProp == incumbent,
                "the incumbent must dissolve in the ghost channel, not vanish")

        var after = pose
        CrabAnimator.applyShadesDrop(elapsed: 20,
                                     endedElapsed: CrabAnimator.shadesFade + 0.1,
                                     ding: true, to: &after)
        #expect(after == pose, "a finished exit must leave the pose untouched")
    }

    /// The ding sparkle exists only in its beat: after touchdown, before the
    /// glow would overstay, never on a dingless showing, never mid-exit.
    @Test("The ding lives in its beat and nowhere else")
    func theDingWindow() {
        func glint(elapsed: Double, ended: Double? = nil, ding: Bool = true) -> Bool {
            var pose = CrabAnimator.pose(mood: .idle, t: 3, flourishes: false)
            CrabAnimator.applyShadesDrop(elapsed: elapsed, endedElapsed: ended,
                                         ding: ding, to: &pose)
            return pose.shadesGlint
        }
        #expect(!glint(elapsed: 0.2), "no sparkle before touchdown")
        #expect(glint(elapsed: CrabAnimator.shadesDropDuration + 0.1))
        #expect(!glint(elapsed: CrabAnimator.shadesDropDuration + 0.4),
                "the sparkle overstayed its beat")
        #expect(!glint(elapsed: CrabAnimator.shadesDropDuration + 0.1, ding: false),
                "a dingless showing must not sparkle")
        #expect(!glint(elapsed: CrabAnimator.shadesDropDuration + 0.1, ended: 0.05),
                "no sparkle once the exit has begun")
    }
}
