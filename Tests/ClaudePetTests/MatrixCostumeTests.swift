import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ClaudePet

/// The Matrix look: code that crosses his whole shell without eating his face.
///
/// The rain draws on `.front` — after `drawFace` — and writes only where the
/// cell is still `.body`. That mask is what lets it cover the shell instead of
/// trickling down six thin columns, and it is why the eye contract holds by
/// construction rather than by keeping clear of coordinates.
@Suite("Matrix costume")
@MainActor
struct MatrixCostumeTests {

    private func dressed(_ t: Double, mood: PetMood = .working) -> PixelBuffer {
        var pose = CrabAnimator.pose(mood: mood, t: t)
        pose.propPhase = t
        pose.prop = .none
        pose.propVisibility = 0
        return CrabRig.render(pose, costume: .matrix, costumeVisibility: 1)
    }

    private func bare(_ t: Double, mood: PetMood = .working) -> PixelBuffer {
        var pose = CrabAnimator.pose(mood: mood, t: t)
        pose.propPhase = t
        pose.prop = .none
        pose.propVisibility = 0
        return CrabRig.render(pose)
    }

    /// The masking contract, stated directly: the rain may only ever consume
    /// cells that were shell. Anything else — a face, a prop, a heat band — is
    /// not its to take.
    @Test("The rain only ever eats shell cells")
    func rainOnlyConsumesShell() {
        for t in stride(from: 0.0, through: 12.0, by: 0.35) {
            let plain = bare(t)
            let matrix = dressed(t)
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where plain[x, y] != matrix[x, y] {
                    #expect(plain[x, y] == .body,
                            "matrix took a \(plain[x, y]) cell at (\(x),\(y)) at t=\(t)")
                }
            }
        }
    }

    /// Heat outranks the code: a cell mid-cascade is `.bodyHot`, not `.body`,
    /// so the fire burns through rather than being rained on.
    @Test("A heat cascade burns through the code")
    func heatOutranksTheRain() {
        var pose = CrabAnimator.pose(mood: .cooking, t: 2)
        pose.heat = 1
        pose.heatPhase = 0.4
        pose.propPhase = 2
        let buffer = CrabRig.render(pose, costume: .matrix, costumeVisibility: 1)
        var hot = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side
            where buffer[x, y] == .bodyHot || buffer[x, y] == .bodyEmber { hot += 1 }
        }
        #expect(hot > 0, "the cascade lost to the rain")
    }

    /// The point of the redo: it used to light at most 24 cells of a 220-cell
    /// shell in six one-pixel columns. It has to read as a field now.
    @Test("The code crosses the shell instead of trickling down six columns")
    func coverageIsAField() {
        var best = 0
        var columns = Set<Int>()
        for t in stride(from: 0.0, through: 12.0, by: 0.25) {
            let buffer = dressed(t)
            var lit = 0
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side {
                    let ink = buffer[x, y]
                    if ink == .costumeA || ink == .costumeB || ink == .costumeC {
                        lit += 1
                        columns.insert(x)
                    }
                }
            }
            best = max(best, lit)
        }
        #expect(best > 40, "only \(best) cells light at once — still a trickle")
        #expect(columns.count > 12, "the rain only ever falls in \(columns.count) columns")
    }

    /// He must not vanish into his own costume: the shell stays dark, the
    /// heads stay bright, and the eyes out-rank every rain stop so his face
    /// still reads with code crossing it.
    @Test("The palette keeps the shell dark, the code bright, and the eyes on top")
    func paletteSeparates() throws {
        let style = CostumeStyle.of(.matrix)
        let shell = try #require(style.inks[.body])
        let head = try #require(style.inks[.costumeA])
        let mid = try #require(style.inks[.costumeB])
        let tail = try #require(style.inks[.costumeC])
        let eye = try #require(style.inks[.eye])

        func luma(_ c: (r: Double, g: Double, b: Double)) -> Double {
            0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        }
        #expect(luma(shell) < 0.06, "the terminal shell must stay dark")
        #expect(luma(head) > luma(mid), "the streak must fade from its head")
        #expect(luma(mid) > luma(tail), "the tail must be the dimmest stop")
        #expect(luma(tail) > luma(shell), "the tail has to be visible on the shell")
        #expect(luma(eye) > luma(head), "the eyes must out-rank the rain")

        // The montage tag reads the first ink over 0.3 luminance; if the heads
        // ever dim past that the reel's Matrix caption silently changes colour.
        #expect(luma(head) > 0.3)
    }
}
