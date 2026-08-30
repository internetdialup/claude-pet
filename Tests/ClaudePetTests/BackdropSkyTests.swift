import Testing
import Foundation
import SwiftUI
import AppKit
@testable import ClaudePet

/// The hero's sky: the operator's own art, quantised to the grid the crab is
/// drawn on, with the procedural basin still underneath it.
@Suite("Backdrop sky")
// `@MainActor` written down rather than inferred. `Backdrop` conforms to
// `View`, and Swift 6.1 — which is what CI runs — pushes that isolation onto
// the struct's init and instance methods, while 6.3 on this machine does not.
// So this compiled locally and failed on the runner with "call to main
// actor-isolated instance method ... in a synchronous nonisolated context".
// Same trap `ThoughtBubble` and `ReelDeterminismTests` already carry notes about.
@MainActor
struct BackdropSkyTests {

    /// The baked picture has to match the sprite's grid, or it stops being the
    /// same material and goes back to being a photograph pasted behind pixel
    /// art — which is the thing `Style.cells` exists to prevent.
    @Test("The baked picture is 32 cells wide, like the sprite")
    func bakedOnTheSpriteGrid() {
        let sky = Backdrop.Style.sky
        let stops = try! #require(sky.stops)
        #expect(!stops.isEmpty)
        for (row, line) in stops.enumerated() {
            #expect(line.count == sky.cells,
                    "row \(row) is \(line.count) cells, not \(sky.cells)")
        }
    }

    /// Every baked cell must name a stop that exists. An index past the end of
    /// the ramp would be clamped silently into the abyss, which is a bug that
    /// looks like a design decision.
    @Test("Every baked cell indexes a real stop")
    func everyIndexIsInRange() {
        let sky = Backdrop.Style.sky
        for line in sky.stops ?? [] {
            for ch in line {
                let i = try! #require(ch.wholeNumberValue)
                #expect(i >= 0 && i < sky.ramp.count, "index \(i) is outside the ramp")
            }
        }
    }

    /// **The ordering is load-bearing.** `rampIndex` deepens a cell by moving
    /// its index UP, which is only a deepening if the ramp runs light to dark.
    /// Reversed, the basin under his feet would glow.
    @Test("The ramp runs light to deep")
    func rampIsOrdered() {
        var previous = 2.0
        for (i, colour) in Backdrop.Style.sky.ramp.enumerated() {
            let l = luminance(of: colour)
            #expect(l <= previous + 0.001, "stop \(i) is lighter than stop \(i - 1)")
            previous = l
        }
    }

    /// The basin still bites — the point of keeping the procedural field rather
    /// than pasting the picture in whole. Cells under his feet must resolve
    /// DEEPER than the same column at the top, and the corners must be left
    /// alone.
    ///
    /// The first version failed this in spirit while passing in letter: a
    /// linear falloff over `reach` 1.5 gave nearly every cell the same +1, so
    /// the "basin" was a flat coat of darkness. Hence the corner assertion.
    @Test("The trough deepens under the pet and spares the corners")
    func theTroughStillBites() {
        let sky = Backdrop.Style.sky
        let stops = try! #require(sky.stops)
        let rows = stops.count, cols = sky.cells

        func baked(col: Int, row: Int) -> Int {
            Array(stops[row])[col].wholeNumberValue ?? 0
        }
        func rendered(col: Int, row: Int) -> Int {
            Backdrop(style: sky).rampIndex(col: col, row: row, cols: cols, rows: rows)
        }

        let footCol = cols / 2, footRow = rows - 2
        #expect(rendered(col: footCol, row: footRow) > baked(col: footCol, row: footRow),
                "the basin does not deepen the cells under his feet")

        // …and it is a basin, not a coat of paint.
        for (col, row) in [(0, 0), (cols - 1, 0)] {
            #expect(rendered(col: col, row: row) == baked(col: col, row: row),
                    "the trough reached the top corner at (\(col),\(row))")
        }
    }

    private func luminance(of colour: Color) -> Double {
        let c = NSColor(colour).usingColorSpace(.sRGB) ?? .black
        return 0.2126 * Double(c.redComponent)
            + 0.7152 * Double(c.greenComponent)
            + 0.0722 * Double(c.blueComponent)
    }
}
