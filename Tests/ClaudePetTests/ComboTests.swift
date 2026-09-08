import Testing
import Foundation
@testable import ClaudePet

/// **The combo.** The skate session is a chain of tricks now — no roll-away
/// between them — with the score building on his shell as each one lands, a
/// Nyan trail off the back of the board, and a tally line at the end. All of it
/// rides the session's own clock and channels, so nothing offline can carry
/// it: no renderer scripts a session, and the view alone turns `combo` into a
/// colour.
@MainActor
struct ComboTests {

    private let skater = CrabAnimator.MotionWardrobe(current: .skater)

    /// A firing session's start (idle clock), under a wardrobe.
    private func aSession(_ wardrobe: CrabAnimator.MotionWardrobe = .init()) -> Double {
        for cycle in 1...400 {
            let start = Double(cycle) * SpawnRates.skateSession.period + 2
            if CrabAnimator.skateSession(idleT: start + 0.01, wardrobe: wardrobe) != nil { return start }
        }
        Issue.record("no session fired in 400 cycles")
        return 0
    }

    @Test("The chain is tricks back to back, and it ends on the smith")
    func theChainIsTricksBackToBack() {
        let beats = CrabAnimator.skateSessionBeats
        #expect(!beats.contains { $0.0 == .cruise }, "a roll-away is a rest, and a combo has none")
        #expect(beats.last?.0 == .backSmith, "the ledge is the finale")
        for (kind, _) in beats {
            #expect(CrabAnimator.Flourish.skateBeats.contains(kind), "\(kind) is not a skate beat")
        }
        let tricks = beats.reduce(0.0) { $0 + $1.1 }
        #expect(abs(tricks - CrabAnimator.skateSessionTricksLength) < 1e-9)
        #expect(CrabAnimator.skateSessionLength - tricks >= 2.0, "the settle needs room for the tally and the ease-out")
    }

