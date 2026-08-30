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
        /// An optional baked picture, one ramp index per cell, rows top-first.
        ///
        /// When present the depth field stops CHOOSING the stop and starts
        /// DEEPENING it: the picture says what colour a cell is, the field says
        /// how much closer to the abyss it sits. That is what keeps the pet
        /// framed by the darkest part of the frame — he is in the scene rather
        /// than in front of it.
        ///
        /// Baked rather than loaded. A committed asset that resolved an image
        /// at render time would put a file path inside a reproducible render,
        /// and the ResourceBundle round taught this project what that costs.
        public var stops: [String]?

        public init(ramp: [Color] = Palette.Ocean.ramp,
                    foam: Color? = Palette.Ocean.foam,
                    cells: Int = 32,
                    trough: UnitPoint = UnitPoint(x: 0.5, y: 0.92),
                    reach: Double = 1.5,
                    depthBias: Double = 0.86,
                    stops: [String]? = nil) {
            self.ramp = ramp
            self.foam = foam
            self.cells = cells
            self.trough = trough
            self.reach = reach
            self.depthBias = depthBias
            self.stops = stops
        }

        public static let ocean = Style()

        /// The operator's own sky, quantised to the sprite's grid.
        ///
        /// Midjourney art of theirs, cropped 16:9 and averaged down to the
        /// same 32 cells the crab is drawn on. That quantisation is the point,
        /// not a compromise: `cells`' own note says 32 matches the sprite grid
        /// "so the water reads as the same material rather than as a photograph
        /// pasted behind pixel art", and a wallpaper dropped in whole is
        /// exactly what that was written to prevent. Rendered through the grid
        /// it stops being a photo and becomes the same material he is.
        ///
        /// Ten stops, ordered LIGHT to DEEP. The ordering is load-bearing:
        /// `rampIndex` deepens a cell by moving its index up, which is only a
        /// deepening if the ramp runs that way.
        ///
        /// `foam: nil` — the caustic dashes belong to water.
        public static let sky = Style(
            ramp: [
                Color(red: 0.851, green: 0.863, blue: 0.871),
                Color(red: 0.682, green: 0.765, blue: 0.843),
                Color(red: 0.420, green: 0.651, blue: 0.831),
                Color(red: 0.173, green: 0.475, blue: 0.737),
                Color(red: 0.051, green: 0.361, blue: 0.659),
                Color(red: 0.027, green: 0.286, blue: 0.584),
                Color(red: 0.031, green: 0.220, blue: 0.506),
                Color(red: 0.051, green: 0.176, blue: 0.439),
                Color(red: 0.059, green: 0.161, blue: 0.404),
                Color(red: 0.063, green: 0.153, blue: 0.369),
            ],
            foam: nil,
            stops: [
                "99999999999999999999999999888888",
                "99999999999999999988888888888888",
                "99999998899888888888887777777777",
                "99888888878888777777777777777776",
                "88777777777777777766666666666666",
                "77766677666666666666666666666666",
                "76666556666555666665555555555555",
                "66655444455555555555555555555555",
                "66555432223444444445554444444444",
                "66655543211123333334444444444444",
                "55555555442100122222233333333333",
                "55555555444431000001111222233333",
                "55554444444444310000000011122222",
                "44444444444444332100000000011112",
                "44444444443333333322111100001111",
                "44444333333333332222222111111111",
                "33333333333322222222222111111111",
                "33333332222222222221111111100000",
            ])
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
    ///
    /// With a baked picture the depth field no longer CHOOSES the stop, it
    /// DEEPENS the one the picture named — the composition stays the
    /// operator's and the grounding stays procedural, so the pet is framed by
    /// the darkest part of the frame instead of standing in front of a
    /// postcard.
    // Internal rather than private so the suite can ask what a cell resolves
    // to without rendering a Canvas and reading pixels back.
    func rampIndex(col: Int, row: Int, cols: Int, rows: Int) -> Int {
        let u = (Double(col) + 0.5) / Double(cols)
        let v = (Double(row) + 0.5) / Double(rows)

        if let stops = style.stops, !stops.isEmpty {
            // Sample by proportion, so the picture stretches to whatever canvas
            // it is given rather than assuming the grid it was baked at.
            let r = min(Int(v * Double(stops.count)), stops.count - 1)
            let line = Array(stops[r])
            guard !line.isEmpty else { return 0 }
            let c = min(Int(u * Double(line.count)), line.count - 1)
            let baked = line[c].wholeNumberValue ?? 0
            return min(baked + troughDepth(u: u, v: v), style.ramp.count - 1)
        }

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

    /// How many stops deeper the basin under the pet pushes a cell.
    ///
    /// The same trough the procedural field already uses, factored out so the
    /// baked picture can borrow it: strongest directly beneath him, nothing at
    /// the far corners. Capped at three stops — enough to seat him in the
    /// scene, not enough to repaint it.
    ///
    /// SQUARED, and the difference is the whole feature. At `reach` 1.5 a
    /// linear falloff still returns most of its value in the corners, so
    /// rounding handed nearly every cell the same +1 and the "basin" was a flat
    /// coat of darkness over the picture — measured at +2 under his feet and +1
    /// everywhere else, including both top corners. Squaring concentrates it:
    /// three stops beneath him, one at the top edge, none in the far corners.
    private func troughDepth(u: Double, v: Double) -> Int {
        let dx = u - style.trough.x
        let dy = v - style.trough.y
        let radius = (dx * dx + dy * dy).squareRoot() / style.reach
        let falloff = 1 - min(radius, 1)
        return Int((falloff * falloff * 3).rounded())
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
