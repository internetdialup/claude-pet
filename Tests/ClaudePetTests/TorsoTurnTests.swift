import Testing
import Foundation
@testable import ClaudePet

/// The body turn: he yaws about his own vertical axis, and the wardrobe
/// yaws with him.
///
/// The pass is a post-pass over the finished figure, which is what makes
/// the first test here the load-bearing one: at `torsoTurn` 0 the function
/// returns before touching a cell, so every other render in the app — every
/// committed byte, every existing pin, every frozen sentinel — is untouched
/// by construction rather than by argument. Everything below that pins the
/// shape of the turn itself.
@Suite("Torso turn")
@MainActor
struct TorsoTurnTests {

    /// A pose grid rendered with and without a whole number of turns.
    /// Whole turns are the identity, and so is a turn small enough to round
    /// away — the `turn − floor(turn)` guard, including for the negative
    /// values `truncatingRemainder` would have mishandled.
    @Test("At rest, and at whole turns, the rig renders exactly as it always did")
    func restIsByteIdentical() {
        var poses: [CrabPose] = []
        for bob in [-9, -4, 0, 1] {
            for lean in [-1, 0, 1] {
                for squash in [0, 1] {
                    for eyes in [CrabPose.EyeStyle.round, .determined, .wide, .squint] {
                        var pose = CrabPose()
                        pose.bob = bob; pose.lean = lean; pose.squash = squash
                        pose.eyes = eyes
                        pose.armLeft = 0.6; pose.legAmplitude = 1.6; pose.legPhase = .pi / 2
                        poses.append(pose)
                    }
                }
            }
        }
        for mood in PetMood.allCases {
            poses.append(CrabAnimator.pose(mood: mood, t: 0, flourishes: false))
        }
        for pose in poses {
            for costume in Costume.allCases {
                let plain = CrabRig.render(pose, costume: costume)
                for turn in [0.0, 1.0, -1.0, -2.0, 3.0, 1e-9, -1e-9] {
                    var turned = pose
                    turned.torsoTurn = turn
                    #expect(CrabRig.render(turned, costume: costume).cells == plain.cells,
                            "torsoTurn \(turn) moved a cell on \(costume)")
                }
            }
        }
    }

    /// Rendering is a pure function of the pose, turn or no turn.
    @Test("The turn renders the same twice")
    func theTurnIsDeterministic() {
        for step in 1..<20 {
            var pose = airborne()
            pose.torsoTurn = Double(step) / 20
            for costume in Costume.allCases {
                #expect(CrabRig.render(pose, costume: costume).cells
                        == CrabRig.render(pose, costume: costume).cells)
            }
        }
    }

    /// A crab seen from behind has no face. Not by keeping clear of
    /// coordinates — by erasing every face ink on the far half, whatever
    /// the eye style or the gaze, and whatever the wardrobe painted there.
    @Test("His back is faceless")
    func theBackIsFaceless() {
        for turn in [0.42, 0.5, 0.58] {
            for eyes in [CrabPose.EyeStyle.round, .determined, .wide, .squint] {
                for gazeY in [-1, 0, 1] {
                    for costume in Costume.allCases {
                        var pose = airborne(costume)
                        pose.torsoTurn = turn; pose.eyes = eyes; pose.gazeY = gazeY
                        let b = CrabRig.render(pose, costume: costume)
                        var face = 0
                        for y in 0..<PixelBuffer.side {
                            for x in 0..<PixelBuffer.side
                            where b[x, y] == .eye || b[x, y] == .mouth { face += 1 }
                        }
                        #expect(face == 0,
                                "\(face) face cells survived on his back at \(turn), \(costume)")
                    }
                }
            }
        }
    }

    /// The back is one flat step darker, with a single lit row across the
    /// carapace so it is not a featureless slab.
    @Test("The back is a step darker, with one lit row")
    func theBackIsShadedAndRidged() {
        var pose = airborne()
        pose.torsoTurn = 0.5
        let b = CrabRig.render(pose)
        var shade = 0, body = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                if b[x, y] == .bodyShade { shade += 1 }
                if b[x, y] == .body { body += 1 }
            }
        }
        #expect(shade > body, "his back is lit like his front — \(shade) shade to \(body) body")
        #expect(body > 8, "his back has no lit ridge at all")
    }

    /// Edge-on he is the box's depth, not a closing door: six cells of
    /// shell, dark on the flank the light does not reach and lit on the
    /// one it does.
    @Test("Edge-on he is six wide, dark one way and lit the other")
    func edgeOnIsSixWide() {
        for (turn, dark) in [(0.25, true), (0.75, false)] {
            var pose = airborne()
            pose.torsoTurn = turn
            let b = CrabRig.render(pose)
            let top = 10 + pose.bob
            var widths = Set<Int>(), shade = 0, body = 0
            for y in (top + 2)...(19 + pose.bob) {
                var left = 99, right = -1
                for x in 0..<PixelBuffer.side where b[x, y] == .body || b[x, y] == .bodyShade {
                    left = min(left, x); right = max(right, x)
                    if b[x, y] == .bodyShade { shade += 1 } else { body += 1 }
                }
                if right >= 0 { widths.insert(right - left + 1) }
            }
            #expect(widths == [6], "edge-on shell rows are \(widths.sorted()) wide, not 6")
            if dark {
                #expect(shade > 0 && body == 0, "the dark flank is lit — \(shade)/\(body)")
            } else {
                #expect(body > 0 && shade == 0, "the lit flank is dark — \(shade)/\(body)")
            }
        }
    }

    /// A turn and its mirror in time have mirrored OUTLINES. Not mirrored
    /// fills: the light stays where the light is, so the inks differ, and
    /// the face he is turning away from cuts its own asymmetric holes in
    /// the shell. The outline is the part that says which way he is facing,
    /// and it is the part that has to agree.
    @Test("The turn mirrors in time")
    func theSpinMirrorsInTime() {
        for step in 1..<10 {
            let turn = Double(step) / 20
            var forward = airborne(), backward = airborne()
            forward.torsoTurn = turn
            backward.torsoTurn = 1 - turn
            let a = CrabRig.render(forward), c = CrabRig.render(backward)
            func extent(_ b: PixelBuffer, _ y: Int) -> (Int, Int)? {
                var left = 99, right = -1
                for x in 0..<PixelBuffer.side where b[x, y] == .body || b[x, y] == .bodyShade {
                    left = min(left, x); right = max(right, x)
                }
                return right < 0 ? nil : (left, right)
            }
            for y in (11 + forward.bob)...(19 + forward.bob) {
                guard let (aLeft, aRight) = extent(a, y),
                      let (cLeft, cRight) = extent(c, y) else { continue }
                let mirroredLeft = PixelBuffer.side - 1 - cRight
                let mirroredRight = PixelBuffer.side - 1 - cLeft
                #expect(abs(aLeft - mirroredLeft) <= 1 && abs(aRight - mirroredRight) <= 1,
                        "row \(y) at turn \(turn) spans \(aLeft)…\(aRight); its mirror spans \(mirroredLeft)…\(mirroredRight)")
            }
        }
    }

    /// The eyes narrow and leave; they never leave a wardrobe's face paint
    /// behind them. Sonic is the case that named this rule — his white
    /// field outliving his eyes is exactly the "costume covering a face"
    /// the eye-cover ban exists to prevent.
    @Test("The eyes and the face paint leave together")
    func theFaceLeavesTogether() {
        for step in 0...20 {
            let turn = Double(step) / 40          // 0 … 180°
            var pose = airborne(.sonic)
            pose.torsoTurn = turn
            let b = CrabRig.render(pose, costume: .sonic)
            var eyes = 0, field = 0
            for y in (11 + pose.bob)...(17 + pose.bob) {
                for x in 0..<PixelBuffer.side {
                    if b[x, y] == .eye { eyes += 1 }
                    if b[x, y] == .paper { field += 1 }
                }
            }
            #expect(eyes > 0 || field == 0,
                    "sonic wears a blank white face at turn \(turn): \(field) field cells, no eyes")
        }
    }

    /// What wraps around him shows from behind; what is painted on his face
    /// does not. The ninja's headband is the whole reason the rule is a run
    /// length rather than a rectangle of coordinates.
    @Test("A band round him survives his back; face paint does not")
    func wrapRowsSurviveTheBack() {
        var pose = airborne(.ninja)
        pose.torsoTurn = 0.5
        let ninja = CrabRig.render(pose, costume: .ninja)
        var band = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where ninja[x, y] == .costumeA { band += 1 }
        }
        #expect(band >= 8, "the ninja's headband did not come round with him (\(band) cells)")

        var sonicPose = airborne(.sonic)
        sonicPose.torsoTurn = 0.5
        let sonic = CrabRig.render(sonicPose, costume: .sonic)
        var muzzle = 0
        for y in (15 + sonicPose.bob)...(19 + sonicPose.bob) {
            for x in 0..<PixelBuffer.side where sonic[x, y] == .costumeC { muzzle += 1 }
        }
        #expect(muzzle == 0, "sonic's muzzle is painted on the back of his head")
    }

    /// A flank is a side, and the side of a pixel crab is a colour. Edge-on
    /// the whole shell IS the flank slab, so this is where every ink that
    /// should not be riding it shows up at once: a ninja's ribbon, a
    /// tiger's tail, a turkey's fan, a rain streak, a stripe. All of it is
    /// either behind him or painted on a face he is no longer showing.
    @Test("The flank slab carries no detail, in any wardrobe")
    func theFlankIsOneFlatStep() {
        for costume in Costume.allCases {
            for turn in [0.25, 0.75] {
                var pose = airborne(costume)
                pose.torsoTurn = turn
                let b = CrabRig.render(pose, costume: costume)
                for y in (12 + pose.bob)...(19 + pose.bob) {
                    // Inside his own outline only — the weather beyond it is
                    // the world's, and the world is not turning.
                    var left = 99, right = -1
                    for x in 0..<PixelBuffer.side where b[x, y] == .body || b[x, y] == .bodyShade {
                        left = min(left, x); right = max(right, x)
                    }
                    guard right >= left else { continue }
                    for x in left...right {
                        let ink = b[x, y]
                        guard ink != .clear else { continue }
                        #expect(ink == .body || ink == .bodyShade,
                                "\(ink) rode \(costume)'s flank at (\(x),\(y)), turn \(turn)")
                    }
                }
            }
        }
    }

    /// The blend finishes the turn rather than unwinding it the long way,
    /// and never in one jump.
    @Test("A blend out of a turn takes the short way round")
    func blendFinishesTheTurnTheShortWay() {
        var from = CrabPose(), to = CrabPose()
        from.torsoTurn = 0.7
        #expect(CrabPose.blend(from: from, to: to, u: 0.5).torsoTurn == 0.85,
                "0.7 → 0 should finish forward, not unwind")
        from.torsoTurn = 0.3
        #expect(CrabPose.blend(from: from, to: to, u: 0.5).torsoTurn == 0.15,
                "0.3 → 0 should unwind, not run forward")
        #expect(CrabPose.blend(from: from, to: to, u: 0).torsoTurn == 0.3)
        #expect(CrabPose.blend(from: from, to: to, u: 1).torsoTurn == 0)

        // …and the crossfade steps it rather than jumping. Measured the way
        // the rig reads it — a whole turn is the same picture as none, so
        // the last frame's 1.0 → 0 is a number changing, not a crab moving.
        from.torsoTurn = 0.7
        var previous = 0.7
        for frame in 1...12 {
            let u = Double(frame) / 12
            let turn = CrabPose.blend(from: from, to: to, u: u).torsoTurn
            let step = abs(turn - previous).truncatingRemainder(dividingBy: 1)
            #expect(min(step, 1 - step) <= 0.07, "the blend jumped \(step) of a turn")
            previous = turn
        }
    }

    /// Every recoloured shell owns its own step. Without one the hero flank
    /// and the whole turned back fall through to the bare crab's terracotta
    /// — a brown smear on a green monster, which five costumes wore for a
    /// while before anyone noticed.
    @Test("Every shell override carries its own shade")
    func everyShellOverrideHasAStep() {
        for costume in Costume.allCases {
            let inks = CostumeStyle.of(costume).inks
            guard inks[.body] != nil else { continue }
            #expect(inks[.bodyShade] != nil,
                    "\(costume) repaints the shell but has no step below it")
        }
    }

    /// The white costume's snow is the world's, not his: it falls where it
    /// falls while he turns underneath it.
    @Test("Arctic White's snow is world-anchored")
    func whiteWeatherIsWorldAnchored() {
        var still = airborne(), turned = airborne()
        turned.torsoTurn = 0.25
        let a = CrabRig.render(still, costume: .white)
        let b = CrabRig.render(turned, costume: .white)
        // Above his crown the only thing in the frame is weather.
        var moved = 0
        for y in 0..<max(0, 9 + still.bob) {
            for x in 0..<PixelBuffer.side where a[x, y] != b[x, y] { moved += 1 }
        }
        #expect(moved == 0, "\(moved) flakes turned with him")
        _ = still
    }

    /// Everything below his feet is the world's too — the deck, the wheels,
    /// the shadow. A crab may spin; his board may not.
    @Test("Nothing below his feet moves")
    func nothingBelowTheLegsMoves() {
        for prop in [CrabPose.Prop.skateboardVarial, .skateboardOllie, .skateboard] {
            for step in 1..<20 {
                var turned = airborne()
                turned.prop = prop; turned.propVisibility = 1; turned.propPhase = 0.4
                var still = turned
                turned.torsoTurn = Double(step) / 20
                let a = CrabRig.render(still), b = CrabRig.render(turned)
                for y in (25 + still.bob)..<PixelBuffer.side {
                    for x in 0..<PixelBuffer.side {
                        #expect(a[x, y] == b[x, y],
                                "\(prop) moved at (\(x),\(y)) on turn \(Double(step) / 20)")
                    }
                }
            }
        }
    }

    /// **The body may not turn unless the board turns with it.**
    ///
    /// This is the rule the whole channel answers to, and it is here because
    /// the first version broke it: the body spun a full turn while the board
    /// yawed half of one on a separate clock. Skaters have a name for a body
    /// that rotates without its board — a sex change — and the operator
    /// recognised it on sight. So the pin is not "the varial turns" but
    /// "nothing turns alone".
    @Test("He never turns without the board turning with him")
    func theBoardTurnsWithHim() {
        for kind in CrabAnimator.Flourish.allCases {
            var everTurned = false
            for step in 0...120 {
                let pose = CrabAnimator.flourishPose(kind, at: Double(step) * kind.duration / 120)
                let turn = pose.torsoTurn - pose.torsoTurn.rounded(.down)
                guard turn > 0.001, turn < 0.999 else { continue }
                everTurned = true
                // Whatever is under him while he is mid-turn must be a board
                // that turns. A pitching or flipping board is not enough —
                // it has to YAW.
                #expect(pose.prop == .skateboardBigspin,
                        "\(kind) turned his body over a \(pose.prop), which does not turn with him")
            }
            if kind == .bigspin {
                #expect(everTurned, "the bigspin never turned him")
            } else {
                #expect(!everTurned, "\(kind) turns his body, and only the bigspin may")
            }
        }
    }

    /// The bigspin's own contract: he takes half a turn in the air while the
    /// board takes a whole one — the two-to-one the trick is named for — and
    /// then finishes the rotation on the way out rather than unwinding it,
    /// so he lands square without ever reversing.
    @Test("The bigspin turns half in the air and finishes on the landing")
    func theBigspinFinishesItsTurn() {
        let duration = CrabAnimator.Flourish.bigspin.duration
        var previous = 0.0
        // Up to, not past: beyond its own duration the trick is over and
        // the plain idle pose comes back with no turn at all.
        for step in 0..<240 {
            let progress = Double(step) / 240
            let pose = CrabAnimator.flourishPose(.bigspin, at: progress * duration)
            #expect(pose.torsoTurn >= previous - 1e-9,
                    "he unwound at progress \(progress) — a bigspin does not reverse")
            previous = pose.torsoTurn
        }
        // Square at both ends: a whole turn renders as no turn at all.
        let landed = CrabAnimator.flourishPose(.bigspin, at: duration - 0.01)
        #expect(abs(landed.torsoTurn - 1) < 0.02, "he landed mid-turn at \(landed.torsoTurn)")
        // Not a byte-compare: a thousandth of a turn short of square is
        // still a thousandth of a turn, and it moves a catchlight. What
        // matters is that he ARRIVES square — the silhouette on his last
        // airborne frame is the silhouette he lands with, to within a cell,
        // so the stomp has nothing left to snap through.
        var flat = landed
        flat.torsoTurn = 0
        let turned = CrabRig.render(landed), square = CrabRig.render(flat)
        func span(_ b: PixelBuffer, _ y: Int) -> (Int, Int)? {
            var left = 99, right = -1
            for x in 0..<PixelBuffer.side where b[x, y] == .body || b[x, y] == .bodyShade {
                left = min(left, x); right = max(right, x)
            }
            return right < 0 ? nil : (left, right)
        }
        for y in (11 + landed.bob)...(19 + landed.bob) {
            guard let a = span(turned, y), let c = span(square, y) else { continue }
            #expect(abs(a.0 - c.0) <= 1 && abs(a.1 - c.1) <= 1,
                    "row \(y) lands at \(a) but square is \(c) — he stomped mid-turn")
        }

        // Half in the air, where the board has come round once.
        let apex = CrabAnimator.flourishPose(.bigspin, at: 0.795 * duration)
        #expect(abs(apex.torsoTurn - 0.5) < 0.05,
                "he should be halfway round as the air ends, not \(apex.torsoTurn)")
    }

    /// At every rate anything renders him at, the silhouette's edges walk
    /// rather than jump. The bounds are recorded per rate rather than
    /// tightened to one: a 360 in two seconds simply moves more cells per
    /// frame at ten a second than at thirty, and pretending otherwise would
    /// mean pinning a number nothing can meet.
    @Test("The turning silhouette never teleports")
    func theTurningSilhouetteNeverTeleports() {
        let duration = CrabAnimator.Flourish.bigspin.duration
        for (rate, bound) in [(30.0, 2), (20.0, 3), (12.0, 5), (10.0, 6)] {
            var previous: (Int, Int)?
            for frame in 0...Int(duration * rate) {
                let pose = CrabAnimator.flourishPose(.bigspin, at: Double(frame) / rate)
                let b = CrabRig.render(pose)
                var left = 99, right = -1
                for y in (11 + pose.bob)...(19 + pose.bob) {
                    for x in 0..<PixelBuffer.side
                    where b[x, y] == .body || b[x, y] == .bodyShade {
                        left = min(left, x); right = max(right, x)
                    }
                }
                guard right >= 0 else { continue }
                if let (wasLeft, wasRight) = previous {
                    #expect(abs(left - wasLeft) <= bound && abs(right - wasRight) <= bound,
                            "at \(Int(rate))fps an edge moved \(max(abs(left - wasLeft), abs(right - wasRight))) cells")
                }
                previous = (left, right)
            }
        }
    }

    /// The mid-air stance the turn actually happens in.
    ///
    /// The height is asked for per costume: a tall-crowned look is lifted
    /// less than a bare crab so its crest stays on the grid, and a test that
    /// derives its scan rows from `pose.bob` has to be told the same number
    /// the rig will use, or it reads the wrong rows and calls it a bug.
    private func airborne(_ costume: Costume = .none) -> CrabPose {
        var pose = CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false)
        pose.bob = max(-9, CrabRig.crownFloor(costume: costume, ghostCostume: .none,
                                              headwear: .none))
        pose.legAmplitude = 1.6
        pose.legPhase = .pi / 2
        return pose
    }
}
