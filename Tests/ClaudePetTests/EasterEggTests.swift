import Testing
import Foundation
@testable import ClaudePet

/// The press classifier: movement always wins, stillness matures into petting,
/// anything shorter is a click. Pure, so the thresholds are pinned here rather
/// than discovered by dragging a crab around.
@Suite("Press gesture")
struct PressGestureTests {

    @Test func aShortStillPressIsAClick() {
        #expect(PressGesture.classify(elapsed: 0.1, movement: 0) == .click)
        #expect(PressGesture.classify(elapsed: 0.34, movement: 2.9) == .click)
    }

    @Test func movementAlwaysWins() {
        #expect(PressGesture.classify(elapsed: 0.1, movement: 4) == .drag)
        #expect(PressGesture.classify(elapsed: 5, movement: 4) == .drag,
                "even a long-held press is a drag once it moves")
    }

    @Test func aStillHoldMaturesIntoPetting() {
        #expect(PressGesture.classify(elapsed: 0.35, movement: 0) == .pet)
        #expect(PressGesture.classify(elapsed: 2, movement: 3) == .pet,
                "sub-threshold jitter does not cancel petting")
    }
}

/// The Shift+click-then-K gate for the secret animation-testing menu. Pure
/// over dates and characters, same as the press classifier above, so the
/// arming window and the one-shot rule are pinned without key events.
@Suite("Secret menu gate")
struct SecretMenuGateTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func armedKSummonsExactlyOnce() {
        var gate = SecretMenuGate()
        #expect(!gate.isArmed)
        gate.arm(at: t0)
        #expect(gate.isArmed)
        #expect(gate.press("k", at: t0.addingTimeInterval(1)) == .summon)
        #expect(!gate.isArmed, "the summon spends the arming — one menu per handshake")
        #expect(gate.press("k", at: t0.addingTimeInterval(1.1)) == .ignore)
    }

    @Test func shiftStillHeldCapitalKSummons() {
        var gate = SecretMenuGate()
        gate.arm(at: t0)
        #expect(gate.press("K", at: t0.addingTimeInterval(0.5)) == .summon,
                "the arming Shift is usually still down when K lands")
    }

    @Test func wrongKeyClosesTheGateQuietly() {
        var gate = SecretMenuGate()
        gate.arm(at: t0)
        #expect(gate.press("j", at: t0.addingTimeInterval(0.5)) == .disarm,
                "consumed — a wrong key must not beep or fall through")
        #expect(gate.press("k", at: t0.addingTimeInterval(0.6)) == .ignore,
                "and the gate is closed behind it")
    }

    @Test func aLapsedWindowDisarms() {
        var gate = SecretMenuGate()
        gate.arm(at: t0)
        #expect(gate.press("k", at: t0.addingTimeInterval(SecretMenuGate.armWindow)) == .disarm)
    }

    @Test func reArmingResetsTheWindow() {
        var gate = SecretMenuGate()
        gate.arm(at: t0)
        gate.arm(at: t0.addingTimeInterval(2.5))
        #expect(gate.press("k", at: t0.addingTimeInterval(3.5)) == .summon,
                "a second Shift+click means still trying, not a fault")
    }

    @Test func unarmedNeverConsumes() {
        var gate = SecretMenuGate()
        #expect(gate.press("k", at: t0) == .ignore)
        #expect(gate.press(nil, at: t0) == .ignore)
    }

    @Test func aDeadKeyIsAWrongKey() {
        var gate = SecretMenuGate()
        gate.arm(at: t0)
        #expect(gate.press(nil, at: t0.addingTimeInterval(0.5)) == .disarm)
    }
}

/// The quiet-hour schedules: deterministic, dice-gated, silent at t=0, and
/// invisible to offline renderers.
@Suite("Easter egg schedules")
struct EasterEggScheduleTests {

