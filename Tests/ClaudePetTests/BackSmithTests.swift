import Testing
import Foundation
@testable import ClaudePet

/// **The back smith, third cut.** A ledge comes in from HIS RIGHT and slides
/// right to left — FORTY-FOUR long, five tall, three little bushes drifting
/// behind it at half its speed — he pops onto it, locks the back truck on the
/// top with the nose dipped two rows, steezes it out through a two-and-a-half
/// second grind with sparks off the truck, kickflips out over a whole unhurried
/// second, and stomps. Every channel eased across every phase seam; the ledge
/// and the bushes are ground and never rise with him.
///
/// The phase fractions are named once here and used throughout, because this
/// cut moved every one of them: crouch to `pop`, air to `lock`, grind to
/// `exit`, flip to `stomp`.
@MainActor
struct BackSmithTests {

    private let duration = CrabAnimator.Flourish.backSmith.duration
    /// The phase seams, as fractions of the trick.
    private let pop = 0.10, lock = 0.375, exit = 0.755, stomp = 0.93
    private func frame(_ p: Double) -> CrabPose {
        CrabAnimator.flourishPose(.backSmith, at: p * duration)
    }
    /// The ledge's own cells: a steel top at 24, slate below. (The landing
    /// dust is steel too, two rows above the feet; the bushes are green.)
    private func ledgeCells(_ buffer: PixelBuffer) -> [(x: Int, y: Int)] {
        var cells: [(Int, Int)] = []
        // A steel cell on row 24 is the ledge's top only if slate stands
        // under it — the landing dust is steel too and lands on that row.
        for y in 24...28 {
            for x in 0..<PixelBuffer.side where (y == 24 && buffer[x, y] == .steel && buffer[x, 25] == .slate) || (y > 24 && buffer[x, y] == .slate) {
                cells.append((x, y))
            }
        }
        return cells
    }
    private func bushCells(_ buffer: PixelBuffer) -> [(x: Int, y: Int)] {
        var cells: [(Int, Int)] = []
        for y in 21...23 { for x in 0..<PixelBuffer.side where buffer[x, y] == .green { cells.append((x, y)) } }
        return cells
    }

