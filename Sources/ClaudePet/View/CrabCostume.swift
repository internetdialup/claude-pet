import SwiftUI

/// What a costume looks like: which palette slots it repaints and whether its
/// crown accessory steps aside for a crown-worn prop.
///
/// Colours are stored as sRGB components rather than `Color`s so a costume
/// change can *mix* between two wardrobes — swapping the map in one frame would
/// pop the ninja's dark shell back to terracotta, which is exactly the kind of
/// cut the no-snap rule bans.
struct CostumeStyle {
    /// Palette overrides keyed by ink. `.body` recolours the shell; the two
    /// costume slots colour the accessory pixels.
    let inks: [PixelBuffer.Ink: (r: Double, g: Double, b: Double)]
    /// Wizard hats and space helmets occupy the same crown as the hard hat;
    /// the prop is a status signal, so the costume yields.
    let yieldsCrownToProps: Bool

    static func of(_ costume: Costume) -> CostumeStyle {
        switch costume {
        case .none:
            return CostumeStyle(inks: [:], yieldsCrownToProps: false)
        case .ninja:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x47_4751),      // shadowed shell
                    .costumeA: rgb(0xC2_4141),  // headband + tails
                    .costumeB: rgb(0xCE_7B5C),  // the mask's eye window — his own terracotta
                ],
                yieldsCrownToProps: false)
        case .retroBlack:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x1C_1C1E),      // matte black shell
                    .costumeB: rgb(0x3A_3A40),  // charcoal eye backing — black-on-black eyes vanish
                ],
                yieldsCrownToProps: false)
        case .matrix:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x0C_100C),      // terminal-dark shell
                    .costumeA: rgb(0x53_F26A),  // rain heads, phosphor bright
                    .costumeB: rgb(0x1E_6B2E),  // rain trails, dim
                    .eye: rgb(0x53_F26A),       // he IS in the terminal
                    .mouth: rgb(0x2E_9C43),
                ],
                yieldsCrownToProps: false)
        case .tiger:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x3E_7A45),      // jungle green shell
                    .costumeA: rgb(0x1F_4023),  // stripes
                ],
                yieldsCrownToProps: false)
        case .white:
            return CostumeStyle(
                inks: [
                    .body: rgb(0xEC_EAE2),      // warm arctic white
                    .mouth: rgb(0x3D_3D3A),     // a white mouth on a white shell is no mouth
                ],
                yieldsCrownToProps: false)
        case .gundam:
            return CostumeStyle(
                inks: [
                    .body: rgb(0xE8_EAF0),      // RX-78 white
                    .costumeA: rgb(0x2C_4FA3),  // federation blue — shoulders, chest
                    .costumeB: rgb(0xC6_3A3A),  // the red — crest, chin, feet
                    .costumeC: rgb(0x14_161A),  // the visor recess — the black the face is built on
                    .eye: rgb(0xF2_D23C),       // camera-yellow, straight off the reference
                    .mouth: rgb(0x3D_3D3A),
                ],
                yieldsCrownToProps: true)       // the V-fin yields the crown to the hard hat
        case .sonic:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x23_50D2),      // that blue
                    .costumeA: rgb(0x15_2F8E),  // quill shadow-blue
                    .costumeB: rgb(0xD8_3030),  // the sneakers
                    .costumeC: rgb(0xF2_CE9E),  // muzzle-and-belly tan
                    .mouth: rgb(0x2B_1B10),     // a dark mouth on the tan muzzle
                ],
                yieldsCrownToProps: true)       // the quills yield to the hard hat
        }
    }

    /// The palette colour a slot mixes against when one side of a costume
    /// change has no opinion — eyes anchor to ink-black, mouths to white, the
    /// body to terracotta. Without this, a change into the Matrix look would
    /// snap the eyes green at the first blend frame instead of easing there.
    private static func defaultRGB(for slot: PixelBuffer.Ink) -> (r: Double, g: Double, b: Double)? {
        switch slot {
        case .body: SpriteTint.bodyRGB
        case .eye: (0, 0, 0)
        case .mouth: (1, 1, 1)
        default: nil
        }
    }

    private static func rgb(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255,
         Double((hex >> 8) & 0xFF) / 255,
         Double(hex & 0xFF) / 255)
    }

    /// The ink→colour map for the canvas, mixed between an outgoing and an
    /// incoming wardrobe so a costume change glides. Slots one side lacks fall
    /// back to the other side's colour (their pixels are dissolving anyway) and
    /// a missing `.body` mixes against Claw'd's own terracotta.
    static func blendedOverrides(from: Costume, to: Costume, u: Double) -> [PixelBuffer.Ink: Color] {
        let a = of(from).inks
        let b = of(to).inks
        var out: [PixelBuffer.Ink: Color] = [:]
        for slot in Set(a.keys).union(b.keys) {
            let fallback = defaultRGB(for: slot) ?? a[slot] ?? b[slot]
            guard let fromRGB = a[slot] ?? fallback, let toRGB = b[slot] ?? fallback else { continue }
            let m = Ease.clamp01(u)
            out[slot] = Color(red: fromRGB.r + (toRGB.r - fromRGB.r) * m,
                              green: fromRGB.g + (toRGB.g - fromRGB.g) * m,
                              blue: fromRGB.b + (toRGB.b - fromRGB.b) * m)
        }
        return out
    }
}

