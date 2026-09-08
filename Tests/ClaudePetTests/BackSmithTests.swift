import Testing
import Foundation
@testable import ClaudePet

/// **The back smith.** A ledge slides in from the left, he pops onto it,
/// locks the back truck on the edge with the nose dipped two rows, steezes it
/// out, and pops off as the ledge leaves. Every channel eased across every
/// phase seam; the ledge is ground and never rises with him.
@MainActor
struct BackSmithTests {

    private let duration = CrabAnimator.Flourish.backSmith.duration
    private func frame(_ p: Double) -> CrabPose {
        CrabAnimator.flourishPose(.backSmith, at: p * duration)
    }
    private func ledgeCells(_ buffer: PixelBuffer) -> [(x: Int, y: Int)] {
        var cells: [(Int, Int)] = []
        // The ledge's own rows only: a steel top at 25, slate below. (The
        // landing dust is steel too, two rows above the feet.)
        for y in 25...28 {
            for x in 0..<PixelBuffer.side where (y == 25 && buffer[x, y] == .steel) || (y > 25 && buffer[x, y] == .slate) {
                cells.append((x, y))
            }
        }
        return cells
    }

    @Test("The ledge is off the grid at both ends of the trick")
    func theLedgeBookendsAreClean() {
        for p in [0.0, 0.005] {
            let pose = frame(p)
            #expect(pose.ledge < 0.01, "ledge \(pose.ledge) at p=\(p)")
            #expect(ledgeCells(CrabRig.render(pose)).isEmpty, "ledge cells on the grid at p=\(p)")
        }
        // …and gone off the RIGHT before the stomp lands, so he never comes
        // down on half a ledge.
        for p in [0.90, 0.95, 0.999] {
            #expect(ledgeCells(CrabRig.render(frame(p))).isEmpty, "ledge still on the grid at p=\(p)")
        }
        // The frozen sentinel, by the trick: frame 0 is a crab on a flat board.
        let zero = frame(0)
        #expect(zero.bob >= 0 && zero.combo == 0 && zero.legKick == 0)
    }

    @Test("Nothing snaps: bob moves a row a frame at most, outside the two stomps")
    func nothingSnaps() {
        var previous = frame(0)
        var t = 0.0
        var jumps: [(Double, Int)] = []
        // Inside the trick only: at t == duration the flourish is over and
        // every channel is at rest, which is a different frame, not a jump.
        while t < duration - 1.0 / 30 - 1e-9 {
            t += 1.0 / 30
            let pose = frame(min(1, t / duration))
            let step = abs(pose.bob - previous.bob)
            let p = t / duration
            // The take-off (crouch → pop) and the landing squash are the
            // exemption; everywhere else a row a frame.
            let stomp = (p > 0.13 && p < 0.17) || (p > 0.88 && p < 0.92)
            if step > 1 && !stomp { jumps.append((p, step)) }
            // The travel never retreats (left to right, the operator's
            // direction) and its fastest leg — the exit, 26 of 46 cells over
            // 0.14 of the trick at smoothstep's 1.5 peak — is under three
            // cells a frame.
            #expect(pose.ledge >= previous.ledge - 1e-9, "the ledge retreated at p=\(p)")
            #expect((pose.ledge - previous.ledge) * 46 <= 3 + 1e-6, "the ledge leapt at p=\(p)")
            previous = pose
        }
        #expect(jumps.isEmpty, "bob jumped: \(jumps)")
        // …and the pop LANDS on the ledge: the grind's height, not the ground.
        #expect(frame(0.399).bob == -3, "the pop ended at \(frame(0.399).bob), not on the ledge")
        #expect(frame(0.40).bob == -3)
        #expect(frame(0.78).bob == -3, "the pop-off did not start from the ledge")
    }

