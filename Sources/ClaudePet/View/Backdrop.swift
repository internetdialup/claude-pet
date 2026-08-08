import SwiftUI

/// The water Claw'd stands on in the composed marketing scenes.
///
/// **This is not a gradient, and that is the whole design.** A SwiftUI
/// `LinearGradient` at 192px produces 200-odd tones; the GIF encoder then picks
/// its own ~30 boundaries, and because a GIF's colour table is *global* across
/// every frame, those boundaries shift whenever anything else in the palette
/// moves. The party loop retints the body on every frame, so a smooth ramp
/// behind it would visibly crawl.
///
/// Instead the field is quantised at authoring time into flat blocks drawn on
/// whole-pixel edges. The output contains exactly `Palette.Ocean.ramp.count`
/// colours, the encoder has nothing to decide, and every stop survives into the
/// colour table verbatim. Measured, this also costs 1.41× the transparent
/// baseline where a smooth ramp costs 1.79×.
///
/// It is also the only version consistent with `Palette`'s opening rule — flat
/// colour, no shading ramp. A soft gradient behind a flat-colour sprite is
/// exactly the sort of thing that stops a copy reading as the original.
public struct Backdrop: View {

    /// How the depth field is shaped. Defaults produce the ocean.
    public struct Style: Sendable {
        /// Surface first, abyss last.
        public var ramp: [Color]
        /// A highlight for the caustic dashes, or nil for none.
        public var foam: Color?
        /// Blocks across the width. 32 matches the sprite grid, so the water
        /// reads as the same material rather than as a photograph pasted behind
        /// pixel art.
        public var cells: Int
        /// Where the water is deepest, in unit space — under the pet's feet.
        public var trough: UnitPoint
        /// How far the trough reaches, in widths.
        public var reach: Double
        /// Weight of the top-to-bottom term against the radial one.
        public var depthBias: Double

        public init(ramp: [Color] = Palette.Ocean.ramp,
                    foam: Color? = Palette.Ocean.foam,
                    cells: Int = 32,
                    trough: UnitPoint = UnitPoint(x: 0.5, y: 0.92),
                    reach: Double = 1.5,
                    depthBias: Double = 0.86) {
            self.ramp = ramp
            self.foam = foam
            self.cells = cells
            self.trough = trough
            self.reach = reach
            self.depthBias = depthBias
        }

        public static let ocean = Style()
    }

    public var style: Style
    /// 0…1, advancing the swell. Left at 0 for every committed asset: Claw'd's
    /// whole performance is one- and two-pixel moves, and a field drifting at a
    /// similar amplitude competes with him instead of sitting behind him.
    public var phase: Double

    public init(style: Style = .ocean, phase: Double = 0) {
        self.style = style
        self.phase = phase
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let cols = max(1, style.cells)
            let cell = size.width / Double(cols)
            let rows = max(1, Int((size.height / cell).rounded(.up)))

            for row in 0..<rows {
                // Coalesce horizontal runs of equal depth, the same trick
                // `PixelBuffer.runs()` uses — tens of rects instead of hundreds.
                var col = 0
                while col < cols {
                    let index = rampIndex(col: col, row: row, cols: cols, rows: rows)
                    var length = 1
                    while col + length < cols,
                          rampIndex(col: col + length, row: row, cols: cols, rows: rows) == index {
                        length += 1
                    }
                    // Whole-pixel edges. Blocks tile exactly, so there is no
                    // overdraw and therefore no antialiasing to smuggle
                    // intermediate colours into the palette.
                    let x0 = (Double(col) * cell).rounded()
                    let x1 = (Double(col + length) * cell).rounded()
                    let y0 = (Double(row) * cell).rounded()
                    let y1 = (Double(row + 1) * cell).rounded()
                    context.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)),
                                 with: .color(style.ramp[index]))
                    col += length
                }
            }

            if let foam = style.foam { drawCaustics(in: &context, size: size, cell: cell, foam: foam) }
        }
    }

    /// Which stop a block belongs to.
    private func rampIndex(col: Int, row: Int, cols: Int, rows: Int) -> Int {
        let u = (Double(col) + 0.5) / Double(cols)
        let v = (Double(row) + 0.5) / Double(rows)

        // Most of the read is simply "deeper as you go down".
        var depth = v * style.depthBias

        // A basin under the pet, so he is framed by the darkest water rather
        // than standing on an arbitrary band boundary.
        let dx = u - style.trough.x
        let dy = v - style.trough.y
        let radius = (dx * dx + dy * dy).squareRoot() / style.reach
        depth += (1 - min(radius, 1)) * (1 - style.depthBias)

        // Two incommensurate frequencies, so the bands are not concentric rings
        // and the pattern does not repeat inside one canvas.
        depth += 0.025 * sin((u * 2.3 + v * 1.1 + phase) * 2 * .pi)

        return min(max(Int(depth * Double(style.ramp.count)), 0), style.ramp.count - 1)
    }

    /// A few short dashes near the surface. Deterministic positions — no
    /// randomness anywhere in a renderer whose output is supposed to be
    /// reproducible commit to commit.
    private func drawCaustics(in context: inout GraphicsContext,
                              size: CGSize, cell: Double, foam: Color) {
        let dashes: [(u: Double, v: Double, cells: Int)] = [
            (0.11, 0.035, 3), (0.58, 0.02, 2), (0.79, 0.05, 2),
        ]
        for dash in dashes {
            let x = (dash.u * size.width).rounded()
            let y = (dash.v * size.height).rounded()
            let w = (Double(dash.cells) * cell).rounded()
            context.fill(Path(CGRect(x: x, y: y, width: w, height: (cell * 0.5).rounded())),
                         with: .color(foam))
        }
    }
}
