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
