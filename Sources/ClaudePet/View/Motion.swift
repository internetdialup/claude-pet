import SwiftUI

/// The easing vocabulary. Everything reactive in the sprite goes through one of
/// these instead of flipping in a single frame: a state change eases in AND
/// eases out, because at desktop-pet scale a one-frame change reads as a glitch,
/// not a decision. The only exempt movements are single-pixel steps — the grid's
/// own quantum — and things that snap in nature, like a blink.
enum Ease {

    @inline(__always)
    static func clamp01(_ u: Double) -> Double { min(1, max(0, u)) }

    /// u²(3−2u): zero slope at both ends, so whatever it drives arrives and
    /// leaves without a corner.
    @inline(__always)
    static func smoothstep(_ u: Double) -> Double {
        let c = clamp01(u)
        return c * c * (3 - 2 * c)
    }

    /// A reaction envelope: rises 0→1 over `attack` from `since`, and after
    /// `endedAt` falls from *wherever it had reached* over `release` — so a
    /// pointer that leaves mid-rise eases back down from that height rather
    /// than jumping to 1 first. Continuous at the handoff by construction.
    static func amount(now: Double, since: Double?, endedAt: Double?,
                       attack: Double = 0.35, release: Double = 0.45) -> Double {
        guard let since, now > since else { return 0 }
        let rise = smoothstep((now - since) / attack)
        guard let endedAt, now > endedAt else { return rise }
        let held = smoothstep((endedAt - since) / attack)
        return held * (1 - smoothstep((now - endedAt) / release))
    }

    /// An eased gate on an oscillating signal: 0 below the threshold, 1 above,
    /// smoothstepped across a band of width `2 * soft` around it. This is the
    /// replacement for every `sin(t * x) > threshold ? a : b` — same rhythm,
    /// no cliff.
    @inline(__always)
    static func gate(_ signal: Double, above threshold: Double = 0, soft: Double = 0.45) -> Double {
        smoothstep((signal - threshold + soft) / (2 * soft))
    }

    /// The eased square wave: sits at 0 or 1 for most of each half-cycle and
    /// smoothsteps the flip. `angle` is in radians, like the `sin` it replaces.
    @inline(__always)
    static func square(_ angle: Double, soft: Double = 0.45) -> Double {
        gate(sin(angle), soft: soft)
    }

    /// A trapezoid over a window: eases in over `edge`, holds 1, eases out over
    /// the final `edge`. Zero outside `0...duration`.
    static func window(_ t: Double, duration: Double, edge: Double) -> Double {
        guard t > 0, t < duration else { return 0 }
        return min(smoothstep(t / edge), smoothstep((duration - t) / edge))
    }

    /// A hit: the asymmetric trapezoid `window` cannot say. Eases up over
    /// `attack`, **holds at exactly 1** for `hold`, eases down over `decay`,
    /// and is zero everywhere outside — so a schedule of these carries its own
    /// frozen sentinel.
    ///
    /// `window` is this shape at leisure, with one `edge` for both sides. Light
    /// does not work that way: it arrives faster than it leaves, and a flash
    /// that fades in as slowly as it fades out never reads as a flash. Both
    /// junctions are still C¹ (smoothstep has zero slope at each end), so the
    /// plateau arrives and leaves without a corner — the no-snap rule bans a
    /// one-frame change, not a fast one.
    @inline(__always)
    static func pulse(_ t: Double, attack: Double, hold: Double, decay: Double) -> Double {
        guard t > 0, t < attack + hold + decay else { return 0 }
        if t < attack { return smoothstep(t / attack) }
        if t < attack + hold { return 1 }
        return 1 - smoothstep((t - attack - hold) / decay)
    }
}

/// Colour arithmetic for the body tint. The palette itself stays flat; the only
/// smooth values in the system are time-domain tint amounts, which is the
/// precedent `rainbowTint` set.
public enum SpriteTint {
    public typealias RGB = (r: Double, g: Double, b: Double)

    /// Claw'd terracotta, `Palette.body`'s 0xCE7B5C, as components.
    public static let bodyRGB: RGB = (r: 206.0 / 255, g: 123.0 / 255, b: 92.0 / 255)

