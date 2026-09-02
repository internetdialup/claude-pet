import SwiftUI

/// A 32×32 indexed-colour buffer — the sprite grid Claw'd is drawn on.
///
/// The grid is deliberately coarse. Claw'd is chunky, low-resolution pixel art;
/// drawing him on a fine grid produces smooth edges and small features, which is
/// exactly what makes a copy stop reading as the original. Every primitive here
/// snaps to whole cells for the same reason.
public struct PixelBuffer: Sendable {
    public static let side = 32

    /// Palette slots. Index 0 is transparent. Flat colours only — Claw'd has no
    /// shading ramp, so there is deliberately no "light"/"dark" body slot.
    public enum Ink: UInt8, Sendable {
        case clear = 0
        case body
        case eye
        case mouth
        case screenDark
        case screenLight
        case green
        case yellow
        case pink
        /// Tools — wrench, screwdriver.
        case steel
        /// Flame body.
        case flame
        /// Hottest part of the burst.
        case flameCore
        /// Deep outer licks.
        case ember
        /// Paper — the plan clipboard.
        case paper
        /// Costume accessory slots. Their colours come from the worn
        /// `CostumeStyle` via `PixelCanvasView.inkOverrides`, so one pair of
        /// inks dresses every costume.
        case costumeA
        case costumeB
        /// A third accessory slot — the Gundam's visor recess earned it.
        case costumeC
        /// The cooking heat bands — body cells repainted as quantised heat.
        case bodyHot
        case bodyEmber
        /// Alarm red — the npm cube; promoted from `Palette.alert` chrome.
        case alert
        /// A costume-immune charcoal — the service marks' field.
        ///
        /// `.eye` and `.mouth` are the only inks that consult `inkOverrides`,
        /// so a case with no override lookup **cannot** be recoloured by a
        /// wardrobe. The GitHub mark used to be drawn in `.eye` and turned
        /// pale green under the Matrix look and yellow under the Gundam.
        case slate
        /// The torso-turn shade — the sampler's ollie variants selling a
        /// slight body rotation. This is NOT the shading ramp the header
        /// bans: it is one flat step below the shell, override-consulting so
        /// every wardrobe supplies its own step, raised and lowered inside a
        /// single trick's air by the drip-feed sampler, and never set by any
        /// live pose. An EVENT, not a state — the glint's defence, borrowed
        /// whole. If it ever reads as a ramp sneaking in, delete it; do not
        /// soften it into one.
        case bodyShade
        /// The deal-with-it black — the meme shades off the operator's desk
        /// sticker, which are PURE black on the print. `.slate` renders as
        /// the soft charcoal the service badges need, and `.eye` takes
        /// wardrobe overrides (camera-yellow shades on the Gundam would be
        /// a different meme). No override lookup, so the lenses are the same
        /// black in every costume — which is the joke's whole uniform.
        case memeBlack
        /// The ground shadow under him — the one ink that renders
        /// TRANSLUCENT, because a solid pool would fight every wallpaper it
        /// lands on. Appended, like every ink before it.
        case shadow
        /// The skate deck's own black — darker than `.slate` at the
        /// operator's call, and its own case so the board tests can keep
        /// measuring the deck by its ink alone (the bearing comment's
        /// argument, now with a name instead of a loan).
        case deck
    }

    private(set) var cells: [UInt8]

    public init() {
        cells = Array(repeating: 0, count: Self.side * Self.side)
    }

    @inline(__always)
    public subscript(x: Int, y: Int) -> Ink {
        get {
            guard x >= 0, y >= 0, x < Self.side, y < Self.side else { return .clear }
            return Ink(rawValue: cells[y * Self.side + x]) ?? .clear
        }
        set {
            guard x >= 0, y >= 0, x < Self.side, y < Self.side else { return }
            cells[y * Self.side + x] = newValue.rawValue
        }
    }

    // MARK: - Primitives

