import Foundation
import CoreGraphics

/// Every animatable part of Claw'd, in whole sprite pixels.
///
/// Claw'd's silhouette is a rectangle with four stubby legs and a nub on each
/// side. There is very little to move, which is the point: the character reads
/// from a handful of pixels, so the animation has to be legible at that scale —
/// a one-pixel bob, an eye that blinks to a single row, arms that go up.
public struct CrabPose: Sendable, Equatable {
    /// Whole-pixel vertical offset of the whole body. Negative is up.
    public var bob: Int = 0
    /// Whole-pixel horizontal lean.
    public var lean: Int = 0

    /// 0 = eyes open (3×3 squares), 1 = shut (a single row).
    public var blink: Double = 0
    /// Which single eye is closed. Separate from `blink`, which is one scalar
    /// consumed for both eyes at once and so cannot express a wink.
    public var winkEye: EyeSide = .none
    public enum EyeSide: Sendable { case none, left, right }
    /// Eye shape. `.determined` carves the inner-top corner into a focused slant.
    public var eyes: EyeStyle = .round
    public enum EyeStyle: Sendable { case round, determined, wide }
    /// Whole-pixel vertical offset applied to the eyes in opposite directions —
    /// a head tilt, on a grid that cannot rotate.
    public var tilt: Int = 0
    /// Eye offset in whole pixels.
    public var gazeX: Int = 0
    public var gazeY: Int = 0

    /// 0 = arm nub at rest on the body's side, 1 = arm raised straight up.
    public var armLeft: Double = 0
    public var armRight: Double = 0

    /// Walk cycle phase, and how much the legs actually move.
    public var legPhase: Double = 0
    public var legAmplitude: Double = 0

    public var mouth: Mouth = .smile
    public enum Mouth: Sendable { case smile, flat, open, none }

    /// Forces the eyes open even in the sleeping pose. Set when the pointer is
    /// on him: a pet you poke should stir, not keep snoring.
    public var asleepOverride: Bool = false

    /// Landing squash: the body draws one row shorter and one column wider per
    /// unit, so a jump lands with weight instead of stopping dead.
    public var squash: Int = 0
    /// Whole-body scale for the click reaction. 1 = full size. Never above 1:
    /// at the largest pixel size the sprite already fills its window.
    public var scale: Double = 1

    /// The prop drawn with Claw'd. Straight from the sticker set — he is almost
    /// always pictured *with* something.
    public var prop: Prop = .none
    public enum Prop: String, Sendable, CaseIterable {
        case none
        // World props: drawn at a fixed spot in the frame.
        case sparkles, terminal, check, bang, zzz, servers, balloon, plan
        // Worn props: drawn on the body, and must travel with `bob` and `lean`.
        case hardHat, phone, fire, glasses

        var isWorn: Bool {
            switch self {
            case .hardHat, .phone, .fire, .glasses: true
            default: false
            }
        }

        /// The props Claw'd picks between while a tool is running.
        static let working: [Prop] = [.terminal, .hardHat, .servers, .phone, .fire, .glasses]
    }

    /// Drives the prop's own animation (scrolling code, blinking cursor,
    /// drifting z's, flickering flame).
    public var propPhase: Double = 0

    /// How much of the prop is present, 0…1. Below 1 the prop renders as a
    /// deterministic pixel dissolve — an indexed grid has no alpha to fade.
    public var propVisibility: Double = 1
    /// The outgoing prop during a swap or a mood blend, dissolving away.
    public var ghostProp: Prop = .none
    public var ghostPropPhase: Double = 0
    public var ghostPropVisibility: Double = 0

    /// Fire-state body heat, 0…1, and the cascade's own clock. Inert until a
    /// pose sets them; the rig repaints body rows in banded heat inks.
    public var heat: Double = 0
    public var heatPhase: Double = 0
}

extension CrabPose.Prop {
    /// A dissolve seed that is stable across runs — `String.hashValue` is
    /// per-process randomised, which would re-deal the dissolve every launch.
    var stableSeed: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Rasterises a `CrabPose` into a `PixelBuffer`.
public enum CrabRig {
    // Claw'd's proportions on the 32×32 grid, measured off the sticker art:
    // a wide body, eyes high and far apart, four legs with a wide centre gap.
    // Wider than tall, with a wide gap between the inner pair of legs and thin
    // nubs for arms. Getting this ratio wrong is what made the first attempt
    // read as a cat rather than as Claw'd.
    private static let bodyX = 6
    private static let bodyW = 20
    private static let bodyY = 10
    private static let bodyH = 11