/// Rasterises costume accessories onto the sprite grid, in three passes so the
/// rig can interleave them with its own: `behind` before the legs, `onBody`
/// after the body rect but before the face, `front` after the face.
enum CrabCostume {
    enum Layer { case behind, onBody, front }

    /// Body geometry from `CrabRig` — the accessories are tailored to the
    /// same measurements the shell is drawn with. Aliases, not copies, so the
    /// mirror cannot drift.
    private static let bodyX = CrabRig.bodyX, bodyW = CrabRig.bodyW,
                       bodyY = CrabRig.bodyY, bodyH = CrabRig.bodyH

    static func draw(_ b: inout PixelBuffer, costume: Costume, layer: Layer,
                     dx: Int, dy: Int, squash: Int, pose: CrabPose) {
        switch costume {
        case .none:
            break

        case .ninja:
            let crown = bodyY + dy + squash
            switch layer {
            case .behind:
                // Two tail ribbons off the knot, fluttering on the prop clock.
                let flutter = sin(pose.propPhase * 2.4) > 0 ? 0 : 1
                b.pixel(27 + dx, crown + 2, .costumeA)
                b.pixel(28 + dx, crown + 3 + flutter, .costumeA)
                b.pixel(28 + dx, crown + 4 + flutter, .costumeA)
                b.pixel(29 + dx, crown + 5 - flutter, .costumeA)
            case .onBody:
                // The mask's eye window first — his own terracotta showing
                // through — then the band above it, then the knot.
                b.rect(bodyX + 2 + dx, 13 + dy, bodyW - 4, 4, .costumeB)
                b.rect(bodyX + dx - squash, crown + 1, bodyW + squash * 2, 2, .costumeA)
                b.pixel(bodyX + bodyW + dx - 1, crown + 2, .costumeA)
            case .front:
                break
            }




        case .retroBlack:
            guard layer == .onBody else { break }
            // Only the eye backing — the whole point of this look is what it
            // leaves out. Charcoal behind the eyes, or black-on-black blinds him.
            b.rect(bodyX + 2 + dx, 12 + dy, bodyW - 4, 5, .costumeB)

        case .matrix:
            guard layer == .onBody else { break }
            // The rain: one drop per column, scrolling DOWN the shell on the
            // prop clock, each column offset by its own constant so the field
            // never marches in step. Head bright, three-cell trail dim, all
            // clipped to the shell.
            let top = bodyY + dy + squash
            let height = bodyH - squash
            let span = height + 6
            for (index, column) in [7, 10, 13, 16, 19, 22].enumerated() {
                let phase = pose.propPhase * 3.0 + Double(index) * 7.3
                let head = Int(phase.truncatingRemainder(dividingBy: Double(span)))
                for trail in 0..<4 {
                    let y = top + head - trail
                    guard y >= top, y < top + height else { continue }
                    b.pixel(column + dx, y, trail == 0 ? .costumeA : .costumeB)
                }
            }

        case .tiger:
            guard layer == .onBody else { break }
            // Three bold 2-wide stripes per band, staggered — the first draft
            // ran twelve thin dashes and read cactus, not cat. Columns chosen
            // clear of the eye windows (10-12 and 19-21), where a stripe just
            // vanishes behind the face.
            let base = bodyY + dy + squash
            // Stripes hang from the back and rise from the belly — staggered
            // bars, not spots; spots read leopard.
            for column in [7, 14, 22] {
                b.rect(column + dx, base, 2, 3, .costumeA)
            }
            for column in [10, 18] {
                b.rect(column + dx, base + 7, 2, 3, .costumeA)
            }

        case .white:
            break   // the colourway IS the costume — no accessories

        case .gundam:
            if layer == .onBody {
                // The face is built on black: a visor recess across the eye
                // rows — the reference's whole read — with the camera eyes
                // yellow inside it and the crest's red tip dropping between
                // them. Same window geometry as the ninja mask, opposite
                // intent: the ninja lets his own shell through, the Gundam
                // sinks the eyes into shadow.
                b.rect(bodyX + 2 + dx, 13 + dy, bodyW - 4, 4, .costumeC)
                b.pixel(16 + dx, 13 + dy, .costumeB)
                break
            }
            guard layer == .front else { break }
            let crown = bodyY + dy + squash
            // The RX-78 merge, per the operator's reference sheet: long V-fin
            // antennae sweeping up and out, the red crest at their root, blue
            // shoulder plates, red chin under the mouth, a blue chest band
            // with yellow vents, and red feet on all four legs. The camera
            // eyes go yellow through the ink override.
            b.pixel(10 + dx, crown - 6, .yellow)        // antenna tips, high and wide
            b.pixel(22 + dx, crown - 6, .yellow)
            b.pixel(11 + dx, crown - 5, .yellow)
            b.pixel(21 + dx, crown - 5, .yellow)
            b.pixel(12 + dx, crown - 4, .yellow)
            b.pixel(20 + dx, crown - 4, .yellow)
            b.pixel(13 + dx, crown - 3, .yellow)
            b.pixel(19 + dx, crown - 3, .yellow)
            b.pixel(14 + dx, crown - 2, .yellow)
            b.pixel(18 + dx, crown - 2, .yellow)
            b.rect(16 + dx, crown - 3, 1, 3, .costumeB) // crest: a proper red blade
            b.pixel(15 + dx, crown - 1, .yellow)
            b.pixel(17 + dx, crown - 1, .yellow)
            b.rect(bodyX + dx - squash, crown, 2, 2, .costumeA)
            b.rect(bodyX + bodyW - 2 + dx + squash, crown, 2, 2, .costumeA)
            // Side armor running down both flanks from the shoulders — the
            // punch-up pass: more federation blue down the sides, framing
            // the visor's black.
            b.rect(bodyX + dx - squash, crown + 2, 2, 5, .costumeA)
            b.rect(bodyX + bodyW - 2 + dx + squash, crown + 2, 2, 5, .costumeA)
            b.pixel(13 + dx, 19 + dy, .yellow)          // collar, per the reference
            b.pixel(19 + dx, 19 + dy, .yellow)
            b.rect(15 + dx, 19 + dy, 3, 1, .costumeB)   // chin
            b.rect(12 + dx, 20 + dy, 9, 1, .costumeA)   // chest band, full width
            b.pixel(15 + dx, 20 + dy, .yellow)          // twin vents
            b.pixel(17 + dx, 20 + dy, .yellow)
            for leg in [7, 11, 20, 24] {                // red feet
                b.rect(leg + dx, 23 + dy, 2, 2, .costumeB)
            }

        case .sonic:
            let crown = bodyY + dy + squash
            if layer == .onBody {
                // The muzzle-and-belly tan; the face pass draws the mouth
                // over it, and the eyes stay his own.
                b.rect(12 + dx, 16 + dy, 8, 4, .costumeC)
                // Red sneakers with white socks, on all four feet.
                for leg in [7, 11, 20, 24] {
                    b.rect(leg + dx, 22 + dy, 2, 1, .paper)
                    b.rect(leg + dx, 23 + dy, 2, 2, .costumeB)
                }
                break
            }
            guard layer == .front else { break }
            // The quills, all in the shadow blue so they read against the
            // shell: three back-swept points across the crown and one
            // flaring out past each flank, drooping at the tip.
            b.rect(14 + dx, crown - 2, 4, 1, .costumeA)
            b.pixel(15 + dx, crown - 3, .costumeA)
            b.pixel(16 + dx, crown - 3, .costumeA)
            b.rect(10 + dx, crown - 1, 3, 1, .costumeA)
            b.pixel(11 + dx, crown - 2, .costumeA)
            b.rect(19 + dx, crown - 1, 3, 1, .costumeA)
            b.pixel(20 + dx, crown - 2, .costumeA)
            b.rect(3 + dx, 12 + dy, 3, 1, .costumeA)
            b.pixel(3 + dx, 13 + dy, .costumeA)
            b.rect(26 + dx, 12 + dy, 3, 1, .costumeA)
            b.pixel(28 + dx, 13 + dy, .costumeA)
        }
    }
}

/// Records when the wardrobe changed, so the incoming costume can dissolve in
/// while the outgoing one dissolves away — mirroring `MoodClock`, and like it,
/// live-only: offline renderers never note a change, so they render whatever
/// costume they are handed at full strength.
@MainActor
public final class CostumeClock {
    public static let shared = CostumeClock()
    public init() {}
    nonisolated static let fadeDuration = 0.35

    private(set) var current: Costume = .none
    private(set) var previous: Costume = .none
    private var changedAt: Double = -.infinity

    func note(_ costume: Costume) {
        guard costume != current else { return }
        previous = current
        current = costume
        changedAt = Date.timeIntervalSinceReferenceDate
    }

    /// Eased progress of the swap at `time`: 1 means the incoming costume is
    /// fully on and the ghost is gone.
    func progress(at time: Double) -> Double {
        Ease.smoothstep((time - changedAt) / Self.fadeDuration)
    }
}
