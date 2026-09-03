import Testing
import Foundation
import SwiftUI
@testable import ClaudePet

/// The wardrobe contract: every costume renders on every mood without touching
/// the eyes, yields its crown to a crown prop, and round-trips through
/// `Preferences` by raw value.
@Suite("Costumes")
struct CostumeTests {

    /// Eye cells are the character. A costume may frame them (the ninja mask's
    /// window) but never paint over an open eye.
    @Test func noCostumeCoversAnOpenEye() {
        for costume in Costume.allCases {
            for mood in PetMood.allCases where mood != .sleeping {
                for step in 0..<12 {
                    var pose = CrabAnimator.pose(mood: mood, t: Double(step) * 0.5)
                    guard pose.blink < 0.5 else { continue }
                    // Both renders must sit at the same height for a
                    // cell-by-cell comparison to mean anything, and a
                    // tall-crowned costume is now lifted less than a bare
                    // crab is — so ask for a height every look can reach.
                    pose.bob = max(pose.bob, CrabRig.crownFloor(costume: costume,
                                                                ghostCostume: .none,
                                                                headwear: pose.headwear))

                    let bare = CrabRig.render(pose)
                    let dressed = CrabRig.render(pose, costume: costume)
                    for y in 0..<PixelBuffer.side {
                        for x in 0..<PixelBuffer.side where bare[x, y] == .eye {
                            #expect(dressed[x, y] == .eye,
                                    "\(costume.rawValue) covers an eye at (\(x),\(y)) in \(mood.rawValue)")
                        }
                    }
                }
            }
        }
    }

    /// **A declared measurement nobody re-measures is a comment.**
    ///
    /// `crownRows` tells the rig how high a look reaches so it can stop him
    /// jumping his hat off the grid. If a costume grows a taller crest and
    /// this number stays put, the crest silently starts clipping again — the
    /// exact bug it was added to fix. So it is checked against what the
    /// costume actually draws, at a height where nothing can clip.
    @Test("Every costume's declared crown room is the room it uses")
    func crownRoomIsHonest() {
        var pose = CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
        pose.bob = 0
        for costume in Costume.allCases {
            // Arctic White's snow is the world's weather, not a hat: it
            // falls above his crown without being attached to it, so it is
            // measured out rather than counted as headroom.
            guard costume != .white else { continue }
            let buffer = CrabRig.render(pose, costume: costume)
            var highest = CrabRig.bodyY
            for y in 0..<CrabRig.bodyY {
                for x in 0..<PixelBuffer.side where buffer[x, y] != .clear {
                    highest = min(highest, y)
                    break
                }
            }
            let used = CrabRig.bodyY - highest
            #expect(CostumeStyle.of(costume).crownRows == used,
                    "\(costume) declares \(CostumeStyle.of(costume).crownRows) crown rows and draws \(used)")
        }
    }

    /// Every costume × mood × a spread of times renders without trapping and
    /// still paints something.
    @Test func everyCostumeRendersEverywhere() {
        for costume in Costume.allCases {
            for mood in PetMood.allCases {
                for step in 0..<8 {
                    let pose = CrabAnimator.pose(mood: mood, t: Double(step) * 0.7)
                    let buffer = CrabRig.render(pose, costume: costume)
                    #expect(!buffer.runs().isEmpty)
                }
            }
        }
    }

    /// Crown accessories step aside for the hard hat; status beats wardrobe.
    /// The yield suppresses the whole `.front` layer — under a hard hat the
    /// Gundam also loses his chest band and red feet for the 20-second prop
    /// spell, which is accepted and documented at the yield site. The visor
    /// lives on the `.onBody` layer and rightly persists: it is the face,
    /// not the crown.
    @Test func crownAccessoryYieldsToTheHardHat() {
        var pose = CrabPose()
        pose.prop = .hardHat
        let dressed = CrabRig.render(pose, costume: .gundam)

        // No costume ink in the crown band — the V-fin and crest stand down.
        for y in 0..<10 {
            for x in 0..<PixelBuffer.side {
                let ink = dressed[x, y]
                #expect(ink != .costumeA && ink != .costumeB && ink != .costumeC,
                        "gundam crown pixel at (\(x),\(y)) under the hard hat")
            }
        }

        // The visor recess is the new bow tie: nowhere near the crown, stays.
        var visorSeen = false
        for y in 13...16 {
            for x in 0..<PixelBuffer.side where dressed[x, y] == .costumeC {
                visorSeen = true
            }
        }
        #expect(visorSeen, "the visor is the face, not the crown — it stays")
    }

    /// `.none` must render byte-identically to the pre-costume rig.
    @Test func noCostumeIsTheIdentity() {
        for mood in PetMood.allCases {
            let pose = CrabAnimator.pose(mood: mood, t: 2.3)
            let bare = CrabRig.render(pose)
            let dressed = CrabRig.render(pose, costume: .none)
            #expect(bare.runs().count == dressed.runs().count)
            for (a, b) in zip(bare.runs(), dressed.runs()) {
                #expect(a.x == b.x && a.y == b.y && a.length == b.length && a.ink == b.ink)
            }
        }
    }

    /// Unknown raw values — a costume from a newer build — fall back to `.none`.
    @Test func unknownStoredCostumeFallsBack() {
        #expect(Costume(rawValue: "jetpack") == nil)
        let decoded = Costume(rawValue: "jetpack") ?? .none
        #expect(decoded == .none)
    }

    /// The blended override map hits its endpoints: at u=0 the outgoing
    /// wardrobe's colours, at u=1 the incoming one's.
    @Test func overrideBlendEndpoints() {
        let settled = CostumeStyle.blendedOverrides(from: .ninja, to: .ninja, u: 1)
        #expect(settled[.body] != nil)

        let arriving = CostumeStyle.blendedOverrides(from: .none, to: .ninja, u: 1)
        #expect(arriving[.body] == settled[.body])

        // Mid-blend the body colour is neither endpoint (mixing, not swapping).
        let mid = CostumeStyle.blendedOverrides(from: .none, to: .ninja, u: 0.5)
        #expect(mid[.body] != settled[.body])
    }
}

