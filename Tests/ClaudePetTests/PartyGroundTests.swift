import Testing
import Foundation
@testable import ClaudePet

/// 🎉 **Party central.**
///
/// A third cut of the same grind with the room joining in: a plate that pulses
/// on the beat, rings leaving his truck, a crest travelling the ledge's edge and
/// pale hearts drifting up behind him.
///
/// What is pinned is the thing that makes ten moving layers survivable — the
/// VALUE AND SATURATION GAP — plus the arithmetic each layer is built on. Hue
/// cannot do the separating and this file says why in the one place someone
/// would go looking to change it.
@MainActor
struct PartyGroundTests {

    /// Hue, chroma and luminance recovered from an RGB triple, so every pin here
    /// asks what colour was PRODUCED rather than trusting what went in.
    private func hcl(_ rgb: SpriteTint.RGB) -> (hue: Double, chroma: Double, luma: Double) {
        let high = max(rgb.r, max(rgb.g, rgb.b)), low = min(rgb.r, min(rgb.g, rgb.b))
        let delta = high - low
        var hue = 0.0
        if delta > 1e-9 {
            if high == rgb.r { hue = (rgb.g - rgb.b) / delta }
            else if high == rgb.g { hue = 2 + (rgb.b - rgb.r) / delta }
            else { hue = 4 + (rgb.r - rgb.g) / delta }
            hue = hue / 6 - floor(hue / 6)
        }
        let luma = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        return (hue, high > 1e-9 ? delta / high : 0, luma)
    }

    private var reelLength: Double { SkateDemo.partyReel.seconds }