    private static let legTop = 21
    private static let legH = 4
    private static let legW = 2
    private static let legX = [7, 11, 20, 24]

    private static let armW = 2
    private static let armH = 3
    private static let armY = 14

    private static let eyeSize = 3
    private static let eyeY = 13
    private static let eyeLeftX = 10
    private static let eyeRightX = 19

    public static func render(_ pose: CrabPose) -> PixelBuffer {
        var buffer = PixelBuffer()

        let dx = pose.lean
        let dy = pose.bob

        // Behind the body. The flame dissolves with its prop's visibility, so a
        // prop swap away from fire cannot vanish the burst in one frame.
        firePass(&buffer, pose: pose, dx: dx, dy: dy)

        drawLegs(&buffer, dx: dx, dy: dy, pose: pose)
        drawArms(&buffer, dx: dx, dy: dy, pose: pose)

        // Squash widens and shortens the body, keeping its feet on the ground.
        let squash = max(0, pose.squash)
        buffer.rect(bodyX + dx - squash, bodyY + dy + squash,
                    bodyW + squash * 2, bodyH - squash, .body)

        drawFace(&buffer, dx: dx, dy: dy, pose: pose)

        // Ghost first, so an incoming prop paints over an outgoing one where
        // they overlap.
        propPass(&buffer, pose: pose, prop: pose.ghostProp,
                 phase: pose.ghostPropPhase, visibility: pose.ghostPropVisibility,
                 dx: dx, dy: dy)
        propPass(&buffer, pose: pose, prop: pose.prop,
                 phase: pose.propPhase, visibility: pose.propVisibility,
                 dx: dx, dy: dy)

        // Applied last so props shrink with him rather than floating free.
        return pose.scale < 0.999 ? buffer.scaled(pose.scale) : buffer
    }

    /// The behind-the-body flame layer for whichever of the live and ghost
    /// props is `.fire`, at its own visibility.
    private static func firePass(_ b: inout PixelBuffer, pose: CrabPose, dx: Int, dy: Int) {
        func layer(phase: Double, visibility: Double) {
            guard visibility > 0.001 else { return }
            if visibility > 0.999 {
                drawFire(&b, dx: dx, dy: dy, phase: phase)
            } else {
                var scratch = PixelBuffer()
                drawFire(&scratch, dx: dx, dy: dy, phase: phase)
                b.composite(scratch, visibility: visibility, seed: CrabPose.Prop.fire.stableSeed)
            }
        }
        if pose.ghostProp == .fire { layer(phase: pose.ghostPropPhase, visibility: pose.ghostPropVisibility) }
        if pose.prop == .fire { layer(phase: pose.propPhase, visibility: pose.propVisibility) }
    }

    /// One prop at a given visibility. Full visibility draws straight into the
    /// buffer — byte-identical to the pre-dissolve renderer; anything less
    /// renders to a scratch buffer and composites as a stable pixel dissolve.
    private static func propPass(_ b: inout PixelBuffer, pose: CrabPose, prop: CrabPose.Prop,
                                 phase: Double, visibility: Double, dx: Int, dy: Int) {
        guard prop != .none, visibility > 0.001 else { return }
        var proxy = pose
        proxy.prop = prop
        proxy.propPhase = phase
        if visibility > 0.999 {
            drawProp(&b, dx: dx, dy: dy, pose: proxy)
        } else {
            var scratch = PixelBuffer()
            drawProp(&scratch, dx: dx, dy: dy, pose: proxy)
            b.composite(scratch, visibility: visibility, seed: prop.stableSeed)
        }
    }

    // MARK: - Legs

    private static func drawLegs(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        for (index, x) in legX.enumerated() {
            // Alternating pairs, so the scuttle reads as a gait rather than a jitter.
            let swing = sin(pose.legPhase + Double(index) * .pi / 2) * pose.legAmplitude
            let lift = Int(swing.rounded())
            b.rect(x + dx, legTop + dy - min(0, lift), legW, legH - abs(lift), .body)
        }
    }

    // MARK: - Arms

    /// At rest the arm is a short nub on the body's side. Raised, it becomes a
    /// narrower vertical bar rising above the shoulder — the "arms up" pose from
    /// the sticker set.
    private static func drawArms(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        drawArm(&b, lift: pose.armLeft, isLeft: true, dx: dx, dy: dy)
        drawArm(&b, lift: pose.armRight, isLeft: false, dx: dx, dy: dy)
    }

