import Testing
import Foundation
@testable import ClaudePet

/// The easing vocabulary's contract: envelopes hit their endpoints, rise
/// monotonically, and stay continuous across the attack→release handoff. The
/// no-snap rule is only as good as these shapes.
@Suite("Ease")
struct EaseTests {

    @Test func smoothstepEndpoints() {
        #expect(Ease.smoothstep(-1) == 0)
        #expect(Ease.smoothstep(0) == 0)
        #expect(Ease.smoothstep(1) == 1)
        #expect(Ease.smoothstep(2) == 1)
        #expect(abs(Ease.smoothstep(0.5) - 0.5) < 1e-12)
    }

    @Test func smoothstepMonotone() {
        var previous = -0.1
        for i in 0...100 {
            let v = Ease.smoothstep(Double(i) / 100)
            #expect(v >= previous)
            previous = v
        }
    }

    @Test func amountRisesAndHolds() {
        let since = 100.0
        #expect(Ease.amount(now: 99.9, since: since, endedAt: nil) == 0)
        #expect(Ease.amount(now: since + 0.35, since: since, endedAt: nil) == 1)
        #expect(Ease.amount(now: since + 10, since: since, endedAt: nil) == 1)
        let mid = Ease.amount(now: since + 0.17, since: since, endedAt: nil)
        #expect(mid > 0 && mid < 1)
    }

    @Test func amountIsContinuousAtRelease() {
        let since = 100.0
        // Release fired mid-rise: the envelope must pick up from the height it
        // had reached, not jump to 1 first.
        let endedAt = since + 0.2
        let before = Ease.amount(now: endedAt - 0.0001, since: since, endedAt: nil)
        let after = Ease.amount(now: endedAt + 0.0001, since: since, endedAt: endedAt)
        #expect(abs(before - after) < 0.01)
        // And it decays to zero within the release.
        #expect(Ease.amount(now: endedAt + 0.45, since: since, endedAt: endedAt) == 0)
    }

    @Test func squareSitsAtPolesOutsideTheSoftWindow() {
        // At the crests of the sine the eased square is pinned to its poles.
        #expect(abs(Ease.square(.pi / 2) - 1) < 1e-9)
        #expect(abs(Ease.square(3 * .pi / 2)) < 1e-9)
        // And in between it is strictly inside them.
        let edge = Ease.square(0.05)
        #expect(edge > 0 && edge < 1)
    }

    @Test func windowShape() {
        #expect(Ease.window(-0.1, duration: 10, edge: 0.6) == 0)
        #expect(Ease.window(0, duration: 10, edge: 0.6) == 0)
        #expect(Ease.window(5, duration: 10, edge: 0.6) == 1)
        #expect(Ease.window(10, duration: 10, edge: 0.6) == 0)
        let rising = Ease.window(0.3, duration: 10, edge: 0.6)
        #expect(rising > 0 && rising < 1)
    }
}

/// Continuity across mood changes: blending any mood pair at the crossfade's
/// frame rate must move every channel gradually. One-frame pops are exactly
/// what the blend exists to remove, so a pop here is a regression by
/// definition.
@Suite("Motion continuity")
struct MotionContinuityTests {

    /// Every mood pair, blended over the crossfade duration at 30fps: no Int
    /// channel may jump more than one pixel between consecutive frames, and no
    /// Double channel more than 0.15.
    @Test func blendStepsAreBounded() {
        let frames = Int((MoodClock.blendDuration * 30).rounded())   // 12
        for fromMood in PetMood.allCases {
            for toMood in PetMood.allCases where toMood != fromMood {
                let from = CrabAnimator.pose(mood: fromMood, t: 3.7)
                let to = CrabAnimator.pose(mood: toMood, t: 0)
                var previous = from
                for frame in 1...frames {
                    let u = Ease.smoothstep(Double(frame) / Double(frames))
                    let blended = CrabPose.blend(from: from, to: to, u: u)
                    #expect(abs(blended.bob - previous.bob) <= 1)
                    #expect(abs(blended.lean - previous.lean) <= 1)
                    #expect(abs(blended.squash - previous.squash) <= 1)
                    #expect(abs(blended.gazeX - previous.gazeX) <= 1)
                    #expect(abs(blended.gazeY - previous.gazeY) <= 1)
                    #expect(abs(blended.armLeft - previous.armLeft) <= 0.15)
                    #expect(abs(blended.armRight - previous.armRight) <= 0.15)
                    #expect(abs(blended.scale - previous.scale) <= 0.15)
                    previous = blended
                }
            }
        }
    }

