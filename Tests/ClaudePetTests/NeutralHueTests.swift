import Testing
import Foundation
import AppKit
@testable import ClaudePet

/// 🌈 **The neutral wheel.**
///
/// The operator's note was *"remove pink from the rainbow trail, it kind of
/// looks like a pride flag and we want to remain neutral"*, and then, a round
/// later, *"take the magenta out of the body too"*. The ribbon lost its pink by
/// swapping an ink. The body cannot: its colour is generated, so what changes is
/// the RANGE the generator is allowed to reach — folded at the ribbon's own far
/// end rather than clamped there or scaled into it.
///
/// Everything here is measured on the colour that comes OUT, not on the hue that
/// went in, so it catches the shade as well as the shell.
@MainActor
struct NeutralHueTests {

    /// Hue recovered from an RGB triple, so a pin can ask what colour was
    /// actually produced rather than trusting the input.
    private func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        guard high - low > 1e-9 else { return 0 }
        let d = high - low
        let h: Double
        if high == r { h = (g - b) / d } else if high == g { h = 2 + (b - r) / d }
        else { h = 4 + (r - g) / d }
        return h / 6 - floor(h / 6)
    }
    private func hue(_ tint: SpriteTint.Tint) -> Double { hue(tint.r, tint.g, tint.b) }
    private func hue(hex: Int) -> Double {
        hue(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }

    /// 🔎 The ceiling is not a taste number: it is where the ribbon stops.
    /// Derived here from the palette rather than restated, so the two cannot
    /// drift apart silently — if someone re-tunes `Palette.water`, this fails
    /// and the body's range follows the ribbon's, which is the whole claim.
    @Test("The body stops exactly where the ribbon stops")
    func theCeilingIsTheRibbons() {
        #expect(abs(SpriteTint.hueCeiling - hue(hex: 0x7FC6EC)) < 0.001,
                "the ceiling is \(SpriteTint.hueCeiling), the ribbon's last stripe is \(hue(hex: 0x7FC6EC))")
        // …and the ribbon really does end there: every stripe at or below it.
        for ink in CrabRig.trailInks {
            let colour = PixelCanvasView.color(for: ink, bodyTint: nil, inkOverrides: [:])
            guard let components = NSColor(colour).usingColorSpace(.sRGB) else { continue }
            let h = hue(Double(components.redComponent), Double(components.greenComponent),
                        Double(components.blueComponent))
            #expect(h <= SpriteTint.hueCeiling + 0.001,
                    "the ribbon's \(ink) is at hue \(h), past the ceiling the body was held to")
        }
    }

    /// 🔎 A FOLD, NOT A SCALE. `phase * ceiling` would step sky straight back to
    /// red in one frame at every wrap — the banned one-frame change, on a
    /// channel with nowhere to hide it. Continuity at the wrap is the property
    /// that makes the narrowing legal, so it is pinned first.
    @Test("The fold is continuous at the wrap and never leaves the range")
    func theFoldFolds() {
        #expect(SpriteTint.neutralHue(0) == SpriteTint.neutralHue(1),
                "the wheel jumps at the wrap")
        #expect(abs(SpriteTint.neutralHue(0.9999) - SpriteTint.neutralHue(0)) < 0.001,
                "the wheel jumps just before the wrap")
        for step in 0...400 {
            let phase = Double(step) / 100 - 2            // negative phases too
            let h = SpriteTint.neutralHue(phase)
            #expect(h >= 0 && h <= SpriteTint.hueCeiling + 1e-12,
                    "phase \(phase) produced hue \(h), outside the range")
        }
        // Symmetric about the turn, which is what "out and back" means.
        for step in 0...50 {
            let u = Double(step) / 100
            #expect(abs(SpriteTint.neutralHue(u) - SpriteTint.neutralHue(1 - u)) < 1e-12,
                    "the fold is lopsided at \(u)")
        }
        #expect(abs(SpriteTint.neutralHue(0.5) - SpriteTint.hueCeiling) < 1e-12,
                "the turn is not at the ceiling")
        // 🔎 THE PACE WAS NOT QUIETLY LOST. Out and back covers 2 x ceiling per
        // cycle against the full wheel's 1.0, so the colour changes fractionally
        // FASTER than it did — which is why no producer's rate needed touching.
        var travelled = 0.0
        for step in 0..<2000 {
            travelled += abs(SpriteTint.neutralHue(Double(step + 1) / 2000)
                             - SpriteTint.neutralHue(Double(step) / 2000))
        }
        #expect(travelled > 1.0, "a cycle now covers only \(travelled) hue-units, against a wheel's 1.0")
    }

    /// 🔎 THE POINT OF THE WHOLE ROUND: no violet and no magenta reaches him,
    /// from any producer, at any moment of its live range, on the shell OR the
    /// shade. Measured on the produced colour, so it would still catch a
    /// producer that found its way there by some other arithmetic.
    @Test("No producer ever puts a violet or a magenta on him")
    func nothingIsEverViolet() {
        // 🔎 HUE IS NOT A MEANINGFUL AXIS ON A NEAR-GREY, and the first cut of
        // this test forgot it. `towards` mixes in RGB, so a 40% blend of his
        // terracotta toward sky lands on (0.545, 0.571, 0.617) — a slate at
        // TWELVE PER CENT saturation, whose hue coordinate reads 0.605 and whose
        // appearance is grey. Flagging that as "violet" would have forced a
        // change to fix a colour nobody can see is a colour. The gate is
        // therefore saturation-first: below a quarter he is wearing a neutral,
        // and the operator's note was about colours that read.
        func saturation(_ r: Double, _ g: Double, _ b: Double) -> Double {
            let high = max(r, max(g, b)), low = min(r, min(g, b))
            return high > 1e-9 ? (high - low) / high : 0
        }
        func check(_ tint: SpriteTint.Tint?, _ where_: String) {
            guard let tint else { return }
            for (h, sat, part) in [(hue(tint), saturation(tint.r, tint.g, tint.b), "shell"),
                                   (hue(tint.shadeR, tint.shadeG, tint.shadeB),
                                    saturation(tint.shadeR, tint.shadeG, tint.shadeB), "shade")]
            where sat >= 0.25 {
                #expect(!(h > 0.60 && h < 0.99),
                        "\(where_): the \(part) is a \(Int(sat * 100))%-saturated hue \(h) — violet or magenta")
            }
        }
        for step in 0...400 {
            let t = Double(step) / 100
            check(CrabView.rainbowTint(elapsed: t), "rainbow at \(t)")
        }
        for step in 0...1000 {
            let t = Double(step) / 100
            check(CrabView.epicTint(doneT: t), "epic at \(t)")
        }
        // 🔎 THE COMBO IS SCOPED TO WHAT THE RAINBOW CONTRIBUTES, and the first
        // cut of this test was not — it swept every costume at partial score and
        // flagged the SKATER, whose own shell is grape (hue 0.75) and whose own
        // shade is deeper still. That violet is the costume, not the rainbow:
        // `comboTint` mixes OUT of the worn inks precisely so the first rung
        // eases out of grape instead of snapping to terracotta, which is a fix
        // this suite pins elsewhere. A partial mix between a grape crab and a
        // red target passes through violet because the crab is violet, and
        // removing that would mean repainting the Skater, which nobody asked
        // for. What the round is about is the colour the rainbow REACHES, so
        // that is what is pinned: full score, where the target owns the shell,
        // for every costume — and every amount for the bare crab, whose own
        // terracotta is warm and cannot contribute a violet to the mix.
        for step in 0...600 {
            let t = Double(step) / 100
            for costume in Costume.allCases {
                check(CrabView.comboTint(t: t, combo: 1, costume: costume), "combo \(costume) at \(t)")
            }
            for score in [0.2, 0.4, 0.6, 0.8] {
                check(CrabView.comboTint(t: t, combo: score), "bare combo \(score) at \(t)")
            }
        }
        // The disco is dice-gated, so drive its hue expression over its own
        // five-second flash rather than hoping the die lands.
        for step in 0...500 {
            let since = Double(step) / 100
            let rgb = SpriteTint.rgb(hue: SpriteTint.neutralHue(since / 5),
                                     saturation: 0.5, brightness: 0.92)
            check(SpriteTint.towards(rgb, amount: 1), "disco at \(since)")
        }
        // …and the party's backdrop, whose eight wedges used to include one
        // violet and one magenta fanning out behind him in the same frames.
        // Asking `RainbowRays` for the number IT paints, not recomputing the
        // fold here — the first cut of this arm did the latter and was blind:
        // putting the raw wheel back in the backdrop left it green.
        for ray in 0..<RainbowRays.rayCount {
            let h = RainbowRays.hue(ray: ray)
            #expect(h <= SpriteTint.hueCeiling + 1e-12, "ray \(ray) is at hue \(h)")
        }
    }

    /// The companion to the scope note above: at FULL score the target owns the
    /// shell outright, so every costume — the grape Skater included — lands on
    /// the identical colour, and that colour is one of the neutral wheel's.
    @Test("At full score the rainbow owns the shell, whatever he is wearing")
    func fullScoreIsTheSameColourForEveryone() {
        for step in 0...40 {
            let t = Double(step) / 10
            let bare = CrabView.comboTint(t: t, combo: 1)
            #expect(bare != nil)
            guard let bare else { continue }
            for costume in Costume.allCases {
                let worn = CrabView.comboTint(t: t, combo: 1, costume: costume)
                #expect(worn != nil)
                guard let worn else { continue }
                // Near-equal, not equal: `towards` mixes from a different base
                // per costume and lands on the same target by arithmetic that
                // differs in the last bit. A tolerance of a thousandth is far
                // tighter than a cell of colour and far looser than an ULP.
                let apart = abs(worn.r - bare.r) + abs(worn.g - bare.g) + abs(worn.b - bare.b)
                    + abs(worn.shadeR - bare.shadeR) + abs(worn.shadeG - bare.shadeG)
                    + abs(worn.shadeB - bare.shadeB)
                #expect(apart < 0.001,
                        "at full score \(costume) is \(apart) away from the bare crab's colour")
            }
            #expect(!(hue(bare) > 0.60 && hue(bare) < 0.99),
                    "full score reached hue \(hue(bare))")
        }
    }

    /// The narrowing must not have cost him the warm end or the cool end — a
    /// range that never leaves red would satisfy every pin above and be a
    /// disaster.
    @Test("He still gets all the way out to sky and all the way home to red")
    func theRangeIsStillWorthHaving() {
        var lowest = 1.0, highest = 0.0
        for step in 0...600 {
            guard let tint = CrabView.comboTint(t: Double(step) / 100, combo: 1) else { continue }
            let h = hue(tint)
            lowest = min(lowest, h); highest = max(highest, h)
        }
        #expect(lowest < 0.02, "the warmest he gets is hue \(lowest)")
        #expect(highest > SpriteTint.hueCeiling - 0.02, "the coolest he gets is hue \(highest)")
    }
}