    private static func drawArm(_ b: inout PixelBuffer, lift: Double, isLeft: Bool, dx: Int, dy: Int) {
        let clamped = max(0, min(1, lift))
        let x = (isLeft ? bodyX - armW : bodyX + bodyW) + dx

        // The nub always stays put at the body's side; raising grows a bar
        // upward from it. Moving the whole nub instead made the arms detach and
        // read as ears poking off the top corners.
        b.rect(x, armY + dy, armW, armH, .body)

        let reach = Int((clamped * 6).rounded())
        if reach > 0 {
            // Stepped one pixel further out. Flush against the body, a raised
            // arm merges into the top corner and the whole silhouette reads as
            // a cat with ears; the step keeps it reading as a raised arm.
            let outward = isLeft ? x - 1 : x + 1
            b.rect(outward, armY + dy - reach, armW, reach, .body)
        }
    }

    // MARK: - Face

    private static func drawFace(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        let eyeTop = eyeY + dy + pose.gazeY
        // Tilt raises one eye and drops the other. The grid cannot rotate, so a
        // head tilt is expressed entirely in the face.
        for (side, baseX) in [(CrabPose.EyeSide.left, eyeLeftX), (.right, eyeRightX)] {
            let x = baseX + dx + pose.gazeX
            let top = eyeTop + (side == .left ? -pose.tilt : pose.tilt)

            // A wink is checked independently of `blink`, and deliberately not
            // gated on `asleepOverride` — the hover greeting sets that flag on
            // every frame, so routing a wink through `blink` renders two open
            // eyes and nothing else.
            let shut = (pose.blink > 0.5 && !pose.asleepOverride) || pose.winkEye == side
            guard !shut else {
                b.rect(x, top + 1, eyeSize, 1, .eye)
                continue
            }

            switch pose.eyes {
            case .round:
                b.rect(x, top, eyeSize, eyeSize, .eye)
            case .wide:
                // One row taller, for the expectant "well?" of the nudge.
                b.rect(x, top - 1, eyeSize, eyeSize + 1, .eye)
            case .determined:
                // Carve the inner-top corner so the brows slant toward the nose.
                // drawFace runs after the body, so painting `.body` over a corner
                // is a clean erase — cutting the OUTER corners instead would read
                // as worried rather than focused.
                b.rect(x, top, eyeSize, eyeSize, .eye)
                b.pixel(side == .left ? x + eyeSize - 1 : x, top, .body)
            }
        }

        let mouthY = 17 + dy
        let centre = bodyX + bodyW / 2 + dx
        switch pose.mouth {
        case .none:
            break
        case .flat:
            b.rect(centre - 2, mouthY, 4, 1, .mouth)
        case .smile:
            // A shallow bowl: wide bottom row with the ends stepping up.
            b.rect(centre - 2, mouthY + 1, 5, 1, .mouth)
            b.pixel(centre - 3, mouthY, .mouth)
            b.pixel(centre + 3, mouthY, .mouth)
        case .open:
            // Small — a wide white block reads as bared teeth, not delight.
            b.rect(centre - 1, mouthY, 3, 2, .mouth)
        }
    }

    // MARK: - Props
    //
    // Claw'd in the official art is nearly always holding or standing next to
    // something. Reusing that vocabulary is what makes each state instantly
    // readable at dock size.