    /// The score is an envelope: 0 at the first pop, up a step through every
    /// stomp, 1 at the settle, 0 again by the ride's end — never a jump.
    @Test("The score builds through each landing and eases off in the settle")
    func theScoreBuildsAndEasesOff() {
        let start = aSession()
        let n = Double(CrabAnimator.skateSessionBeats.count)
        var previous = 0.0
        var t = start
        var peak = 0.0
        // smoothstep's steepest slope is 1.5 over a 0.15-of-a-beat step of 1/n,
        // or over the 0.8 s ease-out — the larger of the two bounds a frame.
        let shortestBeat = CrabAnimator.skateSessionBeats.map(\.1).min() ?? 2.2
        let maxStep = max(1.5 / n / (0.15 * shortestBeat) / 30, 1.5 / 0.8 / 30) + 1e-6
        // …and half a second PAST the ride's end: the settle's ease-out is the
        // only thing standing between a full score and a one-frame cut to zero.
        while t < start + CrabAnimator.skateSessionLength + 0.5 {
            let combo = CrabAnimator.pose(mood: .idle, t: t).combo
            #expect(combo >= 0 && combo <= 1)
            #expect(abs(combo - previous) <= maxStep, "the score jumped \(combo - previous) at \(t - start)s")
            previous = combo
            peak = max(peak, combo)
            t += 1.0 / 30
        }
        #expect(peak > 0.999, "the score never reached full")
        #expect(CrabAnimator.pose(mood: .idle, t: start).combo < 0.01, "the ride began scoring before the first pop")
        let settleStart = start + CrabAnimator.skateSessionTricksLength
        #expect(CrabAnimator.pose(mood: .idle, t: settleStart + 0.5).combo > 0.999, "the settle does not hold the full score")
        #expect(CrabAnimator.pose(mood: .idle, t: start + CrabAnimator.skateSessionLength + 0.05).combo == 0,
                "the score outlived the ride")
        // Monotone through the tricks: a landing never takes points away.
        var last = 0.0
        t = start
        while t < settleStart {
            let combo = CrabAnimator.pose(mood: .idle, t: t).combo
            #expect(combo >= last - 1e-9, "the score fell at \(t - start)s")
            last = combo
            t += 0.1
        }
    }

    @Test("Nothing offline ever scores, and the frozen instant is cold")
    func offlineNeverScores() {
        for kind in CrabAnimator.Flourish.allCases {
            for t in stride(from: 0.0, through: kind.duration, by: 0.3) {
                let pose = CrabAnimator.flourishPose(kind, at: t)
                #expect(pose.combo == 0, "\(kind) scored offline")
            }
        }
        for t in stride(from: 0.0, through: 170, by: 0.7) {
            #expect(CrabAnimator.pose(mood: .idle, t: t).combo == 0, "scored outside a session at \(t)")
        }
        #expect(CrabView.composedTint(mood: .idle, t: 3, rainbowElapsed: nil,
                                      celebrating: false, taskFraction: nil) == nil)
        #expect(CrabView.composedTint(mood: .idle, t: 3, rainbowElapsed: nil,
                                      celebrating: false, taskFraction: nil, combo: 1) != nil,
                "a full score paints no rainbow")
        // …and the score shows through a session preview, which has no tint
        // of its own — the review must show the ride, not the trail alone.
        let frame = CrabAnimator.PreviewFrame(effect: .skateSession, t: 5)
        #expect(CrabView.composedTint(mood: .idle, t: 5, rainbowElapsed: nil,
                                      celebrating: false, taskFraction: nil,
                                      preview: frame, combo: 0.6) != nil)
    }

    @Test("A mood blend carries the score and the ledge with the pose")
    func blendCarriesTheScore() {
        var from = CrabPose(), to = CrabPose()
        from.combo = 1
        from.ledge = 1
        let half = CrabPose.blend(from: from, to: to, u: 0.5)
        #expect(abs(half.combo - 0.5) < 1e-9)
        #expect(abs(half.ledge - 0.5) < 1e-9)
    }

    /// The trail is rainbow ink in rows 19…24 (plus his bob), only while he
    /// is scoring, and never in a frame with no score.
    @Test("The trail streams behind the board only while he is scoring")
    func theTrailStreamsOnlyWhileScoring() {
        let rainbow: Set<PixelBuffer.Ink> = [.alert, .flame, .yellow, .green, .water, .pink]
        func trailCells(_ pose: CrabPose) -> Int {
            let buffer = CrabRig.render(pose)
            var n = 0
            for y in 0..<PixelBuffer.side { for x in 0..<8 where rainbow.contains(buffer[x, y]) { n += 1 } }
            return n
        }
        var scoring = CrabPose()
        scoring.combo = 1
        scoring.comboPhase = 0.3
        let full = trailCells(scoring)
        #expect(full >= 6 * 6, "a full score drew only \(full) trail cells")
        var quiet = CrabPose()
        quiet.combo = 0
        #expect(trailCells(quiet) == 0, "a trail with no score")
        // Rows: rainbow only in the trail's band, shifted by bob.
        scoring.bob = -4
        let lifted = CrabRig.render(scoring)
        for y in 0..<PixelBuffer.side {
            let hasRainbow = (0..<8).contains { rainbow.contains(lifted[$0, y]) }
            #expect(!hasRainbow || (y >= 19 - 4 && y <= 24 - 4 + 1), "trail ink on row \(y) with bob −4")
        }
        // The wave moves with the clock.
        var later = scoring
        later.comboPhase = 0.3 + 1.0 / 6
        let a = CrabRig.render(scoring), b = CrabRig.render(later)
        var moved = false
        for y in 0..<PixelBuffer.side { for x in 0..<8 where a[x, y] != b[x, y] { moved = true } }
        #expect(moved, "the trail does not wave")
    }

    /// The tally is said at the first instant of the settle, where the
    /// schedule says the tricks end — under the wardrobe the ride was dealt.
    @Test("The tally's instant is the schedule's own settle")
    func theTallyLandsOnTheSettle() {
        for wardrobe in [CrabAnimator.MotionWardrobe(), skater] {
            var t = 1.0, checked = 0
            let horizon = 20_000.0
            while let tallied = CrabAnimator.nextSkateSessionEnd(after: t, wardrobe: wardrobe), tallied < horizon {
                let local = CrabAnimator.skateSession(idleT: tallied - 0.02, wardrobe: wardrobe)
                let onSettle = local.map { abs($0 - (CrabAnimator.skateSessionTricksLength - 0.02)) < 0.03 } ?? false
                #expect(onSettle, "tally at \(tallied) is not the settle's first instant (local \(String(describing: local)))")
                #expect(CrabAnimator.skateSession(idleT: tallied + 0.5, wardrobe: wardrobe) != nil,
                        "the ride is over before the tally can be read")
                checked += 1
                t = tallied + 0.1
            }
            #expect(checked > 10, "\(wardrobe.current): only \(checked) rides in the sweep")
            // COMPLETE, not merely correct: every ride this wardrobe fires is
            // predicted. A bare predictor would only ever find the rides the
            // bare crab also rides — and the Skater rides twice as many.
            var fired = 0
            for cycle in 1...Int(horizon / SpawnRates.skateSession.period) {
                let start = Double(cycle) * SpawnRates.skateSession.period + 2
                guard start + CrabAnimator.skateSessionTricksLength < horizon else { continue }
                if CrabAnimator.skateSession(idleT: start + 0.01, wardrobe: wardrobe) != nil { fired += 1 }
            }
            #expect(checked == fired, "\(wardrobe.current): \(fired) rides fired, \(checked) tallies predicted")
        }
        // A hidden landing is not a shout landing: the flourish schedule keeps
        // dealing inside a session, and those tricks are not on screen.
        let start = aSession(skater)
        var hidden = 0
        var t = start
        while t < start + CrabAnimator.skateSessionTricksLength {
            if let landing = CrabAnimator.nextSkateTrickLanding(after: t, wardrobe: skater),
               landing < start + CrabAnimator.skateSessionTricksLength {
                let inSession = CrabAnimator.skateSession(idleT: landing - 0.02, wardrobe: skater) != nil
                if inSession { hidden += 1 }
                t = landing + 0.1
            } else { break }
        }
        #expect(hidden > 0, "the flourish schedule dealt no trick inside the ride — the guard is untestable here")
    }

    /// 🎉🛹 Three pokes, dressed as Skater, start the ride; every other look
    /// keeps the party. The poked ride is the whole combo on its own clock and
    /// ends by itself.
    @Test("Three pokes start the combo for the Skater, and the ride runs its length")
    func pokesStartTheRide() {
        #expect(PetInstance.clickAction(verdict: 3, mood: .idle, onBody: true, snackBusy: false,
                                        costume: .skater) == .combo)
        #expect(PetInstance.clickAction(verdict: 5, mood: .working, onBody: false, snackBusy: false,
                                        costume: .skater) == .combo)
        for costume in Costume.allCases where costume != .skater {
            #expect(PetInstance.clickAction(verdict: 3, mood: .idle, onBody: true, snackBusy: false,
                                            costume: costume) == .party, "\(costume) lost its party")
        }
        #expect(PetInstance.clickAction(verdict: 2, mood: .idle, onBody: true, snackBusy: false,
                                        costume: .skater) == .snack, "two pokes still feed the Skater")
        let first = CrabAnimator.skateSessionBeats[0].0
        #expect(CrabAnimator.comboRide(local: 0.1, wardrobe: skater)?.prop.isBoard == true)
        #expect(CrabAnimator.comboRide(local: 0.1, wardrobe: skater)?.prop == CrabAnimator.flourishPose(first, at: 0.1).prop)
        #expect((CrabAnimator.comboRide(local: 16.5, wardrobe: skater)?.combo ?? 0) > 0.999, "the settle is not at full score")
        #expect((CrabAnimator.comboRide(local: 18.05, wardrobe: skater)?.combo ?? 1) < 0.05, "the score outlived the ride")
        #expect(CrabAnimator.comboRide(local: CrabAnimator.skateSessionLength, wardrobe: skater) == nil)
        #expect(CrabAnimator.comboRide(local: 30, wardrobe: skater) == nil)
        #expect(CrabAnimator.comboRide(local: -0.1, wardrobe: skater) == nil)
        // The Skater stands on his deck at the settle — the stance is his.
        #expect((CrabAnimator.comboRide(local: 17.0, wardrobe: skater)?.deckUnderfoot ?? 0) == 1)
    }

    /// The tally's words fit the plain bubble and the 3.4 s window, prefix
    /// included, so the score is never cut off mid-line.
    @Test("Every tally line fits, count in front")
    func tallyLinesFit() {
        let count = CrabAnimator.skateSessionBeats.count
        let lines = Vocab.lines(for: .combo)
        #expect(lines.count > 2)
        for line in lines {
            let said = "×\(count) " + line
            #expect(said.count <= ThoughtBubble.plainColumns, "\"\(said)\" does not fit the plain bubble")
            #expect(ActivityCoordinator.bubbleStyle(for: said) == .plain)
        }
    }
}