    /// The workhorse. Coordinates are whole cells; callers round before calling
    /// so that motion steps a pixel at a time instead of blurring across two.
    public mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ ink: Ink) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) {
            for xx in x..<(x + w) {
                self[xx, yy] = ink
            }
        }
    }

    /// Every non-clear cell becomes `.body` — the afterimage read: a whole-
    /// figure silhouette a single bodyTint can hue-shift cleanly. Without
    /// this, a trail carries ink-black eyes and full-colour props at trail
    /// opacity: floating ghost faces.
    func silhouette() -> PixelBuffer {
        var out = self
        for y in 0..<Self.side {
            for x in 0..<Self.side where out[x, y] != .clear {
                out[x, y] = .body
            }
        }
        return out
    }

    public mutating func pixel(_ x: Int, _ y: Int, _ ink: Ink) {
        self[x, y] = ink
    }

    /// Rows of a shape given as a bitmap string, one character per cell.
    /// `.` is transparent; any other character maps through `key`.
    /// Small glyphs — the check mark, the `z`, the terminal chrome — are far
    /// clearer written out than expressed as arithmetic.
    public mutating func stamp(_ rows: [String], at origin: (x: Int, y: Int), key: [Character: Ink]) {
        for (dy, row) in rows.enumerated() {
            for (dx, character) in row.enumerated() where character != "." {
                guard let ink = key[character] else { continue }
                self[origin.x + dx, origin.y + dy] = ink
            }
        }
    }

    /// Nearest-neighbour scale, anchored at the feet and centred horizontally.
    ///
    /// Done here rather than with `.scaleEffect` on the view: `CrabView` ends in
    /// `.drawingGroup()`, so a view-level scale resamples a finished bitmap and
    /// softens the deliberately hard pixel edges. Resampling the grid keeps every
    /// cell square. Upscales (the epic finale's transform) keep the feet pinned
    /// and crop at the grid's top edge — the buffer never grows; content that
    /// leaves the 32 rows is simply gone for the beat it is gone.
    func scaled(_ factor: Double) -> PixelBuffer {
        guard abs(factor - 1) > 0.001, factor > 0.1, factor < 2 else { return self }
        var out = PixelBuffer()
        let side = Double(Self.side)
        let inset = (side - side * factor) / 2

        for y in 0..<Self.side {
            for x in 0..<Self.side {
                // Map the destination cell back to a source cell. Anchoring the
                // bottom edge means he compresses onto the ground rather than
                // shrinking toward the middle of the air.
                let sourceY = (Double(y) - (side - side * factor)) / factor
                let sourceX = (Double(x) - inset) / factor
                guard sourceY >= 0, sourceX >= 0 else { continue }
                let ink = self[Int(sourceX), Int(sourceY)]
                if ink != .clear { out[x, y] = ink }
            }
        }
        return out
    }

    /// Copies the non-clear cells of `overlay` in, keeping each cell only when
    /// its hash clears `visibility` — the pixel-art alpha fade. The hash is a
    /// pure function of the cell and `seed`, so a dissolve is a stable pattern
    /// that fills in as visibility rises rather than a per-frame shimmer. At
    /// visibility 1 this is a plain paint: identical output to drawing direct.
    /// - Parameter preservingExisting: when true, destination cells that are
    ///   already painted keep their ink — the overlay slides in BEHIND the
    ///   scene instead of over it. This is how a ground object (the completion
    ///   badge) lets the character stand in front of it.
    mutating func composite(_ overlay: PixelBuffer, visibility: Double, seed: Int,
                            preservingExisting: Bool = false) {
        guard visibility > 0 else { return }
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let ink = overlay[x, y]
                guard ink != .clear else { continue }
                if preservingExisting, self[x, y] != .clear { continue }
                if visibility >= 1 || Self.hash01(x, y, seed) < visibility {
                    self[x, y] = ink
                }
            }
        }
    }

    /// splitmix64's finaliser over the cell index — the same generator the
    /// animator schedules with, for the same reason: deterministic, avalanched.
    private static func hash01(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var v = UInt64(bitPattern: Int64(x &+ y &* side &+ seed &* 4099))
        v = v &+ 0x9E37_79B9_7F4A_7C15
        v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
        v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
        v = v ^ (v >> 31)
        return Double(v >> 11) / Double(1 << 53)
    }

    /// Horizontal runs of identical ink, so the renderer draws tens of rects
    /// instead of hundreds.
    func runs() -> [(x: Int, y: Int, length: Int, ink: Ink)] {
        var result: [(Int, Int, Int, Ink)] = []
        for y in 0..<Self.side {
            var x = 0
            while x < Self.side {
                let ink = self[x, y]
                if ink == .clear { x += 1; continue }
                var length = 1
                while x + length < Self.side, self[x + length, y] == ink { length += 1 }
                result.append((x, y, length, ink))
                x += length
            }
        }
        return result
    }
}

/// Draws a `PixelBuffer` at hard pixel edges, filling whatever frame it is
/// given.
///
/// It deliberately sets **no** frame of its own. An earlier version pinned
/// itself to 32×32 points, so the sprite rendered at 32pt and was merely
/// centred inside the larger frame the caller asked for — the size preference
/// silently did nothing.
public struct PixelCanvasView: View {
    let buffer: PixelBuffer
    /// Overrides `.body` only. His eyes, mouth and props keep their own colours —
    /// tinting everything would just look like a hue-rotated screenshot.
    var bodyTint: Color?

    /// Costume colours by ink slot. Resolution order for the body is
    /// `bodyTint ?? inkOverrides[.body] ?? Palette.body` — status tints always
    /// beat wardrobe, wardrobe beats the default shell.
    var inkOverrides: [PixelBuffer.Ink: Color] = [:]

    /// Hairline overdraw that hides seams when a cell lands on a fractional
    /// device pixel.
    ///
    /// Harmless against transparency, which is what every caller drew on until
    /// the backdrop existed. Against an opaque backdrop it is not harmless: the
    /// half pixel blends terracotta into the water down the right and bottom of
    /// the silhouette, which is a one-sided outline on a character this file's
    /// palette defines as having none. The composed scenes pass `0` because they
    /// guarantee whole-pixel cells.
    var seamBleed: CGFloat = 0.5