    /// …and the hero shade that cuts through it, `Palette.bodyShade`'s
    /// 0xB8674B. The belly row and the right flank wear it on EVERY frame —
    /// it is a permanent look, not an event — which is why a tint that never
    /// reached it left a dark stripe through every colour the shell took.
    public static let bodyShadeRGB: RGB = (r: 184.0 / 255, g: 103.0 / 255, b: 75.0 / 255)

    /// How much darker that shade is than the shell it cuts through, per
    /// channel — read off the palette's own pair rather than chosen, so a
    /// tinted shade keeps exactly the relationship the flat palette has.
    public static let shadeRatio: RGB = (r: 184.0 / 206, g: 103.0 / 123, b: 75.0 / 92)

    /// A body colour and the shade that goes with it.
    ///
    /// They travel together because they are one decision. `bodyTint` reaches
    /// `.body` and nothing else, so for as long as a tint was a lone `Color`
    /// the shade stayed whatever the palette said — and at full rainbow that
    /// is roughly twenty-six cells of unchanged dark ink cut through a bright
    /// shell. The operator found it; this is the shape that makes it
    /// unrepresentable.
    public struct Tint: Equatable, Sendable {
        public var r, g, b: Double
        public var shadeR, shadeG, shadeB: Double
        public var body: Color { Color(red: r, green: g, blue: b) }
        public var shade: Color { Color(red: shadeR, green: shadeG, blue: shadeB) }
    }

    /// Hot gold, `Palette.flameCore`'s 0xF7D046, as components — the warm the
    /// afternoon puts on his shell while he stands in it.
    public static let goldRGB: RGB = (r: 247.0 / 255, g: 208.0 / 255, b: 70.0 / 255)

    /// 🌈 THE FAR END OF THE NEUTRAL WHEEL: `Palette.water`'s own hue
    /// (0x7FC6EC → 200.9° → 0.5581), which is exactly where `CrabRig.trailInks`
    /// stops.
    ///
    /// The ribbon lost its pink at the operator's call — a red-to-violet ramp
    /// read as a flag they did not intend to fly — and the shell now sweeps the
    /// same extent, endpoint for endpoint. Their six stripes measure 0.0000,
    /// 0.0595, 0.1157, 0.3567, 0.4867 and this; the ink that was dropped,
    /// `Palette.pink`, is 0.9365 and is now unreachable by construction.
    public static let hueCeiling = 0.558

    /// A 0…1 phase mapped onto that extent, OUT AND BACK.
    ///
    /// **A fold, not a scale and not a clamp, and that is the whole design.**
    /// `phase * hueCeiling` would step from sky straight back to red in a single
    /// frame at every wrap — a full-saturation jump on a smooth channel, which
    /// is the one-frame change banned at the top of this file. There is nowhere
    /// to hide it either: the wrap lands mid-party for `rainbowTint`, mid-finale
    /// for `epicTint`, and every two seconds for `comboTint`, whose amount is
    /// the combo score and sits near 1 for a whole nineteen-second ride. A clamp
    /// is no better — it parks him on one colour for a third of every cycle.
    ///
    /// The fold is continuous at the wrap by construction, `f(0) == f(1) == 0`,
    /// and it arrives at and leaves every seam on RED — the hue nearest his own
    /// terracotta — so the turn is also the least visible instant in the cycle.
    /// It costs a corner in hue velocity and no discontinuity in hue, and
    /// `Ease.pulse` already records the standard: the rule bans a one-frame
    /// change, not a fast one.
    ///
    /// The pace needs no compensating. Out and back covers `2 * hueCeiling` =
    /// 1.116 hue-units per cycle against the full wheel's 1.000, so the colour
    /// changes fractionally faster than it did, not slower.
    ///
    /// `phase - floor(phase)`, never `truncatingRemainder`: that one goes
    /// negative for a negative phase and would fold the wrong way.
    public static func neutralHue(_ phase: Double) -> Double {
        let u = phase - floor(phase)
        return hueCeiling * (1 - abs(2 * u - 1))
    }

