import Testing
import Foundation
@testable import ClaudePet

/// 🛹 **The trick loop, and the seam it lives or dies on.**
///
/// No rig behaviour changes in this file's round — what is pinned is the EDIT.
/// And one claim matters more than all the others put together: a clip that
/// exists only to repeat has no internal boundary to hide behind, so its wrap is
/// the whole product.
///
/// 🔎 That pin is not theoretical. Both of the infinitely-looping GIFs this repo
/// already ships wrap badly — `1-laserflip` comes round on a one-frame board pop
/// against a crouch, and `3-backsmith` snaps a flaming board and a near-full
/// score back to a cold board in a single frame. Both were built with internal
/// cross-dissolves specifically to avoid that defect at their *middles*, and
/// neither spent the same care on the join that actually plays. Hence
/// `theLoopClosesOnItself`, which compares rendered cells rather than intent.
@Suite(.serialized)
@MainActor
struct TrickLoopTests {

    private func pose(_ t: Double) -> CrabPose { TrickLoop.pose(t) }
    private func frame(_ index: Int) -> CrabPose { TrickLoop.pose(frame: index) }

    // MARK: - The grid

    @Test("Eight seconds, sixteen beats, a hundred and sixty frames")
    func theGridHolds() {
        // 🔎 Against the NUMBERS, not against the constants that produced them.
        // `loopLength` is a sum of three other constants, so asserting it equals
        // its own summands would pass no matter what any of them became.
        let beat = 0.5
        #expect(TrickLoop.loopLength == 8.0, "the loop runs \(TrickLoop.loopLength)s, not 8")
        #expect(TrickLoop.loopLength / beat == 16, "the loop is not sixteen beats")
        #expect(TrickLoop.frameCount == 160, "the loop is \(TrickLoop.frameCount) frames, not 160")

        // 🔎 THE CLIP is on the grid; the tricks inside it are not, and cannot
        // be. The laser flip runs 3.2s — six and two fifths of a beat — so no
        // arrangement puts the seam after it on a beat without opening a gap,
        // and §2 forbids stretching a trick to fit. That is what the tail is
        // for: it is sized to the remainder rather than to taste, exactly as
        // `FeedCuts.oneTail` is. Asserting otherwise would be asserting a thing
        // this repo has already decided is not true.
        let flipBeats = TrickLoop.flipLength / beat
        #expect(abs(flipBeats - 6.4) < 1e-9, "the laser flip is \(flipBeats) beats")
        #expect(abs(TrickLoop.cabLength / beat - 8) < 1e-9, "the half cab is not eight beats")
        #expect(abs(TrickLoop.tail / beat - 1.6) < 1e-9, "the tail is not the remainder")
        // A feed clip that runs long is a feed clip nobody finishes.
        #expect(TrickLoop.loopLength <= 10, "the loop runs \(TrickLoop.loopLength)s")
    }

    // MARK: - The wrap

    /// 🔁 THE WHOLE PRODUCT, and the right way to ask about it.
    ///
    /// An equality pin would be wrong here: frame 159 hands to frame 0, and if
    /// those two were the same pose the clip would carry a duplicate and stutter
    /// once a pass forever. What a loop actually owes is the §3 boundary test —
    /// the join must be no louder than the joins the clip already makes between
    /// its own consecutive frames. So: measure every interior step, then measure
    /// the wrap against the loudest of them.
    @Test("The wrap is quieter than any cut the clip already makes")
    func theWrapIsNoLouderThanTheClip() {
        var buffers: [PixelBuffer] = []
        for index in 0..<TrickLoop.frameCount { buffers.append(CrabRig.render(frame(index))) }

        var steps: [Int] = []
        for index in 1..<buffers.count {
            steps.append(buffers[index].changedCells(from: buffers[index - 1]))
        }
        let wrap = buffers[0].changedCells(from: buffers[buffers.count - 1])
        let loudest = steps.max() ?? 0

        let quiet = wrap <= loudest
        let note = "the wrap moves \(wrap) cells against a loudest interior step of "
            + "\(loudest) — the join is the worst cut in the clip"
        #expect(quiet, "\(note)")

        // …and it is not a duplicate frame dressed up as a seam.
        #expect(wrap > 0, "the last frame is identical to the first — the loop stutters")

        // …nor is the clip loop-clean by being a still. Something has to move.
        #expect(loudest > 0, "nothing happens inside the loop")
    }

    // MARK: - The seams

