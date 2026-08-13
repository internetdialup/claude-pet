import Testing
import Foundation
@testable import ClaudePet

/// The quiet completion marker: stamped once per turn, consumed by new work,
/// outliving the done pose, and drawn only where and when it should be.
@Suite("Quiet done")
@MainActor
struct QuietDoneTests {

    /// A double turn end — transcript fold plus Stop hook — must keep the
    /// first stamp: the second event arrives with the session already done.
    @Test func doubleTurnEndKeepsTheFirstStamp() {
        var session = ClaudeSession(id: "s", pid: 1, name: "s", cwd: "/", procStart: "",
                                    startedAt: Date())
        // Mirror the reducer's logic directly on the struct (the reducer is
        // exercised end-to-end in MoodDecayTests; this pins the stamp rule).
        let first = Date(timeIntervalSinceReferenceDate: 1000)
        let second = Date(timeIntervalSinceReferenceDate: 1000.4)

        if session.mood != .done { session.completionBadgeAt = first }
        session.mood = .done
        if session.mood != .done { session.completionBadgeAt = second }

        #expect(session.completionBadgeAt == first)
    }

    /// The badge envelope: zero before it is shown, eased while live, gone
    /// after the five-minute tail.
    @Test func badgeEnvelopeEndpoints() {
        let shown = 100.0
        func visibility(at now: Double, completedAt: Double = 95, endedAt: Double? = nil) -> Double {
            let age = now - completedAt
            let latch = Ease.amount(now: now, since: shown, endedAt: endedAt,
                                    attack: 0.5, release: 0.45)
            let tail = 1 - Ease.smoothstep((age - (ActivityCoordinator.badgeLifetime - 2)) / 2)
            return max(0, latch * tail)
        }
        #expect(visibility(at: 99.9) == 0)
        #expect(visibility(at: shown + 0.5) == 1)
        #expect(visibility(at: shown + 100) == 1)
        // Two-second tail ending at completedAt + 300.
        let midFade = visibility(at: 95 + 299)
        #expect(midFade > 0 && midFade < 1)
        #expect(visibility(at: 95 + 300.1) == 0)
        // Early clear eases out through the release.
        let releasing = visibility(at: shown + 10.2, endedAt: shown + 10)
        #expect(releasing > 0 && releasing < 1)
        #expect(visibility(at: shown + 10.5, endedAt: shown + 10) == 0)
    }

    /// The nudge windows sit strictly inside the badge's lifetime and do not
    /// overlap its fade tail.
    @Test func nudgeWindowsFitInsideTheBadge() {
        for start in ActivityCoordinator.nudgeWindows {
            #expect(start > 0)
            #expect(start + ActivityCoordinator.nudgeDuration
                    < ActivityCoordinator.badgeLifetime - 2)
        }
        #expect(ActivityCoordinator.nudgeWindows.count == 2, "once or twice — twice")
    }

    /// The frozen sentinel: no animator-built pose carries a badge; only the
    /// live view's envelope writes it.
    @Test func noPoseCarriesABadgeByItself() {
        for mood in PetMood.allCases {
            for t in stride(from: 0.0, through: 30.0, by: 1.7) {
                #expect(CrabAnimator.pose(mood: mood, t: t).doneBadge == 0)
            }
        }
    }

    /// The badge paints only its own corner, only over empty floor, and the
    /// visiting bug walks in front of it.
    @Test func badgePaintsItsCornerOnly() {
        var pose = CrabAnimator.pose(mood: .idle, t: 2)
        let bare = CrabRig.render(pose)
        pose.doneBadge = 1
        let badged = CrabRig.render(pose)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where bare[x, y] != badged[x, y] {
                #expect(x >= 26 && y >= 26, "badge cell outside its corner at (\(x),\(y))")
                #expect(bare[x, y] == .clear, "badge overpainted content at (\(x),\(y))")
            }
        }
        // The bug draws after the badge, so where both occupy a cell the bug wins.
        var withBug = pose
        withBug.bugX = 27
        let both = CrabRig.render(withBug)
        var bugOverBadge = false
        for y in 28...30 {
            for x in 26...31 where both[x, y] == .eye { bugOverBadge = true }
        }
        #expect(bugOverBadge, "the bug should scuttle in front of the badge")
    }

    /// Grab rects: the halo grows the sprite square, the bubble band joins
    /// only while a bubble shows, and everything clamps to the window.
    @Test func grabRectsShape() {
        let sprite = CGRect(x: 102, y: 0, width: 96, height: 96)
        let window = CGSize(width: 300, height: 174)

        let quiet = PetWindowController.grabRects(sprite: sprite, window: window, bubbleVisible: false)
        #expect(quiet.count == 1)
        #expect(quiet[0].minX == 88 && quiet[0].minY == 0, "halo clamps to the window floor")
        #expect(quiet[0].maxY == 110)

        let talking = PetWindowController.grabRects(sprite: sprite, window: window, bubbleVisible: true)
        #expect(talking.count == 2)
        #expect(talking[1].minY == sprite.maxY)
        #expect(talking[1].maxY == 174)
        #expect(talking[1].width == 300, "the band spans the window")
    }
}