    private static func drawProp(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        let phase = pose.propPhase
        switch pose.prop {
        case .none:
            break
        case .fire:
            // The blaze itself is drawn behind him; only its sparks come forward.
            drawSparks(&b, dx: dx, dy: dy, phase: phase)

        case .sparkles:
            // Three sparkles pulsing out of phase above his head.
            let positions = [(3, 5), (27, 3), (25, 9)]
            for (index, position) in positions.enumerated() {
                let p = phase + Double(index) * 2.1
                guard sin(p) > -0.2 else { continue }
                b.pixel(position.0, position.1, .yellow)
                if sin(p) > 0.6 {
                    b.pixel(position.0 - 1, position.1, .yellow)
                    b.pixel(position.0 + 1, position.1, .yellow)
                    b.pixel(position.0, position.1 - 1, .yellow)
                    b.pixel(position.0, position.1 + 1, .yellow)
                }
            }

        case .terminal:
            drawTerminal(&b, dx: dx, dy: dy, phase: phase)

        case .check:
            let key: [Character: PixelBuffer.Ink] = ["g": .green, "w": .mouth]
            b.stamp([
                ".gggg.",
                "gggggg",
                "ggg.wg",
                "gw.wgg",
                "g.wggg",
                ".gggg.",
            ], at: (x: 0, y: 1), key: key)

        case .bang:
            b.rect(15, 1, 2, 5, .pink)
            b.rect(15, 7, 2, 2, .pink)

        case .zzz:
            let key: [Character: PixelBuffer.Ink] = ["z": .screenLight]
            let drift = Int((sin(phase) * 1.5).rounded())
            b.stamp(["zzz", "..z", ".z.", "zzz"], at: (x: 25, y: 3 + drift), key: key)
            if sin(phase * 0.7) > 0 {
                b.stamp(["zz", ".z", "zz"], at: (x: 22, y: 9 - drift), key: key)
            }

        case .servers:
            // The blue rack he leans on in the sticker set. Status lights blink
            // independently so the stack looks powered rather than painted.
            let key: [Character: PixelBuffer.Ink] = ["d": .screenDark, "l": .screenLight]
            for (index, top) in [9, 14, 19].enumerated() {
                b.stamp([
                    "llllll",
                    "d....d",
                    "dddddd",
                ], at: (x: 26, y: top), key: key)
                let lit = sin(phase * 2 + Double(index) * 1.7) > -0.3
                b.pixel(28, top + 1, lit ? .green : .screenDark)
            }

        case .balloon:
            // String first, so the knot sits under the balloon.
            let sway = Int((sin(phase * 0.9) * 1.5).rounded())
            for y in 9...14 {
                b.pixel(4 + sway + (y > 11 ? 1 : 0), y, .steel)
            }
            let key: [Character: PixelBuffer.Ink] = ["g": .green, "b": .screenLight]
            b.stamp([
                ".ggggg.",
                "ggbbbgg",
                "gbbbbbg",
                "ggbbbgg",
                ".ggggg.",
            ], at: (x: 1 + sway, y: 3), key: key)

        case .hardHat:
            drawHardHat(&b, dx: dx, dy: dy, phase: phase)

        case .glasses:
            drawGlasses(&b, dx: dx, dy: dy, pose: pose)

        case .plan:
            // A little clipboard: clip, page, ruled lines. He holds it out.
            let key: [Character: PixelBuffer.Ink] = ["p": .paper, "s": .steel, "l": .screenLight]
            b.stamp([
                "..ss..",
                "pppppp",
                "pllllp",
                "pllllp",
                "pppppp",
                "pllllp",
                "pppppp",
            ], at: (x: 25, y: 4), key: key)

        case .phone:
            // Held at his side, screen facing out, content flickering.
            let x = 27 + dx
            let y = 11 + dy
            b.rect(x, y, 4, 7, .screenDark)
            b.rect(x + 1, y + 1, 2, 4, sin(phase * 3) > 0 ? .green : .screenLight)
            b.pixel(x + 2, y + 6, .steel)
        }
    }

    /// The little code window, with output scrolling up through it.
    ///
    /// Held in front of him like a laptop: the frame overlaps the lower body
    /// and the inner legs, his claws grip the top corners, and his eyes peer
    /// over the lid — so it reads as something he is using, not backdrop
    /// furniture. It tracks `dx`/`dy` for the same reason: a console that
    /// ignores his bob reads as painted onto the wall behind him.
    private static func drawTerminal(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let originX = 10 + dx
        let originY = 17 + dy
        let width = 12
        let height = 7

        b.rect(originX, originY, width, height, .screenDark)
        b.rect(originX, originY, width, 2, .screenLight)

        // Title-bar dots cycling, like a window that is doing something.
        let dots: [PixelBuffer.Ink] = [.pink, .yellow, .green]
        for index in 0..<3 {
            let active = Int(phase * 1.5) % 3 == index
            b.pixel(originX + 1 + index * 2, originY + 1, active ? dots[index] : .screenDark)
        }

        // Interior: rows 3..<height-1. Code lines scroll upward and wrap.
        let interiorTop = originY + 3
        let interiorHeight = height - 4
        let lineWidths = [5, 3, 6, 2, 4, 7]
        let scroll = Int(phase * 3) % lineWidths.count

        for row in 0..<interiorHeight {
            let width = lineWidths[(row + scroll) % lineWidths.count]
            let indent = (row + scroll) % 2
            b.rect(originX + 1 + indent, interiorTop + row, width, 1, .green)
        }

        // Cursor on the bottom line.
        if sin(phase * 4) > 0 {
            b.rect(originX + 1, interiorTop + interiorHeight, 2, 1, .green)
        }

        // Claw tips over the top corners: the grip is what sells "held".
        b.rect(originX, originY, 2, 1, .body)
        b.rect(originX + width - 2, originY, 2, 1, .body)
    }