    @Test("The ledge and the bushes are off the grid at both ends of the trick")
    func theLedgeBookendsAreClean() {
        // 🔎 The opening frame, and only it. This used to sample p = 0.005 as
        // well, which was fair while the block crept in on a smoothstep — but
        // at an honest 23 cells a second its leading column arrives 23
        // milliseconds in, and a sample at 32ms is past it. That is the ledge
        // being correct, not the stage being dirty.
        let opening = frame(0)
        #expect(opening.ledge < 0.01, "ledge \(opening.ledge) at p=0")
        let stage = CrabRig.render(opening)
        #expect(ledgeCells(stage).isEmpty, "ledge cells on the opening frame")
        #expect(bushCells(stage).isEmpty, "bushes on the opening frame")
        // …and when it does arrive it arrives as ONE column at the right edge,
        // which is the same claim in the form the new speed can keep.
        var firstCells: [(x: Int, y: Int)] = []
        for step in 1...60 {
            firstCells = ledgeCells(CrabRig.render(frame(Double(step) / 60 * 0.05)))
            if !firstCells.isEmpty { break }
        }
        #expect(!firstCells.isEmpty, "the ledge never arrives")
        #expect(Set(firstCells.map(\.x)) == [PixelBuffer.side - 1],
                "the ledge arrives at columns \(Set(firstCells.map(\.x))), not the right edge")
        // …and gone off the LEFT before the stomp lands, so he never comes
        // down on half a ledge; the bushes dissolve out just after.
        for p in [0.91, 0.95, 0.999] {
            #expect(ledgeCells(CrabRig.render(frame(p))).isEmpty, "ledge still on the grid at p=\(p)")
        }
        #expect(ledgeCells(CrabRig.render(frame(stomp))).isEmpty,
                "the ledge is still under him when the stomp begins")
        #expect(bushCells(CrabRig.render(frame(0.999))).isEmpty, "bushes still on the grid at the end")
        let zero = frame(0)
        #expect(zero.bob >= 0 && zero.combo == 0 && zero.legKick == 0 && zero.boardFire == 0)
    }

    @Test("Nothing snaps: bob moves a row a frame at most, outside the two stomps")
    func nothingSnaps() {
        var previous = frame(0)
        var t = 0.0
        var jumps: [(Double, Int)] = []
        while t < duration - 1.0 / 30 - 1e-9 {
            t += 1.0 / 30
            let pose = frame(min(1, t / duration))
            let step = abs(pose.bob - previous.bob)
            let p = t / duration
            // The take-off (crouch → pop) and the landing squash are the
            // exemption; everywhere else a row a frame.
            let impact = (p > pop && p < pop + 0.04) || (p > stomp - 0.03 && p < stomp + 0.03)
            if step > 1 && !impact { jumps.append((p, step)) }
            // The travel never retreats (right to left) and its fastest leg is
            // under two cells a frame.
            #expect(pose.ledge >= previous.ledge - 1e-9, "the ledge retreated at p=\(p)")
            #expect((pose.ledge - previous.ledge) * Double(CrabRig.ledgeTravel) <= 2 + 1e-6, "the ledge leapt at p=\(p)")
            previous = pose
        }
        #expect(jumps.isEmpty, "bob jumped: \(jumps)")
        // The pop LANDS on the ledge — the grind's height — and the kickflip
        // out starts from it.
        #expect(frame(lock).bob == -4, "the pop ended at \(frame(lock).bob), not on the ledge")
        #expect(frame(lock + 0.005).bob == -4)
        #expect(frame(exit).bob == -4, "the kickflip out did not start from the ledge")
    }

    @Test("Mid-grind the nose is down, the tail truck is on the top, the leg is out, sparks fly")
    func theGrind() {
        let pose = frame((lock + exit) / 2)
        #expect(pose.prop == .skateboardSmith)
        #expect(pose.bob == -4)
        #expect(pose.legKick > 0.99, "no steeze mid-grind")
        #expect(pose.grindSparks > 0.99, "no sparks mid-grind")
        #expect(pose.torsoTurn == 0, "only the bigspin may turn him")
        #expect(pose.eyes == .determined)
        let buffer = CrabRig.render(pose)
        func deckRow(_ x: Int) -> Int? { (0..<PixelBuffer.side).first { buffer[x, $0] == .deck } }
        #expect(deckRow(9) == 21, "tail row \(String(describing: deckRow(9)))")
        #expect(deckRow(22) == 23, "nose row \(String(describing: deckRow(22))) — not dipped two rows")
        // The tail wheel's bottom row is the row above the ledge's steel top.
        // Measured with the sparks off: they are flame ink drawn over the truck
        // and land ON the wheel's lower cell on some phases, so reading the
        // live frame here measures the spark's dice, not the geometry.
        var still = pose
        still.grindSparks = 0
        let dry = CrabRig.render(still)
        let wheelBottom = (0..<PixelBuffer.side).last { dry[11, $0] == .yellow }
        let ledgeTop = (0..<PixelBuffer.side).first { dry[5, $0] == .steel }
        #expect(wheelBottom == 23 && ledgeTop == 24,
                "wheel bottom \(String(describing: wheelBottom)), ledge top \(String(describing: ledgeTop))")
        // The ledge's right end has slid on past his landing spot (19) toward
        // 🔎 Mid-grind the ledge fills the row, and that is the point. At
        // forty-four cells its right end sat beside him at 19 and this pinned
        // the position; at ninety-three the end is still fifty cells off to the
        // right, because that is the runway a real two-and-a-half-second grind
        // needs. What is pinned instead is what he is actually standing on:
        // ledge under his truck, and no gap anywhere across the row.
        let cells = ledgeCells(buffer)
        #expect(cells.contains { $0.x == CrabRig.ledgeTailTruck && $0.y == 24 },
                "there is no ledge under his tail truck mid-grind")
        // Row 26, not the steel top: the top row legitimately has things
        // standing ON it — the nose wheel, and the spark cone the operator
        // asked to spray back along the edge — so a no-gaps pin there would be
        // pinning that nothing ever touches the ledge.
        let body = Set(cells.filter { $0.y == 26 }.map(\.x))
        #expect(body == Set(0..<PixelBuffer.side),
                "the ledge has gaps mid-grind: \(Set(0..<PixelBuffer.side).subtracting(body).sorted())")
        // Sparks: flame inks near the tail wheel, over several frames.
        var sparks = 0
        for t in stride(from: 0.40, through: 0.70, by: 0.01) {
            let b = CrabRig.render(frame(t))
            for y in 19...24 { for x in 8...13 where b[x, y] == .flameCore || b[x, y] == .flame { sparks += 1 } }
        }
        #expect(sparks > 20, "only \(sparks) spark cells across the grind")
        #expect(frame(lock).legKick == 0 && frame(exit).legKick == 0)
        #expect(frame(lock).grindSparks == 0 && frame(exit).grindSparks == 0)
    }

    @Test("The ledge comes from his right, travels left under him, and the bushes lag it")
    func theLedgeTravelsRightToLeft() {
        // He lands ON it with runway ahead — the far end is off to the right,
        // out of frame — and by the pop that end has come all the way to his
        // truck. `SkateDemoTests.theGrindIsTravel` owns the cell positions;
        // this owns what they look like on the grid.
        #expect(!ledgeCells(CrabRig.render(frame(lock))).isEmpty, "no ledge under him at the lock")
        #expect(CrabRig.ledgeRightEnd(travel: frame(lock).ledge) > PixelBuffer.side,
                "the ledge's far end is already in frame at the lock — no runway")
        let late = ledgeCells(CrabRig.render(frame(exit - 0.005))).map(\.x).max() ?? 99
        #expect(late <= 14, "the ledge did not slide under him: right end \(late) at the grind's end")
        // Entering: its LEFT end appears at the right edge first.
        var t = 0.0, entered = false
        while t < duration * lock {
            let cells = ledgeCells(CrabRig.render(frame(t / duration)))
            if let leftmost = cells.map(\.x).min() {
                if !entered { #expect(leftmost >= 25, "the ledge appeared at column \(leftmost), not from the right"); entered = true }
            }
            t += 1.0 / 30
        }
        #expect(entered)
        // 🔎 The parallax, measured on the SCROLLS rather than on visible
        // edges. Comparing `max(x)` of visible cells worked while both layers'
        // right ends were on screen; now the ledge's is off-grid for most of
        // the trick, so that measurement pins both to column 31 and quietly
        // stops measuring anything at all.
        let a = frame(0.42), b = frame(0.72)
        let ledgeMoved = CrabRig.ledgeTravelled(travel: b.ledge) - CrabRig.ledgeTravelled(travel: a.ledge)
        let bushMoved = CrabRig.bushScroll(travel: b.ledge) - CrabRig.bushScroll(travel: a.ledge)
        #expect(ledgeMoved > 40, "the ledge only moved \(ledgeMoved) cells through the grind")
        #expect(bushMoved > 0 && bushMoved < ledgeMoved,
                "bushes moved \(bushMoved), ledge \(ledgeMoved) — no parallax")
        #expect(abs(bushMoved * 2 - ledgeMoved) <= 1,
                "the far layer is not at half speed: \(bushMoved) against \(ledgeMoved)")
        // …and the hedge is on the grid the whole way, which three fixed domes
        // could not manage once the ground started travelling this far.
        for p in stride(from: 0.40, through: 0.74, by: 0.02) {
            #expect(!bushCells(CrabRig.render(frame(p))).isEmpty, "no hedge at p=\(p)")
        }
    }

    @Test("He kickflips out and stomps")
    func theKickflipOut() {
        let air = frame((exit + stomp) / 2)
        #expect(air.prop == .skateboard, "the exit board is \(air.prop)")
        #expect(air.propPhase > 0.3 && air.propPhase < 0.7,
                "the board is not mid-turn halfway out: \(air.propPhase)")
        #expect(air.bob < -4, "he is not in the air on the way out: bob \(air.bob)")
        let landing = frame(0.965)
        #expect(landing.prop == .skateboard && landing.propPhase == 0
                && landing.squash == 1 && landing.bob == 1)
        #expect(landing.dustBurst != nil, "no boom")
        // 🔎 The exit takes a whole unhurried second — measured on the board's
        // own rotation, not on the width of the phase that holds it. At 0.648s
        // the underside slab strobed against the ledge and read as a crab
        // riding a black box with no board: the glitch the operator reported.
        var began: Double?, finished: Double?
        for step in 0...Int((stomp - exit) * duration * 30) {
            let local = exit * duration + Double(step) / 30
            let turned = CrabAnimator.flourishPose(.backSmith, at: local).propPhase
            if began == nil, turned >= 0.02 { began = local }
            if finished == nil, turned >= 0.98 { finished = local }
        }
        let turn = (finished ?? 0) - (began ?? 0)
        #expect(turn >= 1.0, "the board turns in \(turn)s — fast enough to strobe")
    }

    @Test("The ledge and the bushes never rise with him")
    func theLedgeIsGround() {
        // 🔎 THIS TEST USED TO BE A TAUTOLOGY, and it is worth saying why.
        //
        // It rendered at a raised bob and asserted that `ledgeCells` all sat in
        // rows 24…28 and `bushCells` in 21…23 — but those collectors only SCAN
        // those rows. The assertions restated the collectors' own definitions,
        // so they were true no matter what the rig did, and a ground layer that
        // started riding the bob would have sailed straight through them.
        //
        // The real claim is a comparison, not a range: render the same instant
        // at two different heights and the ground has to come out IDENTICAL.
        for p in stride(from: 0.2, through: exit + 0.09, by: 0.05) {
            var grounded = frame(p)
            guard !ledgeCells(CrabRig.render(grounded)).isEmpty else { continue }
            grounded.bob = 0
            var lifted = grounded
            lifted.bob = -8                               // a jump the ground must ignore
            let low = CrabRig.render(grounded), high = CrabRig.render(lifted)
            // Every row the ground owns — the hedge's, the ledge's and the
            // rush's — must be the same in both.
            for y in [21, 22, 23, 24, 25, 26, 27, 28] + CrabRig.rushRows {
                for x in 0..<PixelBuffer.side {
                    // Skip what HE puts there: his legs, his board and his
                    // sparks all legitimately move with the bob.
                    let his: Set<PixelBuffer.Ink> = [.body, .bodyShade, .deck, .yellow,
                                                     .flame, .flameCore, .screenDark,
                                                     .costumeA, .costumeB, .costumeC, .paper]
                    guard !his.contains(low[x, y]), !his.contains(high[x, y]) else { continue }
                    #expect(low[x, y] == high[x, y],
                            "the ground moved with his bob at (\(x),\(y)) on p=\(p): \(low[x, y]) against \(high[x, y])")
                }
            }
        }
    }

    @Test("The smith board paints inside the grid at every phase, and starts as the resting deck")
    func theBoardIsWellBehaved() {
        for step in 0..<20 {
            var pose = CrabPose()
            pose.prop = .skateboardSmith
            pose.propPhase = Double(step) * 0.31
            let buffer = CrabRig.render(pose)
            var deck = 0
            for y in 0..<PixelBuffer.side { for x in 0..<PixelBuffer.side where buffer[x, y] == .deck { deck += 1 } }
            #expect(deck == 17, "phase \(pose.propPhase): \(deck) deck cells")
        }
        let buffer = CrabRig.render(frame(0.55))
        for y in 0..<PixelBuffer.side {
            var run = 0
            for x in 0..<PixelBuffer.side {
                run = buffer[x, y] == .yellow ? run + 1 : 0
                #expect(run <= 3, "a yellow run of \(run) on row \(y)")
            }
        }
    }

    /// 🔎 THE OPERATOR'S NOTE, AS A LAW: *"he like pauses at the end, grinds
    /// don't stop, that physically is impossible in real life — have it as one
    /// continuous movement."*
    ///
    /// He was describing a pile-up, not one channel. At the pop frame the
    /// steeze, the nose pitch, the sparks and both bracing arms all reached
    /// nought together, AND the ledge's velocity fell off a cliff: the drift
    /// was linear and saturated at exactly that progress, and the exit was a
    /// smoothstep, whose slope starts at zero. Nothing moved and nothing
    /// emitted on the frame he left the ledge.
    ///
    /// Stated as the defect: **no frame between the lock and the stomp may be
    /// identical to the one before it.** That is the strongest form of "one
    /// continuous movement" the grid can express, and it catches a stall
    /// arriving by any route — a channel that fades early, a ledge that
    /// saturates, a hedge that runs out of domes.
    /// 🔎 Measured AT THE RATES ANYTHING RENDERS HIM AT — twelve for the
    /// committed GIF, twenty for the reels and the live app, thirty for the
    /// MP4 — and not at some finer sampling of my own choosing. A 32×32 grid
    /// moving at twenty-three cells a second has fewer than fifty distinct
    /// frames in a second; asking it for fifty-five and calling the repeats a
    /// stall would be inventing a defect the eye can never see. Fourteen
    /// frames repeat at 55fps. None repeats at 30.
    @Test("Nothing ever stops between the lock and the stomp")
    func theWorldNeverStops() {
        for fps in [12.0, 20.0, 30.0] {
            var previous = CrabRig.render(CrabAnimator.flourishPose(.backSmith, at: lock * duration))
            var still: [String] = []
            var index = 1
            while lock * duration + Double(index) / fps < stomp * duration {
                let at = lock * duration + Double(index) / fps
                let now = CrabRig.render(CrabAnimator.flourishPose(.backSmith, at: at))
                if now.same(as: previous) { still.append(String(format: "%.2fs", at)) }
                previous = now
                index += 1
            }
            #expect(still.isEmpty,
                    "at \(Int(fps))fps the world stopped at \(still.joined(separator: ", "))")
        }
    }

    /// 🔎 THE OTHER HALF OF THE DEAD BEAT — the one the world-never-stops law
    /// above cannot see.
    ///
    /// That law is carried by the ledge, the hedge and the rush; they move
    /// every frame now, so the picture is never still even if every channel ON
    /// him has quietly gone limp. And they had: the steeze reached nought a
    /// tenth of a second before the pop, the nose spent a third of a second
    /// un-dipping before he left, and the sparks faded with it. Putting those
    /// envelopes back does not fail the law — measured, not assumed — so the
    /// claim needs its own pin.
    ///
    /// The grind is ALIVE until he leaves it: a beat before the pop he is still
    /// fully locked, fully steezed and throwing sparks; and the sparks are
    /// still at full on the last frame of the grind, because steel on stone
    /// does not fade out — it stops.
    @Test("The grind is alive right up to the pop")
    func theGrindDoesNotGoLimpBeforeThePop() {
        let beat = frame(0.72)
        #expect(beat.propPhase > 0.95, "the nose is already coming up: \(beat.propPhase)")
        #expect(beat.legKick > 0.95, "the steeze is already tucked: \(beat.legKick)")
        #expect(beat.grindSparks > 0.95, "the sparks are already dying: \(beat.grindSparks)")
        // The last moment of the grind: sparks at full, then gone on the frame
        // he is airborne. `grindSparks` is documented glint-class, where a
        // one-frame change is allowed — and this is the frame it is for.
        #expect(frame(0.75).grindSparks > 0.95,
                "the sparks fade out instead of stopping: \(frame(0.75).grindSparks)")
        #expect(frame(exit).grindSparks == 0, "the sparks outlive the ledge")
    }

    /// 💨 The floor rushing past under the ledge, and the hedge behind it.
    ///
    /// A ninety-three-cell slab moving at twenty-three cells a second looks
    /// exactly like a ninety-three-cell slab standing still — it has no
    /// features to track. These two layers are the only things on screen that
    /// can show the speed, which is why the operator asked for both.
    @Test("The ground shows its own speed")
    func theGroundShowsItsSpeed() {
        func rushCells(_ p: Double) -> Set<Int> {
            let buffer = CrabRig.render(frame(p))
            var columns: Set<Int> = []
            for y in CrabRig.rushRows {
                for x in 0..<PixelBuffer.side where buffer[x, y] == .shadow { columns.insert(x) }
            }
            return columns
        }
        var moved = 0
        var previous = rushCells(lock)
        #expect(!previous.isEmpty, "there is no ground rush at the lock")
        for step in 1...30 {
            let now = rushCells(lock + (exit - lock) * Double(step) / 30)
            #expect(!now.isEmpty, "the rush went out mid-grind")
            if now != previous { moved += 1 }
            previous = now
        }
        #expect(moved >= 27, "the rush only moved on \(moved) of 30 frames")
        // …and it stays off the ledge's own rows, or the ledge collectors
        // would count it and every bookend pin would quietly change meaning.
        #expect(CrabRig.rushRows.allSatisfy { $0 > 28 },
                "the rush is drawing on the ledge's rows: \(CrabRig.rushRows)")
    }

    /// ✨ The cone. The sparks used to sit in a knot directly under the truck,
    /// which reads as a glow; the operator asked for them coming off the side.
    @Test("The sparks spray back and down off the truck")
    func theSparksSprayBackwards() {
        var seen: Set<Int> = []
        var lowest = 0
        for step in 0...60 {
            let buffer = CrabRig.render(frame(lock + (exit - lock) * Double(step) / 60))
            for y in 18...26 {
                for x in 0..<PixelBuffer.side
                where buffer[x, y] == .flame || buffer[x, y] == .flameCore {
                    seen.insert(x); lowest = max(lowest, y)
                }
            }
        }
        // He travels RIGHT, so back is −x: the cone must reach well behind the
        // tail truck, not just sit on it.
        let furthestBack = seen.min() ?? 99
        #expect(furthestBack <= CrabRig.ledgeTailTruck - 4,
                "the cone only reaches column \(furthestBack); the truck is at \(CrabRig.ledgeTailTruck)")
        #expect(seen.contains { $0 >= CrabRig.ledgeTailTruck },
                "nothing sparks at the contact point itself")
        #expect(lowest >= 24, "the cone never reaches the ledge's own top line")
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