    /// 🔎 THE LAW THAT MAKES THE REST POSSIBLE.
    ///
    /// Ten moving layers on a 32-cell grid only survive on a hierarchy, and the
    /// hierarchy cannot be hue: `SpriteTint.neutralHue` is a TRIANGLE fold, so a
    /// backdrop offset half a period from his shell crosses it at both quarter
    /// points — `neutralHue(0.25)` and `neutralHue(0.75)` are the same number.
    /// His shell sweeps that fold four times across this clip, so a hue-matched
    /// backdrop would land on his exact colour eight times.
    ///
    /// Value and saturation have no such crossing, so they do the work: the
    /// whole backdrop lives in the light, unsaturated corner and he is the only
    /// saturated thing in frame.
    @Test("Nothing in the backdrop is ever dark or saturated")
    func theCeilingHolds() {
        #expect(neutralHueIsATriangle(), "the fold stopped being a triangle — re-read this pin")
        for step in 0...400 {
            let t = Double(step) / 400 * reelLength
            let plate = hcl(PartyGround.plateRGB(t, party: 1))
            #expect(plate.chroma <= PartyGround.chromaCeiling,
                    "the plate is \(plate.chroma) saturated at reel \(t)")
            #expect(plate.chroma * PartyGround.chromaRatio <= 0.85,
                    "the plate is within \(0.85 / plate.chroma)x of his shell's saturation")
            #expect(plate.luma >= PartyGround.valueFloor,
                    "the plate is \(plate.luma) bright at reel \(t)")
            // …and every ring, which mixes toward its own hue by its own amount.
            for ring in PartyGround.rings(t) {
                let target = SpriteTint.rgb(hue: ring.hue, saturation: 0.80, brightness: 0.90)
                let cream = PartyGround.creamRGB
                let a = PartyGround.ringAmount
                let mixed: SpriteTint.RGB = (r: cream.r + (target.r - cream.r) * a,
                                             g: cream.g + (target.g - cream.g) * a,
                                             b: cream.b + (target.b - cream.b) * a)
                let ringHCL = hcl(mixed)
                #expect(ringHCL.chroma <= PartyGround.chromaCeiling,
                        "a ring is \(ringHCL.chroma) saturated at reel \(t)")
                #expect(ringHCL.chroma * PartyGround.chromaRatio <= 0.85,
                        "a ring is within \(0.85 / ringHCL.chroma)x of his shell")
                #expect(ringHCL.luma >= PartyGround.valueFloor,
                        "a ring is \(ringHCL.luma) bright at reel \(t)")
            }
        }
        // …against his shell, which is four times the chroma. That gap is the
        // whole hierarchy; if it ever closes, he stops reading.
        let shell = hcl(SpriteTint.rgb(hue: 0.3, saturation: 0.85, brightness: 1.0))
        #expect(shell.chroma >= PartyGround.chromaCeiling * PartyGround.chromaRatio,
                "his shell is only \(shell.chroma) saturated — the gap has closed")
    }

    /// The fold's own shape, asserted rather than assumed, because the pin above
    /// reasons from it.
    private func neutralHueIsATriangle() -> Bool {
        abs(SpriteTint.neutralHue(0.25) - SpriteTint.neutralHue(0.75)) < 1e-12
    }

    /// 🔎 THE PLATE AND THE SHELL CAN SHARE A HUE, and this pin exists to say
    /// so out loud rather than to forbid it.
    ///
    /// The half-fold offset in `plateHue` looks like a complement and is not
    /// one: `neutralHue` is a triangle, so a half-period offset crosses the
    /// original at both quarter points. The first version of this test asserted
    /// they never come within 0.08 of each other and measured a separation of
    /// EXACTLY ZERO — the arithmetic was in the file's own doc comment and the
    /// assertion contradicted it.
    ///
    /// So what is pinned is what is actually true and actually keeps him
    /// readable: on every frame where they DO share a hue, the chroma gap still
    /// holds — he is three times more saturated than the room.
    @Test("Where the plate wears his hue, saturation still separates them")
    func theyMayShareAHueButNeverAValue() {
        var collisions = 0
        for step in 0...800 {
            let t = Double(step) / 800 * reelLength
            let plate = SkateDemo.plateHueForTests(t)
            guard let shell = CrabView.comboTint(t: t, combo: 1, costume: .skater) else { continue }
            let shellHCL = hcl((shell.r, shell.g, shell.b))
            let apart = abs(plate - shellHCL.hue)
            guard min(apart, 1 - apart) < 0.03 else { continue }
            collisions += 1
            let plateHCL = hcl(PartyGround.plateRGB(t, party: 1))
            #expect(shellHCL.chroma >= plateHCL.chroma * PartyGround.chromaRatio,
                    "at reel \(t) they share a hue and he is only \(shellHCL.chroma / plateHCL.chroma)x more saturated")
        }
        #expect(collisions > 0, "they never share a hue — the triangle argument no longer applies")
    }

    /// 🔎 THREE COLOURS, HELD — not a continuous slide. A GIF's colour table is
    /// global across all hundred and sixty frames and holds 256 entries, and
    /// `comboTint` already regenerates two inks from a continuous hue on every
    /// one of them. A plate that slid would spend the rest of the table, and a
    /// plate that recoloured every pixel every frame would defeat the disposal-1
    /// delta coding the opaque render buys.
    @Test("The plate steps on the beat, through three colours, and never through the ribbon's")
    func thePlateHoldsItsColours() {
        var seen: Set<Int> = []
        for step in 0...800 {
            let t = Double(step) / 800 * reelLength
            seen.insert(Int((SkateDemo.plateHueForTests(t) * 1000).rounded()))
        }
        // Three held colours plus the eased crossings between them.
        let held = seen.filter { hue in
            [0, 279, 558].contains { abs(hue - $0) <= 1 }
        }
        #expect(held.count >= 3, "the plate only settles on \(held.count) colours")
        // …and it never HOLDS the ribbon's two brightest stripes. It transits
        // them on the eased crossings — a sixth of a beat — which reads as a
        // change rather than as a colour, so the pin is about dwell, not reach.
        var yellowFrames = 0
        for step in 0...800 {
            let t = Double(step) / 800 * reelLength
            let hue = SkateDemo.plateHueForTests(t)
            if hue > 0.100 && hue < 0.135 { yellowFrames += 1 }
        }
        #expect(Double(yellowFrames) / 800 < 0.08,
                "the plate spends \(Double(yellowFrames) / 8) per cent of the clip in the ribbon's yellow")
    }

    /// The rings expand a whole cell a frame at the rate the clip is watched at,
    /// and their weight rides their THICKNESS — a whole-pixel step, which is the
    /// grid's own quantum and the one motion the no-snap rule exempts. A band
    /// changing brightness in place would be exactly the change it bans.
    @Test("The rings step one cell a frame, and change thickness one cell at a time")
    func theRingsStepWholeCells() {
        let fps = Double(SkateDemo.gifFps)
        for n in 0...6 {
            var previousRadius = -1
            var previousThickness = 0
            for step in 0...Int(PartyGround.ringLife * fps) {
                let t = Double(n) * PartyGround.ringPeriod + Double(step) / fps
                guard let ring = PartyGround.rings(t).first(where: {
                    $0.radius == Int((PartyGround.ringSpeed * (t - Double(n) * PartyGround.ringPeriod)).rounded())
                }) else { continue }
                if previousRadius >= 0 {
                    #expect(ring.radius - previousRadius == 1,
                            "ring \(n) jumped \(ring.radius - previousRadius) cells at step \(step)")
                    #expect(abs(ring.thickness - previousThickness) <= 1,
                            "ring \(n) changed thickness by \(abs(ring.thickness - previousThickness))")
                }
                previousRadius = ring.radius
                previousThickness = ring.thickness
            }
        }
        // Born on the beat, and nothing drawn while it is still inside him.
        #expect(PartyGround.ringPeriod == SkateDemo.beat, "the rings are off the house grid")
        #expect(PartyGround.ringThickness(radius: 2) == 0, "a ring draws inside his own silhouette")
    }

    /// The crest is a band travelling the ledge's edge — every visible column
    /// gets a strength, so it reads as a highlight rather than as three lit dots.
    @Test("The crest is a gradient on the ledge, and never leaves it")
    func theCrestStaysOnTheLedge() {
        var everLit = 0
        for step in 0...400 {
            let reel = Double(step) / 400 * reelLength
            let travel = SkateDemo.ridePose(reel: reel)?.ledge ?? 0
            let lit = SkateDemo.crest(travel: travel, t: reel)
            guard !lit.isEmpty else { continue }
            everLit = max(everLit, lit.count)
            let right = CrabRig.ledgeRightEnd(travel: travel)
            let left = right - (CrabRig.ledgeLength - 1)
            for cell in lit {
                #expect(cell.x >= max(0, left) && cell.x <= min(PixelBuffer.side - 1, right),
                        "the crest lit column \(cell.x) with the ledge at \(left)…\(right)")
                #expect(cell.level > 0 && cell.level <= 1, "the crest's level is \(cell.level)")
            }
        }
        // A band, not a dotted line: the first cut lit one column in twelve,
        // which is three cells on a thirty-two cell row and invisible at any
        // size the clip is watched at.
        #expect(everLit >= 12, "the crest only ever lights \(everLit) columns — that is a dotted line")
        // …and it is on the steel top row, leaving the dark slab alone. The slab
        // is the darkest large area in frame and what his silhouette reads
        // against.
        #expect(SkateDemo.crestRow == 24, "the crest moved off the ledge's lit edge")
    }

    /// The hearts keep to the outer thirds. The middle is the widest span his
    /// body takes at any magnification, and a glyph field that reserves columns
    /// around the subject is the same thing `heartColumns` already does around
    /// the service glyph.
    @Test("The hearts stay out of his way")
    func theHeartsKeepTheirColumns() {
        for step in 0...400 {
            let t = Double(step) / 400 * reelLength
            for heart in PartyGround.hearts(t) {
                #expect(heart.x < 0.30 || heart.x > 0.70,
                        "a heart is at \(heart.x), inside the span his body takes")
                #expect(heart.y >= -0.05 && heart.y <= 1.05, "a heart is at \(heart.y)")
            }
        }
        #expect(PartyGround.heartOpacity < 0.2, "the hearts are no longer the faintest thing in frame")
    }

    /// 🔎 THE LAYERS TAKE TURNS. Through the grind the sprite side is already
    /// carrying seven layers, so the backdrop drops to its floor; by the finale
    /// the ledge, the hedge and the sparks have all gone, so it takes over.
    /// What changes across the reel is not how much is moving — it is which side
    /// of the sprite box it is on.
    @Test("The backdrop gets out of the grind's way and takes over the finale")
    func theLayersTakeTurns() {
        let grind = stride(from: 3.2, through: 5.2, by: 0.1).map { SkateDemo.partyLevel(reel: $0) }
        let finale = stride(from: 6.6, through: 7.9, by: 0.1).map { SkateDemo.partyLevel(reel: $0) }
        // 🔎 Against the NUMBER, not against the constant that produced it. The
        // first cut of this line compared the grind's level to
        // `SkateDemo.partyFloor + 0.06` — both sides moved together when that
        // constant did, so raising the floor to 1.0 and abolishing the duck
        // entirely left the pin green. A third is the claim; a third is what is
        // written.
        #expect(grind.allSatisfy { $0 <= 0.33 },
                "the backdrop is at \(grind.max() ?? 0) through the grind")
        #expect(finale.allSatisfy { $0 > 0.9 },
                "the backdrop only reaches \(finale.min() ?? 0) in the finale")
        // …and the duck is a real duck: the gap between the two windows is most
        // of the range, not a tenth of it.
        #expect((finale.min() ?? 0) - (grind.max() ?? 1) > 0.5,
                "the backdrop barely changes between the grind and the finale")
        // It arrives with the ride rather than being on from frame zero…
        #expect(SkateDemo.partyLevel(reel: 0) < 0.01, "the party is on before the ride starts")
        // …and it eases, never steps.
        var previous = SkateDemo.partyLevel(reel: 0)
        for step in 1...800 {
            let now = SkateDemo.partyLevel(reel: Double(step) / 800 * reelLength)
            #expect(abs(now - previous) < 0.05, "the party level jumped at step \(step)")
            previous = now
        }
    }

    /// The A/B stays an A/B: the party is a third cut, and the two the operator
    /// is comparing are untouched by it.
    @Test("The party reel is a third cut, and the other two are not party reels")
    func theOtherTwoAreUntouched() {
        #expect(SkateDemo.reels.count == 3)
        #expect(SkateDemo.reels.filter { $0.name.hasSuffix("party") }.count == 1,
                "more than one reel is a party reel")
        for reel in SkateDemo.reels where !reel.name.hasSuffix("party") {
            #expect(!reel.name.contains("party"))
        }
        // All three play the identical shot list, so the framing is comparable.
        for reel in SkateDemo.reels {
            #expect(reel.shots.count == SkateDemo.shots.count)
            #expect(reel.seconds == SkateDemo.plainReel.seconds)
        }
    }
}