    @Test("Mid-grind the nose is down, the tail truck is on the edge, the leg is out")
    func theGrind() {
        let pose = frame(0.6)
        #expect(pose.prop == .skateboardSmith)
        #expect(pose.bob == -3)
        #expect(pose.legKick > 0.99, "no steeze mid-grind")
        #expect(pose.torsoTurn == 0, "only the bigspin may turn him")
        #expect(pose.eyes == .determined)
        let buffer = CrabRig.render(pose)
        // The deck rows: tail (cols 8–13) level at 22, nose (cols 20–24) two rows lower.
        func deckRow(_ x: Int) -> Int? { (0..<PixelBuffer.side).first { buffer[x, $0] == .deck } }
        let tail = deckRow(9), nose = deckRow(22)
        #expect(tail == 22, "tail row \(String(describing: tail))")
        #expect(nose == 24, "nose row \(String(describing: nose)) — the nose is not dipped two rows")
        // The tail wheel's bottom row is the row above the ledge's top.
        let wheelBottom = (0..<PixelBuffer.side).last { buffer[11, $0] == .yellow }
        let ledgeTop = (0..<PixelBuffer.side).first { buffer[5, $0] == .steel }
        #expect(wheelBottom == 24 && ledgeTop == 25,
                "wheel bottom \(String(describing: wheelBottom)), ledge top \(String(describing: ledgeTop))")
        // Mid-grind the ledge has slid on under him: its edge is past column
        // 13 and short of the nose (cols 20–24), and its top row is under the
        // tail wheel (the spark may sit on cell 12).
        let cells = ledgeCells(buffer)
        let edge = cells.map(\.x).max() ?? -1
        #expect(edge > 13 && edge < 20, "mid-grind the ledge's edge is at \(edge)")
        let underTheWheel = buffer[11, 25] == .steel || buffer[11, 25] == .flameCore
        #expect(underTheWheel && buffer[edge, 26] == .slate, "the ledge is not under the tail wheel")
        // The steeze at both ends of the grind is zero: it eases, it does not pop.
        #expect(frame(0.40).legKick == 0 && frame(0.78).legKick == 0)
    }

    @Test("The ledge never rises with him, and travels left to right")
    func theLedgeIsGround() {
        for p in stride(from: 0.2, through: 0.85, by: 0.05) {
            var pose = frame(p)
            let cellsBefore = ledgeCells(CrabRig.render(pose))
            guard !cellsBefore.isEmpty else { continue }
            pose.bob = -8                                 // a jump the ledge must ignore
            let cells = ledgeCells(CrabRig.render(pose))
            #expect(!cells.isEmpty)
            #expect(cells.allSatisfy { $0.y >= 25 && $0.y <= 28 }, "ledge rows moved with bob at p=\(p)")
        }
        // It enters from the left, edge to column 13 by the pop; slides on
        // under him through the grind; and leaves off the right — never a
        // step backwards, never more than three cells a frame.
        var edge = -1
        var t = 0.0
        while t < duration {
            let cells = ledgeCells(CrabRig.render(frame(t / duration)))
            let newEdge = cells.isEmpty ? edge : (cells.map(\.x).max() ?? edge)
            #expect(newEdge >= edge, "the ledge retreated at \(t)")
            #expect(newEdge - edge <= 3 || edge < 0, "the ledge leapt \(newEdge - edge) cells at \(t)")
            edge = newEdge
            t += 1.0 / 30
        }
        let popEdge = ledgeCells(CrabRig.render(frame(0.30))).map(\.x).max()
        #expect(popEdge == 13, "at the pop the ledge's edge is at \(String(describing: popEdge))")
        let lateEdge = ledgeCells(CrabRig.render(frame(0.75))).map(\.x).max()
        #expect((lateEdge ?? 0) >= 17, "the ledge did not slide under him: edge \(String(describing: lateEdge)) at p=0.75")
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
        // No yellow run longer than a wheel, mid-grind.
        let buffer = CrabRig.render(frame(0.6))
        for y in 0..<PixelBuffer.side {
            var run = 0
            for x in 0..<PixelBuffer.side {
                run = buffer[x, y] == .yellow ? run + 1 : 0
                #expect(run <= 3, "a yellow run of \(run) on row \(y)")
            }
        }
    }
}
