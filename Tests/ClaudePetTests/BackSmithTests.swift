import Testing
import Foundation
@testable import ClaudePet

/// **The back smith, second cut.** A ledge comes in from HIS RIGHT and slides
/// right to left — twenty-eight long, five tall, three little bushes drifting
/// behind it at half its speed — he pops onto it, locks the back truck on the
/// top with the nose dipped two rows, steezes it out through a two-and-a-half
/// second grind with sparks off the truck, kickflips out, and stomps. Every
/// channel eased across every phase seam; the ledge and the bushes are ground
/// and never rise with him.
@MainActor
struct BackSmithTests {

    private let duration = CrabAnimator.Flourish.backSmith.duration
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
        for p in [0.90, 0.95, 0.999] {
            #expect(ledgeCells(CrabRig.render(frame(p))).isEmpty, "ledge still on the grid at p=\(p)")
        }
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
            let stomp = (p > 0.10 && p < 0.14) || (p > 0.88 && p < 0.92)
            if step > 1 && !stomp { jumps.append((p, step)) }
            // The travel never retreats (right to left) and its fastest leg is
            // under two cells a frame.
            #expect(pose.ledge >= previous.ledge - 1e-9, "the ledge retreated at p=\(p)")
            #expect((pose.ledge - previous.ledge) * Double(CrabRig.ledgeTravel) <= 2 + 1e-6, "the ledge leapt at p=\(p)")
            previous = pose
        }
        #expect(jumps.isEmpty, "bob jumped: \(jumps)")
        // The pop LANDS on the ledge — the grind's height — and the kickflip
        // out starts from it.
        #expect(frame(0.319).bob == -4, "the pop ended at \(frame(0.319).bob), not on the ledge")
        #expect(frame(0.32).bob == -4)
        #expect(frame(0.78).bob == -4, "the kickflip out did not start from the ledge")
    }

    @Test("Mid-grind the nose is down, the tail truck is on the top, the leg is out, sparks fly")
    func theGrind() {
        let pose = frame(0.55)
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
        let wheelBottom = (0..<PixelBuffer.side).last { buffer[11, $0] == .yellow }
        let ledgeTop = (0..<PixelBuffer.side).first { buffer[5, $0] == .steel }
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
        #expect(frame(0.32).legKick == 0 && frame(0.78).legKick == 0)
        #expect(frame(0.32).grindSparks == 0 && frame(0.78).grindSparks == 0)
    }

    @Test("The ledge comes from his right, travels left under him, and the bushes lag it")
    func theLedgeTravelsRightToLeft() {
        // Right end: 19 as he lands, ≤ 14 late in the grind, off-left at 0.90.
        let atPop = ledgeCells(CrabRig.render(frame(0.32))).map(\.x).max()
        #expect(atPop == 19, "at the pop the ledge's right end is at \(String(describing: atPop))")
        let late = ledgeCells(CrabRig.render(frame(0.75))).map(\.x).max() ?? 99
        #expect(late <= 14, "the ledge did not slide under him: right end \(late) at p=0.75")
        // Entering: its LEFT end appears at the right edge first.
        var t = 0.0, entered = false
        while t < duration * 0.32 {
            let cells = ledgeCells(CrabRig.render(frame(t / duration)))
            if let leftmost = cells.map(\.x).min() {
                if !entered { #expect(leftmost >= 25, "the ledge appeared at column \(leftmost), not from the right"); entered = true }
            }
            t += 1.0 / 30
        }
        #expect(entered)
        // The bushes move at half the ledge's speed between two frames.
        let a = frame(0.40), b = frame(0.70)
        let ledgeMoved = (ledgeCells(CrabRig.render(a)).map(\.x).max() ?? 0) - (ledgeCells(CrabRig.render(b)).map(\.x).max() ?? 0)
        let bushMoved = (bushCells(CrabRig.render(a)).map(\.x).max() ?? 0) - (bushCells(CrabRig.render(b)).map(\.x).max() ?? 0)
        #expect(ledgeMoved > 0, "the ledge did not move through the grind")
        #expect(bushMoved >= 0 && bushMoved < ledgeMoved, "bushes moved \(bushMoved), ledge \(ledgeMoved) — no parallax")
        // The bushes peek above the ledge's top and are green.
        #expect(!bushCells(CrabRig.render(a)).isEmpty, "no bushes mid-grind")
    }

    @Test("He kickflips out and stomps")
    func theKickflipOut() {
        let air = frame(0.84)
        #expect(air.prop == .skateboard, "the exit board is \(air.prop)")
        #expect(air.propPhase > 0.3 && air.propPhase < 0.7, "the board is not mid-turn at p=0.84: \(air.propPhase)")
        #expect(air.bob < -4, "he is not in the air on the way out: bob \(air.bob)")
        let stomp = frame(0.95)
        #expect(stomp.prop == .skateboard && stomp.propPhase == 0 && stomp.squash == 1 && stomp.bob == 1)
        #expect(stomp.dustBurst != nil, "no boom")
    }

    @Test("The ledge and the bushes never rise with him")
    func theLedgeIsGround() {
        for p in stride(from: 0.2, through: 0.85, by: 0.05) {
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
