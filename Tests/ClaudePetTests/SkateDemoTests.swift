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
            // 🔎 Tied to the CONTENT, not to a number. The floor used to be ten
            // seconds, which was right while a reel was a whole scoring combo;
            // these are one trick each, and a reel shorter than the trick it
            // shows is the actual defect. Eight seconds against a six-and-a-half
            // second back smith is the trick entire plus a beat either side.
            #expect(reel.seconds >= CrabAnimator.Flourish.backSmith.duration,
                    "\(reel.name) is \(reel.seconds)s — shorter than the trick it shows")
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

    /// 🔎 THE A/B IS ONLY AN A/B IF IT IS THE SAME TAKE.
    ///
    /// The operator asked for the clip with the rainbow trail and without it.
    /// The whole value of that pair is that one thing differs — so both come
    /// from the same window of the same scoring ride, and the plain version is
    /// that ride with the score's three decorations zeroed and nothing else
    /// touched. This pins it: at every frame of both reels, every channel the
    /// body reads is identical, and the only differences are the ones the
    /// operator is judging.
    @Test("The two versions are the same take, differing only in the score")
    func theVersionsAreOneTake() {
        var differed = 0
        for index in 0..<Int(SkateDemo.plainReel.seconds * Double(SkateDemo.gifFps)) {
            let t = Double(index) / Double(SkateDemo.gifFps)
            let (plain, plainTint) = SkateDemo.plainPose(reel: t)
            let (trail, trailTint) = SkateDemo.trailPose(reel: t)
            // Everything he DOES is the same take.
            #expect(plain.bob == trail.bob && plain.squash == trail.squash
                    && plain.lean == trail.lean && plain.tilt == trail.tilt
                    && plain.prop == trail.prop && plain.legKick == trail.legKick
                    && plain.ledge == trail.ledge && plain.bushes == trail.bushes
                    && plain.grindSparks == trail.grindSparks,
                    "the two versions are different takes at reel \(t)")
            // …and the score's three decorations are the only difference.
            #expect(plain.combo == 0 && plain.boardFire == 0,
                    "the plain version is scoring at reel \(t)")
            #expect(plainTint == nil, "the plain version is tinted at reel \(t)")
            if trail.combo > 0 || trailTint != nil { differed += 1 }
        }
        #expect(differed > 100, "the trail version only differs on \(differed) frames")
        // Both reels play the identical shot list, so the framing cannot drift.
        #expect(SkateDemo.plainReel.shots.count == SkateDemo.trailReel.shots.count)
        for (a, b) in zip(SkateDemo.plainReel.shots, SkateDemo.trailReel.shots) {
            #expect(a.start == b.start && a.seconds == b.seconds && a.stop == b.stop
                    && a.cellsRight == b.cellsRight && a.groundName == b.groundName,
                    "the shot lists diverge at \(a.start)s")
        }
    }

    /// 🔎 THE PARALLAX, MEASURED WHERE IT LIVES NOW.
    ///
    /// This used to compare the ledge's visible right end against the bushes'
    /// visible right end. That worked while the ledge's end spent the grind on
    /// screen; once the block became ninety-three cells the end is off-grid for
    /// most of the trick, both measurements pin to column 31, and the test
    /// degenerates into `0 == 0 * 2` — green, and measuring nothing.
    ///
    /// So it measures the two SCROLLS against each other, which is the claim
    /// the shot was cut to show: the hedge is the far layer and moves at half
    /// the near one's rate. And it measures the rendered hedge as well, because
    /// a scroll function that is right while the drawing is empty is a fact
    /// about arithmetic rather than about the picture.
    @Test("The hedge scrolls at exactly half the ledge's rate")
    func theParallaxIsTwoToOne() {
        func world(_ local: Double) -> (ledge: Int, hedge: Int) {
            let pose = CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance)
            let travelled = Int((Double(CrabRig.ledgeTravel) * pose.ledge).rounded())
            return (travelled, CrabRig.bushScroll(travel: pose.ledge))
        }
        let opening = world(1.5), closing = world(5.0)
        let ledgeCells = closing.ledge - opening.ledge
        let hedgeCells = closing.hedge - opening.hedge
        #expect(ledgeCells == 80, "the ledge moved \(ledgeCells) cells, not 80")
        // Within a cell, not exactly: the hedge is the ledge's own whole-cell
        // travel halved, so an odd travel truncates. A cell is the grid's
        // quantum and the tightest this can honestly be pinned.
        #expect(abs(hedgeCells * 2 - ledgeCells) <= 1,
                "the parallax is \(Double(ledgeCells) / Double(hedgeCells)):1")
        // …and the hedge is really there and really moving on screen, over the
        // whole window, not just at its ends.
        func greenColumns(_ local: Double) -> Set<Int> {
            let pose = CrabAnimator.flourishPose(.backSmith, at: local, base: SkateDemo.skateStance)
            let buffer = CrabRig.render(pose, costume: .skater)
            var columns: Set<Int> = []
            for y in 21...23 {
                for x in 0..<PixelBuffer.side where buffer[x, y] == .green { columns.insert(x) }
            }
            return columns
        }
        var moves = 0
        var previous = greenColumns(1.5)
        for step in 1...14 {
            let now = greenColumns(1.5 + Double(step) * 0.25)
            #expect(!now.isEmpty, "the hedge is empty at local \(1.5 + Double(step) * 0.25)")
            if now != previous { moves += 1 }
            previous = now
        }
        #expect(moves >= 12, "the hedge only changed on \(moves) of 14 samples")
        // …and the reel really plays that window — it spans the roll-in shot
        // and the grind shot, which is why this is pinned against the reel
        // rather than against any one shot.
        let firstLocal = SkateDemo.ride(reel: 0) - SkateDemo.rideOpensAt
        let lastLocal = SkateDemo.ride(reel: SkateDemo.plainReel.seconds) - SkateDemo.rideOpensAt
        #expect(firstLocal <= 1.5 && lastLocal >= 5.0,
                "the reel covers local \(firstLocal) → \(lastLocal), which misses the parallax window")
    }

    /// 🔎 THE GRIND IS TRAVEL. The operator watched the demo and said he
    /// pauses at the end, that grinds do not stop, that it is physically
    /// impossible — and the numbers agreed with him: the roll-in ran at 23
    /// cells a second and the grind at **2.4**, because he locked on with only
    /// eight cells of ledge ahead of him and the rig bought two and a half
    /// seconds out of them by nearly stopping the world.
    ///
    /// One speed now, from the first frame to the last. This pins the whole
    /// shape of that: the speed, the runway he lands with, and the beat the
    /// runway buys — the block's far end arriving at his tail truck on the
    /// exact frame he pops off it.
    @Test("The ground runs at one speed, and he pops off the end of the ledge")
    func theGrindIsTravel() {
        let duration = CrabAnimator.Flourish.backSmith.duration
        func right(_ progress: Double) -> Int {
            CrabRig.ledgeRightEnd(travel: CrabAnimator.flourishPose(.backSmith, at: progress * duration,
                                                                   base: SkateDemo.skateStance).ledge)
        }
        // The three phases, at one speed. The grind used to be a tenth of this.
        for (name, from, to) in [("roll-in", 0.0, 0.375), ("grind", 0.375, 0.755),
                                 ("exit", 0.755, 0.93)] {
            let speed = Double(right(from) - right(to)) / ((to - from) * duration)
            #expect(abs(speed - 23.1) < 1.0, "the \(name) runs at \(speed) cells a second")
        }
        // …and no frame anywhere travels a different distance from its
        // neighbour by more than the grid's own rounding.
        var previous = right(0)
        for step in 1...130 {
            let now = right(Double(step) / 130 * 0.83)
            let moved = previous - now
            #expect(moved >= 0, "the ledge went backwards at step \(step)")
            #expect(moved <= 2, "the ledge leapt \(moved) cells at step \(step)")
            previous = now
        }
        #expect(right(0.375) == 68, "he lands beside column \(right(0.375)), not 68")
        #expect(right(0.375) - CrabRig.ledgeTailTruck == 57,
                "he lands with \(right(0.375) - CrabRig.ledgeTailTruck) cells of runway, not 57")
        // 🔎 THE BEAT THE RUNWAY BUYS: the far end reaches his tail truck on
        // the frame he pops. He grinds to the end of the ledge and leaves it,
        // rather than popping off an arbitrary moment in the middle.
        #expect(right(0.755) == CrabRig.ledgeTailTruck,
                "the ledge's end is at \(right(0.755)) when he pops, not his truck")
        #expect(right(0.93) < 0, "the ledge is still on the grid when he stomps")
    }

    /// 🔎 THE GLITCH THE OPERATOR SAW    /// 🔎 THE GLITCH THE OPERATOR SAW: *"he sometimes rides the ledge with no
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

    /// The clock maps straight onto the ride with one offset and no seam —
    /// there is nothing skipped any more, because the window IS the trick.
    @Test("The reel's clock is monotone and always inside the ride")
    func theClockMapHolds() {
        var previous = -1.0
        var t = 0.0
        while t <= SkateDemo.plainReel.seconds + 1e-9 {
            let ride = SkateDemo.ride(reel: t)
            #expect(ride > previous, "the ride went backwards at reel \(t)")
            previous = ride
            if t >= SkateDemo.head {
                #expect(CrabAnimator.comboRide(local: ride, wardrobe: .init(current: .skater)) != nil,
                        "the ride is over at reel \(t) (ride \(ride))")
            }
            t += 1.0 / Double(SkateDemo.videoFps)
        }
        // The window is the back smith entire, plus a beat of the settle.
        #expect(abs(SkateDemo.ride(reel: SkateDemo.head) - SkateDemo.rideOpensAt) < 1e-9)
        #expect(abs(SkateDemo.ride(reel: SkateDemo.plainReel.seconds) - SkateDemo.rideClosesAt) < 1e-9,
                "the reel closes at ride \(SkateDemo.ride(reel: SkateDemo.plainReel.seconds))")
        // 🔎 …and it closes INSIDE the score's plateau, not in its fade. The
        // ride's own ease-out begins at 19.6; ending past it would close the
        // trail version on a fire going out, which is the opposite of the job.
        let skater = CrabAnimator.MotionWardrobe(current: .skater)
        let last = CrabAnimator.comboRide(local: SkateDemo.rideClosesAt, wardrobe: skater)
        #expect((last?.boardFire ?? 0) > 0.999, "the reel ends on a dying fire")
        let late = CrabAnimator.comboRide(local: 19.8, wardrobe: skater)
        #expect((late?.boardFire ?? 1) < 0.3, "the fade moved — this guard can be retired")
    }

    /// Real speed everywhere: a shot's ride window is exactly as long as its
    /// reel window. Nothing is slowed, nothing is sped up.
    @Test("Compression is exactly one in every shot")
    func nothingIsStretched() {
        for shot in SkateDemo.shots {
            let inRide = SkateDemo.ride(reel: shot.start)
            let outRide = SkateDemo.ride(reel: shot.end - 1e-9)
            #expect(abs((outRide - inRide) - shot.seconds) < 1e-6,
                    "shot at \(shot.start) compresses \(outRide - inRide) into \(shot.seconds)")
        }
    }

    /// 🌈 The trail version really does carry the trail, all the way — the
    /// window opens at four rungs of score and never drops below them. (The
    /// old reel opened scoreless and built; this one is a window of the ride's
    /// finale, so there is nothing to build.)
    @Test("The trail version scores throughout, and the plain one never does")
    func theColourHasSomewhereToGo() {
        for t in stride(from: SkateDemo.head + 0.05, to: SkateDemo.trailReel.seconds, by: 0.05) {
            let (trail, tint) = SkateDemo.trailPose(reel: t)
            #expect(trail.combo > 0.5, "the trail version is at \(trail.combo) at reel \(t)")
            #expect(tint != nil, "no colour at reel \(t)")
            let (plain, plainTint) = SkateDemo.plainPose(reel: t)
            #expect(plain.combo == 0 && plainTint == nil, "the plain version scored at reel \(t)")
        }
        // …and it closes on a full score with the board alight.
        let (closing, _) = SkateDemo.trailPose(reel: SkateDemo.trailReel.seconds - 0.05)
        #expect(closing.combo > 0.999, "the trail version closes at \(closing.combo)")
        #expect(closing.boardFire > 0.999, "the board is not alight at the close")
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
                for shot in SkateDemo.shots where shot.stop == stop {
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