    /// Yellow hat on his crown, wrench and screwdriver at his sides.
    private static func drawHardHat(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let hatY = bodyY + dy - 4
        let centre = bodyX + bodyW / 2 + dx

        b.rect(centre - 5, hatY + 1, 10, 3, .yellow)   // dome
        b.rect(centre - 4, hatY, 8, 1, .yellow)        // crown
        b.rect(centre - 7, hatY + 4, 14, 1, .yellow)   // brim

        // Tools, bobbing gently so they read as held rather than glued on.
        let jiggle = sin(phase * 2) > 0 ? 0 : 1
        b.rect(2, 13 + jiggle, 2, 6, .steel)           // wrench shaft
        b.rect(1, 12 + jiggle, 4, 2, .steel)           // wrench head
        b.rect(29, 14 - jiggle, 2, 5, .steel)          // screwdriver shaft
        b.rect(28, 12 - jiggle, 4, 2, .screenDark)     // screwdriver handle
    }

    /// Wire frames around both eyes.
    ///
    /// Drawn as an outline only — filling the lenses would cover the eyes, and
    /// his eyes are most of his expression. Steel rather than black so the frame
    /// separates from the pupils behind it.
    private static func drawGlasses(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        let top = eyeY + dy + pose.gazeY - 1
        let bridgeY = top + 2

        for lensX in [eyeLeftX + dx - 1, eyeRightX + dx - 1] {
            b.rect(lensX, top, 5, 1, .steel)          // upper rim
            b.rect(lensX, top + 4, 5, 1, .steel)      // lower rim
            b.rect(lensX, top + 1, 1, 3, .steel)      // outer edge
            b.rect(lensX + 4, top + 1, 1, 3, .steel)  // inner edge
        }

        // Bridge between the lenses, and a temple arm on each side.
        b.rect(eyeLeftX + dx + 4, bridgeY, 6, 1, .steel)
        b.rect(eyeLeftX + dx - 3, bridgeY, 2, 1, .steel)
        b.rect(eyeRightX + dx + 4, bridgeY, 2, 1, .steel)
    }

    /// The blaze. An upward burst rising off his back, with sparks.
    ///
    /// Authored as silhouettes rather than computed: at this size a flame drawn
    /// by arithmetic reads as bars, and the eye recognises fire by its ragged
    /// outline. Three frames cycle, so it flickers by changing shape.
    ///
    /// Drawn BEFORE the body (`render`), so it may bleed down behind him and be
    /// harmlessly overpainted. Rows 0-9 are free in every fire-bearing pose.
    private static let flameFrames: [[String]] = [
        [
            "....cc....",
            "...cffc...",
            "..cffffc..",
            ".cffffffc.",
            ".cfffeefc.",
            "cffeeeeffc",
            "cfeeeeeefc",
            ".eeeeeeee.",
        ],
        [
            "...cc.c...",
            "..cffcfc..",
            ".cffffffc.",
            ".cfffffec.",
            "cffffeeefc",
            "cffeeeeefc",
            ".feeeeeef.",
            "..eeeeee..",
        ],
        [
            ".....cc...",
            "....cffc..",
            "...cffffc.",
            "..cffffefc",
            ".cfffeeefc",
            "cffeeeeeef",
            "cfeeeeeef.",
            ".eeeeee...",
        ],
    ]

    private static func drawFire(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let key: [Character: PixelBuffer.Ink] = [
            "c": .flameCore, "f": .flame, "e": .ember,
        ]
        // Slow enough to read as flame rather than strobe.
        let frame = flameFrames[Int(phase * 6) % flameFrames.count]
        // Sits behind his back, rising into the free band above him. The old
        // version anchored at the frame edge and clamped, so most of its flicker
        // produced an identical bar.
        b.stamp(frame, at: (x: 17 + dx, y: 1 + dy), key: key)
    }

    /// Sparks thrown off the blaze, drawn in FRONT of him.
    ///
    /// Four-pointed stars, from the reference art. They scatter and fade on
    /// their own cycles so the fire never looks like a static decal.
    private static func drawSparks(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let spots = [(14, 3), (28, 6), (24, 0), (12, 8)]
        for (index, spot) in spots.enumerated() {
            let life = sin(phase * 3 + Double(index) * 1.9)
            guard life > 0 else { continue }
            let x = spot.0 + dx, y = spot.1 + dy
            let ink: PixelBuffer.Ink = life > 0.7 ? .flameCore : .flame
            b.pixel(x, y, ink)
            // At full brightness it opens into a four-pointed star.
            if life > 0.45 {
                b.pixel(x - 1, y, ink)
                b.pixel(x + 1, y, ink)
                b.pixel(x, y - 1, ink)
                b.pixel(x, y + 1, ink)
            }
        }
    }

}
