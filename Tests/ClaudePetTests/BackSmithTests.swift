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
        for p in [0.0, 0.005] {
            let pose = frame(p)
            #expect(pose.ledge < 0.01, "ledge \(pose.ledge) at p=\(p)")
            let buffer = CrabRig.render(pose)
            #expect(ledgeCells(buffer).isEmpty, "ledge cells on the grid at p=\(p)")
            #expect(bushCells(buffer).isEmpty, "bushes on the grid at p=\(p)")
        }
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
        // the grind's end (13), still short of the nose at 20–24.
        let cells = ledgeCells(buffer)
        let edge = cells.map(\.x).max() ?? -1
        #expect(edge >= 13 && edge < 20, "mid-grind the ledge's right end is at \(edge)")
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
        // Right end: 19 as he lands, ≤ 14 late in the grind, off-left at 0.91.
        let atPop = ledgeCells(CrabRig.render(frame(lock))).map(\.x).max()
        #expect(atPop == 19, "at the pop the ledge's right end is at \(String(describing: atPop))")
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
        // The bushes move at half the ledge's speed between two frames.
        let a = frame(0.42), b = frame(0.72)
        let ledgeMoved = (ledgeCells(CrabRig.render(a)).map(\.x).max() ?? 0) - (ledgeCells(CrabRig.render(b)).map(\.x).max() ?? 0)
        let bushMoved = (bushCells(CrabRig.render(a)).map(\.x).max() ?? 0) - (bushCells(CrabRig.render(b)).map(\.x).max() ?? 0)
        #expect(ledgeMoved > 0, "the ledge did not move through the grind")
        #expect(bushMoved >= 0 && bushMoved < ledgeMoved, "bushes moved \(bushMoved), ledge \(ledgeMoved) — no parallax")
        // The bushes peek above the ledge's top and are green.
        #expect(!bushCells(CrabRig.render(a)).isEmpty, "no bushes mid-grind")
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
        for p in stride(from: 0.2, through: exit + 0.09, by: 0.05) {
            var pose = frame(p)
            guard !ledgeCells(CrabRig.render(pose)).isEmpty else { continue }
            pose.bob = -8                                 // a jump the ground must ignore
            let buffer = CrabRig.render(pose)
            #expect(ledgeCells(buffer).allSatisfy { $0.y >= 24 && $0.y <= 28 }, "ledge rows moved with bob at p=\(p)")
            #expect(bushCells(buffer).allSatisfy { $0.y >= 21 && $0.y <= 23 }, "bush rows moved with bob at p=\(p)")
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
}
