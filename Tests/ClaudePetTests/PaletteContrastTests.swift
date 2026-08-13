import Testing
import SwiftUI
import AppKit
@testable import ClaudePet

/// Contrast cover for the ocean backdrop.
///
/// `Palette.Ocean`'s doc comment quotes specific contrast ratios as the reason
/// its lightness sits where it does. Numerical Grounding says a
/// stated metric needs a runnable command behind it — this is that command.
///
/// The stops exist because the *sampled* wallpaper colours could not be used:
/// the aerial's mid-water lands within 1.02:1 of Claw'd's body, which shimmers.
/// If someone later "corrects" the ramp back toward the real wallpaper, these
/// tests fail and say why.
@Suite("Ocean contrast")
struct PaletteContrastTests {

    /// WCAG relative luminance of a SwiftUI `Color`, via its sRGB components.
    ///
    /// Goes through `NSColor` rather than storing the hex twice — the point is
    /// to measure the colour the app will actually draw, not a number written
    /// down beside it.
    static func luminance(_ color: Color) -> Double {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            Issue.record("colour would not convert to sRGB")
            return 0
        }
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
             + 0.7152 * channel(srgb.greenComponent)
             + 0.0722 * channel(srgb.blueComponent)
    }

    static func ratio(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The stops Claw'd actually stands on. He occupies the lower third, so the
    /// top two are behind the bubble, not behind him.
    static let standingOn: [Color] = [Palette.Ocean.mid,
                                      Palette.Ocean.deep,
                                      Palette.Ocean.abyss]

    @Test("Claw'd separates from every stop he stands on")
    func bodySeparatesFromBackdrop() {
        for stop in Self.standingOn {
            let r = Self.ratio(Palette.body, stop)
            #expect(r >= 3.0, "body vs backdrop is \(String(format: "%.2f", r)):1 — under 3:1 he mushes into the water")
        }
    }

    /// The whole reason the ramp is not the sampled wallpaper.
    @Test("The ramp avoids the luminance band that collides with the sprite")
    func rampAvoidsTheCollisionBand() {
        // The sampled aerial mid-water, kept here as the counter-example.
        let sampledMidWater = Color(hex: 0x3F98C3)
        let collision = Self.ratio(Palette.body, sampledMidWater)
        #expect(collision < 1.2,
                "the sampled colour is supposed to be a near-exact luminance match — if this drifts, the doc comment's reasoning is stale")

        // Every shipped stop must be clear of it.
        for stop in Palette.Ocean.ramp {
            #expect(Self.ratio(Palette.body, stop) > collision,
                    "a shipped stop is no better than the colour we rejected")
        }
    }

    /// Bubbles float over the upper stops. `.sleeping` is exempt: `PetRootView`
    /// suppresses the bubble entirely in that mood.
    @Test("Bubble fills stay legible over the backdrop")
    func bubblesSeparateFromBackdrop() {
        let overlaid = [Palette.Ocean.shelf, Palette.Ocean.mid, Palette.Ocean.deep]
        for mood in PetMood.allCases where mood != .sleeping && mood != .working {
            for stop in overlaid {
                let r = Self.ratio(mood.style.bubbleFill, stop)
                #expect(r >= 3.0,
                        "\(mood.rawValue) bubble vs backdrop is \(String(format: "%.2f", r)):1")
            }
        }
    }

    /// `.working`'s indigo is the one fill that does not clear 3:1. It is
    /// documented rather than hidden: the bubble is a large solid block with
    /// high-contrast text inside, and it takes a keyline in backdrop scenes.
    /// The assertion pins the known weakness so it cannot quietly get worse.
    @Test("The working bubble's known weakness is bounded")
    func workingBubbleIsTheKnownException() {
        let r = Self.ratio(PetMood.working.style.bubbleFill, Palette.Ocean.mid)
        #expect(r < 3.0, "if this now clears 3:1, delete this test and the keyline")
        #expect(r >= 2.0, "…but it must not get worse than it is")
    }

    /// Ordering is load-bearing: the backdrop reads as depth only if it darkens
    /// monotonically, and the sprite's separation depends on the dark end being
    /// where the sprite is.
    @Test("The ramp darkens monotonically, surface to abyss")
    func rampIsMonotonic() {
        let lums = Palette.Ocean.ramp.map(Self.luminance)
        for (a, b) in zip(lums, lums.dropFirst()) {
            #expect(b < a, "the ramp must get darker with depth")
        }
        #expect(Self.luminance(Palette.Ocean.foam) > lums[0],
                "foam is a highlight; it has to be lighter than the surface")
    }

    /// Guards the doc comment's headline claim in one assertion.
    @Test("The published ratios are what the code actually produces")
    func publishedRatiosHold() {
        let expected: [(Color, Double)] = [
            (Palette.Ocean.surface, 2.49),
            (Palette.Ocean.shelf, 3.26),
            (Palette.Ocean.mid, 4.17),
            (Palette.Ocean.deep, 5.21),
            (Palette.Ocean.abyss, 5.69),
        ]
        for (stop, claimed) in expected {
            let actual = Self.ratio(Palette.body, stop)
            #expect(abs(actual - claimed) < 0.05,
                    "documented \(claimed):1 but measured \(String(format: "%.2f", actual)):1")
        }
    }
}
