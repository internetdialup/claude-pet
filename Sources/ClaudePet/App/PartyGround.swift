import SwiftUI

/// 🎉 **Party central — the room joining in behind the grind.**
///
/// The operator asked for the trail clip "with the bg pulsating rainbow mode…
/// maybe the ledge has a gradient shimmer… just full on party central, with the
/// heart flutter mechanics in the bg."
///
/// Everything here is a pure function of reel time, drawn in canvas points
/// BEHIND the sprite. Nothing touches `PixelBuffer`, no ink is appended, and no
/// pose channel is borrowed — so the trick underneath renders exactly as it does
/// in the plain cut, and the A/B stays an A/B.
///
/// ---
///
/// 🔎 **HUE CANNOT SEPARATE HIM FROM THIS, so value and saturation do.**
///
/// The obvious idea — put the backdrop on the opposite side of the rainbow from
/// his shell — does not work, and it is worth writing down why so nobody tries
/// it again. `SpriteTint.neutralHue` is a TRIANGLE fold, not a ramp. Offsetting
/// a triangle by half a period crosses the original at both quarter points:
/// `neutralHue(0.25)` and `neutralHue(0.75)` are the same number, 0.279. His
/// shell sweeps that fold four times across this clip, so a hue-matched backdrop
/// would land on his exact colour EIGHT times, and on those frames he is a
/// coloured shape on a same-coloured field.
///
/// So the separation is chroma and value, which have no such crossing:
///
/// | layer | luminance | chroma |
/// |---|---|---|
/// | the plate and the rings | ≥ 0.75 | ≤ 0.28 |
/// | the hearts | ≥ 0.80 | ≤ 0.15 |
/// | HIS SHELL | 0.35 – 0.90 | **0.85** |
/// | his eyes, his deck | ≈ 0 | — |
///
/// He is the only saturated thing in frame and the only thing carrying a dark
/// ink. That is `MarketingBackdrop`'s own recorded ruling, and it is what makes
/// ten moving layers survivable.
@MainActor
enum PartyGround {

    // MARK: - The ceiling

    /// 🔎 The law is a RATIO, with an absolute as a backstop — and the reason
    /// is that cream is not neutral. `MarketingPalette.cream` is 0xFCF4E0, which
    /// is already **0.111 chroma** on its own, so an absolute ceiling of 0.20
    /// leaves nine hundredths of headroom and would force the plate down to a
    /// mix of 0.11, which is very nearly invisible. The first cut of this file
    /// declared 0.20 anyway, lifted from a design note without checking what the
    /// plate was starting from; the pins caught it at 0.26.
    ///
    /// What actually keeps him legible is that he is MUCH more saturated than
    /// the room, not that the room is under some particular number. His shell
    /// runs at 0.85. A backdrop at a third of that or less is the hierarchy.
    nonisolated static let chromaRatio = 3.0
    nonisolated static let chromaCeiling = 0.28
    nonisolated static let valueFloor = 0.75

    /// Cream, as components, so a backdrop colour can be mixed toward a hue
    /// without asking AppKit to introspect a `Color`.
    nonisolated static let creamRGB: SpriteTint.RGB =
        (r: 252.0 / 255, g: 244.0 / 255, b: 224.0 / 255)

    // MARK: - The plate

    /// 🔎 **THE PULSE IS A HOLD, NOT A SLIDE.** The hue steps on the beat and
    /// eases across the last breath of it, rather than sweeping continuously.
    ///
    /// Three reasons, in order of force. A GIF's colour table is GLOBAL across
    /// every frame and holds 256 entries; `comboTint` already regenerates
    /// `.body` and `.bodyShade` from a continuous hue on all hundred and sixty
    /// frames, so the shell alone is asking for up to three hundred and twenty
    /// before the backdrop spends anything. A plate that recolours every pixel
    /// every frame also defeats the disposal-1 delta coding `isOpaque: true`
    /// buys — measured at 3.7–4.1× in this repo. And a whole-frame brightness
    /// cycle at twenty frames a second is a strobe, which is why the literal
    /// reading of "pulsating" was put back to the operator rather than built.
    nonisolated static let plateAmount = 0.20
    nonisolated static let plateEase = 0.15

