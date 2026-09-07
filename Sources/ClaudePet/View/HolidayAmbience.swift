import Foundation

/// The seasons' weather and furniture — pure static draws the rig calls when
/// a pose carries a resolved `Holiday`. Every colour is an existing palette
/// ink; every cell is clear-masked or composited `preservingExisting`, so
/// ambience frames him and never paints over him.
enum HolidayAmbience {

    /// The white costume's snow, extracted verbatim so winter can serve it
    /// to everyone: five columns, per-column speed, `truncatingRemainder`
    /// wrap, sine drift, clear-cell mask. The `.white` case calls this too —
    /// one implementation, byte-identical to the old inline draw.
    static func drawSnow(_ b: inout PixelBuffer, phase: Double) {
        for (column, speed) in [(2, 0.62), (8, 0.9), (14, 0.5), (21, 0.78), (27, 1.05)] {
            let fall = (phase * speed * 5 + Double(column * 3))
                .truncatingRemainder(dividingBy: Double(PixelBuffer.side))
            let drift = Int(sin(phase * 0.8 + Double(column)) * 1.4)
            let x = column + drift, y = Int(fall)
            guard x >= 0, x < PixelBuffer.side, b[x, y] == .clear else { continue }
            b.pixel(x, y, .paper)
        }
    }

    /// 💗 Valentine's hearts, RISING — the snow's arithmetic turned upside
    /// down.
    ///
    /// Snow and leaves fall, so their `y` grows with the phase; hearts go the
    /// other way, because a heart that sinks is a different feeling entirely.
    /// Same five-column spread, same clear-cell mask, same no-dice rule:
    /// weather does not take turns.
    ///
    /// Two sizes, by column parity. A one-cell heart is a dot, and a field of
    /// dots is static; the three-cell one gives the eye something to read as
    /// a shape, and mixing them keeps the field from looking like a grid.
    static func drawHearts(_ b: inout PixelBuffer, phase: Double) {
        for (index, pair) in [(3, 0.5), (10, 0.72), (16, 0.44), (23, 0.63), (29, 0.85)].enumerated() {
            let (column, speed) = pair
            let side = Double(PixelBuffer.side)
            // RISING: subtract, so the field climbs out of the floor.
            let climb = (side - (phase * speed * 4 + Double(column * 5))
                .truncatingRemainder(dividingBy: side))
            let sway = Int(sin(phase * 0.6 + Double(column)) * 1.6)
            let x = column + sway, y = Int(climb)
            guard x >= 2, x < PixelBuffer.side - 2, y >= 1, y < PixelBuffer.side else { continue }
            let ink: PixelBuffer.Ink = index % 2 == 0 ? .alert : .pink
            if index % 2 == 0 {
                // The small one: a single cell, for the far-away hearts.
                guard b[x, y] == .clear else { continue }
                b.pixel(x, y, ink)
            } else {
                // The near one, FIVE wide rather than three.
                //
                // The first cut reused the idle heart's opening shape —
                // `r.r / rrr / .r.` — on the reasoning that the shapes in
                // this app should agree with each other. Rendered and zoomed,
                // it reads as antlers: at three cells the notch between the
                // lobes is a third of the width and dominates. The idle heart
                // gets away with it because it is one cell of a sequence that
                // grows into the full seven-wide heart a beat later, and
                // because it sits against his shell rather than alone in the
                // sky. Five cells is the smallest that unambiguously reads as
                // a heart standing on its own.
                let rows = [
                    [-1, 1],
                    [-2, -1, 0, 1, 2],
                    [-1, 0, 1],
                    [0],
                ]
                for (row, offsets) in rows.enumerated() {
                    for dx in offsets {
                        let px = x + dx, py = y + row - 1
                        guard px >= 0, px < PixelBuffer.side,
                              py >= 0, py < PixelBuffer.side,
                              b[px, py] == .clear else { continue }
                        b.pixel(px, py, ink)
                    }
                }
            }
        }
    }

