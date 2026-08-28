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
        case .frankenstein:
            // Named for what it turned out to be. It was built as a handheld's
            // four-tone LCD ramp, and the operator took one look and said it
            // looked like Frankenstein — correctly, because the recipe for a
            // monster is green skin plus a mark on the forehead, and a control
            // panel on his brow is a mark on the forehead. The palette stayed,
            // the name changed, and the marks became what they were already
            // reading as.
            return CostumeStyle(
                inks: [
                    .body: rgb(0x8B_AC0F),      // the same green, now a complexion
                    .eye: rgb(0x0F_380F),
                    .mouth: rgb(0x0F_380F),     // dark, or his face vanishes into it
                    .costumeA: rgb(0x30_6230),  // the seam
                    .costumeB: rgb(0x6E_6E78),  // the bolts, iron rather than magenta
                ],
                yieldsCrownToProps: false)

        case .arcade:
            // THE CABINET, not the handheld. The first attempt at this was
            // green and put its controls on his brow, which is the recipe for a
            // monster — so it kept that job under a new name and this one goes
            // somewhere green cannot follow.
            //
            // A cabinet is a dark box with a lit screen in it. So: near-black
            // shell, and his eyes and mouth in phosphor cyan, which is the one
            // move that says MACHINE rather than "a crab painted black" — the
            // glow has to come from inside him or he is just `retroBlack` with
            // extra steps.
            return CostumeStyle(
                inks: [
                    .body: rgb(0x1A_1A22),      // cabinet black
                    .eye: rgb(0x4D_F2FF),       // phosphor, lit from within
                    .mouth: rgb(0x4D_F2FF),
                    .costumeA: rgb(0xFF_2E88),  // the marquee
                    .costumeB: rgb(0xFF_C20E),  // and its second stripe
                ],
                yieldsCrownToProps: false)

        case .ninja:
            return CostumeStyle(
                inks: [
                    // Properly dark, at the operator's call. It was 0x474751,
                    // a slate grey that read as "in shadow" rather than as
                    // black. Not quite `retroBlack`'s 0x1C1C1E either: that
                    // costume's whole identity is being black, and the ninja
                    // needs somewhere to put a headband. A cool near-black
                    // keeps the red legible on top of it.
                    .body: rgb(0x23_232B),      // near-black, cool
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
                    .body: rgb(0x05_0A05),      // terminal-dark shell, darker so the code carries
                    .costumeA: rgb(0x7C_F08D),  // rain heads
                    .costumeB: rgb(0x2E_A845),  // the streak body
                    .costumeC: rgb(0x1D_7431),  // tails, and the code-lines under them
                    // Brighter than any rain stop on purpose: with code
                    // crossing his whole shell, the eyes have to out-rank the
                    // field or he loses his face in his own costume.
                    .eye: rgb(0xD8_FFE2),
                    .mouth: rgb(0x2E_A845),
                ],
                yieldsCrownToProps: false)
        case .tiger:
            return CostumeStyle(
                inks: [
                    .body: rgb(0xE0_8A2E),      // tiger orange — the operator's
                                                // ruling: green never read cat
                    .costumeA: rgb(0x26_1C10),  // warm near-black stripes
                    .costumeC: rgb(0xF2_EFE4),  // the white belly patch
                    .mouth: rgb(0x3D_3D3A),     // dark mouth on the white patch
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

    /// A costume effect's window: nil when it is not playing, else 0…1 through
    /// it.
    ///
    /// One helper for all of them, because seven copies of "cycle, dice, since"
    /// is seven chances to forget `cycle > 0` — and a costume effect that fires
    /// in cycle zero puts something mid-flight into every frozen render the
    /// project makes.
    ///
    /// The multiplier is always 97: costume effects are a FAMILY on the salt
    /// registry and the addend is what tells them apart, the way `71 &+ 29 &+
    /// slot` already works for the bubble bursts. 97 was the last free
    /// multiplier, so this is the scheme that stops the eighth costume needing
    /// a tenth one.
    static func effectWindow(at t: Double, salt: Int, period: Double,
                             duration: Double, chance: Double) -> Double? {
        let cycle = Int(floor(t / period))
        guard cycle > 0, CrabAnimator.noise(cycle &* 97 &+ salt) < chance else { return nil }
        let since = t - Double(cycle) * period
        guard since >= 0, since < duration else { return nil }
        return since / duration
    }

    /// When a shuriken is in flight, and how far across it has got.
    ///
    /// Scheduled rather than constant: a star permanently spinning beside him
    /// is a screensaver, and the point of a thrown one is that it goes. Never
    /// in the first cycle, so a frozen render at t=0 is a clean crab — the same
    /// sentinel every other dice in the app answers to.
    ///
    /// Salt `97 &+ 11`. 97 is the multiplier the COSTUME EFFECTS take as a
    /// family, with the addend telling them apart — the pattern `71 &+ 29 &+
    /// slot` already set for the bubble bursts. It was the last free multiplier
    /// on the registry, and sharing it is what stops the next eight costumes
    /// each wanting one.
    static func shurikenFlight(at t: Double) -> Double? {
        effectWindow(at: t, salt: 11, period: 9, duration: 2.2, chance: 0.55)
    }

    static func draw(_ b: inout PixelBuffer, costume: Costume, layer: Layer,
                     dx: Int, dy: Int, squash: Int, pose: CrabPose) {
        switch costume {
        case .none:
            break

        case .frankenstein:
            if layer == .onBody {
            // A seam across the brow and two bolts at the temples.
            //
            // These were a D-pad and a pair of buttons, and they read as a scar
            // and a bolt anyway — so they are a scar and a bolt now. The brow is
            // still the only free band on him: his body is solid from row 10 to
            // 20, eyes at 13-15, mouth at 16-18, which leaves rows 10 to 12 and
            // nothing else. That constraint is what made the handheld version
            // look like a monster, and it is what makes this one work.
            let brow = bodyY + dy + squash
            let seam = bodyX + 3 + dx
            b.rect(seam, brow + 1, 9, 1, .costumeA)         // the stitch line
            for tick in [0, 4, 8] {                         // and its sutures
                b.pixel(seam + tick, brow, .costumeA)
                b.pixel(seam + tick, brow + 2, .costumeA)
            }
            // Bolts at the temples, not the neck — he has no neck, and a bolt
            // below his jaw would read as a dropped pixel.
            b.rect(bodyX + dx, brow + 4, 2, 2, .costumeB)
            b.rect(bodyX + bodyW + dx - 2, brow + 4, 2, 2, .costumeB)
            }
            guard layer == .front,
                  let arc = Self.effectWindow(at: pose.propPhase, salt: 13,
                                              period: 7, duration: 0.7, chance: 0.5)
            else { break }
            // The bolts crackle — and NOT an arc between them. They sit at eye
            // height, so a bar joining them would be drawn straight across his
            // eyes, which is the one thing the wardrobe may never do. The
            // charge stays at each bolt and jitters, which is what a spark
            // looks like from a distance anyway.
            let sparkBrow = bodyY + dy + squash
            let frame = Int(arc * 9)
            for (index, hub) in [bodyX + dx, bodyX + bodyW + dx - 2].enumerated() {
                for spark in 0..<3 {
                    let ox = Int(CrabAnimator.noise(frame &* 31 &+ spark &* 7 &+ index &* 3) * 4) - 1
                    let oy = Int(CrabAnimator.noise(frame &* 17 &+ spark &+ index) * 4) - 1
                    b.pixel(hub + ox, sparkBrow + 4 + oy, .paper)
                }
            }

        case .arcade:
            guard layer == .onBody else { break }
            // A marquee across his lower body, and NOTHING on his face — which
            // is the whole reason this costume exists separately. Every mark up
            // there reads as a feature, and that is how the first attempt at
            // this became Frankenstein.
            //
            // Rows 19 and 20 are the only clear band below his mouth: two rows,
            // which is exactly a two-colour stripe and nothing more ambitious.
            // A cabinet is a dark box with a lit band on it, and so is he.
            //
            // And it CHASES. Two solid bars are a paint job; bulbs running
            // along a cabinet's crown are what a marquee actually is, and the
            // travel is the entire difference between a lit sign and a stripe.
            // Continuous, because a marquee that only ran on a dice would look
            // broken rather than restrained.
            let marquee = bodyY + dy + squash + 9
            let chase = Int(pose.propPhase * 7)
            for step in 0..<(bodyW - 4) {
                let x = bodyX + 2 + dx + step
                let lit = (step + chase) % 4 < 2
                b.pixel(x, marquee, lit ? .costumeA : .costumeB)
                b.pixel(x, marquee + 1, lit ? .costumeB : .costumeA)
            }

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
                // A shuriken, thrown. Enters from the right, spins across the
                // airspace over his head, and is gone — rows 4 to 8 and the
                // margins beyond his claws are the only ground in the frame
                // nothing else occupies.
                //
                // The spin is two frames, a plus and a cross, alternating fast.
                // That is the whole trick and it is the only one available: a
                // five-point star cannot rotate on this grid by any amount
                // other than 45 degrees, so it rotates by exactly that, which
                // is what a spinning blade looks like anyway.
                guard let travel = Self.shurikenFlight(at: pose.propPhase) else { break }
                let x = 30 - Int(travel * 38)
                let cross = Int(travel * 26) % 2 == 0
                let art = cross
                    ? ["s...s", ".s.s.", "..s..", ".s.s.", "s...s"]
                    : ["..s..", "..s..", "sssss", "..s..", "..s.."]
                // Steel, not the headband's red. `.costumeA` was to hand and
                // wrong: a red star reads as a decoration, and a blade has to
                // look like metal or it is bunting. `.steel` is also one of the
                // inks a costume cannot repaint, so it stays a blade whatever
                // else the wardrobe does.
                b.stamp(art, at: (x: x, y: 4), key: ["s": .steel])
            }




        case .retroBlack:
            if layer == .onBody {
                // Only the eye backing — the whole point of this look is what
                // it leaves out. Charcoal behind the eyes, or black-on-black
                // blinds him.
                b.rect(bodyX + 2 + dx, 12 + dy, bodyW - 4, 5, .costumeB)
            }
            guard layer == .front,
                  let sweep = Self.effectWindow(at: pose.propPhase, salt: 31,
                                                period: 11, duration: 1.6, chance: 0.45)
            else { break }
            // Clearcoat catching a light as you walk past it. Diagonal on
            // purpose: a vertical bar reads as a wipe and a horizontal one as a
            // scanline, and neither of those is a reflection.
            //
            // Written only where the cell is still `.body` — the mask the
            // matrix rain established. His eyes and mouth are their own inks by
            // the `.front` pass, so the sheen cannot cross them however far it
            // travels.
            let lead = Int(sweep * Double(bodyW + bodyH + 10)) - 5 + bodyX + dx
            for row in 0..<PixelBuffer.side {
                for offset in 0..<2 {
                    let x = lead - row + offset
                    guard x >= 0, x < PixelBuffer.side, b[x, row] == .body else { continue }
                    // `.steel`, not `.costumeB`. The costume slot here is the
                    // charcoal eye backing — a highlight painted in it is a
                    // shade of black on black and does not exist. A specular is
                    // LIGHT; it has to out-rank the shell it is sliding over.
                    b.pixel(x, row, .steel)
                }
            }
        case .matrix:
            // The rain runs on `.front`, i.e. AFTER `drawFace`, and writes
            // only where the cell is still `.body`. That mask is the whole
            // trick — the eyes and mouth are `.eye`/`.mouth` by then, so they
            // are simply not written, and the wardrobe's promise never to
            // cover an open eye holds by construction instead of by keeping
            // clear of coordinates. It also frees the rain to cross his whole
            // shell rather than trickling down six thin columns.
            //
            // Heat outranks it: a cell mid-cascade is `.bodyHot`, not `.body`,
            // so the fire burns through the code.
            guard layer == .front else { break }
            let top = bodyY + dy + squash
            let height = bodyH - squash
            guard height > 0 else { break }
            let left = bodyX + dx - squash
            let width = bodyW + squash * 2

            @inline(__always) func onShell(_ x: Int, _ y: Int, _ ink: PixelBuffer.Ink) {
                guard b[x, y] == .body else { return }
                b.pixel(x, y, ink)
            }

            // Code-lines first: varying-width bars scrolling down behind the
            // rain, borrowed from the terminal prop's vocabulary — the way
            // this rig already spells "source code". They read as structure;
            // the rain reads as motion over it.
            let lineWidths = [5, 3, 6, 2, 4, 7]
            let scroll = Int(pose.propPhase * 1.6)
            for row in 0..<height {
                let index = ((row - scroll) % lineWidths.count + lineWidths.count)
                    % lineWidths.count
                // One row in three carries a line. Denser than this and the
                // shell stops reading as a dark terminal with code on it and
                // starts reading as a green crab.
                guard (row &+ scroll) % 3 == 0 else { continue }
                let indent = (row &+ scroll) % 4 == 0 ? 1 : 4
                for step in 0..<lineWidths[index] {
                    onShell(left + indent + step, top + row, .costumeC)
                }
            }

            // The rain: every column of the shell, each with its own speed and
            // streak length off the shared die, so the field never marches in
            // step. Three stops — bright head, phosphor body, dim tail — which
            // is what makes a streak read as falling rather than blinking.
            // The span is generously longer than the shell so each column is
            // dark most of the time: a streak has to be an event, or the
            // whole field is on at once and nothing appears to fall.
            let span = height + 16
            for column in 0..<width {
                let x = left + column
                let speed = 2.0 + CrabAnimator.noise(column &* 37 &+ 11) * 4.0
                let offset = CrabAnimator.noise(column &* 91 &+ 17) * Double(span)
                let length = 2 + Int(CrabAnimator.noise(column &* 53 &+ 29) * 3)
                let head = Int((pose.propPhase * speed + offset)
                    .truncatingRemainder(dividingBy: Double(span)))
                for trail in 0...length {
                    let y = top + head - trail
                    guard y >= top, y < top + height else { continue }
                    let ink: PixelBuffer.Ink = trail == 0 ? .costumeA
                        : (trail <= length / 2 ? .costumeB : .costumeC)
                    onShell(x, y, ink)
                }
            }

        case .tiger:
            if layer == .onBody {
            // Three bold 2-wide stripes per band, staggered — the first draft
            // ran twelve thin dashes and read cactus, not cat. Columns chosen
            // clear of the eye windows (10-12 and 19-21), where a stripe just
            // vanishes behind the face.
            let base = bodyY + dy + squash
            // The white belly patch first, under the mouth — the stripes and
            // the face paint over it.
            b.rect(13 + dx, base + 8, 7, 2, .costumeC)
            // Stripes hang from the back and rise from the belly — staggered
            // bars, not spots; spots read leopard.
            for column in [7, 14, 22] {
                b.rect(column + dx, base, 2, 3, .costumeA)
            }
            for column in [10, 18] {
                b.rect(column + dx, base + 7, 2, 3, .costumeA)
            }
            }

            guard layer == .behind else { break }
            // A TAIL. He has none of his own, which is exactly why the costume
            // may give him one — the ninja's ribbons set that precedent on this
            // same layer, and behind him is where a tail goes, so it can never
            // cross his face.
            //
            // Continuous, and slow. A tail that only swished on a dice would
            // read as a twitch; the charm of one is that it never stops.
            let swish = sin(pose.propPhase * 1.5)
            let root = bodyX + bodyW + dx - 1
            for segment in 0..<6 {
                let x = root + segment
                let y = bodyY + dy + 9 - Int((Double(segment) * 0.55 * swish).rounded())
                guard x < PixelBuffer.side, y >= 1, y < PixelBuffer.side else { continue }
                b.pixel(x, y, .body)
                // Ticked with the stripes' own near-black every other segment,
                // so it reads as a tiger's tail rather than as a wire.
                if segment % 2 == 1 { b.pixel(x, y - 1, .costumeA) }
            }

        case .white:
            // The colourway is most of the costume; the weather is the rest.
            guard layer == .front else { break }
            // Snow, drawn ONLY where the cell is still clear. White flakes on
            // an arctic-white shell would simply disappear — the mask makes
            // that impossible rather than merely unlikely, and it puts the snow
            // behind him instead of over him, which is where snow goes.
            //
            // Continuous rather than scheduled: weather does not take turns.
            for (column, speed) in [(2, 0.62), (8, 0.9), (14, 0.5), (21, 0.78), (27, 1.05)] {
                let fall = (pose.propPhase * speed * 5 + Double(column * 3))
                    .truncatingRemainder(dividingBy: Double(PixelBuffer.side))
                let drift = Int(sin(pose.propPhase * 0.8 + Double(column)) * 1.4)
                let x = column + drift, y = Int(fall)
                guard x >= 0, x < PixelBuffer.side, b[x, y] == .clear else { continue }
                b.pixel(x, y, .paper)
            }
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

            guard layer == .front,
                  let scan = Self.effectWindow(at: pose.propPhase, salt: 19,
                                               period: 6, duration: 1.1, chance: 0.7)
            else { break }
            // The camera sweeping: one bright column crossing his shell, drawn
            // only where the cell is still `.body`. That mask puts it BEHIND
            // the visor and the eyes rather than over them — a scan that
            // blanked the eyes it is meant to be looking through would be the
            // wardrobe covering a face, which is the one forbidden thing.
            let column = bodyX + dx + Int(scan * Double(bodyW))
            guard column >= 0, column < PixelBuffer.side else { break }
            // `.paper` rather than a costume slot: `.costumeB` here is the
            // sneaker red, and a red bar sweeping his chest reads as an alarm
            // going off rather than as a camera looking around.
            for row in 0..<PixelBuffer.side where b[column, row] == .body {
                b.pixel(column, row, .paper)
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

            // No layer check here, and that is not an omission: the quills'
            // `guard layer == .front` above already narrowed this case to the
            // front pass, so everything below it is front-only. The first
            // version asked for `.behind` and was simply unreachable — the
            // render showed nothing at all and it took reading the case's
            // shape, not the effect's code, to see why.
            guard let dash = Self.effectWindow(at: pose.propPhase, salt: 23,
                                               period: 5, duration: 0.75, chance: 0.5)
            else { break }
            // Speed lines, in the margins beside him. He is standing
            // still, so the lines do all the work — the same trick the skate
            // cruise uses and for the same reason: on a fixed camera the world
            // moves and the character does not.
            for lane in 0..<3 {
                let y = bodyY + dy + 3 + lane * 5
                let reach = Int(dash * 9)
                // `.paper`, not `.costumeA`. That slot is his quill
                // shadow-blue — a dark blue streak beside a blue crab on a dark
                // desktop is three kinds of invisible, and the render proved it
                // by showing nothing at all. Speed lines are white because
                // speed lines have always been white.
                b.rect(max(0, bodyX + dx - 4 - reach), y, 3, 1, .paper)
                b.rect(min(PixelBuffer.side - 3, bodyX + bodyW + dx + 1 + reach), y, 3, 1, .paper)
            }

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
