import Testing
import Foundation
@testable import ClaudePet

/// **The wheels turn.** A wheel is 2×2 — three rim cells and a bearing — so
/// rotation is the bearing walking the four cells of the square, and there is
/// no other lever at this size.
///
/// The operator's read was that the wheels are static. Half true: the cruise
/// has walked its bearing since it was written, in its own hand-rolled copy of
/// the wheel, while `drawWheel` drew one that could not turn. So the rig
/// carried two wheels and only one of them rolled. This suite pins the fold —
/// one wheel function, every board — and the four facts that make a turning
/// wheel legible rather than noisy.
@MainActor
struct WheelRollTests {

    /// Rest is bottom-right, one cell for every wheel on every board.
    ///
    /// Eight of the eleven call sites never pass a roll, so they render through
    /// the default — counted, because the last round wrote "seven of the ten"
    /// and neither number was ever right: folding the cruise in made an
    /// eleventh site, and three of them pass a roll.
    ///
    /// `DeckStanceTests` holds six tricks' first frames to the
    /// resting deck cell-for-cell — which still passes, because rest moved for
    /// the resting deck and for the tricks together. A wheel that began a trick
    /// on a different cell from the deck it started on would be a one-frame
    /// change at the instant the first law forbids one.
    ///
    /// Bottom-right rather than bottom-left because `BackSmithTests` reads
    /// `.yellow` in column 11 — the tail hub's left cell — to pin the grind
    /// wheel's bottom row.
    @Test("every wheel rests on the same cell, bottom-right")
    func restIsShared() {
        #expect(CrabRig.bearingCell(roll: 0) == (1, 1))
    }

