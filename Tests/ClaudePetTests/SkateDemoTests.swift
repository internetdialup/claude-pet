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

    /// The two passes are the same 6.5s trick from the same base at the same
    /// local instants, so the operator's A/B is exact rather than approximate.
    @Test("The skate reel's two passes are bit-identical in the buffer")
    func thePassesMatch() {
        let duration = CrabAnimator.Flourish.backSmith.duration
        #expect(duration == 6.5, "the trick is \(duration)s — the reel's onsets assume 6.5")
        for local in stride(from: 0.0, through: duration, by: 0.15) {
            let (a, _) = SkateDemo.skatePose(reel: SkateDemo.skateOnsetA + local)
            let (b, _) = SkateDemo.skatePose(reel: SkateDemo.skateOnsetB + local)
            let same = CrabRig.render(a, costume: .skater)
                .same(as: CrabRig.render(b, costume: .skater))
            #expect(same, "the passes diverge at local \(local)")
        }
    }

    /// 🔎 The measurement shot 4 exists to make. `bushOffset` halves the
    /// ledge's own column and rounds, so a window whose ends both land on an
    /// ODD column reads exactly 2:1 and one that does not reads 1.83 or 2.18 —
    /// the ratio the operator grades has to be the one that was built, so the
    /// boundary is chosen for it. Over local 1.500 → 5.000 the ledge travels 24
    /// cells and the bushes 12. The first cut of this test ran 1.5 → 4.5 and
    /// measured 1.75:1 against a 28-cell ledge; both ends moved this round.
    @Test("The parallax window measures exactly two to one")
    func theParallaxIsTwoToOne() {
        func world(_ local: Double) -> (ledge: Int, bush: Int) {
            let pose = CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance)
            let right = CrabRig.ledgeRightEnd(travel: pose.ledge)
            return (right, CrabRig.bushOffset(travel: pose.ledge))
        }
        let opening = world(1.5), closing = world(5.0)
        let ledgeCells = opening.ledge - closing.ledge
        let bushCells = opening.bush - closing.bush
        #expect(ledgeCells == 24, "the ledge moved \(ledgeCells) cells, not 24")
        #expect(bushCells == 12, "the bushes moved \(bushCells) cells, not 12")
        #expect(ledgeCells == bushCells * 2, "the parallax is \(Double(ledgeCells) / Double(bushCells)):1")
        // …and the window is the one shot 4 actually plays.
        let shot = SkateDemo.skateReel.shots[3]
        #expect(shot.start - SkateDemo.skateOnsetB == 1.5 && shot.end - SkateDemo.skateOnsetB == 5.0,
                "shot 4 no longer covers local 1.5 → 5.0")
    }

    /// 🔎 The operator's note was *"make the ledge longer but you nailed the
    /// movement"* — so the block grew and the speed did not. The entry is a
    /// single eased leg from off-grid right to the landing column, and its
    /// average is what the eye reads as "how fast the ledge comes in".
    @Test("The ledge is longer and the entry keeps its old speed")
    func theEntryKeepsItsSpeed() {
        #expect(CrabRig.ledgeLength == 44, "the ledge is \(CrabRig.ledgeLength) cells")
        #expect(CrabRig.ledgeTravel == 32 + CrabRig.ledgeLength,
                "the travel must carry both ends off the grid")
        let duration = CrabAnimator.Flourish.backSmith.duration
        let lock = 0.375 * duration
        func right(_ local: Double) -> Int {
            CrabRig.ledgeRightEnd(travel: CrabAnimator.flourishPose(.backSmith, at: local,
                                                                   base: SkateDemo.skateStance).ledge)
        }
        let cells = Double(right(0) - right(lock))
        #expect(cells == 56, "the entry covers \(cells) cells, not 56")
        let speed = cells / lock
        #expect(abs(speed - 23.1) / 23.1 < 0.02,
                "the entry runs at \(speed) cells/s — the first cut ran at 23.1")
        // Every key position the operator approved, to the cell.
        #expect(right(lock) == 19, "he lands beside column \(right(lock)), not 19")
        #expect(right(0.755 * duration) == 13, "the drift ended at \(right(0.755 * duration)), not 13")
        #expect(right(0.93 * duration) < 0, "the ledge is still on the grid when he stomps")
    }

    /// 🔎 THE GLITCH THE OPERATOR SAW: *"he sometimes rides the ledge with no
    /// skateboard"*. No frame was ever boardless. The exit used to spin a whole
    /// rotation in 0.648s — 2.8× faster than this rig's own kickflip — so the
    /// board's seven-cell-thick underside strobed while he was level with the
    /// ledge, and slab and ledge read as one black box. The fix is the rate.
    @Test("The kickflip out takes a whole second to turn")
    func theExitDoesNotStrobe() {
        let duration = CrabAnimator.Flourish.backSmith.duration
        let start = 0.755 * duration, end = 0.93 * duration
        func phase(_ local: Double) -> Double {
            CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance).propPhase
        }
        // 🔎 Measure the ROTATION, not the phase branch. Widening the branch
        // while leaving the sweep inside it fast is exactly the bug, so the
        // quantity pinned is the seconds propPhase spends actually turning and
        // the most it advances between two frames the operator will see.
        var began: Double?, finished: Double?, biggest = 0.0
        var previous = phase(start)
        var local = start
        while local <= end + 1e-9 {
            let now = phase(local)
            #expect(now >= previous - 1e-9, "the board unwound at local \(local)")
            biggest = max(biggest, now - previous)
            if began == nil, now >= 0.02 { began = local }
            if finished == nil, now >= 0.98 { finished = local }
            previous = now
            local += 1.0 / Double(SkateDemo.videoFps)
        }
        #expect(previous > 0.95, "the exit turned \(previous) of a rotation, not one")
        let turn = (finished ?? end) - (began ?? start)
        #expect(turn >= 1.0, "the board turns in \(turn)s — fast enough to strobe")
        // A whole turn in 0.648s is 1/20 of a rotation a frame; the underside
        // slab flickers in and out and reads as a black box with no board.
        #expect(biggest <= 0.04,
                "the board jumps \(biggest) of a turn between frames — it will strobe")
        // …and the board is a board the whole way out.
        for l in stride(from: start, through: end, by: 0.02) {
            let pose = CrabAnimator.flourishPose(.backSmith, at: l, base: SkateDemo.skateStance)
            #expect(pose.prop == .skateboard, "the exit board is \(pose.prop) at local \(l)")
            #expect(pose.propVisibility > 0.99, "the board faded at local \(l)")
        }
    }

    /// The clock map removes 6.9s of a 20.4s ride and must never ask for a
    /// frame the ride cannot give.
    @Test("The rainbow clock map is monotone and always in range")
    func theClockMapHolds() {
        var previous = -1.0
        var t = 0.0
        while t <= SkateDemo.rainbowReel.seconds + 1e-9 {
            let ride = SkateDemo.ride(reel: t)
            #expect(ride > previous, "the ride went backwards at reel \(t)")
            previous = ride
            guard t >= SkateDemo.head else { t += 1.0 / Double(SkateDemo.videoFps); continue }
            #expect(CrabAnimator.comboRide(local: ride, wardrobe: .init(current: .skater)) != nil,
                    "the ride is over at reel \(t) (ride \(ride))")
            t += 1.0 / Double(SkateDemo.videoFps)
        }
        // The three cuts account for the whole difference: the frozen head, the
        // one contiguous ellipsis, and the tail.
        let session = CrabAnimator.skateSessionLength
        let tail = session - SkateDemo.ride(reel: SkateDemo.rainbowReel.seconds)
        #expect(abs(SkateDemo.skip - 5.8) < 1e-9)
        #expect(abs(tail - 1.1) < 1e-9, "the tail trim is \(tail)s")
        #expect(abs((session - SkateDemo.rainbowReel.seconds)
                    - (SkateDemo.skip + tail - SkateDemo.head)) < 1e-9)
        // 🔎 The tail exists to clear the ride's OWN ease-out, which begins at
        // 19.6: a reel ending at 19.8 would close on the fire going out.
        let skater = CrabAnimator.MotionWardrobe(current: .skater)
        let last = CrabAnimator.comboRide(local: SkateDemo.ride(reel: SkateDemo.rainbowReel.seconds),
                                          wardrobe: skater)
        #expect((last?.boardFire ?? 0) > 0.999, "the reel ends on a dying fire")
        let late = CrabAnimator.comboRide(local: 19.8, wardrobe: skater)
        #expect((late?.boardFire ?? 1) < 0.3, "the fade moved — this guard can be retired")
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
        for t in stride(from: 13.0, through: SkateDemo.rainbowReel.seconds - 0.05, by: 0.05) {
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

    /// At 44 cells the ledge is half again as long as the buffer, so no frame
    /// can hold all of it — the sheet's job is to show it overrunning, and its
    /// first frame is the moment of greatest coverage: the right end at the
    /// last column with the block running clear off the left edge.
    @Test("The ledge sheet catches the ledge overrunning the frame")
    func theSheetCatchesTheWholeLedge() {
        #expect(CrabRig.ledgeLength > PixelBuffer.side,
                "the ledge fits the frame again — the sheet can go back to whole-ledge frames")
        var previous = PixelBuffer.side
        for (index, local) in SkateDemo.fullExtentFrames.enumerated() {
            let pose = CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance)
            let right = CrabRig.ledgeRightEnd(travel: pose.ledge)
            #expect(right >= 0 && right <= PixelBuffer.side - 1,
                    "at local \(local) the ledge's right end is at \(right) — off the grid")
            #expect(right - (CrabRig.ledgeLength - 1) < 0,
                    "at local \(local) the ledge's left end is on the grid — pick a longer ledge")
            #expect(right < previous, "the sheet's frames do not travel: \(right) after \(previous)")
            previous = right
            if index == 0 {
                #expect(right == PixelBuffer.side - 1,
                        "the first frame is not the greatest coverage: right end \(right)")
            }
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