    @Test func blendEndpointsAreExact() {
        let from = CrabAnimator.pose(mood: .working, t: 5)
        let to = CrabAnimator.pose(mood: .done, t: 0)
        #expect(CrabPose.blend(from: from, to: to, u: 0) == from)
        #expect(CrabPose.blend(from: from, to: to, u: 1) == to)
    }

    /// A blend across differing props carries the outgoing one as a dissolving
    /// ghost rather than deleting it.
    @Test func blendGhostsTheOutgoingProp() {
        var from = CrabAnimator.pose(mood: .nudging, t: 2)     // .plan
        from.prop = .plan
        let to = CrabAnimator.pose(mood: .done, t: 0)          // .check
        let mid = CrabPose.blend(from: from, to: to, u: 0.3)
        #expect(mid.ghostProp == .plan)
        #expect(mid.ghostPropVisibility > 0)
        #expect(mid.propVisibility < 1)
    }

    /// The working-prop re-roll dissolves across its spell boundary instead of
    /// teleporting: visibility dips into and out of the boundary, and only
    /// when the prop actually changes.
    @Test func propSwapDissolvesAtTheSpellBoundary() {
        // Find a boundary where the prop changes.
        var boundary: Double?
        for cycle in 1...40 {
            let t = Double(cycle) * 20
            if CrabAnimator.workingProp(at: t - 1) != CrabAnimator.workingProp(at: t + 1) {
                boundary = t
                break
            }
        }
        guard let boundary else {
            Issue.record("no prop change in 40 cycles — the dice are broken")
            return
        }
        let fadingOut = CrabAnimator.pose(mood: .working, t: boundary - 0.1)
        let fadingIn = CrabAnimator.pose(mood: .working, t: boundary + 0.1)
        let settled = CrabAnimator.pose(mood: .working, t: boundary + 1)
        #expect(fadingOut.propVisibility < 1)
        #expect(fadingIn.propVisibility < 1)
        #expect(settled.propVisibility == 1)
    }
}

/// The frozen sentinel: at t=0 no scheduled effect may be mid-flight. Offline
/// renderers and the debug picker freeze time at zero, so anything that fires
/// there ships in every screenshot.
@Suite("Frozen sentinel")
struct FrozenSentinelTests {

    @Test func nothingFiresAtTimeZero() {
        for mood in PetMood.allCases {
            let pose = CrabAnimator.pose(mood: mood, t: 0)
            #expect(pose.propVisibility == 1, "mood \(mood)")
            #expect(pose.ghostProp == .none, "mood \(mood)")
            #expect(pose.ghostPropVisibility == 0, "mood \(mood)")
            #expect(pose.heat == 0, "mood \(mood)")
            // Latch-driven, never scheduled — a frozen render must not carry
            // a service glyph a live latch never handed it.
            #expect(pose.serviceGlyph == nil, "mood \(mood)")
            #expect(pose.serviceGlyphVisibility == 0, "mood \(mood)")
        }
    }

    /// The first working spell never fades in — there was nothing before it to
    /// put down.
    @Test func firstSpellHasNoFadeIn() {
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(CrabAnimator.pose(mood: .working, t: t).propVisibility == 1)
        }
    }

    /// The dissolve at full visibility must be the identity — the pre-dissolve
    /// renderer byte for byte.
    @Test func fullVisibilityCompositeIsIdentity() {
        let pose = CrabAnimator.pose(mood: .working, t: 3)
        var direct = CrabRig.render(pose)
        var faded = pose
        faded.propVisibility = 1
        let rendered = CrabRig.render(faded)
        #expect(direct.runs().count == rendered.runs().count)
        for (a, b) in zip(direct.runs(), rendered.runs()) {
            #expect(a.x == b.x && a.y == b.y && a.length == b.length && a.ink == b.ink)
        }
        _ = direct
    }
}