    /// The plate's hue at a reel instant.
    ///
    /// 🔎 **THE `+ 0.5` IS NOT A COMPLEMENT, and the first draft of this comment
    /// claimed it was.** A half-fold offset would be the widest hue separation
    /// available if the fold were a ramp — but it is a TRIANGLE, so offsetting
    /// by half a period crosses the original at both quarter points. The plate
    /// and the shell genuinely do share a hue at moments in this clip; a pin
    /// written to assert otherwise measured a separation of exactly zero.
    ///
    /// It is kept because it still spreads them apart most of the time, and
    /// because the separation that actually matters is chroma, not hue: even on
    /// the frames they share a hue, he is three times more saturated than the
    /// room and is the only thing in frame carrying a dark ink.
    ///
    /// The `0.25` step is doing real work though: it settles the plate on only
    /// THREE colours — sky, green and red — so it never HOLDS yellow or flame,
    /// which are the ribbon's two brightest stripes and the two it could least
    /// afford to sit behind. It transits them for a breath on the eased
    /// crossings, which is a sixth of a beat and reads as a change rather than
    /// as a colour.
    nonisolated static func plateHue(_ t: Double) -> Double {
        let beat = floor(t / SkateDemo.beat)
        let into = t - beat * SkateDemo.beat
        let here = SpriteTint.neutralHue(beat * 0.25 + 0.5)
        let next = SpriteTint.neutralHue((beat + 1) * 0.25 + 0.5)
        let u = Ease.smoothstep((into - (SkateDemo.beat - plateEase)) / plateEase)
        return here + (next - here) * u
    }

    nonisolated static func plateRGB(_ t: Double, party: Double) -> SpriteTint.RGB {
        let target = SpriteTint.rgb(hue: plateHue(t), saturation: 0.85, brightness: 1.0)
        let a = plateAmount * Ease.clamp01(party)
        return (r: creamRGB.r + (target.r - creamRGB.r) * a,
                g: creamRGB.g + (target.g - creamRGB.g) * a,
                b: creamRGB.b + (target.b - creamRGB.b) * a)
    }

    // MARK: - The rings

    /// 🔎 **THE RINGS ARE THE PULSE, and their weight is their THICKNESS.**
    ///
    /// A ring born every half second — one a beat at 120, five alive at once —
    /// expanding out of a hub on the ledge's steel line under his tail truck, so
    /// the pulse leaves the trick rather than decorating it.
    ///
    /// Twenty cells a second is not taste: at the GIF's twenty frames a second
    /// that is EXACTLY one cell per frame, a perfectly even cadence at the rate
    /// the operator actually scrubs. And a ring's apparent weight rides its
    /// thickness — one cell, two, three, two, one — because a whole-pixel step
    /// is the grid's own quantum and the one motion the no-snap rule exempts. A
    /// flat band changing brightness instead would be precisely the one-frame
    /// change the rule bans.
    nonisolated static let ringPeriod = 0.5
    nonisolated static let ringSpeed = 20.0
    nonisolated static let ringLife = 2.5
    nonisolated static let ringAmount = 0.16

    /// A ring's thickness in cells for its age, or nought if it is not drawn.
    nonisolated static func ringThickness(radius: Int) -> Int {
        switch radius {
        case ..<3: 0            // born inside his own silhouette
        case 3..<9: 1
        case 9..<20: 2
        case 20..<34: 3
        case 34..<44: 2
        default: 1
        }
    }

    /// Every ring alive at a reel instant, as (radius in cells, thickness, hue).
    nonisolated static func rings(_ t: Double) -> [(radius: Int, thickness: Int, hue: Double)] {
        var out: [(Int, Int, Double)] = []
        let newest = Int(floor(t / ringPeriod))
        guard newest >= 0 else { return [] }
        for n in max(0, newest - 5)...newest {
            let age = t - Double(n) * ringPeriod
            guard age >= 0, age < ringLife else { continue }
            let radius = Int((ringSpeed * age).rounded())
            let thickness = ringThickness(radius: radius)
            guard thickness > 0 else { continue }
            out.append((radius, thickness, RainbowRays.hue(ray: n % RainbowRays.rayCount)))
        }
        return out
    }

    // MARK: - The hearts