/// The tiger reads tiger: orange shell, darker stripes, lighter belly.
/// Sonic's golden rings: scheduled on `97 &+ 29`, drawn only into empty sky,
/// and never in a first cycle — the frozen sentinel every dice answers to.
@Suite("Sonic rings")
struct SonicRingTests {

    /// The cadence pin: chance 0.4 on the dice means about two cycles in five
    /// carry a flight. A drifted salt or chance moves this immediately.
    @Test func ringsFireAboutTwoCyclesInFive() {
        var fired = 0
        for cycle in 1...2000 where CrabAnimator.noise(cycle &* 97 &+ 29) < 0.4 {
            fired += 1
        }
        let rate = Double(fired) / 2000
        #expect(rate > 0.36 && rate < 0.44, "ring dice fire at \(rate)")
    }

    /// No scheduled flight in cycle zero, at any instant of it — a frozen
    /// render at small t must be a clean crab.
    @Test func scheduledRingsRespectTheSentinel() {
        for step in 0..<80 {
            #expect(CrabCostume.effectWindow(at: Double(step) * 0.1, salt: 29,
                                             period: 8, duration: 2.0, chance: 0.4) == nil)
        }
    }

    /// A flight paints gold into cells that were empty, and nowhere else: not
    /// over the quills, not below the sky rows, never anything but ring inks.
    @Test func ringsOnlyFillEmptySky() {
        // Cycle 0 on the prop clock, so the costume's own scheduled dash and
        // rings are silent and the staged flight is the only delta.
        var pose = CrabAnimator.pose(mood: .idle, t: 0.5, flourishes: false)
        pose.propPhase = 0.5
        let bare = CrabRig.render(pose, costume: .sonic)
        var sweep = false
        for step in 1...19 {
            var staged = pose
            staged.ringFlight = Double(step) * 0.05
            let dressed = CrabRig.render(staged, costume: .sonic)
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where dressed[x, y] != bare[x, y] {
                    sweep = true
                    #expect(bare[x, y] == .clear,
                            "a ring painted over \(bare[x, y]) at (\(x),\(y))")
                    #expect(dressed[x, y] == .yellow || dressed[x, y] == .flameCore,
                            "a ring drew \(dressed[x, y])")
                    #expect(y < 8, "a ring left the sky rows at (\(x),\(y))")
                }
            }
        }
        #expect(sweep, "no flight instant drew any ring at all")
    }
}

