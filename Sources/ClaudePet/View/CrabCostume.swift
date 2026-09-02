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
                    // One step below the shell, for the sampler's torso-turn
                    // shade — the ollie variants sell a slight body rotation
                    // with an edge band, and "one step darker" is relative to
                    // whichever shell is worn. Inert in every live buffer:
                    // only the drip-feed sampler ever sets `torsoShade`.
                    .bodyShade: rgb(0x15_1519),
                    .costumeA: rgb(0xC2_4141),  // headband + tails
                    .costumeB: rgb(0xCE_7B5C),  // the mask's eye window — his own terracotta
                ],
                yieldsCrownToProps: false)
        case .retroBlack:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x1C_1C1E),      // matte black shell
                    .bodyShade: rgb(0x0E_0E10), // the turn shade's step — see ninja's note
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
                    .bodyShade: rgb(0xC9_CDD8), // the turn shade's step — see ninja's note
                    .costumeA: rgb(0x2C_4FA3),  // federation blue — shoulders, chest
                    .costumeB: rgb(0xC6_3A3A),  // the red — crest, chin, feet
                    .costumeC: rgb(0x14_161A),  // the visor recess — the black the face is built on
                    .eye: rgb(0xF2_D23C),       // camera-yellow, straight off the reference
                    // Faint grey, one step under the shell — a Gundam face is
                    // a MASK, and the crab's dark smile read as a grille
                    // floating between visor and chin (the operator's "the
                    // bottom part looks odd"). The expression survives as a
                    // subtle mask seam instead of vanishing outright.
                    .mouth: rgb(0xC9_CDD8),
                ],
                yieldsCrownToProps: true)       // the V-fin yields the crown to the hard hat
        case .pumpkin:
            // 🎃 The jack-o'-lantern: his own eyes ARE the carving — the
            // eye-cover ban honored by concept, not just geometry.
            return CostumeStyle(
                inks: [
                    .body: rgb(0xE0_7A1E),      // pumpkin orange shell
                    .bodyShade: rgb(0xB8_5E10), // the turn shade's step — see ninja's note
                    .costumeA: rgb(0x2E_6224),  // stem + leaf green
                    .costumeB: rgb(0x2A_160A),  // carved-dark accents
                    .costumeC: rgb(0xC0_5A10),  // rib shadow
                    .mouth: rgb(0x1A_0E06),     // dark, so his own mouth reads carved
                ],
                yieldsCrownToProps: true)       // the stem steps aside for the hard hat
        case .turkey:
            // 🦃 The turkey: the first big behind-layer costume — the tail
            // fan lives behind him, the ninja-ribbon precedent at scale.
            return CostumeStyle(
                inks: [
                    .body: rgb(0x8A_5530),      // brown shell
                    .bodyShade: rgb(0x6E_4224), // the turn shade's step
                    .costumeA: rgb(0x53_311B),  // dark feather
                    .costumeB: rgb(0xC2_3A2A),  // the wattle
                    .costumeC: rgb(0xE0_A050),  // tail-fan gold
                    .mouth: rgb(0x3D_3D3A),
                ],
                yieldsCrownToProps: false)      // the fan is behind, not crown furniture
        case .santa:
            // 🎅 An OUTFIT, not a respray: his own terracotta stays — the
            // one seasonal look that keeps the shell, which also varies the
            // montage.
            return CostumeStyle(
                inks: [
                    .costumeA: rgb(0xC0_3030),  // hat + scarf red
                    .costumeB: rgb(0xF2_EFE4),  // trim, pom, fringe
                ],
                yieldsCrownToProps: true)       // a hat is crown furniture
        case .skater:
            // 🛹 The skater fit: an OUTFIT on his own shell, like the santa —
            // backwards cap, dark tee, pads. The board stays the prop system's.
            return CostumeStyle(
                inks: [
                    .costumeA: rgb(0x2A_2A30),  // the tee, worn charcoal
                    .costumeB: rgb(0x24_304A),  // the cap, navy
                    .costumeC: rgb(0xB8_B4A8),  // pads, scuffed off-white
                ],
                yieldsCrownToProps: true)       // the cap is crown furniture
        case .sonic:
            return CostumeStyle(
                inks: [
                    .body: rgb(0x23_50D2),      // that blue
                    .bodyShade: rgb(0x16_348E), // the turn shade's step — see ninja's note
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
    /// - Parameter eyeVariant: a substitute `.eye` colour for the INCOMING
    ///   wardrobe — the gundam's rare darker-turquoise cameras, rolled once
    ///   per wearing by the live view and never by an offline renderer, so
    ///   committed media always shows the camera-yellow default. Routed
    ///   through the blend so even the variant eases in with the costume.
    static func blendedOverrides(from: Costume, to: Costume, u: Double,
                                 eyeVariant: (r: Double, g: Double, b: Double)? = nil)
        -> [PixelBuffer.Ink: Color] {
        let a = of(from).inks
        var b = of(to).inks
        if let eyeVariant { b[.eye] = eyeVariant }
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
            // ⚡ Juiced, per the operator: the first cut jittered three
            // pale pixels at each bolt and read as nothing at desk size. Now
            // each bolt throws a real spark — a four-point star that climbs
            // up and away from the bolt, flaring open mid-flight and closing
            // back to a single cell before it dies (glint-class at both
            // ends, so the no-snap rule holds by geometry). The right bolt
            // fires a beat behind the left, which is what makes it read as
            // arcing electricity rather than two synchronized lamps.
            let sparkBrow = bodyY + dy + squash
            for (index, hub) in [bodyX + dx, bodyX + bodyW + dx - 1].enumerated() {
                let u = min(1, max(0, arc * 1.4 - Double(index) * 0.4))
                guard u > 0, u < 1 else { continue }
                let away = index == 0 ? -1 : 1
                let cx = hub + away * (1 + Int(u * 2))
                let cy = sparkBrow + 3 - Int(u * 4)
                let flare = sin(u * .pi)
                b.pixel(cx, cy, .paper)
                if flare > 0.35 {
                    b.pixel(cx - 1, cy, .yellow)
                    b.pixel(cx + 1, cy, .yellow)
                    b.pixel(cx, cy - 1, .yellow)
                    b.pixel(cx, cy + 1, .yellow)
                }
                // A stub of charge left glowing on the bolt itself while
                // the star is in flight — the source reads, not just the arc.
                b.pixel(hub, sparkBrow + 4, .yellow)
            }

        case .arcade:
            // The chasing marquee stripe lived here and died on the
            // operator's review — at desk size it read as a glitch band
            // crossing his belly, not a cabinet's lit sign. The costume is
            // its palette now: black cabinet shell, phosphor face, nothing
            // animated. `break` on purpose, not an unfinished case.
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
            if layer == .onBody {
                // 🤓 The glasses — what turned "Matrix" into "Coder" on the
                // operator's call. Steel rims framing each eye window, a
                // bridge between them. Body pass, so the face paints the
                // eyes over the rim interiors and the eye-cover ban holds
                // by draw order; the rain and code-lines above only write
                // `.body` cells, so they part around the frames on their
                // own — which is exactly the way light behaves on glasses.
                for rim in [9, 18] {
                    b.rect(rim + dx, 12 + dy, 5, 1, .steel)
                    b.rect(rim + dx, 16 + dy, 5, 1, .steel)
                    b.rect(rim + dx, 13 + dy, 1, 3, .steel)
                    b.rect(rim + 4 + dx, 13 + dy, 1, 3, .steel)
                }
                b.rect(14 + dx, 14 + dy, 4, 1, .steel)
                break
            }
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
            HolidayAmbience.drawSnow(&b, phase: pose.propPhase)
        case .gundam:
            if layer == .onBody {
                // The face is built on black: a visor recess across the eye
                // rows — the reference's whole read — with the camera eyes
                // yellow inside it and the crest's red tip dropping between
                // them. Same window geometry as the ninja mask, opposite
                // intent: the ninja lets his own shell through, the Gundam
                // sinks the eyes into shadow.
                // The visor TAPERS — the reference's whole face is
                // triangular: full width through the eye rows, then cut in
                // two cells a side on the bottom row, so the black converges
                // toward the chin instead of sitting as a slab. The white
                // that reappears at the corners is the mask's cheeks.
                b.rect(bodyX + 2 + dx, 13 + dy, bodyW - 4, 3, .costumeC)
                b.rect(bodyX + 4 + dx, 16 + dy, bodyW - 8, 1, .costumeC)
                // And the helmet brow dips to a point BETWEEN the eyes — the
                // wedge that turns one black band into two angled eye
                // recesses, which is most of what makes a Gundam face a
                // Gundam face. White, not red: the crest stays up on the
                // helmet, and the old red pixel here read as a third eye.
                b.rect(15 + dx, 13 + dy, 3, 1, .body)
                b.pixel(16 + dx, 14 + dy, .body)
                // The nose: a small steel block dropping from the brow
                // wedge's point, splitting the visor's black between the eye
                // recesses the way every reference mask does. Body pass, so
                // the eyes still paint after it — the face stays his.
                b.pixel(16 + dx, 15 + dy, .steel)
                b.pixel(16 + dx, 16 + dy, .steel)
                // THE CARVE — the operator's grant: "you can adjust clawd's
                // body so it isn't a full square, angle it like the
                // reference", deepened on the sixth fitting ("the angled
                // parts more apparent"): a five-cell diagonal off each dome
                // corner and one cell off each jaw corner. `.clear` is a raw
                // erase; the cells track the squash the way the flanks do.
                // On the body pass, so the shape survives a crown prop (the
                // yield suppresses `.front` only) — and a costume crossfade
                // re-squares the corners until it settles, which the
                // whole-shell pixel dissolve visually absorbs.
                let dome = bodyY + dy + squash
                for side in [bodyX + dx - squash, bodyX + bodyW - 3 + dx + squash] {
                    b.pixel(side, dome, .clear)
                    b.pixel(side + 1, dome, .clear)
                    b.pixel(side + 2, dome, .clear)
                }
                for side in [bodyX + dx - squash, bodyX + bodyW - 2 + dx + squash] {
                    b.pixel(side, dome + 1, .clear)
                    b.pixel(side + 1, dome + 1, .clear)
                }
                b.pixel(bodyX + dx - squash, 20 + dy, .clear)
                b.pixel(bodyX + bodyW - 1 + dx + squash, 20 + dy, .clear)
                // 👁 The glow — "the eyes more glowly": a warm bloom
                // spilling off each camera into the visor's black, one
                // column outboard of each eye. Ember at rest; during a flare
                // window (`97 &+ 41`, next free costume-effect addend — the
                // holiday round has 3/5/7/17/37 reserved) it steps to gold.
                // A re-ink between adjacent warm tones on cells already lit
                // — the arcade marquee's class of scheduled swap, not an
                // appearance — and it lives on the body pass, so a sideways
                // gaze draws the eye OVER the bloom, never under it.
                let flare = Self.effectWindow(at: pose.propPhase, salt: 41,
                                              period: 7, duration: 0.6, chance: 0.5) != nil
                let bloom: PixelBuffer.Ink = flare ? .yellow : .ember
                b.pixel(9 + dx, 14 + dy, bloom)
                b.pixel(22 + dx, 14 + dy, bloom)
                break
            }
            guard layer == .front else { break }
            let crown = bodyY + dy + squash
            // The RX-78 head, fifth fitting — the operator's 16-bit
            // reference, "almost 1:1". The stack from the top: green sensor
            // gem in a steel housing, the red shield running from under it
            // DOWN ONTO the white forehead, and the two-tone fin blades
            // rooting INTO the helmet beside it.
            //
            // The blades: orange (`.ember`) bodies with a gold highlight
            // riding the top edge over the root half, gold tips — metal
            // catching light, not a drawn line. The last step drops
            // vertically INTO the shell edge, per the operator: "bring the
            // little \ / down into the white part."
            for step in 0..<7 {
                let blade: PixelBuffer.Ink = step == 0 ? .yellow : .ember
                b.pixel(8 + step + dx, crown - 7 + step, blade)
                b.pixel(23 - step + dx, crown - 7 + step, blade)
                if step >= 4 {                          // 2px roots → 1px tips
                    b.pixel(8 + step + dx, crown - 8 + step, .yellow)
                    b.pixel(23 - step + dx, crown - 8 + step, .yellow)
                }
            }
            b.pixel(14 + dx, crown, .ember)             // the roots land on the shell
            b.pixel(17 + dx, crown, .ember)
            // The sensor gem: a green square in a steel housing above the
            // blades' crossing — the head's brightest jewel after the eyes.
            b.pixel(14 + dx, crown - 4, .steel)
            b.pixel(17 + dx, crown - 4, .steel)
            b.rect(15 + dx, crown - 4, 2, 1, .green)
            b.pixel(14 + dx, crown - 3, .steel)
            b.pixel(17 + dx, crown - 3, .steel)
            b.rect(15 + dx, crown - 3, 2, 1, .green)
            // The red shield, ON the white part per the operator: a column
            // from under the gem down the forehead, widest just above the
            // brow, tapering into the wedge's point. Rows crown-2…crown+2 —
            // the top two ride the helmet edge, the bottom three are on the
            // shell itself.
            b.rect(15 + dx, crown - 2, 2, 1, .costumeB)
            b.rect(15 + dx, crown - 1, 2, 1, .costumeB)
            b.rect(15 + dx, crown, 2, 1, .costumeB)
            b.rect(14 + dx, crown + 1, 4, 1, .costumeB)
            b.rect(15 + dx, crown + 2, 2, 1, .costumeB)
            // The dome corners, sixth fitting: RED duct cells riding the
            // carved diagonal's edge — the operator's "on each side on the
            // top we get the red part", and nothing else up there. The
            // first cut stacked red, blue AND a shadow down each angle,
            // one pixel of each, and the crown read as confetti: at this
            // scale an angle gets ONE colour.
            b.pixel(bodyX + 3 + dx - squash, crown, .costumeB)
            b.pixel(bodyX + 2 + dx - squash, crown + 1, .costumeB)
            b.pixel(bodyX + bodyW - 4 + dx + squash, crown, .costumeB)
            b.pixel(bodyX + bodyW - 3 + dx + squash, crown + 1, .costumeB)
            b.rect(bodyX + 2 + dx, 17 + dy, 2, 1, .bodyShade)
            b.rect(bodyX + bodyW - 4 + dx, 17 + dy, 2, 1, .bodyShade)
            b.rect(bodyX + dx - squash, 17 + dy, 2, 3, .bodyShade)
            b.rect(bodyX + bodyW - 2 + dx + squash, 17 + dy, 2, 3, .bodyShade)
            // Side armor running down both flanks from the shoulders. Two
            // columns, not three: the visor recess starts at `bodyX + 2`, and
            // a wider flank would eat its frame.
            b.rect(bodyX + dx - squash, crown + 2, 2, 5, .costumeA)
            b.rect(bodyX + bodyW - 2 + dx + squash, crown + 2, 2, 5, .costumeA)
            // Yellow temple pods on the cheeks, level with the visor — the
            // reference heads all carry them.
            b.pixel(bodyX + 1 + dx - squash, crown + 4, .yellow)
            b.pixel(bodyX + bodyW - 2 + dx + squash, crown + 4, .yellow)
            // Vent slits cut into the side armor, bracketing each temple
            // pod — visor-black so the cuts read as depth, not decoration.
            for flank in [bodyX + dx - squash, bodyX + bodyW - 2 + dx + squash] {
                b.rect(flank, crown + 3, 2, 1, .costumeC)
                b.rect(flank, crown + 5, 2, 1, .costumeC)
            }
            // The chest band is two rows of plate now, widening with the
            // squash the way the shell does — anchored to the same
            // expressions as the shoulder plates, so a kickflip crouch cannot
            // open white gaps at its ends. Drawn FIRST so the collar, chin
            // and vents read as fittings on the plate rather than under it.
            b.rect(12 + dx - squash, 19 + dy, 9 + squash * 2, 2, .costumeA)
            // The COLLAR, per the reference: the band's top row re-plated
            // orange — an armor collar directly under the head, the fin
            // body's own ink, so head and collar rhyme.
            b.rect(12 + dx - squash, 19 + dy, 9 + squash * 2, 1, .ember)
            // The chin is a downward TRIANGLE, not a bar — five cells, then
            // three, converging the way the whole reference face does. ONE
            // pair of vents beside its point, nothing else: the first cut
            // scattered four yellow dots across two rows and the bottom read
            // as clutter instead of armor (the operator's note).
            b.rect(14 + dx, 19 + dy, 5, 1, .costumeB)
            b.rect(15 + dx, 20 + dy, 3, 1, .costumeB)
            b.pixel(13 + dx, 20 + dy, .yellow)
            b.pixel(19 + dx, 20 + dy, .yellow)
            for (index, leg) in CrabRig.legX.enumerated() {  // boots, riding the gait
                let lift = max(0, CrabRig.legSwing(index, pose: pose))
                // The boot is as tall as the leg has room for: a lift of two
                // leaves a two-row leg, and a three-row boot on it rode one
                // row up onto the shell for the whole of a kickflip's air —
                // the audit's catch, invisible on the contact sheet because
                // no staged frame was mid-air.
                let height = min(3, 4 - lift)
                b.rect(leg + dx, 24 + dy - lift - height + 1, 2, height, .costumeB)
            }

            // Already narrowed to the front pass by the guard above — the
            // sonic case's own note tells this exact story.
            guard let scan = Self.effectWindow(at: pose.propPhase, salt: 19,
                                               period: 12, duration: 1.8, chance: 0.35)
            else { break }
            // The camera sweeping: a two-column beam easing across his shell
            // — camera-gold leading, steel trailing — drawn only where the
            // cell is still `.body`. That mask puts it BEHIND the visor and
            // the eyes rather than over them: a scan that blanked the eyes it
            // is meant to be looking through would be the wardrobe covering a
            // face, which is the one forbidden thing.
            //
            // The first cut painted `.paper` — kraft white on an RX-78 white
            // shell, a camera nobody ever saw. Ink and cadence are the
            // operator's picks off the contact sheet: slower (12s period,
            // 0.35 chance, 1.8s crossing) and gold, so when it happens it
            // reads as an event.
            // The eased sweep runs three columns PAST the shell on both
            // sides, so smoothstep's zero-slope ends park the beam where the
            // `.body` mask finds nothing — the audit caught it parking ON
            // the shell for a quarter second at each end, popping a handful
            // of gold cells in and out in one frame. Now entry and exit are
            // the mask running out of shell: geometric, the shuriken's
            // defense again.
            let sweep = Ease.smoothstep(scan)
            let column = bodyX - 3 + dx + Int(sweep * Double(bodyW + 6))
            for (offset, ink) in [(0, PixelBuffer.Ink.yellow), (-1, .steel)] {
                let x = column + offset
                guard x >= 0, x < PixelBuffer.side else { continue }
                for row in 0..<PixelBuffer.side where b[x, row] == .body {
                    b.pixel(x, row, ink)
                }
            }

        case .pumpkin:
            let crown = bodyY + dy + squash
            if layer == .onBody {
                // Rib shadows in the brow band — the gourd's segments —
                // and a carved zigzag grin across the chin band. His own
                // dark mouth sits between them and reads as more carving.
                for x in [9, 16, 23] {
                    b.rect(x + dx, crown, 1, 3, .costumeC)
                }
                for (i, x) in stride(from: 12, through: 20, by: 2).enumerated() {
                    b.pixel(x + dx, 19 + dy + (i % 2), .costumeB)
                }
                break
            }
            guard layer == .front else { break }
            // The stem, with one leaf curl.
            b.rect(15 + dx, crown - 2, 2, 2, .costumeA)
            b.pixel(17 + dx, crown - 1, .costumeA)
            // 🕯 The candle flicker: the carved teeth glow from inside for a
            // beat — the arcade's "lit from within" move. Salt 97 &+ 41 is
            // the gundam flare's; this family shares by addend, and the
            // holiday round's reserved addends are 3/5/7/17/37 — the flicker
            // takes 5.
            if Self.effectWindow(at: pose.propPhase, salt: 5,
                                 period: 8, duration: 0.6, chance: 0.5) != nil {
                for (i, x) in stride(from: 12, through: 20, by: 2).enumerated() {
                    b.pixel(x + dx, 19 + dy + (i % 2), .yellow)
                }
            }

        case .turkey:
            let crown = bodyY + dy + squash
            if layer == .behind {
                // The tail fan, third cut. The first was seven thin spokes
                // with a yellow dot on each tip, and the operator's "a bit
                // confusing" was right: it read as candles on a stand. The
                // second was five wide paddles with banded tips, and those
                // read as bottles. Both drew feathers as THINGS standing on
                // his head, and that is the actual mistake — a tom's fan is
                // not a row of objects, it is one SHAPE: a half-disc split
                // into radial wedges. So this draws exactly that. Every cell
                // inside a half-circle over the crown is painted by its
                // angle from the centre — five wedges, gold and dark
                // alternating — and the outer two cells of radius flip to
                // the wedge's contrast colour, the eyespot band real fans
                // carry along their rim. No yellow anywhere. Drawn behind
                // him, so the shell cuts through and the fan reads as HIS.
                let strut = Self.effectWindow(at: pose.propPhase, salt: 7,
                                              period: 9, duration: 0.9, chance: 0.5) != nil
                // The strut spreads the fan a cell wider all round.
                let radius = 9.0 + (strut ? 1.0 : 0.0)
                let centreX = Double(bodyX) + Double(bodyW) / 2
                let baseline = Double(crown)
                let reach = Int(radius.rounded(.up))
                for y in (crown - reach)...(crown - 1) {
                    for x in (Int(centreX) - reach - 1)...(Int(centreX) + reach) {
                        let ex = Double(x) + 0.5 - centreX
                        let ey = baseline - Double(y) - 0.5
                        let r = (ex * ex + ey * ey).squareRoot()
                        guard r <= radius else { continue }
                        let wedge = min(4, Int(atan2(ey, ex) / (.pi / 5)))
                        let gold = wedge % 2 == 0
                        let band = r > radius - 2
                        b.pixel(x + dx, y, gold != band ? .costumeC : .costumeA)
                    }
                }
                break
            }
            if layer == .onBody {
                // The wattle, hanging beside his mouth.
                b.rect(14 + dx, 18 + dy, 1, 2, .costumeB)
                break
            }

        case .santa:
            let crown = bodyY + dy + squash
            if layer == .onBody {
                // The scarf: a red band across the chin rows with a dropped
                // tail in the leg gap and one trim fringe pixel.
                b.rect(bodyX + 1 + dx - squash, 19 + dy, bodyW - 2 + squash * 2, 1, .costumeA)
                b.rect(22 + dx, 20 + dy, 2, 1, .costumeA)
                b.pixel(22 + dx, 21 + dy, .costumeB)
                break
            }
            guard layer == .front else { break }
            // The hat: white brim over the crown edge, red triangle sagging
            // right, pom at its tip.
            b.rect(bodyX + 2 + dx - squash, crown, bodyW - 4 + squash * 2, 1, .costumeB)
            b.rect(11 + dx, crown - 1, 12, 1, .costumeA)
            b.rect(13 + dx, crown - 2, 9, 1, .costumeA)
            b.rect(16 + dx, crown - 3, 6, 1, .costumeA)
            b.pixel(21 + dx, crown - 4, .costumeA)
            b.pixel(22 + dx, crown - 4, .costumeB)
            // ❄️ The breath: two paper puffs drifting off his face on cold
            // dice — clear cells only, never over him.
            if let puff = Self.effectWindow(at: pose.propPhase, salt: 17,
                                            period: 10, duration: 0.8, chance: 0.4) {
                let drift = Int((puff * 3).rounded())
                for (i, cell) in [(27 + drift, 14), (28 + drift, 13)].enumerated() where i <= drift {
                    if b[cell.0 + dx, cell.1 + dy] == .clear {
                        b.pixel(cell.0 + dx, cell.1 + dy, .paper)
                    }
                }
            }

        case .skater:
            let crown = bodyY + dy + squash
            if layer == .onBody {
                // The tee: a charcoal band across the lower shell with a
                // two-cell chest mark, and pads on all four legs riding the
                // gait the way every shoe here does.
                b.rect(bodyX + 1 + dx - squash, 18 + dy, bodyW - 2 + squash * 2, 3, .costumeA)
                b.rect(10 + dx, 19 + dy, 2, 1, .paper)
                for (index, leg) in CrabRig.legX.enumerated() {
                    let lift = max(0, CrabRig.legSwing(index, pose: pose))
                    b.rect(leg + dx, 22 + dy - lift, 2, 1, .costumeC)
                }
                break
            }
            guard layer == .front else { break }
            // The backwards cap: dome over the crown, the bill sticking out
            // BEHIND him (his gaze rides right down the line, so the bill
            // points left), button on top.
            b.rect(12 + dx, crown, 8, 1, .costumeB)
            b.rect(13 + dx, crown - 1, 6, 1, .costumeB)
            b.pixel(16 + dx, crown - 2, .costumeB)
            b.rect(8 + dx, crown - 1, 4, 1, .costumeB)
            // 💨 The kick-push: two short dashes behind his feet now and
            // then, like he just pushed off. Salt 43 on the 97 family.
            if Self.effectWindow(at: pose.propPhase, salt: 43,
                                 period: 9, duration: 0.8, chance: 0.45) != nil {
                b.rect(3 + dx, 22 + dy, 2, 1, .shadow)
                b.rect(2 + dx, 24 + dy, 2, 1, .shadow)
            }

        case .sonic:
            let crown = bodyY + dy + squash
            if layer == .onBody {
                // The connected eye field — the canonical Sonic read, off the
                // operator's pick from the contact sheet. One white patch
                // spanning both sockets and the bridge between them, corners
                // cut so it sits in the face rather than across it like a
                // visor. Drawn on the body pass, so the face pass paints the
                // eyes OVER it: the field frames them, the eye-cover ban is
                // honored by draw order.
                // One row deeper than the sockets on both sides of the
                // middle band: his gaze shifts the eyes a row down (the
                // standard working gaze), and the audit caught their bottom
                // row sliding off the patch. The muzzle draws next and takes
                // this bottom row's centre back, so the extra white survives
                // only in the under-eye margins where it is needed.
                b.rect(10 + dx, 12 + dy, 12, 1, .paper)
                b.rect(9 + dx, 13 + dy, 14, 3, .paper)
                b.rect(10 + dx, 16 + dy, 12, 1, .paper)
                // The muzzle-and-belly tan; the face pass draws the mouth
                // over it, and the eyes stay his own.
                b.rect(12 + dx, 16 + dy, 8, 4, .costumeC)
                // Red sneakers with white socks, on all four feet — offset by
                // the same gait swing the legs shorten by, so a scuttle's
                // lifted foot takes its shoe with it. The stack shrinks with
                // the leg: a lift of two leaves two rows of leg, so the sock
                // sits out that step rather than riding onto the shell (the
                // same breach the audit caught on the gundam boots).
                for (index, leg) in CrabRig.legX.enumerated() {
                    let lift = max(0, CrabRig.legSwing(index, pose: pose))
                    let height = min(3, 4 - lift)
                    let top = 24 + dy - lift - height + 1
                    if height == 3 { b.rect(leg + dx, top, 2, 1, .paper) }
                    b.rect(leg + dx, top + (height == 3 ? 1 : 0), 2, min(2, height), .costumeB)
                }
                break
            }
            guard layer == .front else { break }
            // The quills, all in the shadow blue so they read against the
            // shell — recut to the operator's "sharp spike" pick, with more
            // mass everywhere: a stacked crest narrowing to a single point
            // over the crown, and two-row flares past each flank.
            b.rect(13 + dx, crown - 2, 6, 1, .costumeA)
            b.rect(14 + dx, crown - 3, 4, 1, .costumeA)
            b.rect(15 + dx, crown - 4, 2, 1, .costumeA)
            b.pixel(16 + dx, crown - 5, .costumeA)
            b.rect(10 + dx, crown - 1, 3, 1, .costumeA)
            b.rect(10 + dx, crown - 2, 2, 1, .costumeA)
            b.rect(19 + dx, crown - 1, 3, 1, .costumeA)
            b.rect(20 + dx, crown - 2, 2, 1, .costumeA)
            b.rect(3 + dx, 12 + dy, 3, 1, .costumeA)
            b.rect(3 + dx, 13 + dy, 2, 1, .costumeA)
            b.rect(26 + dx, 12 + dy, 3, 1, .costumeA)
            b.rect(27 + dx, 13 + dy, 2, 1, .costumeA)

            // 👀 Bigger eyes — the operator's note, and the canonical Sonic
            // read: TALL ovals, not wide ones. The costume adds one row above
            // each open eye in the eye's own ink and walks the catchlight up
            // with it (repainting the old catchlight cell, or the eye carries
            // two lights). Drawn on the front pass, AFTER drawFace, so this
            // extends what the face drew instead of racing it — the same
            // draw-order trick the eye field uses underneath. Round eyes
            // only: `.determined` carves its brow slant into the top row and
            // growing it would flatten the focus back out, `.wide` is already
            // a row taller, and a shut lid is one row by design — a bar
            // floating above a blink reads as a second eyebrow.
            if pose.eyes == .round {
                for (side, baseX) in [(CrabPose.EyeSide.left, CrabRig.eyeLeftX),
                                      (.right, CrabRig.eyeRightX)] {
                    let shut = (pose.blink > 0.5 && !pose.asleepOverride)
                        || pose.winkEye == side
                    guard !shut else { continue }
                    let x = baseX + dx + pose.gazeX
                    let top = CrabRig.eyeY + dy + pose.gazeY - 1
                        + (side == .left ? -pose.tilt : pose.tilt)
                    b.rect(x, top, CrabRig.eyeSize, 1, .eye)
                    b.pixel(x, top + 1, .eye)
                    b.pixel(x, top, .paper)
                }
            }

            // 💍 The golden rings, arcing through his airspace right to left.
            // Scheduled on their own addend (salt 29), or handed a flight
            // directly by the secret-menu preview — one draw, two triggers,
            // and the preview wins because dice never roll when a flight is
            // already in hand. BEFORE the dash guard, deliberately: the dash's
            // `break` ends the whole case, and rings that only flew during a
            // dash would be the unreachable-effect bug this case already
            // documents once.
            if let flight = pose.ringFlight
                ?? Self.effectWindow(at: pose.propPhase, salt: 29,
                                     period: 8, duration: 2.0, chance: 0.4) {
                drawRings(&b, flight: flight)
            }

            // No layer check here, and that is not an omission: the quills'
            // `guard layer == .front` above already narrowed this case to the
            // front pass, so everything below it is front-only. The first
            // version asked for `.behind` and was simply unreachable — the
            // render showed nothing at all and it took reading the case's
            // shape, not the effect's code, to see why.
            guard let dash = Self.effectWindow(at: pose.propPhase, salt: 23,
                                               period: 9, duration: 1.6, chance: 0.4)
            else { break }
            // A real dash — the operator's pick: rarer (9s period, 0.4
            // chance), longer (1.6s), TWO lanes instead of three blinky ones,
            // and afterimage ticks off his back legs while it peaks. He is
            // standing still, so the lines do all the work — the same trick
            // the skate cruise uses and for the same reason: on a fixed
            // camera the world moves and the character does not.
            // TRAVELING segments, not parked bars — the audit caught the
            // first cut appearing and vanishing a dozen cells at a time at
            // the window edges while clamps pinned it motionless at the
            // screen edge in between. Now the streak IS its own envelope:
            // `reach` rides sin(π·u), the segment's length is min(3, reach),
            // so it is born as a single cell beside him (glint-class), grows
            // while it travels outward, runs off-grid, and comes back the
            // same way — geometry eases both ends, the shuriken's defense.
            let peak = sin(dash * .pi)
            let reach = Int((peak * 6).rounded())
            let len = min(3, reach)
            if len > 0 {
                for lane in 0..<2 {
                    let y = bodyY + dy + 4 + lane * 6
                    // `.paper`, not `.costumeA`. That slot is his quill
                    // shadow-blue — a dark blue streak beside a blue crab on
                    // a dark desktop is three kinds of invisible, and the
                    // render proved it by showing nothing at all. Speed lines
                    // are white because speed lines have always been white.
                    b.rect(bodyX + dx - 2 - reach, y, len, 1, .paper)
                    b.rect(bodyX + bodyW + dx + 2 + reach - len, y, len, 1, .paper)
                }
            }
            // The afterimages: the back legs' trailing columns go quill-blue
            // through the dash's peak — motion blur ON him, painted only over
            // his own lit cells (masked to `.body`), never onto the desktop,
            // where the audit showed shadow-blue floats invisibly. A two-cell
            // repaint is glint-class: it snaps by nature, inside an eased
            // window.
            if peak > 0.45 {
                for (x, y) in [(7, 22), (11, 22)] where b[x + dx, y + dy] == .body {
                    b.pixel(x + dx, y + dy, .costumeA)
                }
            }

        }
    }

    /// Three rings in staggered flight: enter off-grid right, cross the sky
    /// rows, exit off-grid left — geometry is the no-snap defense, exactly the
    /// shuriken's. The spin is width: 5-wide, 3-wide, edge-on, 3-wide, the
    /// shuriken's two-frame trick with one more step. `.yellow` ring,
    /// `.flameCore` highlight — StarMark's costume-immune key. Every cell is
    /// masked to `.clear`, so quills, props and the glyph box keep their own.
    private static func drawRings(_ b: inout PixelBuffer, flight: Double) {
        for k in 0..<3 {
            let p = min(1.0, max(0.0, flight * 1.3 - Double(k) * 0.15))
            guard p > 0, p < 1 else { continue }
            let x = 30 - Int(p * 38)
            // One whole-pixel crest over his head at mid-flight.
            let y = 2 + ((0.35...0.65).contains(p) ? -1 : 0)
            ringStamp(&b, x: x, y: y, frame: Int(p * 16))
        }
    }

    private static func ringStamp(_ b: inout PixelBuffer, x: Int, y: Int, frame: Int) {
        func put(_ px: Int, _ py: Int, _ ink: PixelBuffer.Ink) {
            guard px >= 0, px < PixelBuffer.side, py >= 0, py < PixelBuffer.side,
                  b[px, py] == .clear else { return }
            b.pixel(px, py, ink)
        }
        switch frame % 4 {
        case 0:  // full face, 5 wide
            for c in 1...3 { put(x + c, y, .yellow); put(x + c, y + 4, .yellow) }
            for r in 1...3 { put(x, y + r, .yellow); put(x + 4, y + r, .yellow) }
            put(x + 4, y + 2, .flameCore)
        case 2:  // edge-on, 1 wide
            for r in 0...4 { put(x + 2, y + r, .yellow) }
            put(x + 2, y + 2, .flameCore)
        default: // three-quarter, 3 wide
            for r in 0...4 { put(x + 1, y + r, .yellow) }
            put(x + 3, y + 2, .yellow)
            put(x + 2, y + 2, .flameCore)
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
    /// Read by the gundam's eye-variant dice: the wear moment is the seed,
    /// so one wearing keeps one pair of eyes.
    private(set) var changedAt: Double = -.infinity

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