    /// Plain HSB→RGB, so a generated hue can be mixed without asking AppKit to
    /// introspect a SwiftUI `Color`.
    ///
    /// Deliberately NOT folded in here. Narrowing inside the converter would be
    /// one edit instead of five, and it would make a function whose name and doc
    /// promise plain HSB quietly lie to every future caller. The fold is a named
    /// helper beside it instead.
    public static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let h = (hue - floor(hue)) * 6
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch i {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    /// The body colour pushed toward a target by `amount`, and the shade
    /// pushed the same distance toward that target darkened.
    ///
    /// At 0 it *is* the base, which is what lets a tint ease in from nothing
    /// and out to nothing with no seam at either end. That claim used to be
    /// true only for the bare crab: the base was hard-wired to terracotta, so
    /// the instant a tint touched a COSTUMED crab his shell stepped from the
    /// costume's colour to Claw'd's own in a single frame — grape to
    /// terracotta, before any colour was visible, in a codebase whose first
    /// law bans one-frame changes. Passing the worn costume's own inks as
    /// `from`/`shadeFrom` is what makes the doc comment true for everyone.
    public static func towards(_ target: RGB, amount: Double,
                        from base: RGB = bodyRGB,
                        shadeFrom: RGB = bodyShadeRGB) -> Tint {
        let a = Ease.clamp01(amount)
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * a }
        return Tint(r: mix(base.r, target.r),
                    g: mix(base.g, target.g),
                    b: mix(base.b, target.b),
                    shadeR: mix(shadeFrom.r, target.r * shadeRatio.r),
                    shadeG: mix(shadeFrom.g, target.g * shadeRatio.g),
                    shadeB: mix(shadeFrom.b, target.b * shadeRatio.b))
    }
}

extension CrabPose {
    /// Interpolates two poses. Numeric channels lerp — Int channels round
    /// through whole pixels, so they *step*, which is the pixel aesthetic; the
    /// ban is on whole-pose pops, not on the grid's quantum. Discrete channels
    /// switch at the midpoint. A prop that differs between the two poses keeps
    /// the outgoing one alive as a dissolving ghost.
    static func blend(from: CrabPose, to: CrabPose, u: Double) -> CrabPose {
        guard u < 1 else { return to }
        guard u > 0 else { return from }
        var out = to

        func lerp(_ a: Int, _ b: Int) -> Int {
            Int((Double(a) + (Double(b) - Double(a)) * u).rounded())
        }
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * u }

        out.bob = lerp(from.bob, to.bob)
        out.lean = lerp(from.lean, to.lean)
        out.tilt = lerp(from.tilt, to.tilt)
        out.gazeX = lerp(from.gazeX, to.gazeX)
        out.gazeY = lerp(from.gazeY, to.gazeY)
        out.squash = lerp(from.squash, to.squash)
        out.blink = lerp(from.blink, to.blink)
        out.armLeft = lerp(from.armLeft, to.armLeft)
        out.armRight = lerp(from.armRight, to.armRight)
        out.legAmplitude = lerp(from.legAmplitude, to.legAmplitude)
        out.scale = lerp(from.scale, to.scale)
        out.heat = lerp(from.heat, to.heat)
        out.stargaze = lerp(from.stargaze, to.stargaze)
        out.sunPatch = lerp(from.sunPatch, to.sunPatch)
        out.deckUnderfoot = lerp(from.deckUnderfoot, to.deckUnderfoot)
        out.combo = lerp(from.combo, to.combo)
        out.ledge = lerp(from.ledge, to.ledge)

        // `torsoTurn` is an angle too, and it IS lerped: the trick that owns
        // it dies the moment a mood changes, and a six-wide pillar snapping
        // to a twenty-wide face is the whole-pose pop this function exists to
        // remove. The short way round — 0.7 → 0 finishes forward to 1.0,
        // which renders as rest; 0.3 → 0 unwinds — so no blend ever whirls
        // him backwards through most of a turn. The endpoint guards above
        // still return `from` and `to` exactly.
        let turnTarget = to.torsoTurn + (from.torsoTurn - to.torsoTurn).rounded()
        out.torsoTurn = lerp(from.torsoTurn, turnTarget)

        // `legPhase` is an angle; averaging two unrelated phases produces a
        // third, unrelated one. The incoming pose owns the walk.

        if u < 0.5 {
            out.eyes = from.eyes
            out.mouth = from.mouth
            out.winkEye = from.winkEye
            out.lidsLowered = from.lidsLowered
        }

        if from.prop != to.prop {
            out.propVisibility = min(out.propVisibility, Ease.smoothstep(u))
            out.ghostProp = from.prop
            out.ghostPropPhase = from.propPhase
            out.ghostPropVisibility = max(from.ghostPropVisibility * (1 - u),
                                          1 - Ease.smoothstep(u))
        }
        return out
    }
}