    /// Every board swap dissolves. A one-frame prop change is a snap like any
    /// other, and this clip makes three of them: into the cab, out of it, and
    /// across the wrap.
    @Test("No board ever changes in a single frame")
    func theSeamsDissolveRatherThanCutting() {
        var previous = frame(0)
        var swaps = 0
        for index in 1..<TrickLoop.frameCount {
            let current = frame(index)
            guard current.prop != previous.prop else { previous = current; continue }
            swaps += 1
            let dissolving = current.ghostPropVisibility > 0 || current.propVisibility < 1
            #expect(dissolving,
                    "frame \(index) swapped \(previous.prop) for \(current.prop) outright")
            previous = current
        }
        // Two swaps inside the clip. The wrap makes no third one, because the
        // stance rides the laser flip's own deck — which is why it was chosen.
        #expect(swaps == 2, "the clip makes \(swaps) board swaps, not 2")
        #expect(frame(TrickLoop.frameCount - 1).prop == frame(0).prop,
                "the wrap swaps a board as well as closing a loop")
    }

    /// 🔎 THE REASON THE TAIL IS AT THE END. `dustBurst` is deliberately absent
    /// from `CrabPose.blend`, so a dissolve laid over the half cab's stomp would
    /// not fade the landing dust — it would delete it mid-puff. Running the tail
    /// afterwards lets the burst finish on its own clock.
    @Test("The stomp's dust runs out on its own rather than being cut mid-puff")
    func theStompKeepsItsDust() {
        // The half cab's own stomp branch, which is the last eighth of it.
        let stompAt = TrickLoop.cabOpensAt + TrickLoop.cabLength * 0.875
        var series: [(t: Double, burst: Double)] = []
        for index in 0..<TrickLoop.frameCount {
            let t = Double(index) / Double(TrickLoop.fps)
            guard t >= stompAt else { continue }
            // `drawDust` fires for any non-nil value below 1 — a 0.0 still draws.
            guard let burst = frame(index).dustBurst, burst < 1 else { continue }
            series.append((t, burst))
        }
        #expect(series.count > 0, "the half cab's landing draws no dust at all")
        if let last = series.last {
            #expect(last.burst > 0.9,
                    "the last dust frame is \(last.burst) — the puff never finished")
        }

        // 🔎 …and it CLIMBS there rather than being teleported there. This pin
        // nearly went blind: a dissolve that replaces the live burst with the
        // trick's own last frame does not TRUNCATE the series, it JUMPS it, and
        // that end sample always reads ~1.0 no matter where the tail opens. So
        // the claim has to be about the step. The burst runs 0 → 1 across ten
        // frames, a tenth each; anything larger is a blend standing in for it.
        for index in 1..<series.count {
            let step = series[index].burst - series[index - 1].burst
            #expect(step <= 0.15,
                    "the dust jumps \(step) at \(series[index].t)s — a blend replaced it")
        }
    }

    // MARK: - The backside

    /// The joke is the payload, so the cheeks have to be at FULL opacity for
    /// every frame that bounces. Below a third of a turn or above two thirds they
    /// are gone entirely, and anywhere but exactly half they are dithered in.
    @Test("He is square-on backwards for every frame that jiggles")
    func theBacksideIsVisibleForTheWholeJiggle() {
        var bouncing = 0
        for index in 0..<TrickLoop.frameCount {
            let pose = frame(index)
            // The quantiser's own boundary, not `!= 0`: `drawBackside` rounds,
            // so a half cell is where a frame starts actually moving — and the
            // zero-crossings sit a hair off nought in floating point anyway.
            guard abs(pose.buttJiggle) >= 0.5 else { continue }
            bouncing += 1
            #expect(pose.torsoTurn == 0.5,
                    "frame \(index) bounces at turn \(pose.torsoTurn) — not square-on")
        }
        // Four cycles of two hertz across two seconds at twenty frames a second
        // is forty frames, of which eight are the rests either side of a state
        // change. Eight moving frames a cycle, four cycles.
        #expect(bouncing == 32, "\(bouncing) frames move the backside, not 32")
    }

    /// At this clip's rate a whole cycle is ten frames and each state change has
    /// a rest frame beside it — so no frame ever moves the row and the width at
    /// once. One whole-pixel step at a time is the grid's own quantum, and the
    /// only motion the no-snap rule exempts. (The committed GIF pins the same
    /// claim at twelve frames a second; this is its twenty-frame twin.)
    @Test("At twenty frames the cycle reads as three states, never two at once")
    func theCycleReadsAtTwentyFrames() {
        let opensAt = TrickLoop.cabOpensAt + CrabAnimator.Flourish.halfCab.duration * 0.25
        var states: [String] = []
        for step in 0..<10 {
            let v = pose(opensAt + Double(step) / Double(TrickLoop.fps)).buttJiggle
            states.append(v.rounded() == -1 ? "squash" : v.rounded() == 1 ? "aloft" : "rest")
        }
        #expect(states == ["rest", "squash", "squash", "squash", "squash",
                           "rest", "aloft", "aloft", "aloft", "aloft"],
                "the ten-frame cycle reads \(states)")
    }

    // MARK: - The frame

    @Test("Every shape is whole-cell and nothing crops")
    func everyFrameIsWholeCell() {
        #expect(TrickLoop.formats.count == 3)
        for format in TrickLoop.formats {
            #expect(format.side.truncatingRemainder(dividingBy: 32) == 0,
                    "\(format.name)'s sprite is \(format.side)pt — not a whole cell")
            #expect(format.cell == format.cell.rounded(),
                    "\(format.name)'s cell is \(format.cell)pt")
            #expect(format.offsetY.truncatingRemainder(dividingBy: format.cell) == 0,
                    "\(format.name) nudges \(format.offsetY)pt — not a whole cell")
            #expect(format.side <= min(format.canvas.width, format.canvas.height),
                    "\(format.name)'s sprite does not fit its canvas")

            let top = (format.canvas.height - format.side) / 2 + format.offsetY
            #expect(top >= 0 && top + format.side <= format.canvas.height,
                    "\(format.name) crops vertically")
            let left = (format.canvas.width - format.side) / 2
            #expect(left >= 0 && left + format.side <= format.canvas.width,
                    "\(format.name) crops horizontally")
        }

        // The three shapes that were asked for, by their actual ratios.
        let ratios = TrickLoop.formats.map { $0.canvas.width / $0.canvas.height }
        #expect(abs(ratios[0] - 1.0) < 1e-9, "the square is \(ratios[0]), not 1:1")
        #expect(abs(ratios[1] - 0.8) < 1e-9, "the feed shape is \(ratios[1]), not 4:5")
        #expect(abs(ratios[2] - 0.5625) < 1e-9, "the tall shape is \(ratios[2]), not 9:16")
    }

    /// 🔎 Read off `colourways`, not off two names typed in here. The first
    /// version of this test rendered `.none` against `.skater` directly, so
    /// changing what the renderer actually ships changed nothing about what the
    /// test asked — it passed happily with both takes set to bare.
    @Test("Both colourways render, and they are not the same clip twice")
    func theColourwaysDiffer() {
        let costumes = TrickLoop.colourways.map(\.costume)
        #expect(costumes.count == 2, "the renderer ships \(costumes.count) colourways, not 2")
        guard costumes.count == 2 else { return }
        #expect(costumes[0] != costumes[1],
                "both takes wear \(costumes[0]) — the second is not a second look")
        let first = CrabRig.render(frame(0), costume: costumes[0])
        let second = CrabRig.render(frame(0), costume: costumes[1])
        let differ = !first.same(as: second)
        #expect(differ, "the two takes render identically")
    }

    // MARK: - Determinism

    /// 🔎 Six renders, not two. The glyph cache is process-global and its first
    /// few draws disagree with every draw after, so a pair can agree while the
    /// clip still comes out different.
    @Test("A frame renders byte-identically on every repeat")
    func theLoopRendersByteIdentically() {
        let format = TrickLoop.formats[0]
        let view = TrickLoop.scene(frame(TrickLoop.frameCount / 3), costume: .skater,
                                   ground: MarketingPalette.gold, format: format)
        func bytes() -> Data? {
            (SpriteImage.cgImage(of: view, scale: 1, isOpaque: true)?
                .dataProvider?.data) as Data?
        }
        let first = bytes()
        #expect(first != nil, "the frame did not render at all")
        for repetition in 1..<6 {
            #expect(bytes() == first, "render \(repetition + 1) differs from the first")
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

    /// How many cells differ — the boundary test's unit, so a seam can be
    /// compared against the cuts the clip already makes rather than judged.
    func changedCells(from other: PixelBuffer) -> Int {
        var changed = 0
        for y in 0..<Self.side {
            for x in 0..<Self.side where self[x, y] != other[x, y] { changed += 1 }
        }
        return changed
    }
}
