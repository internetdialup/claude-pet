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

    /// The prop drawn with Claw'd. Straight from the sticker set — he is almost
    /// always pictured *with* something.
    public var prop: Prop = .none
    public enum Prop: String, Sendable, CaseIterable {
        case none
        // World props: drawn at a fixed spot in the frame.
        case sparkles, terminal, check, bang, zzz, servers, balloon
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

        // Behind the body.
        if pose.prop == .fire { drawFire(&buffer, dx: dx, dy: dy, phase: pose.propPhase) }

        drawLegs(&buffer, dx: dx, dy: dy, pose: pose)
        drawArms(&buffer, dx: dx, dy: dy, pose: pose)

        // Squash widens and shortens the body, keeping its feet on the ground.
        let squash = max(0, pose.squash)
        buffer.rect(bodyX + dx - squash, bodyY + dy + squash,
                    bodyW + squash * 2, bodyH - squash, .body)

        drawFace(&buffer, dx: dx, dy: dy, pose: pose)
        drawProp(&buffer, dx: dx, dy: dy, pose: pose)

        return buffer
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
        for baseX in [eyeLeftX, eyeRightX] {
            let x = baseX + dx + pose.gazeX
            if pose.blink > 0.5 && !pose.asleepOverride {
                // Shut: a single row, held at the eye's vertical centre.
                b.rect(x, eyeTop + 1, eyeSize, 1, .eye)
            } else {
                b.rect(x, eyeTop, eyeSize, eyeSize, .eye)
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
        case .none, .fire:
            break   // fire is drawn behind the body, before the legs

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
            drawTerminal(&b, phase: phase)

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
    /// The frame is stamped once and the code lines are drawn per frame at a
    /// shifting offset, which is what makes it read as a live terminal rather
    /// than a decal.
    private static func drawTerminal(_ b: inout PixelBuffer, phase: Double) {
        let originX = 22
        let originY = 1
        let width = 10
        let height = 9

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

    /// Rocket exhaust behind and below him.
    private static func drawFire(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        // Streaks run leftward from the body's edge. The first version anchored
        // them off-frame, so everything clipped to a single bar at x=0.
        let tailX = bodyX + dx - 1
        let rows = [bodyY + dy + 2, bodyY + dy + 5, bodyY + dy + 8]

        for (index, y) in rows.enumerated() {
            let flicker = sin(phase * 7 + Double(index) * 2.1)
            let length = 5 + Int((flicker * 2).rounded())
            let startX = max(0, tailX - length)
            let width = tailX - startX
            guard width > 1 else { continue }
            b.rect(startX, y, width, 2, .flame)
            // Hotter core at the nozzle end.
            b.rect(startX + width / 2, y, width - width / 2, 1, .yellow)
        }
    }
}