    /// 🔎 The sync itself, read off a render rather than off the signature.
    ///
    /// `bearingCell` takes no wheel any more, so two wheels *cannot* disagree —
    /// but that is an argument about the code, and the operator's note was about
    /// the picture. This draws a board's two wheels at a spread of rolls and
    /// checks the bearing sits at the same offset inside each 2x2, which is the
    /// thing that was actually wrong for one round.
    @Test("both wheels of a board are always on the same cell")
    func theyStayInSync() {
        for step in 0..<16 {
            let roll = Double(step) / 4.3
            var b = PixelBuffer()
            CrabRig.drawWheel(&b, x: 11, y: 25, roll: roll)
            CrabRig.drawWheel(&b, x: 20, y: 25, roll: roll)
            func offset(_ hub: Int) -> (Int, Int)? {
                for dy in 0..<2 where true {
                    for dx in 0..<2 where b[hub + dx, 26 + dy] == CrabRig.bearingInk {
                        return (dx, dy)
                    }
                }
                return nil
            }
            let tail = offset(11), nose = offset(20)
            #expect(tail != nil && nose != nil, "a wheel lost its bearing at roll \(roll)")
            #expect(tail! == nose!,
                    "at roll \(roll) the tail sits at \(tail!) and the nose at \(nose!)")
        }
    }

    /// Turns, not radians — `torsoTurn`'s convention, where a whole turn renders
    /// as rest. A wheel that unwound at the wrap would be the wagon-wheel bug
    /// bought by arithmetic rather than by frame rate.
    @Test("a whole turn comes back to rest, and never unwinds")
    func aTurnIsATurn() {
        #expect(CrabRig.bearingCell(roll: 1.0) == CrabRig.bearingCell(roll: 0))
        #expect(CrabRig.bearingCell(roll: 7.0) == CrabRig.bearingCell(roll: 0))
        // Mid-step, not just on the boundary: three-quarters of the way through
        // a step is still that step.
        #expect(CrabRig.bearingCell(roll: 0.2) == CrabRig.bearingCell(roll: 0))
    }

    /// Four positions, all of them used. A ring that visited three would read as
    /// a rock rather than a roll.
    @Test("the bearing visits all four cells of the square")
    func theRingIsWhole() {
        let seen = Set((0..<4).map { step in
            let c = CrabRig.bearingCell(roll: Double(step) / 4)
            return "\(c.0),\(c.1)"
        })
        #expect(seen.count == 4, "the ring visited \(seen.count) cells, not 4")
    }

    /// 🔎 Clockwise, and both wheels the same way — neither is a preference.
    ///
    /// `drawGroundRush` scrolls the floor with `x = base - scroll`, so the world
    /// goes LEFT and he goes right; a wheel rolling right turns clockwise, which
    /// on a screen with y growing downward means the top cell moves toward `+x`.
    /// And two wheels under one board do not counter-rotate, however symmetric
    /// the static pair used to look — the `inner` mirror is a shading
    /// convention, not a direction — and it is gone now, since both wheels
    /// share one ring.
    @Test("both wheels turn clockwise, the way the ground says they must")
    func theyTurnTheWayHeTravels() {
        // Clockwise on this ring is top-left → top-right → bottom-right →
        // bottom-left, which is the order the cruise has always used.
        #expect(CrabRig.wheelCells.elementsEqual([(0, 0), (1, 0), (1, 1), (0, 1)], by: ==))
        for step in 0..<4 {
            let here = CrabRig.bearingCell(roll: Double(step) / 4)
            let next = CrabRig.bearingCell(roll: Double(step + 1) / 4)
            let i = CrabRig.wheelCells.firstIndex { $0 == here }!
            let j = CrabRig.wheelCells.firstIndex { $0 == next }!
            #expect(j == (i + 1) % 4,
                    "the ring went \(here) → \(next), which is not clockwise")
        }
    }

    /// 🔎 The wheel reads the SAME number its own ground reads.
    ///
    /// The rig has three ground speeds, not one: the ledge does 23.1 cells a
    /// second, the cruise's streaks 23.8, and the manual's rush 13.1 — a manual
    /// is a balance trick and travels at little over half a cruise. Taking one
    /// constant off the ledge, which is the only speed the rig names outright,
    /// would have spun the manual's wheels 1.8× faster than the floor visibly
    /// moving underneath them. That is the disagreement the grind round went to
    /// one constant speed to remove, reintroduced one layer down.
    ///
    /// So each board converts its own travel through the one conversion there
    /// is. This pin fails if anyone gives a wheel a speed its ground does not
    /// have.
    @Test("a wheel turns once per circumference of its own ground")
    func theWheelAgreesWithItsFloor() {
        // One revolution per 2πr of travel, and the wheel is two cells across.
        #expect(abs(CrabRig.wheelTurnsPerCell - 1 / (2 * Double.pi)) < 1e-12)
        let manualTurns = CrabRig.manualGroundCells * CrabRig.wheelTurnsPerCell
        let cruiseTurns = CrabRig.cruiseGroundCells * CrabRig.wheelTurnsPerCell
        // The cruise is the fast one by its own premise — "He rides, fast".
        #expect(cruiseTurns > manualTurns,
                "the manual (\(manualTurns) turns) is out-rolling the cruise (\(cruiseTurns))")
        // And the numbers are the ones the ground itself is drawn from, not a
        // second copy that can drift: 34 cells of rush, 62 of streak.
        #expect(CrabRig.manualGroundCells == 34)
        #expect(CrabRig.cruiseGroundCells == 62)
    }

    /// 🔎 The rate is measured against the GIF, not the live window.
    ///
    /// `GifRenderer.frameDelay` is a twelfth of a second and every committed
    /// clip renders there, so 12fps is the binding clock and the 20fps house
    /// clock is the generous one. The half cab already fixed the limit in this
    /// codebase — *"a three-state cycle in four frames strobes"* — and a
    /// four-state ring is tighter still. Past one step a frame the ring starts
    /// skipping cells, and past two it reads as turning backwards.
    @Test("no wheel outruns the frame rate it is rendered at")
    func theRingStaysUnderTheClock() {
        let beat = CrabAnimator.Flourish.manual.duration
        for (name, cells) in [("manual", CrabRig.manualGroundCells),
                              ("cruise", CrabRig.cruiseGroundCells)] {
            let perFrame = CrabRig.wheelStepsPerFrame(cells: cells, seconds: beat,
                                                      frameDelay: GifRenderer.frameDelay)
            #expect(perFrame < 2,
                    "\(name) steps \(perFrame) cells a frame, which reads backwards")
            // The cruise sits at 1.27 and is the fast one on purpose; nothing
            // should ever be allowed past 1.5 without a render to justify it.
            #expect(perFrame < 1.5, "\(name) steps \(perFrame) cells a frame")
        }
    }

    /// The three rolling boards all run 2.6s today. Nothing depends on that any
    /// more — each reads its own cell count — but if two of them diverge the
    /// speeds above stop being comparable, so it is worth knowing.
    @Test("the rolling beats still share a duration")
    func theRollingBeatsAgree() {
        let beats: [CrabAnimator.Flourish] = [.cruise, .manual, .noseManual]
        let durations = Set(beats.map(\.duration))
        #expect(durations.count == 1, "the rolling beats run \(durations)")
    }

    /// A grind is travel; what it does not do is spin the wheels. The smith
    /// parks its tail truck on the ledge and the ledge does the moving, so its
    /// bearing must never leave rest — and `BackSmithTests` depends on exactly
    /// that, reading `.yellow` in column 11 to pin the wheel's bottom row.
    /// Give the smith a roll and that pin fails, which is the coupling made
    /// explicit rather than left to be rediscovered.
    @Test("the grind, the parked deck and the air never turn a wheel")
    func onlyRollingBoardsRoll() {
        let still: [CrabAnimator.Flourish] = [.backSmith, .ollie, .nollie, .kickflip,
                                              .varialFlip, .shoveIt, .bigspin,
                                              .treFlip, .laserFlip, .halfCab]
        for trick in still {
            for step in 0...40 {
                let t = Double(step) / 40 * trick.duration
                let buffer = CrabRig.render(CrabAnimator.flourishPose(trick, at: t))
                // Every bearing on screen has to sit under a rim cell — the two
                // rest cells are both on the hub row, and a turning wheel is the
                // only thing that puts one on the rim row.
                for y in 0..<PixelBuffer.side where y > 0 {
                    for x in 0..<PixelBuffer.side {
                        guard buffer[x, y] == CrabRig.bearingInk else { continue }
                        guard buffer[x, y - 1] == .yellow || buffer[x, y + 1] == .yellow
                        else { continue }
                        #expect(buffer[x, y - 1] == .yellow,
                                "\(trick) put a bearing on a rim row at \(x),\(y) — it rolled")
                    }
                }
            }
        }
    }

    /// One wheel, drawn once. The cruise kept a private copy for as long as it
    /// existed, at its own rate, and the seam it left is recorded in the
    /// orientation log. `bearingInk` naming the wheel means a second
    /// implementation cannot reappear without this failing.
    @Test("there is exactly one wheel in the rig")
    func theWheelIsNotDuplicated() throws {
        let rig = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ClaudePet/View/CrabRig.swift")
        // CODE lines only. Counting raw occurrences read this file's own prose
        // about the bearing as a second implementation — a pin that fails on a
        // comment is a pin nobody will trust the next time it goes red.
        let source = try String(contentsOf: rig, encoding: .utf8)
        let uses = source.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .reduce(0) { $0 + ($1.components(separatedBy: "bearingInk").count - 1) }
        let note = "`bearingInk` appears \(uses) times — it should be its declaration "
            + "and the one line of `drawWheel` that places it"
        #expect(uses == 2, "\(note)")
    }
}
