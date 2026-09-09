import Testing
import Foundation
@testable import ClaudePet

/// **The demo reels' arithmetic.**
///
/// Nothing here is committed media, so nothing here pins pixels. What it pins
/// is the edit: the grid, the dwells, real speed, and the handful of facts a
/// fourteen-agent design pass found were load-bearing and easy to break —
/// above all the frozen downward gaze that would otherwise be the poster
/// frame of a crab staring at his feet.
@MainActor
struct SkateDemoTests {

    private var reels: [SkateDemo.Reel] { SkateDemo.reels }

    @Test("Every shot boundary is a whole beat and a whole frame at both rates")
    func theGridHolds() {
        for reel in reels {
            var expected = 0.0
            for (index, shot) in reel.shots.enumerated() {
                #expect(abs(shot.start - expected) < 1e-9,
                        "\(reel.name) shot \(index + 1) starts at \(shot.start), not \(expected) — a gap or an overlap")
                expected = shot.end

                let beats = shot.start / SkateDemo.beat
                #expect(abs(beats - beats.rounded()) < 1e-9,
                        "\(reel.name) shot \(index + 1) starts at beat \(beats)")
                for fps in [SkateDemo.gifFps, Int(SkateDemo.videoFps)] {
                    let frames = shot.start * Double(fps)
                    #expect(abs(frames - frames.rounded()) < 1e-9,
                            "\(reel.name) shot \(index + 1) starts on frame \(frames) at \(fps)fps")
                }
            }
            let endBeats = reel.seconds / SkateDemo.beat
            #expect(abs(endBeats - endBeats.rounded()) < 1e-9, "\(reel.name) ends off the beat")
        }
    }

    @Test("Both reels are under the fifteen-second ceiling")
    func bothFitTheCeiling() {
        for reel in reels {
            #expect(reel.seconds < 15.0, "\(reel.name) runs \(reel.seconds)s")
            #expect(reel.seconds > 10.0, "\(reel.name) is only \(reel.seconds)s — too short to review from")
        }
    }

    /// Dwell variety is what separates a reel from a slideshow: the house law
    /// asks for at least three distinct shot lengths, a longest-to-shortest
    /// ratio of at least two, and no two neighbours the same.
    @Test("The dwells are a table, not a metronome")
    func theDwellsVary() {
        for reel in reels {
            let lengths = reel.shots.map(\.seconds)
            let distinct = Set(lengths.map { Int(($0 * 1000).rounded()) })
            #expect(distinct.count >= 3, "\(reel.name) has only \(distinct.count) distinct shot lengths")
            let ratio = (lengths.max() ?? 0) / (lengths.min() ?? 1)
            #expect(ratio >= 2, "\(reel.name)'s longest/shortest is \(ratio)")
            for pair in zip(lengths, lengths.dropFirst()) {
                #expect(abs(pair.0 - pair.1) > 1e-9,
                        "\(reel.name) has two adjacent \(pair.0)s shots — a metronome")
            }
            #expect(lengths.contains { $0 >= 1.0 }, "\(reel.name) has no shot over a second")
        }
    }

    /// 🔎 THE BLOCKING FIX. `pose(mood:.idle, t: 0.4)` runs `gaze(at: 0.4)`,
    /// whose die `noise(0)` is 0.8833 and lands in the `>= 0.68` arm, which
    /// returns `(0, +1)`: a held one-pixel downward dart. Frozen into the base
    /// and held for two seconds, that is a poster frame of a crab looking at
    /// his feet. The wardrobe matters just as much — `deckStance` returns 0
    /// for anything but the Skater, so a bare wardrobe is a crab standing on
    /// nothing, silently.
    @Test("The skate base looks ahead and stands on its deck")
    func theBaseIsCorrect() {
        let stance = SkateDemo.skateStance
        #expect(stance.gazeY == 0, "the base stares down — the poster frame is a crab watching his feet")
        #expect(stance.gazeX == 0, "the base glances sideways")
        #expect(stance.deckUnderfoot == 1, "the base is not on its deck — wrong wardrobe")
        #expect(stance.prop == .skateboardSmith)
        // …and the raw idle pose really does carry the dart, so this test is
        // guarding a live hazard rather than a hypothetical one.
        let raw = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false,
                                    wardrobe: .init(current: .skater))
        #expect(raw.gazeY == 1, "the hazard is gone from the rig — this guard can be retired")
    }

    /// The two passes are the same 5.4s trick from the same base at the same
    /// local instants, so the operator's A/B is exact rather than approximate.
    @Test("The skate reel's two passes are bit-identical in the buffer")
    func thePassesMatch() {
        for local in stride(from: 0.0, through: 5.4, by: 0.15) {
            let (a, _) = SkateDemo.skatePose(reel: 2.0 + local)
            let (b, _) = SkateDemo.skatePose(reel: 8.0 + local)
            let same = CrabRig.render(a, costume: .skater)
                .same(as: CrabRig.render(b, costume: .skater))
            #expect(same, "the passes diverge at local \(local)")
        }
    }

    /// 🔎 The measurement shot 4 exists to make. Over local 1.500 → 4.500 the
    /// ledge travels 14 cells and the bushes 7 — exactly 2:1. The design's
    /// first cut ran to 4.000 and measured 1.75:1, which would have had the
    /// operator grading a parallax that was not the one built.
    @Test("The parallax window measures exactly two to one")
    func theParallaxIsTwoToOne() {
        func world(_ local: Double) -> (ledge: Int, bush: Int) {
            let pose = CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance)
            let right = CrabRig.ledgeRightEnd(travel: pose.ledge)
            return (right, CrabRig.bushOffset(travel: pose.ledge))
        }
        let opening = world(1.5), closing = world(4.5)
        let ledgeCells = opening.ledge - closing.ledge
        let bushCells = opening.bush - closing.bush
        #expect(ledgeCells == 14, "the ledge moved \(ledgeCells) cells, not 14")
        #expect(bushCells == 7, "the bushes moved \(bushCells) cells, not 7")
        #expect(ledgeCells == bushCells * 2, "the parallax is \(Double(ledgeCells) / Double(bushCells)):1")
        // …and the window is the one shot 4 actually plays.
        let shot = SkateDemo.skateReel.shots[3]
        #expect(shot.start - 8.0 == 1.5 && shot.end - 8.0 == 4.5,
                "shot 4 no longer covers local 1.5 → 4.5")
    }

    /// The clock map removes 4.8s of a 19.3s ride and must never ask for a
    /// frame the ride cannot give.
    @Test("The rainbow clock map is monotone and always in range")
    func theClockMapHolds() {
        var previous = -1.0
        var t = 0.0
        while t <= SkateDemo.rainbowReel.seconds + 1e-9 {
            let ride = SkateDemo.ride(reel: t)
            #expect(ride > previous, "the ride went backwards at reel \(t)")
            previous = ride
            #expect(CrabAnimator.comboRide(local: ride, wardrobe: .init(current: .skater)) != nil,
                    "the ride is over at reel \(t) (ride \(ride))")
            t += 1.0 / Double(SkateDemo.videoFps)
        }
        // The removed time is the head trim, the nollie beat and the tail.
        #expect(abs((19.3 - SkateDemo.rainbowReel.seconds) - 4.8) < 1e-9)
    }

    /// Real speed everywhere: a shot's ride window is exactly as long as its
    /// reel window. Nothing is slowed, nothing is sped up.
    @Test("Compression is exactly one in every shot")
    func nothingIsStretched() {
        for shot in SkateDemo.rainbowReel.shots {
            let inRide = SkateDemo.ride(reel: shot.start)
            let outRide = SkateDemo.ride(reel: shot.end - 1e-9)
            #expect(abs((outRide - inRide) - shot.seconds) < 1e-6,
                    "shot at \(shot.start) compresses \(outRide - inRide) into \(shot.seconds)")
        }
    }

    /// The colour has somewhere to go: the opening shot is scoreless, and the
    /// closing one is at full score with the board alight.
    @Test("The rainbow reel opens colourless and closes burning")
    func theColourHasSomewhereToGo() {
        for t in stride(from: 0.0, to: 2.0, by: 0.05) {
            let (pose, tint) = SkateDemo.rainbowPose(reel: t)
            #expect(pose.combo == 0, "the score is \(pose.combo) at reel \(t) — colour before the payoff")
            #expect(tint == nil, "there is a tint at reel \(t)")
            #expect(pose.boardFire == 0)
        }
        for t in stride(from: 13.5, through: 14.4, by: 0.05) {
            let (pose, tint) = SkateDemo.rainbowPose(reel: t)
            #expect(pose.combo > 0.999, "the score is only \(pose.combo) at reel \(t)")
            #expect(pose.boardFire > 0.999, "the board is not alight at reel \(t)")
            #expect(tint != nil, "no rainbow at full score")
        }
    }

    /// Every cut must change the frame. With no type there are three
    /// dimensions available — magnification, ground and horizontal nudge — and
    /// every boundary has to move at least two of them.
    @Test("Every cut changes at least two dimensions of the frame")
    func everyCutIsACut() {
        for reel in reels {
            for (before, after) in zip(reel.shots, reel.shots.dropFirst()) {
                var changed = 0
                if before.stop != after.stop { changed += 1 }
                if before.groundName != after.groundName { changed += 1 }
                if before.cellsRight != after.cellsRight { changed += 1 }
                #expect(changed >= 2,
                        "\(reel.name)'s cut at \(after.start)s changes only \(changed) dimension(s)")
            }
        }
    }

    /// Only the two quiet warm plates are used. Lemon is legal on contrast and
    /// is refused on taste: the operator's recorded direction is that the
    /// character is the only saturated thing in frame.
    @Test("The grounds are the quiet ones, and no two neighbours repeat")
    func theGroundsAreQuiet() {
        for reel in reels {
            for shot in reel.shots {
                #expect(["cream", "gold"].contains(shot.groundName),
                        "\(reel.name) uses \(shot.groundName)")
            }
            for (before, after) in zip(reel.shots, reel.shots.dropFirst())
            where before.groundName == after.groundName {
                #expect(before.stop != after.stop || before.cellsRight != after.cellsRight,
                        "\(reel.name) repeats \(after.groundName) across \(after.start)s with nothing else changing")
            }
        }
    }

    /// Both canvas shapes must be whole-cell at every stop, and nothing may
    /// crop — the ledge runs the buffer's whole width, so a cropped sprite is
    /// a cropped measurement.
    @Test("Both shapes are whole-cell and nothing crops")
    func theFormatsAreClean() {
        for format in SkateDemo.formats {
            for stop in SkateDemo.Stop.allCases {
                let side = format.side(stop)
                #expect(side.truncatingRemainder(dividingBy: 32) == 0,
                        "\(format.name) \(stop) is \(side)pt — not a whole cell")
                #expect(side <= min(format.canvas.width, format.canvas.height),
                        "\(format.name) \(stop) does not fit its canvas")
                let cell = format.cell(stop)
                let dy = format.offsetY(stop)
                #expect(dy.truncatingRemainder(dividingBy: cell) == 0,
                        "\(format.name) \(stop) nudges \(dy)pt — not a whole cell")
                // The sprite, offset, stays inside the canvas.
                let top = (format.canvas.height - side) / 2 + dy
                #expect(top >= 0 && top + side <= format.canvas.height,
                        "\(format.name) \(stop) crops vertically")
                for shot in SkateDemo.rainbowReel.shots + SkateDemo.skateReel.shots
                where shot.stop == stop {
                    let left = (format.canvas.width - side) / 2 + CGFloat(shot.cellsRight) * cell
                    #expect(left >= 0 && left + side <= format.canvas.width,
                            "\(format.name) \(stop) crops horizontally at reel \(shot.start)")
                }
            }
        }
    }

    /// The ledge's full 28 cells are on the grid for a sixth of a second, so
    /// the still sheet is the only artifact that can carry "twice the length".
    @Test("The ledge sheet catches the only frames with the whole ledge")
    func theSheetCatchesTheWholeLedge() {
        for local in SkateDemo.fullExtentFrames {
            let pose = CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance)
            let right = CrabRig.ledgeRightEnd(travel: pose.ledge)
            let left = right - (CrabRig.ledgeLength - 1)
            #expect(left >= 0 && right <= PixelBuffer.side - 1,
                    "at local \(local) the ledge spans \(left)…\(right) — not wholly on the grid")
        }
    }
}

private extension PixelBuffer {
    func same(as other: PixelBuffer) -> Bool {
        for y in 0..<Self.side {
            for x in 0..<Self.side where self[x, y] != other[x, y] { return false }
        }
        return true
    }
}
