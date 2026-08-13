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
        case .wizard:
            return CostumeStyle(
                inks: [
                    .costumeA: rgb(0x53_409E),  // hat
                    .costumeB: rgb(0x7A_65C9),  // hat band
                ],
                yieldsCrownToProps: true)
        case .astro:
            return CostumeStyle(
                inks: [
                    .costumeA: rgb(0xE8_E8EC),  // helmet dome
                    .costumeB: rgb(0xE0_5252),  // antenna beacon
                ],
                yieldsCrownToProps: true)
        case .tuxedo:
            return CostumeStyle(
                inks: [
                    .costumeA: rgb(0x14_1413),  // bow tie
                    .costumeB: rgb(0xF0_EEE6),  // collar studs
                ],
                yieldsCrownToProps: false)
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
            let fallback = slot == .body ? SpriteTint.bodyRGB : (a[slot] ?? b[slot])
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

    /// Body geometry mirrored from `CrabRig` — the accessories are tailored to
    /// the same measurements the shell is drawn with.
    private static let bodyX = 6, bodyW = 20, bodyY = 10

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

        case .wizard:
            guard layer == .front else { break }
            let crown = bodyY + dy + squash
            // Brim, band, and a leaning cone; two stars twinkling on offset
            // phases — a twinkle snaps like a blink, which nature allows.
            b.rect(8 + dx, crown - 1, 16, 1, .costumeA)          // brim
            b.rect(11 + dx, crown - 2, 10, 1, .costumeB)         // band
            b.rect(12 + dx, crown - 3, 8, 1, .costumeA)
            b.rect(13 + dx, crown - 4, 6, 1, .costumeA)
            b.rect(14 + dx, crown - 5, 4, 1, .costumeA)
            b.rect(15 + dx, crown - 6, 2, 1, .costumeA)
            b.pixel(16 + dx, crown - 7, .costumeA)               // tip
            if sin(pose.propPhase * 1.7) > 0.2 { b.pixel(13 + dx, crown - 3, .yellow) }
            if sin(pose.propPhase * 2.3 + 1.9) > 0.2 { b.pixel(18 + dx, crown - 4, .yellow) }

        case .astro:
            guard layer == .front else { break }
            let crown = bodyY + dy + squash
            // A one-pixel dome outline over the crown — never over the eyes;
            // covering an eye is how a costume stops being Claw'd.
            b.rect(11 + dx, crown - 5, 10, 1, .costumeA)         // dome top
            b.pixel(10 + dx, crown - 4, .costumeA)
            b.pixel(21 + dx, crown - 4, .costumeA)
            b.pixel(9 + dx, crown - 3, .costumeA)
            b.pixel(22 + dx, crown - 3, .costumeA)
            b.pixel(8 + dx, crown - 2, .costumeA)
            b.pixel(23 + dx, crown - 2, .costumeA)
            b.pixel(8 + dx, crown - 1, .costumeA)
            b.pixel(23 + dx, crown - 1, .costumeA)
            // Antenna, beacon blinking slowly.
            b.pixel(16 + dx, crown - 6, .costumeA)
            if sin(pose.propPhase * 1.2) > -0.2 { b.pixel(16 + dx, crown - 7, .costumeB) }

        case .tuxedo:
            guard layer == .onBody else { break }
            // Bow tie under the mouth: two wings and a knot, with a collar
            // stud either side.
            let y = 19 + dy
            b.rect(13 + dx, y, 2, 2, .costumeA)
            b.rect(17 + dx, y, 2, 2, .costumeA)
            b.rect(15 + dx, y, 2, 1, .costumeA)
            b.pixel(12 + dx, y, .costumeB)
            b.pixel(19 + dx, y, .costumeB)
        }
    }
}

/// Records when the wardrobe changed, so the incoming costume can dissolve in
/// while the outgoing one dissolves away — mirroring `MoodClock`, and like it,
/// live-only: offline renderers never note a change, so they render whatever
/// costume they are handed at full strength.
@MainActor
final class CostumeClock {
    static let shared = CostumeClock()
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
