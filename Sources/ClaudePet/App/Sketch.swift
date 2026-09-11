import SwiftUI

/// ✏️ **Your scratch pad. Overwrite it freely.**
///
/// This is the one file in the repo with no rules attached. It is tracked only
/// so a clean checkout compiles; nothing reads it but the sketchpad, nothing
/// ships it, and no test pins a single thing about what it draws.
///
/// Two hooks, because the rig has two drawing planes and they compose as a
/// stack rather than as one surface:
///
/// - **`drawSprite`** works in the sprite plane — the 32×32 indexed ink grid
///   Claw'd himself is drawn on. One cell is the quantum; there are no
///   fractions. Reach for `b.rect`, `b.pixel` and `b.stamp`, and see
///   `HolidayAmbience` for how the shipped layers do it.
/// - **`drawCanvas`** works in the canvas plane — SwiftUI points, for anything
///   that wants to be smoother or larger than a cell. See `PartyGround` and
///   `RainbowRays`.
///
/// Both are called once a frame with `t` in **loop-local seconds**: it starts
/// at nought and wraps at the loop length, so `sin(t)` behaves and nothing has
/// to know what time it is.
///
/// 🔎 The one thing that is actually required: **be pure in `t`.** Same `t`,
/// same picture, every time. The live window and the exported GIF are the same
/// function called with different clocks, so a hook that reads `Date()` or
/// keeps a counter will make the export disagree with the thing you were
/// watching — which is the one bug in here that wastes a whole evening.
enum Sketch {

    /// The sprite plane: 32×32 cells of flat ink.
    static func drawSprite(_ b: inout PixelBuffer, t: Double) {
        // An example, so the hook is never a blank stare. Delete it.
        //
        // A cell that walks a circle, one whole pixel at a time — the grid's
        // own quantum, which is the only motion the no-snap rule exempts.
        let angle = 2 * Double.pi * t
        let x = 16 + Int((cos(angle) * 9).rounded())
        let y = 16 + Int((sin(angle) * 9).rounded())
        b.pixel(x, y, .flame)
        b.pixel(x + 1, y, .flameCore)
    }

    /// The canvas plane: SwiftUI points.
    static func drawCanvas(in context: inout GraphicsContext, size: CGSize, t: Double) {
        _ = (context, size, t)
    }
}
