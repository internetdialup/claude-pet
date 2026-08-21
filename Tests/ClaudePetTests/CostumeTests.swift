import Testing
import Foundation
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
                    let pose = CrabAnimator.pose(mood: mood, t: Double(step) * 0.5)
                    guard pose.blink < 0.5 else { continue }

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
