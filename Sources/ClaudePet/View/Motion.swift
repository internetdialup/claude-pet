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
enum SpriteTint {
    /// Claw'd terracotta, `Palette.body`'s 0xCE7B5C, as components.
    static let bodyRGB = (r: 206.0 / 255, g: 123.0 / 255, b: 92.0 / 255)

    /// Hot gold, `Palette.flameCore`'s 0xF7D046, as components — the warm the
    /// afternoon puts on his shell while he stands in it.
    static let goldRGB = (r: 247.0 / 255, g: 208.0 / 255, b: 70.0 / 255)

    /// Plain HSB→RGB, so a generated hue can be mixed without asking AppKit to
    /// introspect a SwiftUI `Color`.
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> (r: Double, g: Double, b: Double) {
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

    /// The body colour pushed toward a target by `amount`. At 0 it *is* the
    /// body colour, which is what lets a tint ease in from nothing and out to
    /// nothing with no seam at either end.
    static func towards(_ target: (r: Double, g: Double, b: Double), amount: Double) -> Color {
        let a = Ease.clamp01(amount)
        return Color(red: bodyRGB.r + (target.r - bodyRGB.r) * a,
                     green: bodyRGB.g + (target.g - bodyRGB.g) * a,
                     blue: bodyRGB.b + (target.b - bodyRGB.b) * a)
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
