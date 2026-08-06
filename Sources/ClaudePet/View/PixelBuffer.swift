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
        /// Rocket flame.
        case flame
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

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let px = size.width / Double(PixelBuffer.side)
            for run in buffer.runs() {
                let rect = CGRect(
                    x: Double(run.x) * px,
                    y: Double(run.y) * px,
                    // A hairline of overdraw keeps neighbouring runs from showing
                    // a seam when px lands on a fractional device pixel.
                    width: Double(run.length) * px + 0.5,
                    height: px + 0.5
                )
                context.fill(Path(rect), with: .color(color(for: run.ink)))
            }
        }
    }

    private func color(for ink: PixelBuffer.Ink) -> Color {
        switch ink {
        case .clear: .clear
        case .body: Palette.body
        case .eye: Palette.ink
        case .mouth: Palette.white
        case .screenDark: Palette.screenDark
        case .screenLight: Palette.screenLight
        case .green: Palette.green
        case .yellow: Palette.yellow
        case .pink: Palette.pink
        case .steel: Palette.steel
        case .flame: Palette.flame
        }
    }
}
