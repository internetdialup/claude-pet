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

    @Test func pettingWinsOverTheGreeting() {
        var pose = CrabAnimator.pose(mood: .idle, t: 5)
        CrabAnimator.applyGreeting(elapsed: 1, seed: 3, amount: 1, to: &pose)
        CrabAnimator.applyPetting(elapsed: 1, amount: 1, to: &pose)
        #expect(pose.blink == 1, "petted eyes ease shut even mid-greeting")
        #expect(pose.heartsElapsed != nil)
        #expect(pose.mouth == .smile)
    }
}