/// The gundam's rare cameras: the eye-variant plumbing is live-only by
/// construction, and these pin the two facts the view relies on — the
/// substitution reaches the blend's output, and the default path is
/// untouched so no offline render can ever roll it.
@Suite("Gundam eye variant")
struct GundamEyeVariantTests {

    @Test func variantSubstitutesTheIncomingEye() {
        let variant = (r: 0x2E / 255.0, g: 0x9C / 255.0, b: 0x80 / 255.0)
        let dressed = CostumeStyle.blendedOverrides(from: .none, to: .gundam, u: 1,
                                                    eyeVariant: variant)
        #expect(dressed[.eye] == Color(red: variant.r, green: variant.g, blue: variant.b))
        let plain = CostumeStyle.blendedOverrides(from: .none, to: .gundam, u: 1)
        #expect(plain[.eye] != dressed[.eye],
                "the default must stay camera-yellow — committed media depends on it")
    }

    /// About one wearing in four, over a spread of plausible wear stamps.
    @Test func variantDiceLandNearAQuarter() {
        var rolled = 0
        for stamp in 0..<4000 where CrabAnimator.noise((700_000_000 + stamp) &* 47 &+ 7) < 0.25 {
            rolled += 1
        }
        let rate = Double(rolled) / 4000
        #expect(rate > 0.22 && rate < 0.28, "variant dice fire at \(rate)")
    }
}

/// The gundam scan's visibility pin — the gap that let the original scan ship
/// white-on-white: no test ever rendered a live scan window, so an invisible
/// ink (or a deleted block) kept all 483 tests green.
@Suite("Gundam scan")
struct GundamScanTests {

    /// Mid-sweep vs no-sweep: the delta must exist, land only on cells that
    /// were shell, and use only the two beam inks — both of which must stay
    /// legible against the RX-78 white by more than a rounding error.
    @Test func theScanPaintsVisibleGold() {
        var lit = CrabAnimator.pose(mood: .idle, t: 1.0, flourishes: false)
        lit.propPhase = 36.9        // salt 19, cycle 3 (dice .145 < .35): 36.0…37.8
        var dark = lit
        dark.propPhase = 34.5       // cycle 2 misses (dice .587) — no window
        let swept = CrabRig.render(lit, costume: .gundam)
        let plain = CrabRig.render(dark, costume: .gundam)
        var cells = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where swept[x, y] != plain[x, y] {
                cells += 1
                #expect(plain[x, y] == .body,
                        "the beam painted over \(plain[x, y]) at (\(x),\(y))")
                #expect(swept[x, y] == .yellow || swept[x, y] == .steel,
                        "the beam drew \(swept[x, y])")
            }
        }
        #expect(cells > 0, "a live scan window painted nothing — the white-on-white bug again")
    }
}

@Suite("Tiger palette")
@MainActor
struct TigerPaletteTests {

    @Test func orangeNotGreen() throws {
        let inks = CostumeStyle.of(.tiger).inks
        let body = try #require(inks[.body])
        #expect(body.r > body.g && body.g > body.b, "a tiger is orange")

        let stripe = try #require(inks[.costumeA])
        #expect(stripe.r + stripe.g + stripe.b < body.r + body.g + body.b,
                "stripes sit darker than the shell")

        let patch = try #require(inks[.costumeC])
        #expect(patch.r + patch.g + patch.b > body.r + body.g + body.b,
                "the belly patch sits lighter than the shell")
        #expect(inks[.mouth] != nil, "a white mouth on the white patch is no mouth")
    }
}
