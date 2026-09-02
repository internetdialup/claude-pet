import SwiftUI

/// Backgrounds for the marketing renders — never the live app, never the
/// composed in-app scenes.
///
/// The operator's direction after the riff board: the quantised sky competes
/// with the mascot (same cell language, so he dissolves into it); the winning
/// ground is quiet and warm, with the character as the only saturated thing
/// in frame.
/// 🎨 THE SUPER-GRAPHICS PALETTE — the operator's own, locked in from their
/// swatch sheet (2026-09-02): five flat grounds the marketing set composes
/// on. Sampled by eye from the sheet; if the operator hands exact hexes
/// from Figma, correct them HERE and re-render — this enum is the single
/// source, nothing else may restate these values.
enum MarketingPalette {
    static let cream = Color(hex: 0xFCF4E0)
    static let lemon = Color(hex: 0xFBF163)
    static let coral = Color(hex: 0xF45050)
    static let pink = Color(hex: 0xFA8FAB)
    static let grape = Color(hex: 0x9A34F0)
    static let gold = Color(hex: 0xFAD873)
    static let cobalt = Color(hex: 0x2569F2)
    static let sky = Color(hex: 0x2BB9FA)
    /// In the sheet's own order, for anything that deals the set.
    static let all: [Color] = [cream, lemon, coral, pink, grape, gold, cobalt, sky]
}

@MainActor
enum MarketingBackdrop {

    /// Warm white, with pixel stars so subtle you find them rather than see
    /// them.
    ///
    /// The stars are a FIXED table — no dice, no clock — so every render is
    /// byte-identical and nothing can twinkle at a loop seam. They sit a few
    /// percent darker than the ground: visible at a look, invisible at a
    /// glance, which is what "super subtle" costs. Two of them are four-pixel
    /// sparks; the rest are single cells.
    static var warmWhite: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let ground = Color(red: 0.980, green: 0.965, blue: 0.938)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))

            let star = Color(red: 0.925, green: 0.898, blue: 0.850)
            let spark = Color(red: 0.894, green: 0.858, blue: 0.796)
            // Positions in unit space, placed by hand to stay out of the
            // bubble band (top ~0.3) and the crab's centre.
            let cells: [(x: CGFloat, y: CGFloat)] = [
                (0.08, 0.18), (0.22, 0.72), (0.31, 0.42), (0.46, 0.88),
                (0.58, 0.16), (0.71, 0.63), (0.83, 0.34), (0.92, 0.80),
                (0.15, 0.94), (0.66, 0.94), (0.89, 0.12), (0.05, 0.55),
            ]
            for c in cells {
                let r = CGRect(x: (c.x * size.width).rounded(), y: (c.y * size.height).rounded(),
                               width: 3, height: 3)
                context.fill(Path(r), with: .color(star))
            }
            // The two sparks: a plus of four cells.
            for c in [(x: CGFloat(0.76), y: CGFloat(0.22)), (x: 0.12, y: 0.38)] {
                let px = (c.x * size.width).rounded(), py = (c.y * size.height).rounded()
                for (dx, dy) in [(0, -3), (0, 3), (-3, 0), (3, 0), (0, 0)] {
                    context.fill(Path(CGRect(x: px + CGFloat(dx), y: py + CGFloat(dy),
                                             width: 3, height: 3)),
                                 with: .color(spark))
                }
            }
        }
    }
}
