import Testing
import Foundation
@testable import ClaudePet

/// The tamagotchi rude awakening: poke a sleeping crab and one claw comes out
/// from under the covers WITH a zzz still rising, then his eyes open annoyed.
///
/// The whole sequence is a pure overlay on the still-sleeping pose (the
/// coordinator's stir is deferred by the click path), driven by one
/// self-closing envelope — so every promise here is arithmetic, not staging.
@Suite("Rude wake")
@MainActor
struct RudeWakeTests {

    private func sleepingBase(t: Double = 4) -> CrabPose {
        CrabAnimator.pose(mood: .sleeping, t: t, flourishes: false)
    }

    /// The frozen sentinel, free of charge: at and before zero the overlay is
    /// a no-op, so no still, sheet, or blend ghost can catch a half-raised claw.
    @Test("Nothing happens before it begins")
    func nothingHappensBeforeItBegins() {
        for elapsed in [-5.0, -0.1, 0.0] {
            var pose = sleepingBase()
            let before = pose
            CrabAnimator.applyRudeWake(elapsed: elapsed, to: &pose)
            #expect(pose == before, "a wake at \(elapsed)s moved him")
        }
    }

    /// It has to end on its own — the latch's clear-out waits a beat past the
    /// duration, and a stale latch must be able to strand nothing.
    @Test("It closes itself")
    func itClosesItself() {
        for elapsed in [CrabAnimator.rudeWakeDuration + 0.05,
                        CrabAnimator.rudeWakeDuration + 1.0, 10.0] {
            var pose = sleepingBase()
            let before = pose
            CrabAnimator.applyRudeWake(elapsed: elapsed, to: &pose)
            #expect(pose == before, "still waking at \(elapsed)s — the envelope never shut")
        }
    }

    /// The claw eases across drawArm's six-cell quantisation one cell at a
    /// time — the no-snap rule, measured at the render's own granularity.
    @Test("The arm rises through every cell")
    func theArmRisesThroughEveryCell() {
        var lastReach = 0
        for step in stride(from: 0.0, through: 0.6, by: 1.0 / 30) {
            var pose = sleepingBase()
            CrabAnimator.applyRudeWake(elapsed: step, to: &pose)
            let reach = Int((max(0, min(1, pose.armRight)) * 6).rounded())
            #expect(reach >= lastReach, "the claw dropped mid-rise at \(step)s")
            #expect(reach - lastReach <= 1, "the claw jumped \(reach - lastReach) cells at \(step)s")
            lastReach = reach
        }
        #expect(lastReach >= 4, "the claw only reached \(lastReach) cells — that is a twitch")
    }

    /// **Phase A is the operator's picture**: still demonstrably asleep — lids
    /// shut even against a hover greeting that opened them — with the zzz
    /// channel untouched, and the annoyed face already pre-seeded so the mood
    /// blend's discrete midpoint switch has nothing to swap later.
    @Test("Phase A keeps him asleep, with the z's")
    func phaseAKeepsHimAsleepWithTheZs() {
        var pose = sleepingBase()
        CrabAnimator.applyRudeWake(elapsed: 0.25, to: &pose)
        #expect(pose.blink == 1)
        #expect(pose.asleepOverride == false)
        #expect(pose.lidsLowered)
        #expect(pose.sleepZElapsed != nil, "the overlay cleared the zzz channel")
        #expect(pose.eyes == .determined, "the annoyed face must be pre-seeded from t=0")
        #expect(pose.mouth == .flat)
    }

    /// Phase B: eyes open, annoyed, at you.
    @Test("Then he is annoyed")
    func thenHeIsAnnoyed() {
        var pose = sleepingBase()
        CrabAnimator.applyRudeWake(elapsed: 0.8, to: &pose)
        #expect(pose.asleepOverride, "the eyes never opened")
        #expect(pose.blink == 0)
        #expect(pose.lidsLowered == false)
        #expect(pose.eyes == .determined)
        #expect(pose.mouth == .flat)
        #expect(pose.gazeY == -1, "he should be glaring up at the poker")
    }

    /// The ordering contract with the hover greeting: the pointer is on him
    /// when the click lands, so the greeting has usually opened his eyes —
    /// and the poke re-shuts them for phase A. Applied in `currentPose`
    /// after the greeting for exactly this veto.
    @Test("A poke outranks the greeting's open eyes")
    func aPokeOutranksTheGreetingsOpenEyes() {
        var pose = sleepingBase()
        CrabAnimator.applyGreeting(elapsed: 0.6, seed: 7, amount: 1, to: &pose)
        #expect(pose.asleepOverride, "the greeting should have opened his eyes first")
        CrabAnimator.applyRudeWake(elapsed: 0.25, to: &pose)
        #expect(pose.asleepOverride == false, "phase A must re-shut the greeting's eyes")
        #expect(pose.blink == 1)
    }

    /// The no-snap sweep: across the whole sequence at 30fps, no channel
    /// teleports. The one-pixel startle dip is the grid's own quantum.
    @Test("No channel teleports")
    func noChannelTeleports() {
        var previous: CrabPose?
        for step in stride(from: 0.0, through: 1.9, by: 1.0 / 30) {
            var pose = sleepingBase()
            CrabAnimator.applyRudeWake(elapsed: step, to: &pose)
            if let previous {
                #expect(abs(pose.bob - previous.bob) <= 1,
                        "bob jumped \(abs(pose.bob - previous.bob)) at \(step)s")
                let armStep = abs(Int((pose.armRight * 6).rounded())
                                  - Int((previous.armRight * 6).rounded()))
                #expect(armStep <= 1, "the arm jumped \(armStep) cells at \(step)s")
                #expect(abs(pose.squash - previous.squash) <= 1)
                #expect(pose.lean == previous.lean)
            }
            previous = pose
        }
    }
}