    @Test func bugNeverVisitsTheFirstCycle() {
        for t in stride(from: 0.0, through: 89.9, by: 0.5) {
            #expect(CrabAnimator.bugPosition(idleT: t) == nil)
        }
    }

    @Test func bugTraversesWhenItFires() {
        // Find a firing cycle within a day of idling.
        var fired: Double?
        for cycle in 1...960 where CrabAnimator.noise(cycle &* 53 &+ 7) < 0.3 {
            fired = Double(cycle) * 90
            break
        }
        let start = try! #require(fired, "the dice should hit within a day")
        // During its six seconds the bug moves monotonically across the floor.
        var columns: [Int] = []
        for dt in stride(from: 0.2, through: 5.8, by: 0.4) {
            if let x = CrabAnimator.bugPosition(idleT: start + dt) { columns.append(x) }
        }
        #expect(columns.count > 8, "the bug should be visible for most of the traverse")
        let sorted = columns.sorted()
        #expect(columns == sorted || columns == sorted.reversed(),
                "the bug walks one way, it does not teleport")
        // And it is gone right after.
        #expect(CrabAnimator.bugPosition(idleT: start + 6.5) == nil)
    }

    @Test func bugOwnsTheGaze() {
        var seen = false
        for t in stride(from: 90.0, through: 86400, by: 1.7) {
            let pose = CrabAnimator.pose(mood: .idle, t: t)
            if let bug = pose.bugX {
                seen = true
                #expect(pose.gazeY == 1, "eyes must drop to the floor at t=\(t)")
                if bug < 14 { #expect(pose.gazeX == -1) }
                if bug > 18 { #expect(pose.gazeX == 1) }
                break
            }
        }
        #expect(seen)
    }

    @Test func stargazerNeedsTheSmallHours() {
        // A fireable cycle exists…
        var cycle = 0
        for c in 1...200 where CrabAnimator.noise(c &* 61 &+ 3) < 0.35 { cycle = c; break }
        let t = Double(cycle) * 120 + 3
        // …but only the night unlocks it.
        #expect(CrabAnimator.stargaze(idleT: t, hourOfDay: 14) == nil)
        #expect(CrabAnimator.stargaze(idleT: t, hourOfDay: nil) == nil,
                "offline renderers pass no hour and must never see the telescope")
        let gazing = CrabAnimator.stargaze(idleT: t, hourOfDay: 1)
        #expect(gazing != nil)
        #expect(gazing!.amount > 0 && gazing!.amount <= 1)
    }

    /// The twin of `stargazerNeedsTheSmallHours`, including the assertion that
    /// matters most: offline renderers pass no hour, so the hour gate is a
    /// second, independent lock on the frozen sentinel.
    @Test func theSunNeedsTheDaylight() {
        var cycle = 0
        for c in 1...400 where CrabAnimator.noise(c &* 73 &+ 5) < 0.25 { cycle = c; break }
        #expect(cycle > 0, "the dice should hit within a couple of days of idling")
        let t = Double(cycle) * 420 + 7

        #expect(CrabAnimator.sunPatch(idleT: t, hourOfDay: 2) == nil, "not in the small hours")
        #expect(CrabAnimator.sunPatch(idleT: t, hourOfDay: 21) == nil, "not in the evening")
        #expect(CrabAnimator.sunPatch(idleT: t, hourOfDay: nil) == nil,
                "offline renderers pass no hour and must never see the light")
        let sun = CrabAnimator.sunPatch(idleT: t, hourOfDay: 13)
        #expect(sun != nil)
        #expect(sun!.amount > 0 && sun!.amount <= 1)

        // Never in the first cycle, at any hour.
        for step in stride(from: 0.0, through: 419.0, by: 3.0) {
            #expect(CrabAnimator.sunPatch(idleT: step, hourOfDay: 13) == nil,
                    "light in the first cycle at t=\(step)")
        }
        // And the telescope's window cannot overlap it — 8-17 against 23-04.
        for hour in 0...23 {
            let day = CrabAnimator.sunPatch(idleT: t, hourOfDay: hour) != nil
            let night = CrabAnimator.stargaze(idleT: t, hourOfDay: hour) != nil
            #expect(!(day && night), "hour \(hour) wants both the sun and the telescope")
        }
    }

    /// The real test of `composite(preservingExisting:)`, and the one that
    /// catches a future reordering that puts the light over his legs instead
    /// of under them: he must be byte-identical with the patch and without it.
    /// Standing IN the light is the entire read.
    @Test("The patch of sun goes in behind him, never over him")
    func theSunIsAGroundObject() {
        var lit = CrabAnimator.pose(mood: .idle, t: 5, flourishes: false)
        var dark = lit
        lit.sunPatch = 1
        lit.sunPatchPhase = 6
        let before = CrabRig.render(dark)
        let after = CrabRig.render(lit)

        var changed = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                if before[x, y] != .clear {
                    #expect(after[x, y] == before[x, y],
                            "the light painted over him at (\(x),\(y))")
                } else if after[x, y] != .clear {
                    changed += 1
                    #expect(after[x, y] == .yellow)
                    #expect(y >= 21, "the light climbed off the floor to row \(y)")
                }
            }
        }
        #expect(changed > 20, "the patch should actually be a patch")
        _ = dark
    }

    /// Basking shuts his eyes. A bug he is meant to be watching arriving on
    /// top of that would flatly contradict it, so the sun owns its spell —
    /// the same rule the telescope gets, for the same reason.
    @Test("Nothing else visits while he is basking")
    func theSunOwnsItsSpell() {
        var basked = false
        for cycle in 1...400 where CrabAnimator.noise(cycle &* 73 &+ 5) < 0.25 {
            for step in 0...(14 * 4) {
                let t = Double(cycle) * 420 + Double(step) / 4
                let pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false, hourOfDay: 13)
                guard pose.sunPatch > 0 else { continue }
                basked = true
                #expect(pose.bugX == nil, "a bug visited mid-bask at t=\(t)")
                #expect(pose.prop != .balloon, "a balloon floated up mid-bask at t=\(t)")
            }
            if basked { break }
        }
        #expect(basked)
    }

    /// "He should move sometimes, and be still most of the time" — the patch
    /// of sun is much bigger on screen than the bug or the balloon, so it has
    /// to be much rarer than either.
    @Test("The light is rare even in daylight")
    func theSunIsRare() {
        var lit = 0
        var total = 0
        for step in 0...(86400 / 2) {           // 24h of idling, sampled every 2s
            let t = Double(step) * 2
            total += 1
            if CrabAnimator.sunPatch(idleT: t, hourOfDay: 13) != nil { lit += 1 }
        }
        let duty = Double(lit) / Double(total)
        #expect(duty < 0.02, "lit \(duty * 100)% of the day is not rare")
        #expect(lit > 0, "and it does have to happen")
    }

    @Test func snackAndPounceStayInsideTheirEnvelopes() {
        var pose = CrabAnimator.pose(mood: .sleeping, t: 4)
        let before = pose
        CrabAnimator.applySnack(elapsed: 3.2, to: &pose)
        #expect(pose == before, "past 2.8s the snack must be over")

        var pounced = CrabAnimator.pose(mood: .idle, t: 100)
        let beforePounce = pounced
        CrabAnimator.applyPounce(elapsed: 1.6, to: &pounced)
        #expect(pounced == beforePounce, "past 1.4s the pounce must be over")

        // Mid-snack the shrimp exists and he is awake.
        var midSnack = CrabAnimator.pose(mood: .sleeping, t: 4)
        CrabAnimator.applySnack(elapsed: 1.2, to: &midSnack)
        #expect(midSnack.snackElapsed != nil)
        #expect(midSnack.asleepOverride)
    }

    @Test("Two hearts greet the purr, then one every four seconds")
    func heartCadenceIsSparse() {
        // The counts the operator will actually see. The old table was a
        // heart every 0.8s forever — thirty-eight in a half-minute hold.
        #expect(CrabAnimator.heartSpawns(elapsed: 0.2).isEmpty, "nothing before the first onset")
        // `heartSpawns` answers "what is in the air now", so counting a hold
        // means sweeping it — which is also what the operator does by eye.
        var seen = Set<Int>()
        var counted: [Double: Int] = [:]
        let checkpoints = [1.0, 3.0, 10.0, 30.0, 60.0]
        for step in 0...(60 * 60) {
            let elapsed = Double(step) / 60
            for heart in CrabAnimator.heartSpawns(elapsed: elapsed) { seen.insert(heart.ordinal) }
            for mark in checkpoints where counted[mark] == nil && elapsed >= mark {
                counted[mark] = seen.count
            }
        }
        let expected: [Double: Int] = [1.0: 1, 3.0: 2, 10.0: 4, 30.0: 9, 60.0: 16]
        for mark in checkpoints {
            #expect(counted[mark] == expected[mark],
                    "a \(mark)s hold should give \(expected[mark] ?? -1) hearts, got \(counted[mark] ?? -1)")
        }
    }

    @Test("No two hearts crowd each other, and never more than two are airborne")
    func heartsKeepTheirDistance() {
        var onsets: [Double] = []
        var seen = Set<Int>()
        var peak = 0
        for step in 0...(60 * 30) {
            let elapsed = Double(step) / 30
            let live = CrabAnimator.heartSpawns(elapsed: elapsed)
            peak = max(peak, live.count)
            for heart in live where !seen.contains(heart.ordinal) {
                seen.insert(heart.ordinal)
                onsets.append(heart.born)
            }
        }
        #expect(peak <= 2, "\(peak) hearts in the air at once is a fountain, not affection")
        for pair in zip(onsets, onsets.dropFirst()) {
            #expect(pair.1 - pair.0 >= 0.85,
                    "two hearts \(pair.1 - pair.0)s apart read as one event")
        }
    }

    /// The pin for the bug that deleted a heart mid-fade: it used to be killed
    /// by a bounds guard at rise 8, while its dissolve was still showing a
    /// quarter of it. Nothing may remove a heart — it has to run out on its own.
    @Test("A heart eases to nothing, and does it inside the grid")
    func heartsEaseToNothing() {
        #expect(CrabAnimator.heartVisibility(age: 0) == 0, "no pop at birth")
        #expect(CrabAnimator.heartVisibility(age: CrabAnimator.heartLife) == 0, "no cut at death")

        var previous = 0.0
        var peaked = false
        for step in 0...Int(CrabAnimator.heartLife * 30) + 2 {
            let age = Double(step) / 30
            let now = CrabAnimator.heartVisibility(age: age)
            #expect(now >= 0 && now <= 1)
            #expect(abs(now - previous) < 0.5, "a \(abs(now - previous)) jump at age \(age) is a snap")
            if now < previous - 1e-9 { peaked = true }
            #expect(!(peaked && now > previous + 1e-9), "the envelope must not rise again at age \(age)")
            previous = now
        }
        #expect(previous < 0.02, "it must be dark by the end of its life")

        // …and it is dark BEFORE it runs out of airspace. This is the number
        // whose absence forced the bounds guard in the first place.
        let topRow = CrabAnimator.heartRow(age: CrabAnimator.heartLife)
        #expect(topRow > 0, "a heart must finish dissolving with grid to spare, not at the edge")
    }

    /// Letting go used to delete every heart in the air in one frame, because
    /// `heartsElapsed` was written only while the purr envelope was above 0.5
    /// and that envelope closes 0.45s after the release — while a heart born
    /// just before it still has 1.3s of climbing to do.
    @Test("Letting go stops new hearts and lets the airborne ones finish")
    func heartsSurviveTheRelease() {
        // Released at 6.0s, just after the refrain heart born at 5.20.
        let released = 6.0
        let inFlight = CrabAnimator.heartSpawns(elapsed: released, until: released)
        #expect(!inFlight.isEmpty, "a heart should still be climbing at the release")

        // Half a second later it is still there…
        let after = CrabAnimator.heartSpawns(elapsed: released + 0.5, until: released)
        #expect(after.contains { $0.ordinal == inFlight[0].ordinal },
                "the heart in the air at the release was deleted by it")

        // …and nothing new was ever born after the release.
        for step in 0...(20 * 30) {
            let elapsed = released + Double(step) / 30
            for heart in CrabAnimator.heartSpawns(elapsed: elapsed, until: released) {
                #expect(heart.born < released,
                        "a heart was born at \(heart.born), after the hold ended")
            }
        }

        // And the whole thing is over within one life of the release.
        #expect(CrabAnimator.heartSpawns(elapsed: released + CrabAnimator.heartLife,
                                         until: released).isEmpty)
    }

    /// The pose must keep carrying the hearts through the release ramp, or the
    /// deletion comes back from the other direction.
    @Test("The petting pose keeps its hearts after the envelope has closed")
    func poseKeepsHeartsPastTheEnvelope() {
        var pose = CrabPose()
        // amount 0 is the envelope fully closed — a second after letting go.
        CrabAnimator.applyPetting(elapsed: 6.6, amount: 0, until: 6.0, to: &pose)
        #expect(pose.heartsElapsed != nil, "the hearts went with the purr")
        #expect(pose.heartsUntil == 6.0)

        // …but not forever: once the last heart has finished, they stop.
        var later = CrabPose()
        CrabAnimator.applyPetting(elapsed: 6.0 + CrabAnimator.heartLife + 0.1,
                                  amount: 0, until: 6.0, to: &later)
        #expect(later.heartsElapsed == nil, "the hearts outstayed their own lifetime")
    }

    /// `dx`/`dy` used to be applied live rather than at birth, so the purr
    /// wiggle dragged every heart already in the air sideways with him.
    @Test("Hearts do not ride the purr")
    func heartsDoNotRideThePurr() {
        for elapsed in [0.5, 1.4, 6.0, 10.5] {
            var left = CrabPose()
            left.heartsElapsed = elapsed
            left.lean = -1
            var right = left
            right.lean = 1
            let a = CrabRig.render(left)
            let b = CrabRig.render(right)
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where a[x, y] == .pink || b[x, y] == .pink {
                    #expect(a[x, y] == b[x, y],
                            "a heart moved with his lean at (\(x),\(y)), elapsed \(elapsed)")
                }
            }
        }
    }

    /// `drawHearts` runs after `servicePass`, so a heart drifting left into
    /// cols 1-8 would eat the service mark's edge.
    @Test("Hearts stay clear of the service glyph's airspace and the grid edge")
    func heartsKeepOffTheGlyph() {
        for step in 0...(60 * 30) {
            var pose = CrabPose()
            pose.heartsElapsed = Double(step) / 30
            let buffer = CrabRig.render(pose)
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where buffer[x, y] == .pink {
                    #expect(x > 8, "a heart reached col \(x), inside the glyph box")
                    #expect(y > 0 && y < PixelBuffer.side, "a heart reached row \(y)")
                }
            }
        }
    }

    @Test func pettingWinsOverTheGreeting() {
        var pose = CrabAnimator.pose(mood: .idle, t: 5)
        CrabAnimator.applyGreeting(elapsed: 1, seed: 3, amount: 1, to: &pose)
        CrabAnimator.applyPetting(elapsed: 1, amount: 1, to: &pose)
        #expect(pose.blink == 1, "petted eyes ease shut even mid-greeting")
        #expect(pose.heartsElapsed != nil)
        #expect(pose.mouth == .smile)
    }
}