    /// How far **every** resolved ink is pushed toward white, 0…1. At 1 he is a
    /// pure white silhouette — eyes, mouth, costume shell, heat bands and held
    /// props included.
    ///
    /// The second channel exists because `bodyTint` deliberately reaches the
    /// `.body` ink and nothing else: a hue-shifted eye reads as a recolour. A
    /// flash is the one effect that has to reach everything at once, because a
    /// "white flash" that leaves black eyes and a dark ninja hood in place is
    /// not white, it is a washed-out peach.
    ///
    /// Applied as a second flat fill of `Palette.white` at `blanch` alpha
    /// rather than as a per-ink colour lerp: the resolved inks are SwiftUI
    /// `Color`s and cannot be taken apart again without asking AppKit to
    /// introspect them, and white over opaque ink at alpha a *is* the lerp —
    /// `c·(1−a) + a`. So `bodyTint` and `inkOverrides` whiten for free, as the
    /// base fill this composites onto.
    var blanch: Double = 0

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let px = size.width / Double(PixelBuffer.side)
            let runs = buffer.runs()
            for run in runs {
                context.fill(Path(rect(for: run, px: px)), with: .color(color(for: run.ink)))
            }
            // One fill over the UNION of the runs, never one per run: with
            // `seamBleed` on, adjacent rects overlap by half a point, and a
            // per-run wash would composite white twice down every seam —
            // painting a bright grid across a sprite whose palette forbids
            // shading. A single path rasterises the overlap as coverage and
            // blends exactly once.
            let wash = Ease.clamp01(blanch)
            guard wash > 0.001 else { return }
            var lit = Path()
            for run in runs { lit.addRect(rect(for: run, px: px)) }
            context.fill(lit, with: .color(Palette.white.opacity(wash)))
        }
    }

    /// One cell run's rectangle. Shared by both passes so the wash provably
    /// covers the same geometry as the ink underneath it.
    private func rect(for run: (x: Int, y: Int, length: Int, ink: PixelBuffer.Ink),
                      px: Double) -> CGRect {
        let x0 = Double(run.x) * px, x1 = Double(run.x + run.length) * px
        let y0 = Double(run.y) * px, y1 = y0 + px
        if seamBleed > 0 {
            return CGRect(x: x0, y: y0,
                          width: x1 - x0 + seamBleed, height: y1 - y0 + seamBleed)
        }
        // No bleed to hide seams with, so snap the edges instead: neighbouring
        // runs then share an exact boundary and tile with neither a gap nor a
        // blend. Necessary because a cell is only a whole number of pixels when
        // the frame happens to be a multiple of 32.
        return CGRect(x: x0.rounded(), y: y0.rounded(),
                      width: x1.rounded() - x0.rounded(),
                      height: y1.rounded() - y0.rounded())
    }

    private func color(for ink: PixelBuffer.Ink) -> Color {
        switch ink {
        case .clear: .clear
        case .body: bodyTint ?? inkOverrides[.body] ?? Palette.body
        // Eye and mouth accept costume overrides too: a white shell swallows
        // a white mouth, and the Matrix look wants terminal-green eyes.
        case .eye: inkOverrides[.eye] ?? Palette.ink
        case .mouth: inkOverrides[.mouth] ?? Palette.white
        case .screenDark: Palette.screenDark
        case .screenLight: Palette.screenLight
        case .green: Palette.green
        case .yellow: Palette.yellow
        case .pink: Palette.pink
        case .steel: Palette.steel
        case .flame: Palette.flame
        case .flameCore: Palette.flameCore
        case .ember: Palette.ember
        case .paper: Palette.kraft
        // A costume slot with no wardrobe behind it should be impossible; the
        // shell colour keeps it invisible-in-practice rather than magenta-loud.
        case .costumeA: inkOverrides[.costumeA] ?? Palette.body
        case .costumeB: inkOverrides[.costumeB] ?? Palette.body
        case .costumeC: inkOverrides[.costumeC] ?? Palette.body
        case .bodyHot: Palette.bodyHot
        case .bodyEmber: Palette.bodyEmber
        case .alert: Palette.alert
        // Deliberately the SOFT slate, not `Palette.slate`: the sizzle's pixel
        // cards ground this badge on `Palette.slate` itself, so a near-black
        // field would be 1.05:1 against its own card and the tile would vanish.
        case .slate: Palette.slateSoft
        // Override-consulting on purpose: "one step below the shell" is a
        // relation, not a colour, and three of the four solo costumes recolour
        // the shell itself — a fixed darker terracotta would sit LIGHTER than
        // the ninja and Retro Black shells and stain the Gundam's white.
        case .bodyShade: inkOverrides[.bodyShade] ?? Palette.bodyShade
        // Deliberately NOT override-consulting — see the case's own comment.
        case .memeBlack: Palette.ink
        case .shadow: Palette.slate.opacity(0.45)
        case .deck: Color(red: 0.012, green: 0.012, blue: 0.016)
        }
    }
}