    /// Autumn leaves for both fall windows: the snow's arithmetic slowed
    /// down and swayed wider — leaves drift, they do not fall — in ember and
    /// gold by column parity. No dice: weather does not take turns.
    static func drawLeaves(_ b: inout PixelBuffer, phase: Double) {
        for (index, pair) in [(3, 0.42), (9, 0.6), (15, 0.36), (22, 0.52), (28, 0.7)].enumerated() {
            let (column, speed) = pair
            let fall = (phase * speed * 5 + Double(column * 3))
                .truncatingRemainder(dividingBy: Double(PixelBuffer.side))
            let drift = Int(sin(phase * 0.6 + Double(column)) * 2.2)
            let x = column + drift, y = Int(fall)
            guard x >= 0, x < PixelBuffer.side, b[x, y] == .clear else { continue }
            b.pixel(x, y, index % 2 == 0 ? .ember : .yellow)
        }
    }

    /// Two little jack-o'-lanterns keeping him company on the floor —
    /// Halloween's ground furniture. Composited LAST and `preservingExisting`
    /// like the patch of sun, so his legs, the bug and the skate lanes all
    /// cut through them: the ordering is the whole reconciliation.
    static func drawFloorPumpkins(_ b: inout PixelBuffer) {
        var scratch = PixelBuffer()
        for x in [2, 27] {
            scratch.stamp([
                ".g.",
                "ooo",
                "oyo",
            ], at: (x: x, y: 28), key: ["g": .green, "o": .ember, "y": .yellow])
        }
        b.composite(scratch, visibility: 1, seed: 765, preservingExisting: true)
    }

    /// 🥚 Easter's floor: an egg at his side, a flower, and tufts of grass.
    ///
    /// The pumpkins' arrangement, re-dressed for spring — ground furniture at
    /// the two flanks, composited `preservingExisting` so it frames him and
    /// never paints over him. The egg stands on the left where a pumpkin
    /// would, a single flower on the right, and grass under both because a
    /// lawn is what makes an egg an Easter egg rather than a breakfast.
    ///
    /// The egg is `.pink` with a `.paper` band — a pattern, because a plain
    /// pink oval three cells wide is a stone.
    static func drawEasterGround(_ b: inout PixelBuffer) {
        var scratch = PixelBuffer()
        // The egg, left flank.
        scratch.stamp([
            ".pp.",
            "pwwp",
            "pppp",
            ".pp.",
        ], at: (x: 1, y: 26), key: ["p": .pink, "w": .paper])
        // The flower, right flank: a yellow face on a green stalk.
        scratch.stamp([
            ".y.",
            "yyy",
            ".g.",
            ".g.",
        ], at: (x: 27, y: 26), key: ["y": .yellow, "g": .green])
        // Grass: blades either side, two heights so it reads as tufts and
        // not as a fence.
        for (x, tall) in [(0, false), (5, true), (6, false), (25, false), (30, true), (31, false)] {
            scratch.pixel(x, 29, .green)
            if tall { scratch.pixel(x, 28, .green) }
        }
        b.composite(scratch, visibility: 1, seed: 766, preservingExisting: true)
    }

    /// A New Year's firework: a paper launch pixel climbing the sky, then
    /// six flecks radiating and dissolving under their own per-fleck seeds
    /// (746–751). The column and palette ride `noise(cycle &* 97 &+ 37)`, so
    /// every burst lands somewhere new. Clear-masked by compositing
    /// `preservingExisting` — the telescope scene draws first and keeps its
    /// own cells, which makes a crab watching fireworks through a telescope
    /// a feature rather than a collision.
    static func drawFireworks(_ b: inout PixelBuffer, progress: Double, cycle: Int) {
        let pick = CrabAnimator.noise(cycle &* 97 &+ 37)
        let column = 6 + Int(pick * 19)                     // 6…24
        if progress < 0.35 {
            let rise = progress / 0.35
            var scratch = PixelBuffer()
            scratch.pixel(column, 8 - Int((rise * 5).rounded()), .paper)
            b.composite(scratch, visibility: 1, seed: 746, preservingExisting: true)
        } else {
            let burst = (progress - 0.35) / 0.65
            let reach = 1 + Int((burst * 3).rounded())
            let inks: [PixelBuffer.Ink] = pick < 0.5
                ? [.yellow, .pink, .screenLight] : [.pink, .screenLight, .yellow]
            for (index, delta) in [(-1, -1), (1, -1), (-1, 1), (1, 1), (0, -1), (0, 1)].enumerated() {
                var scratch = PixelBuffer()
                scratch.pixel(column + delta.0 * reach, 3 + delta.1 * reach,
                              inks[index % inks.count])
                b.composite(scratch, visibility: 1 - burst * burst,
                            seed: 746 + index, preservingExisting: true)
            }
        }
    }
}
