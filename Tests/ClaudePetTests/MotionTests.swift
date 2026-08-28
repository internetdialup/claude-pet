import Testing
import Foundation
import AppKit
import SwiftUI
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

    /// The no-snap rule INSIDE a mood, which nothing checked.
    ///
    /// `blendStepsAreBounded` covers the cross-fade between two moods, so a
    /// mood whose own steady-state motion teleported was invisible to the
    /// suite — and `.needsAttention` did exactly that, flipping bob between 0
    /// and -2 on a hard `sin > 0` threshold. Two pixels in one frame is a
    /// snap, and at four radians a second it read as a flicker rather than a
    /// bounce.
    ///
    /// Sampled at each mood's OWN frame rate, because that is the only rate
    /// the operator ever sees, and with flourishes off: a jump is allowed to
    /// leave the ground, and it is the resting behaviour under test here.
    @Test func moodMotionNeverTeleports() {
        for mood in PetMood.allCases {
            let step = mood.style.frameInterval
            var previous = CrabAnimator.pose(mood: mood, t: 0, flourishes: false)
            var t = step
            while t <= 12.0 {
                let pose = CrabAnimator.pose(mood: mood, t: t, flourishes: false)
                #expect(abs(pose.bob - previous.bob) <= 1,
                        "\(mood) bob jumped \(pose.bob - previous.bob) at t=\(t)")
                #expect(abs(pose.lean - previous.lean) <= 1,
                        "\(mood) lean jumped \(pose.lean - previous.lean) at t=\(t)")
                previous = pose
                t += step
            }
        }
    }

    /// The nudge beacon is an escalation with an end: silent for the first
    /// eighteen seconds while his pose does the asking on its own, then a
    /// breath every eighteen, then nothing at all after three minutes.
    @Test("The waiting light escalates, then gives up")
    func theWaitingLightKnowsWhenToStop() {
        #expect(WaitingLight.breath(nudgeT: 0) == 0, "frozen sentinel")
        for t in stride(from: 0.0, through: 17.9, by: 0.2) {
            #expect(WaitingLight.breath(nudgeT: t) == 0,
                    "it breathed at t=\(t), before his pose had a chance")
        }

        var breaths = 0
        var t = 0.0
        var lastStart = -100.0
        while t < 600 {
            if WaitingLight.breath(nudgeT: t) > 0 {
                if t - lastStart > 5 { breaths += 1; lastStart = t }
                t += 0.1
            } else {
                t += 0.1
            }
        }
        #expect(breaths == 10, "expected ten asks, got \(breaths)")

        // …and then it is done, for good.
        for t in stride(from: 200.0, through: 3600.0, by: 1.7) {
            #expect(WaitingLight.breath(nudgeT: t) == 0, "still breathing at t=\(t)")
        }
    }

    @Test("The waiting light never snaps, and stays soft")
    func theWaitingLightEasesBothWays() {
        var previous = 0.0
        for step in 0...(200 * 30) {
            let value = WaitingLight.breath(nudgeT: Double(step) / 30)
            #expect(value >= 0 && value <= 1)
            #expect(abs(value - previous) < 0.15,
                    "a \(abs(value - previous)) jump at step \(step) is a snap")
            previous = value
        }
    }

    /// The review loop had two opposite faults at once. It hard-coded
    /// `t = 18 + now % 6`, jumping past the `guard cycle > 0` that gives the
    /// live light its ease-from-zero — a full gold ring in one frame, 43% of
    /// the time — and its 6s rest left 3.4s of nothing after clicking a menu
    /// item, which reads as a broken menu rather than as a pause.
    @Test("The waiting light's preview starts dark and never rests for long")
    func thePreviewBreathStartsFromNothing() {
        #expect(WaitingLight.previewBreath(t: 0) == 0, "it arrived mid-breath")

        var previous = 0.0
        var longestDark = 0.0
        var darkSince: Double?
        for step in 0...(Int(WaitingLight.previewPeriod * 4) * 30) {
            let t = Double(step) / 30
            let value = WaitingLight.previewBreath(t: t)
            #expect(value >= 0 && value <= 1)
            #expect(abs(value - previous) < 0.15,
                    "a \(abs(value - previous)) jump at t=\(t) is a snap")
            if value <= 0.001 {
                if darkSince == nil { darkSince = t }
            } else if let began = darkSince {
                longestDark = max(longestDark, t - began)
                darkSince = nil
            }
            previous = value
        }
        #expect(longestDark < 1.6,
                "selecting the waiting light showed nothing for \(longestDark)s")
    }

    /// A pet nobody can see should not be animating at twenty frames a second.
    /// Nothing observed display sleep or occlusion before this, so the timeline
    /// ticked at full rate with the screen off, all night.
    @Test("An unseen pet stops animating, whatever else is true")
    func unseenOutranksEverything() {
        let idle = PetMood.idle.style.frameInterval
        #expect(CrabView.tickInterval(unseen: false, reacting: false, mood: idle) == idle)
        #expect(CrabView.tickInterval(unseen: false, reacting: true, mood: idle) == 1.0 / 30,
                "a reaction still gets the smooth rate")
        // …and unseen beats both, including a reaction — there is nobody there
        // to react for.
        #expect(CrabView.tickInterval(unseen: true, reacting: false, mood: idle) == 1.0)
        #expect(CrabView.tickInterval(unseen: true, reacting: true, mood: idle) == 1.0)
        for mood in PetMood.allCases {
            #expect(CrabView.tickInterval(unseen: true, reacting: true,
                                          mood: mood.style.frameInterval) == 1.0,
                    "\(mood) kept animating unseen")
        }
    }

    /// The hour memo has to answer the same thing `Calendar` does — it is the
    /// gate on the telescope and the patch of sun, and a wrong hour there is a
    /// schedule firing at the wrong time of day.
    @Test("The cached hour agrees with the calendar")
    @MainActor
    func theHourCacheIsHonest() {
        LocalHour.invalidate()
        let fresh = Calendar.current.component(.hour, from: Date())
        #expect(LocalHour.current == fresh, "the memo disagrees with the calendar")
        // …and repeated reads, which is the whole point, keep agreeing.
        for _ in 0..<50 { #expect(LocalHour.current == fresh) }
    }

    /// The sleeping clip has to contain a whole breath and close on itself.
    ///
    /// This fails on the old pose: a 4.0s clip over a 6.98s cycle is 57% of a
    /// breath, so `sleeping.gif` jumped at the loop — and 41 of its 48 frames
    /// were pixel-identical, because a one-pixel square wave spends 85% of its
    /// cycle on one value.
    @Test("The sleeping clip is exactly one breath, and it closes")
    func theSleepingClipIsOneWholeBreath() {
        let clip = PetMood.sleeping.style.clipSeconds
        #expect(clip == CrabAnimator.breathPeriod,
                "the clip must be derived from the breath, not written down beside it")

        let open = CrabAnimator.pose(mood: .sleeping, t: 0, flourishes: false)
        let close = CrabAnimator.pose(mood: .sleeping, t: clip, flourishes: false)
        #expect(open.bob == 0, "t=0 should be the top of the breath")

        // Compare the RENDERED frames, not the poses. `propPhase` carries raw
        // `t` whether or not there is a prop, so two poses a whole period apart
        // differ in a field that draws nothing — the thing that has to loop is
        // the picture.
        let first = CrabRig.render(open)
        let last = CrabRig.render(close)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                #expect(first[x, y] == last[x, y],
                        "the loop does not close: (\(x),\(y)) differs")
            }
        }

        // Three depths, and it steps rather than jumping between them.
        var depths = Set<Int>()
        var previous = open.bob
        for step in 0...Int(clip * 12) {          // the GIF's own rate
            let bob = CrabAnimator.pose(mood: .sleeping, t: Double(step) / 12,
                                        flourishes: false).bob
            depths.insert(bob)
            #expect(abs(bob - previous) <= 1, "the breath jumped \(bob - previous)")
            previous = bob
        }
        #expect(depths.count >= 3, "a two-value breath reads as a twitch, not a breath")
    }

    /// The z's are gone; the lowered lids are what carry "asleep" in the still,
    /// where the breath cannot help.
    ///
    /// It was a head tilt until the operator reported it as a broken eye. They
    /// were right, and the reason is measurable rather than a matter of taste
    /// — see `eyesAreNeverUneven` below.
    @Test("A sleeping crab wears no prop, and lowers his lids")
    func theSleepingPoseCarriesNoProp() {
        let pose = CrabAnimator.pose(mood: .sleeping, t: 2, flourishes: false)
        #expect(pose.prop == .none)
        #expect(pose.blink == 1, "his eyes stay shut")
        #expect(pose.lidsLowered, "the lowered lids are the only thing left in the still")
        #expect(pose.tilt == 0, "a shut lid cannot carry a tilt")
    }

    /// **His eyes are level, in every mood, at every instant.**
    ///
    /// Rendered, not reasoned about. The bug this pins was invisible to every
    /// existing test because nothing looked at the OUTPUT: the sleeping pose
    /// set a one-pixel tilt, `drawFace` raised one eye and dropped the other,
    /// and the two shut lids came out on rows 13 and 15 — a two-pixel gap on a
    /// thirty-two-pixel sprite, in 100% of sleeping frames. Every awake mood
    /// measured 0%.
    ///
    /// A tilt is still legal and the sizzle still uses it: at `eyeSize` 3 the
    /// two blocks overlap by a row and the head reads as tipped. What this
    /// forbids is the case where it cannot read — eyes so thin that an offset
    /// is the only thing you see.
    @Test("His eyes are never uneven")
    func eyesAreNeverUneven() {
        func eyeRows(_ buffer: PixelBuffer) -> (left: Int?, right: Int?) {
            var left: Int?, right: Int?
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where buffer[x, y] == .eye {
                    if x < PixelBuffer.side / 2 { left = left ?? y } else { right = right ?? y }
                }
            }
            return (left, right)
        }

        for mood in PetMood.allCases {
            var t = 0.0
            while t < 20.0 {
                let pose = CrabAnimator.pose(mood: mood, t: t)
                // A wink is one eye shut on purpose — the asymmetry IS the
                // gesture, and it is the only one allowed.
                if pose.winkEye == .none {
                    let rows = eyeRows(CrabRig.render(pose))
                    if let l = rows.left, let r = rows.right {
                        #expect(l == r,
                                "\(mood.rawValue) at t=\(String(format: "%.2f", t)): left eye on row \(l), right on \(r)")
                    }
                }
                t += 0.25
            }
        }
    }

    /// The frozen sentinel, checked on the BODY rather than on the props.
    /// `nothingFiresAtTimeZero` looks at prop visibility, heat and glyphs, so
    /// it never saw that idle's cycle-0 flourish was always a jump and always
    /// already underway — `pose(mood: .idle, t: 0)` came back crouched, and
    /// `still-idle.png`, rendered at t = 0.4, was a crab five pixels up.
    @Test("Nobody is mid-flourish at the frozen instant")
    func idlePoseIsAtRestAtTimeZero() {
        #expect(CrabAnimator.flourish(at: 0) == nil, "a flourish is playing at t=0")
        for mood in PetMood.allCases {
            let zero = CrabAnimator.pose(mood: mood, t: 0)
            #expect(zero.squash == 0, "\(mood) is mid-squash at t=0")
            #expect(zero.scale == 1, "\(mood) is mid-scale at t=0")
        }
        // …and the instant every marketing still is sampled at.
        let still = CrabAnimator.pose(mood: .idle, t: 0.4)
        #expect(still.squash == 0 && still.bob >= -1,
                "still-idle.png is a crab in the air: bob=\(still.bob)")
    }

    /// The clip has to contain what it advertises. `idle`'s flourishes now
    /// start at cycle 1, and the six-second clip is shorter than the
    /// seven-second period, so an anchor at zero would capture nothing.
    @Test("The idle clip still catches a flourish")
    func idleClipContainsAFlourish() {
        let begin = CrabAnimator.firstFlourishAt
        #expect(begin > 0)
        var seen = false
        var t = begin
        while t < begin + PetMood.idle.style.clipSeconds {
            if CrabAnimator.flourish(at: t) != nil { seen = true; break }
            t += 1.0 / 12
        }
        #expect(seen, "six seconds from \(begin) contains no flourish")
        #expect(PetMood.idle.style.clipStart == begin)
        for mood in PetMood.allCases where mood != .idle {
            #expect(mood.style.clipStart == 0, "\(mood) should still start at zero")
        }
    }

    /// `moodMotionNeverTeleports` checks bob and lean, and calls `pose(mood:t:)`
    /// with no hour — so the telescope never comes out in it and the gaze
    /// channels were never checked at all. Both eyes used to jump two rows in
    /// one frame on a third of every stargaze firing.
    @Test("The stargazer's gaze eases in and out instead of snapping")
    func gazeOverridesNeverTeleport() {
        // Every firing cycle in a day of night-time idling, at idle's 20fps.
        var firings = 0
        for cycle in 1...720 where CrabAnimator.noise(cycle &* 61 &+ 3) < 0.35 {
            firings += 1
            let base = Double(cycle) * 120
            var previous = CrabAnimator.pose(mood: .idle, t: base - 0.05,
                                             flourishes: false, hourOfDay: 1)
            var step = 0
            while step <= 13 * 20 {
                let t = base + Double(step) / 20
                let pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false, hourOfDay: 1)
                #expect(abs(pose.gazeY - previous.gazeY) <= 1,
                        "gazeY jumped \(pose.gazeY - previous.gazeY) at t=\(t)")
                #expect(abs(pose.gazeX - previous.gazeX) <= 1,
                        "gazeX jumped \(pose.gazeX - previous.gazeX) at t=\(t)")
                previous = pose
                step += 1
            }
        }
        #expect(firings > 100, "a day of small-hours idling should fire plenty of telescopes")
    }

    /// The bug puts his eyes on the floor and the telescope puts them on the
    /// sky. All three ambient treats start on cycle boundaries with periods
    /// that share multiples, so they collide 57 times a day — and this is the
    /// one pairing where he would have to look two ways at once.
    @Test("The telescope and the floor bug are never out together")
    func theTelescopeOwnsItsSpell() {
        var sawTelescope = false
        for cycle in 1...720 where CrabAnimator.noise(cycle &* 61 &+ 3) < 0.35 {
            for step in 0...(12 * 5) {
                let t = Double(cycle) * 120 + Double(step) / 5
                let pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false, hourOfDay: 1)
                guard pose.stargaze > 0 else { continue }
                sawTelescope = true
                #expect(pose.bugX == nil, "a bug visited mid-telescope at t=\(t)")
                #expect(pose.prop != .balloon, "a balloon floated up mid-telescope at t=\(t)")
            }
        }
        #expect(sawTelescope)
    }

    /// The celebration overlay is applied ON TOP of the done pose, so
    /// `moodMotionNeverTeleports` never saw it — and its two re-armed hops kept
    /// the very shape the base hop was rewritten to lose.
    @Test func celebrationMotionNeverTeleports() {
        let step = PetMood.done.style.frameInterval
        for epic in [false, true] {
            var previous: CrabPose?
            var t = 0.0
            while t <= 12.0 {
                var pose = CrabAnimator.pose(mood: .done, t: t, flourishes: false)
                CrabAnimator.applyCelebration(t: t, epic: epic, to: &pose)
                if let previous {
                    #expect(abs(pose.bob - previous.bob) <= 1,
                            "celebration bob jumped \(pose.bob - previous.bob) at t=\(t) epic=\(epic)")
                }
                previous = pose
                t += step
            }
        }
    }

    /// Arms are a Double channel, but `CrabRig.drawArm` quantises them to whole
    /// cells — so the no-snap rule applies to the DRAWN reach, not to the raw
    /// value. `.needsAttention` used to flip 0.7 to 1.0 on a hard threshold,
    /// which is four cells to six in one frame, about three times a second.
    @Test func armReachLandsOnEveryCell() {
        func reach(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 6).rounded()) }
        for mood in PetMood.allCases {
            let step = mood.style.frameInterval
            let first = CrabAnimator.pose(mood: mood, t: 0, flourishes: false)
            var left = reach(first.armLeft), right = reach(first.armRight)
            var t = step
            while t <= 12.0 {
                let pose = CrabAnimator.pose(mood: mood, t: t, flourishes: false)
                let nextLeft = reach(pose.armLeft), nextRight = reach(pose.armRight)
                #expect(abs(nextLeft - left) <= 1,
                        "\(mood) left arm skipped \(abs(nextLeft - left)) cells at t=\(t)")
                #expect(abs(nextRight - right) <= 1,
                        "\(mood) right arm skipped \(abs(nextRight - right)) cells at t=\(t)")
                left = nextLeft
                right = nextRight
                t += step
            }
        }
    }

    /// The states that are asking you something have to be seen from across
    /// the room, so they get real travel rather than a one-pixel twitch.
    @Test func theAskingMoodsCarry() {
        for mood in [PetMood.nudging, .needsAttention] {
            var lowest = Int.max, highest = Int.min
            var t = 0.0
            while t <= 12.0 {
                let bob = CrabAnimator.pose(mood: mood, t: t, flourishes: false).bob
                lowest = min(lowest, bob)
                highest = max(highest, bob)
                t += mood.style.frameInterval
            }
            #expect(highest - lowest >= 2,
                    "\(mood) travels \(highest - lowest)px — too small to notice")
        }
    }

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

    /// A full dissolve draws the whole prop, a partial one draws part of it,
    /// and nothing draws none.
    ///
    /// This replaces a test that could not fail. It rendered a `.working` pose
    /// at t = 3, copied it, set `propVisibility = 1` on the copy, and compared
    /// the two renders — but at t = 3 the pose is in cycle 0 with no boundary
    /// nearby, so `propVisibility` was ALREADY exactly 1 and the assignment
    /// changed nothing. It compared a render against itself and passed on any
    /// dissolve behaviour whatsoever, including none.
    @Test func theDissolveActuallyDissolves() {
        func lit(_ buffer: PixelBuffer) -> Int {
            var count = 0
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where buffer[x, y] != .clear { count += 1 }
            }
            return count
        }

        var pose = CrabAnimator.pose(mood: .working, t: 3)
        pose.prop = .terminal

        pose.propVisibility = 0
        let none = lit(CrabRig.render(pose))
        pose.propVisibility = 0.5
        let half = lit(CrabRig.render(pose))
        pose.propVisibility = 1
        let whole = lit(CrabRig.render(pose))

        #expect(whole > none, "a fully visible prop drew nothing")
        #expect(half > none, "a half dissolve drew no more than an absent prop")
        #expect(half < whole, "a half dissolve drew the whole prop — \(none)/\(half)/\(whole)")
    }

    @Test("A hit holds at exactly one, and is its own frozen sentinel")
    func pulseHoldsAndSleeps() {
        #expect(Ease.pulse(0, attack: 0.09, hold: 0.12, decay: 0.28) == 0, "frozen sentinel")
        #expect(Ease.pulse(-1, attack: 0.09, hold: 0.12, decay: 0.28) == 0)
        #expect(Ease.pulse(0.5, attack: 0.09, hold: 0.12, decay: 0.28) == 0, "past the tail")
        // The plateau: anywhere inside [attack, attack + hold] is exactly 1.
        // Reaching EXACTLY 1 is the point — a hit that tops out at 0.9 is a
        // grey, and a hit that tops out at 0.4 is the peach this replaced.
        #expect(Ease.pulse(0.10, attack: 0.09, hold: 0.12, decay: 0.28) == 1)
        #expect(Ease.pulse(0.20, attack: 0.09, hold: 0.12, decay: 0.28) == 1)
        // And it ramps rather than steps on both sides.
        let rising = Ease.pulse(0.045, attack: 0.09, hold: 0.12, decay: 0.28)
        let falling = Ease.pulse(0.35, attack: 0.09, hold: 0.12, decay: 0.28)
        #expect(rising > 0.4 && rising < 0.6)
        #expect(falling > 0.05 && falling < 0.95)
    }
}

