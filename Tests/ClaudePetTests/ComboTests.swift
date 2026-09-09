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
        let rainbow = Set(CrabRig.trailInks)
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
        // Rows: rainbow only in the trail's band (two layers: the far one a
        // row lower), shifted by bob.
        scoring.bob = -4
        let lifted = CrabRig.render(scoring)
        for y in 0..<PixelBuffer.side {
            let hasRainbow = (0..<8).contains { rainbow.contains(lifted[$0, y]) }
            #expect(!hasRainbow || (y >= 19 - 4 && y <= 24 - 4 + 2), "trail ink on row \(y) with bob −4")
        }
        // Two layers: the far one moves slower than the near one — between two
        // phases the near wave has flipped and the far one has not.
        var p0 = CrabPose(); p0.combo = 1; p0.comboPhase = 0.0
        var p1 = CrabPose(); p1.combo = 1; p1.comboPhase = 1.0 / 6
        let r0 = CrabRig.render(p0), r1 = CrabRig.render(p1)
        var nearChanged = 0, farRowChanged = 0
        for x in 0..<8 {
            for y in 19...24 where r0[x, y] != r1[x, y] { nearChanged += 1 }
            if r0[x, 26] != r1[x, 26] { farRowChanged += 1 }
        }
        #expect(nearChanged > 0, "the near ribbons did not wave")
        #expect(farRowChanged < nearChanged, "the far layer is not slower than the near one")
        // …and the far layer EXISTS: its lowest stripe reaches row 26 on the
        // frames its wave is up, a row the near layer never touches.
        let farPresent = (0..<8).contains { rainbow.contains(r0[$0, 26]) || rainbow.contains(r1[$0, 26]) }
        #expect(farPresent, "no far layer behind the ribbons")
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

    /// 🔥 The board catches fire at full score: nothing before the last
    /// landing, alight through the settle, out with the score — and never
    /// offline.
    @Test("The board burns at full score and nowhere else")
    func theBoardBurnsAtFullScore() {
        let start = aSession()
        let tricks = CrabAnimator.skateSessionTricksLength
        let lastBeat = CrabAnimator.skateSessionBeats.last!.1
        #expect(CrabAnimator.pose(mood: .idle, t: start + tricks - lastBeat + 0.5).combo < 0.81)
        #expect(CrabAnimator.pose(mood: .idle, t: start + tricks - lastBeat + 0.5).boardFire == 0, "alight before the last landing")
        let settle = CrabAnimator.pose(mood: .idle, t: start + tricks + 0.6)
        #expect(settle.boardFire > 0.999, "not alight in the settle")
        #expect(CrabAnimator.pose(mood: .idle, t: start + CrabAnimator.skateSessionLength + 0.05).boardFire == 0)
        // Flames in the gaps between his legs, on the deck — counted in the
        // board's own columns, clear of the ribbons' orange stripe at the left.
        func flameCells(_ buffer: PixelBuffer) -> Int {
            var n = 0
            for y in 21...24 { for x in 9...23 where buffer[x, y] == .flame || buffer[x, y] == .flameCore { n += 1 } }
            return n
        }
        let flames = flameCells(CrabRig.render(settle))
        #expect(flames >= 8, "only \(flames) flame cells on the burning board")
        var cold = settle
        cold.boardFire = 0
        let coldFlames = flameCells(CrabRig.render(cold))
        #expect(coldFlames == 0, "flames with the fire out")
        for kind in CrabAnimator.Flourish.allCases {
            #expect(CrabAnimator.flourishPose(kind, at: 0.4).boardFire == 0, "\(kind) burned offline")
        }
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
        let tricks = CrabAnimator.skateSessionTricksLength, length = CrabAnimator.skateSessionLength
        #expect((CrabAnimator.comboRide(local: tricks + 0.5, wardrobe: skater)?.combo ?? 0) > 0.999, "the settle is not at full score")
        #expect((CrabAnimator.comboRide(local: length - 0.05, wardrobe: skater)?.combo ?? 1) < 0.05, "the score outlived the ride")
        #expect(CrabAnimator.comboRide(local: CrabAnimator.skateSessionLength, wardrobe: skater) == nil)
        #expect(CrabAnimator.comboRide(local: 30, wardrobe: skater) == nil)
        #expect(CrabAnimator.comboRide(local: -0.1, wardrobe: skater) == nil)
        // The Skater stands on his deck at the settle — the stance is his.
        #expect((CrabAnimator.comboRide(local: tricks + 0.8, wardrobe: skater)?.deckUnderfoot ?? 0) == 1)
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

    /// 🔎 THE OPERATOR'S NOTE: *"remove pink from the rainbow trail, it kind of
    /// looks like a pride flag and we want to remain neutral."* Six stripes
    /// still — the far layer needs the weight — but the violet end is gone and
    /// a teal takes its place, so the ramp runs red → sky and stops.
    @Test("The ribbon is six stripes with a teal and no pink")
    func theRibbonIsNeutral() {
        #expect(CrabRig.trailInks.count == 6, "the ribbon has \(CrabRig.trailInks.count) stripes")
        #expect(CrabRig.trailInks.contains(.teal), "no teal in the ribbon")
        #expect(!CrabRig.trailInks.contains(.pink), "the pink is back in the ribbon")
        #expect(Set(CrabRig.trailInks).count == 6, "a stripe repeats")
        // …and no pink reaches the drawn ribbon either, whatever the inks say.
        var scoring = CrabPose()
        scoring.combo = 1
        scoring.comboPhase = 0.3
        let buffer = CrabRig.render(scoring)
        for y in 0..<PixelBuffer.side {
            for x in 0..<8 {
                #expect(buffer[x, y] != .pink, "a pink cell at \(x),\(y)")
            }
        }
        var teal = 0
        for y in 0..<PixelBuffer.side { for x in 0..<8 where buffer[x, y] == .teal { teal += 1 } }
        #expect(teal > 0, "the teal stripe never draws")
    }

    /// 🔎 THE GRAPE→TERRACOTTA SNAP. `SpriteTint.towards` used to blend out of
    /// Claw'd's own shell whatever the crab was wearing, so the Skater's grape
    /// jumped to terracotta on the first rung and walked back over the ride.
    /// The costume's own body is the base now, so at zero score the tint IS the
    /// costume and there is nothing to step from.
    @Test("Every costume's tint starts as that costume, body and shade")
    func theTintStartsWhereTheCostumeIs() {
        for costume in Costume.allCases {
            let body = CostumeStyle.bodyRGB(for: costume)
            let shade = CostumeStyle.shadeRGB(for: costume)
            let tint = SpriteTint.towards((1, 0, 0), amount: 0, from: body, shadeFrom: shade)
            #expect(abs(tint.r - body.r) < 1e-12 && abs(tint.g - body.g) < 1e-12
                    && abs(tint.b - body.b) < 1e-12, "\(costume)'s body steps at zero score")
            #expect(abs(tint.shadeR - shade.r) < 1e-12 && abs(tint.shadeG - shade.g) < 1e-12
                    && abs(tint.shadeB - shade.b) < 1e-12, "\(costume)'s shade steps at zero score")
        }
        // …and the live path is continuous across the first rung: the last
        // colourless frame and the first coloured one are the same shell.
        let grape = CostumeStyle.bodyRGB(for: .skater)
        let first = CrabView.comboTint(t: 2.6, combo: 0.002, costume: .skater)
        #expect(first != nil, "the first rung drew no tint")
        #expect(abs((first?.r ?? 0) - grape.r) < 0.01 && abs((first?.g ?? 0) - grape.g) < 0.01
                && abs((first?.b ?? 0) - grape.b) < 0.01,
                "the shell jumps on the first rung: \(String(describing: first))")
    }

    /// 🔎 THE UNTINTED SHADE. `bodyTint` only ever reached `.body`; the belly
    /// row and the right flank are `.bodyShade` and were repainted at the
    /// palette's own colour every frame, so a full-score crab wore a rainbow
    /// shell with a terracotta underside. The shade tracks the tint now,
    /// through the palette's own body→shade ratio.
    @Test("The shade tracks the tint, and no untinted shade cell survives full score")
    func theShadeTracksTheTint() {
        let tint = CrabView.comboTint(t: 3.0, combo: 1, costume: .skater)
        #expect(tint != nil)
        guard let tint else { return }
        // At full score the shade is the tint darkened by the palette's ratio.
        #expect(abs(tint.shadeR - tint.r * SpriteTint.shadeRatio.r) < 1e-9,
                "the shade is \(tint.shadeR), not \(tint.r * SpriteTint.shadeRatio.r)")
        #expect(abs(tint.shadeG - tint.g * SpriteTint.shadeRatio.g) < 1e-9)
        #expect(abs(tint.shadeB - tint.b * SpriteTint.shadeRatio.b) < 1e-9)
        // …and it is a different colour from the body, or the shading is gone.
        #expect(abs(tint.shadeG - tint.g) > 0.05, "the shade lost its contrast")
        // The Skater's own shade is nowhere near the full-score shade, which is
        // exactly what made the old frames read as an untinted underside.
        let grapeShade = CostumeStyle.shadeRGB(for: .skater)
        let drift = abs(tint.shadeR - grapeShade.r) + abs(tint.shadeG - grapeShade.g)
            + abs(tint.shadeB - grapeShade.b)
        #expect(drift > 0.2, "the full-score shade is still the costume's own: drift \(drift)")
        // …and the canvas actually ASKS for it. The shade used to be resolved
        // from the costume override with the tint never consulted, so a
        // full-score crab wore a rainbow shell over a grape underside.
        let overrides = CostumeStyle.blendedOverrides(from: .skater, to: .skater, u: 1)
        let painted = PixelCanvasView.color(for: .bodyShade, bodyTint: tint.body,
                                            bodyShadeTint: tint.shade, inkOverrides: overrides)
        #expect(painted == tint.shade,
                "the canvas painted \(painted) where the tint asked for \(tint.shade)")
        #expect(painted != (overrides[.bodyShade] ?? Palette.bodyShade),
                "the canvas is still painting the costume's own shade at full score")
    }

    /// 🔎 *"The rainbow fade needs to be brighter, it looks kind of awkward."*
    /// The mix used to stop at 85% of a 0.72-saturated, 0.92-bright hue — a
    /// muddy three-quarter step. Full score is the full hue now.
    @Test("Full score is the full hue, not a muddy three-quarters of it")
    func theRainbowIsBright() {
        for step in 0..<12 {
            let tint = CrabView.comboTint(t: Double(step) * 0.37, combo: 1, costume: .skater)
            #expect(tint != nil)
            guard let tint else { continue }
            let channels = [tint.r, tint.g, tint.b]
            let high = channels.max() ?? 0, low = channels.min() ?? 0
            #expect(high > 0.99, "the brightest channel is only \(high)")
            #expect((high - low) / high > 0.84, "the saturation is only \((high - low) / high)")
        }
        // …and it is still a ramp, not a step: half score sits between the
        // costume's own shell and the full hue.
        let grape = CostumeStyle.bodyRGB(for: .skater)
        let half = CrabView.comboTint(t: 3.0, combo: 0.5, costume: .skater)
        let full = CrabView.comboTint(t: 3.0, combo: 1, costume: .skater)
        guard let half, let full else { return }
        #expect(half.g > grape.g && half.g < full.g, "the green channel does not ramp")
    }

}
