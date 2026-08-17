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

    /// The badge envelope: zero before it is shown, eased while live, and —
    /// this is the point — NOT expired by any clock. Only the latch ends it.
    @Test func badgeEnvelopeEndpoints() {
        let shown = 100.0
        func visibility(at now: Double, endedAt: Double? = nil) -> Double {
            Ease.amount(now: now, since: shown, endedAt: endedAt,
                        attack: 0.5, release: 0.45)
        }
        #expect(visibility(at: 99.9) == 0)
        #expect(visibility(at: shown + 0.5) == 1)
        #expect(visibility(at: shown + 301) == 1,
                "the badge outlives the old five-minute cap — consumed, not expired")
        #expect(visibility(at: shown + 7200) == 1)
        // Early clear eases out through the release.
        let releasing = visibility(at: shown + 10.2, endedAt: shown + 10)
        #expect(releasing > 0 && releasing < 1)
        #expect(visibility(at: shown + 10.5, endedAt: shown + 10) == 0)
    }

    /// The reminder pulse: silent through the first cycle, one bounded eased
    /// breath at the top of every later one.
    @Test func pulseCycleMath() {
        for age in stride(from: 0.0, through: 179.9, by: 2.3) {
            #expect(CrabView.badgePulse(age: age) == 0, "no pulse in the first cycle (age \(age))")
        }
        #expect(CrabView.badgePulse(age: 181.2) > 0.5, "mid-breath at the top of cycle two")
        #expect(CrabView.badgePulse(age: 183.5) == 0, "the breath is over")
        #expect(CrabView.badgePulse(age: 250) == 0, "quiet between cycles")
        #expect(CrabView.badgePulse(age: 361.2) > 0.5, "and it comes back next cycle")
        // Every value inside a breath is eased and bounded.
        for phase in stride(from: 180.0, through: 182.4, by: 0.1) {
            let value = CrabView.badgePulse(age: phase)
            #expect(value >= 0 && value <= 1)
        }
    }

    /// The stale-stamp cap: a replayed completion older than the cap must not
    /// stamp — the badge no longer expires, so archaeology would pulse forever.
    @Test func staleReplayDoesNotStamp() {
        var session = ClaudeSession(id: "s", pid: 1, name: "s", cwd: "/", procStart: "",
                                    startedAt: Date())
        let stale = Date().addingTimeInterval(-ActivityCoordinator.completionStampMaxAge - 60)
        let fresh = Date().addingTimeInterval(-120)

        if session.mood != .done,
           Date().timeIntervalSince(stale) < ActivityCoordinator.completionStampMaxAge {
            session.completionBadgeAt = stale
        }
        #expect(session.completionBadgeAt == nil, "a completion from beyond the cap stays quiet")

        if session.mood != .done,
           Date().timeIntervalSince(fresh) < ActivityCoordinator.completionStampMaxAge {
            session.completionBadgeAt = fresh
        }
        #expect(session.completionBadgeAt == fresh, "a recent one still greets you")
    }

    /// The frozen sentinel: no animator-built pose carries a badge; only the
    /// live view's envelope writes it.
    @Test func noPoseCarriesABadgeByItself() {
        for mood in PetMood.allCases {
            for t in stride(from: 0.0, through: 30.0, by: 1.7) {
                let pose = CrabAnimator.pose(mood: mood, t: t)
                #expect(pose.doneBadge == 0)
                #expect(pose.doneBadgePulse == 0)
            }
        }
    }

    /// The badge paints only its footline patch, never over content, and the
    /// body wins wherever a lean or squash pushes him over it.
    @Test func badgePaintsItsCornerOnly() {
        var pose = CrabAnimator.pose(mood: .idle, t: 2)
        let bare = CrabRig.render(pose)
        pose.doneBadge = 1
        // Pulse at full, too: the shimmer must stay inside the same footprint —
        // this is the regression net for the clipped-ring bug, where a glow
        // ring one cell out painted his trailing foot and fell off the grid.
        pose.doneBadgePulse = 1
        let badged = CrabRig.render(pose)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where bare[x, y] != badged[x, y] {
                #expect(x >= 26 && x <= 31 && y >= 19 && y <= 24,
                        "badge cell outside its footline patch at (\(x),\(y))")
                #expect(bare[x, y] == .clear, "badge overpainted content at (\(x),\(y))")
            }
        }
        // Bottom edge ON the footline: something of the badge paints row 24,
        // nothing below it.
        #expect((26...31).contains { badged[$0, 24] != bare[$0, 24] || badged[$0, 24] != .clear },
                "the badge's bottom edge belongs on the footline")

        // A lean-and-squash pose pushes his edge over column 26: the body must
        // win those cells — the badge is a ground object he stands in front of.
        var leaning = CrabAnimator.pose(mood: .idle, t: 2)
        leaning.lean = 1
        leaning.squash = 1
        let bareLean = CrabRig.render(leaning)
        leaning.doneBadge = 1
        leaning.doneBadgePulse = 1
        let badgedLean = CrabRig.render(leaning)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where bareLean[x, y] != .clear {
                #expect(badgedLean[x, y] == bareLean[x, y],
                        "the badge overpainted him at (\(x),\(y))")
            }
        }

        // The floor bug's walk (rows 28-30) no longer intersects the badge at
        // all — pinned so the geometry claim cannot drift silently.
        var withBug = pose
        withBug.bugX = 27
        let both = CrabRig.render(withBug)
        for y in 28...30 {
            for x in 26...31 where both[x, y] == .eye {
                #expect(bare[x, y] == .clear || badged[x, y] == bare[x, y],
                        "bug and badge should occupy disjoint rows now")
            }
        }
    }

    /// The idle-chatter gate: constant company while idle is fresh, roughly
    /// one cycle in three past the quiet horizon — and the status ticker
    /// (chosen by `seed % 3 == 2` on the SAME seed) must stay reachable,
    /// which is why the gate rolls split dice instead of `seed % 3`.
    @Test func chatterGate() {
        // Fresh idle always talks.
        for seed in 0..<50 {
            #expect(ActivityCoordinator.idleChatterShows(quietFor: 30, seed: seed))
        }
        // Past the horizon: intermittent, in the neighbourhood of a third.
        let shown = (0..<300).filter {
            ActivityCoordinator.idleChatterShows(quietFor: 600, seed: $0)
        }
        let duty = Double(shown.count) / 300
        #expect(duty > 0.2 && duty < 0.47, "duty cycle \(duty) is not ~1/3")
        // And some of the shown cycles are ticker cycles.
        #expect(shown.contains { $0 % 3 == 2 },
                "the status ticker must survive the quiet hours")
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