/// The blanch: the channel that takes the WHOLE sprite to white, as opposed to
/// `bodyTint`, which reaches one ink by design. These are the tests that would
/// have caught the peach — a "white" flash that left black eyes and a dark
/// costume standing in the middle of it.
@Suite("The blanch")
@MainActor
struct BlanchTests {

    /// A fixture carrying every hard case at once: heat bands present, and the
    /// Gundam wardrobe, whose `costumeC` is near-black, whose eyes are
    /// overridden yellow, and whose `costumeA`/`costumeB` are saturated.
    private func hardestBuffer() -> PixelBuffer {
        var pose = CrabAnimator.pose(mood: .done, t: 0.3)
        pose.heat = 1
        pose.heatPhase = 0.4
        return CrabRig.render(pose, costume: .gundam, costumeVisibility: 1)
    }

    private func pixels(_ view: some View) throws -> NSBitmapImageRep {
        let image = try #require(SpriteImage.cgImage(of: view.frame(width: 96, height: 96)))
        return NSBitmapImageRep(cgImage: image)
    }

    @Test("At full blanch every lit cell is pure white — eyes and costume too")
    func fullBlanchIsPureWhite() throws {
        let rep = try pixels(PixelCanvasView(buffer: hardestBuffer(),
                                             inkOverrides: CostumeStyle.blendedOverrides(
                                                from: .none, to: .gundam, u: 1),
                                             seamBleed: 0,
                                             blanch: 1))
        var checked = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let colour = rep.colorAt(x: x, y: y),
                      colour.alphaComponent > 0.99 else { continue }
                checked += 1
                #expect(colour.redComponent > 0.99 && colour.greenComponent > 0.99
                        && colour.blueComponent > 0.99,
                        "an opaque cell at (\(x),\(y)) survived the flash: \(colour)")
            }
        }
        #expect(checked > 500, "the fixture should cover a real sprite, not a few cells")
    }

    /// `seamBleed: 0` on purpose. At the default 0.5 the run rects end on
    /// half-points, and comparing two INDEPENDENT renders of antialiased edges
    /// is the byte-instability this suite has a documented history of (the
    /// glow's fractional centre, the `.clipped()` incident) — it fails
    /// intermittently under full-suite parallel load and passes in isolation,
    /// which makes it a coin flip rather than a pin. Whole-pixel geometry has
    /// no antialiasing to be unstable about, so the byte comparison means what
    /// it says. What is under test is the `> 0.001` guard skipping the wash
    /// entirely, and that is geometry-independent.
    @Test("Blanch zero is the identity — inert for every existing caller")
    func blanchZeroIsIdentity() throws {
        let buffer = hardestBuffer()
        let plain = SpriteImage.png(of: PixelCanvasView(buffer: buffer, seamBleed: 0)
            .frame(width: 96, height: 96))
        let unlit = SpriteImage.png(of: PixelCanvasView(buffer: buffer, seamBleed: 0, blanch: 0)
            .frame(width: 96, height: 96))
        #expect(plain != nil && plain == unlit)
    }

    /// The seam trap. `seamBleed` (0.5 in the live view) makes neighbouring run
    /// rects OVERLAP, so a wash filled per-run would composite white twice down
    /// every seam and paint a bright grid across a sprite whose palette forbids
    /// shading — and an even-odd fill of the union would punch transparent
    /// holes there instead. One non-zero-wound path over the union does
    /// neither. A solid block spanning many runs makes either bug visible as a
    /// pixel that differs from its neighbours.
    @Test("A partial blanch leaves no seam grid across a solid area")
    func partialBlanchHasNoSeams() throws {
        var buffer = PixelBuffer()
        for y in 8..<24 {
            for x in 8..<24 { buffer[x, y] = .body }
        }
        let rep = try pixels(PixelCanvasView(buffer: buffer, blanch: 0.5))
        // Sample well inside the block so no antialiased outer edge is caught:
        // grid cells 10…21 at 3pt per cell.
        var seen = Set<Int>()
        for x in (10 * 3)...(21 * 3) {
            for y in (10 * 3)...(21 * 3) {
                let colour = try #require(rep.colorAt(x: x, y: y))
                #expect(colour.alphaComponent > 0.99, "a hole at (\(x),\(y)) — even-odd fill?")
                seen.insert(Int((colour.redComponent * 255).rounded()))
            }
        }
        #expect(seen.count == 1,
                "uneven wash across a solid block (\(seen.sorted())) — it composited more than once somewhere")
    }

    @Test("The blanch ramps the darkest ink rather than snapping it")
    func blanchIsMonotoneNotBinary() throws {
        // Sampled on the whole sprite rather than one cell: the darkest pixel
        // in the frame has to climb with the wash, which is the property that
        // matters and the one that cannot drift with the rig's geometry.
        var previous = -1.0
        for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let rep = try pixels(PixelCanvasView(buffer: hardestBuffer(),
                                                 seamBleed: 0,
                                                 blanch: amount))
            var darkest = 1.0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let colour = rep.colorAt(x: x, y: y),
                          colour.alphaComponent > 0.99 else { continue }
                    darkest = min(darkest, colour.redComponent)
                }
            }
            #expect(darkest > previous,
                    "blanch \(amount) did not lift the darkest ink past \(previous)")
            previous = darkest
        }
        #expect(previous > 0.99, "a full blanch must land the darkest ink on white")
    }
}
