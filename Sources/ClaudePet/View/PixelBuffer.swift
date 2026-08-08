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

    /// Nearest-neighbour shrink, anchored at the feet and centred horizontally.
    ///
    /// Done here rather than with `.scaleEffect` on the view: `CrabView` ends in
    /// `.drawingGroup()`, so a view-level scale resamples a finished bitmap and
    /// softens the deliberately hard pixel edges. Resampling the grid keeps every
    /// cell square.
    func scaled(_ factor: Double) -> PixelBuffer {
        guard factor < 0.999, factor > 0.1 else { return self }
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

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let px = size.width / Double(PixelBuffer.side)
            for run in buffer.runs() {
                let x0 = Double(run.x) * px, x1 = Double(run.x + run.length) * px
                let y0 = Double(run.y) * px, y1 = y0 + px
                let rect: CGRect
                if seamBleed > 0 {
                    rect = CGRect(x: x0, y: y0,
                                  width: x1 - x0 + seamBleed, height: y1 - y0 + seamBleed)
                } else {
                    // No bleed to hide seams with, so snap the edges instead:
                    // neighbouring runs then share an exact boundary and tile
                    // with neither a gap nor a blend. Necessary because a cell
                    // is only a whole number of pixels when the frame happens to
                    // be a multiple of 32.
                    rect = CGRect(x: x0.rounded(), y: y0.rounded(),
                                  width: x1.rounded() - x0.rounded(),
                                  height: y1.rounded() - y0.rounded())
                }
                context.fill(Path(rect), with: .color(color(for: run.ink)))
            }
        }
    }

    private func color(for ink: PixelBuffer.Ink) -> Color {
        switch ink {
        case .clear: .clear
        case .body: bodyTint ?? Palette.body
        case .eye: Palette.ink
        case .mouth: Palette.white
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
        }
    }
}