    /// 🔎 **VIEW-SIDE, and the rig's own hearts were not available.**
    ///
    /// `HolidayAmbience.drawHearts` rides `pose.propPhase`, and `propPhase` is
    /// fully load-bearing through the back smith — it is the nose's pitch across
    /// the grind and the board's rotation across the kickflip. Borrowing it for
    /// hearts would destroy the trick. So these are drawn in canvas points at a
    /// coarser quantum than a sprite cell, which is also what makes them read as
    /// far away rather than as sprite furniture.
    ///
    /// The columns are the outer thirds only. The middle 40% is the widest span
    /// his body takes at any of the three magnifications, and a glyph field that
    /// keeps its columns off the subject is the same reservation `heartColumns`
    /// already makes around the service glyph.
    nonisolated static let heartColumns = [0.06, 0.15, 0.24, 0.76, 0.85, 0.94]
    nonisolated static let heartOpacity = 0.13
    nonisolated static let heartRise = 0.34
    nonisolated static let heartPeriod = 0.55

    /// The hearts alive at a reel instant, as (x fraction, y fraction, scale).
    nonisolated static func hearts(_ t: Double) -> [(x: Double, y: Double, size: Double)] {
        var out: [(Double, Double, Double)] = []
        let newest = Int(floor(t / heartPeriod))
        guard newest >= 0 else { return [] }
        for n in max(0, newest - 6)...newest {
            let age = t - Double(n) * heartPeriod
            let life = 1.0 / heartRise
            guard age >= 0, age < life else { continue }
            let u = age / life
            let column = heartColumns[abs(n &* 7 &+ 3) % heartColumns.count]
            // One held sway across the middle of the flight — the shape
            // `drawIdleHeart` uses, so the two heart systems drift alike.
            let sway = (u > 0.35 && u < 0.7) ? 0.012 : 0
            out.append((column + sway, 1.0 - u, n % 2 == 0 ? 1.0 : 0.6))
        }
        return out
    }

    // MARK: - The draw

    /// The whole backdrop, pure in `t`. `party` is the envelope that lets the
    /// layers take turns — at its floor through the grind, full in the finale.
    static func draw(in context: inout GraphicsContext, size: CGSize,
                     t: Double, party: Double, cell: CGFloat) {
        let plate = plateRGB(t, party: party)
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: plate.r, green: plate.g, blue: plate.b)))
        guard party > 0.001 else { return }

        // The rings, out of a hub on the ledge's line under his tail truck.
        let hub = CGPoint(x: (size.width / 2).rounded(),
                          y: (size.height / 2 + cell * 8).rounded())
        for ring in rings(t) {
            let target = SpriteTint.rgb(hue: ring.hue, saturation: 0.80, brightness: 0.90)
            let a = ringAmount * party
            let colour = Color(red: creamRGB.r + (target.r - creamRGB.r) * a,
                               green: creamRGB.g + (target.g - creamRGB.g) * a,
                               blue: creamRGB.b + (target.b - creamRGB.b) * a)
            let half = CGFloat(ring.radius) * cell
            let thick = CGFloat(ring.thickness) * cell
            let outer = CGRect(x: hub.x - half, y: hub.y - half, width: half * 2, height: half * 2)
            var path = Path(outer)
            path.addPath(Path(outer.insetBy(dx: thick, dy: thick)))
            context.fill(path, with: .color(colour), style: FillStyle(eoFill: true))
        }

        // …and the hearts, in front of the rings and behind everything else.
        for heart in hearts(t) {
            let w = cell * 2 * heart.size
            let x = (size.width * heart.x).rounded()
            let y = (size.height * heart.y).rounded()
            var path = Path()
            path.addEllipse(in: CGRect(x: x - w, y: y - w / 2, width: w, height: w))
            path.addEllipse(in: CGRect(x: x, y: y - w / 2, width: w, height: w))
            path.move(to: CGPoint(x: x - w, y: y + w / 4))
            path.addLine(to: CGPoint(x: x + w, y: y + w / 4))
            path.addLine(to: CGPoint(x: x, y: y + w * 1.4))
            path.closeSubpath()
            context.fill(path, with: .color(Palette.alert.opacity(heartOpacity * party)))
        }
    }
}
