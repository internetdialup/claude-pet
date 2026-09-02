import Testing
import Foundation
@testable import ClaudePet

/// The seasons on the sprite: the nil-lock that keeps every offline render
/// season-free, the sentinels, the suppression contracts, and the politeness
/// rules — the `theSunNeedsTheDaylight` shape, one flight up.
@Suite("Holiday specials")
struct HolidaySpecialsTests {

    private func cells(_ b: PixelBuffer) -> [(Int, Int, PixelBuffer.Ink)] {
        var out: [(Int, Int, PixelBuffer.Ink)] = []
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where b[x, y] != .clear { out.append((x, y, b[x, y])) }
        }
        return out
    }

    /// THE LOCK: with no holiday injected, every mood renders byte-identical
    /// to the pre-season baseline over a broad t-sweep — offline renderers
    /// pass nothing, so no committed byte can ever carry a season.
    @Test("No holiday, no season — byte-identical everywhere")
    func nilLock() {
        for mood in PetMood.allCases {
            for step in 0..<10 {
                let t = Double(step) * 1.3
                let bare = CrabRig.render(CrabAnimator.pose(mood: mood, t: t, flourishes: false))
                let passed = CrabRig.render(CrabAnimator.pose(mood: mood, t: t,
                                                              flourishes: false, holiday: nil))
                #expect(bare.cells == passed.cells,
                        "a nil holiday changed \(mood.rawValue) at t=\(t)")
            }
        }
    }

    /// The firework sentinel: nothing in dice cycle zero, at any instant.
    @Test("No firework in a first cycle")
    func fireworkSentinel() {
        for step in 0..<130 {
            let pose = CrabAnimator.pose(mood: .idle, t: Double(step) * 0.1,
                                         flourishes: false, holiday: .newYear)
            #expect(pose.fireworkProgress == nil,
                    "a firework flew at t=\(Double(step) * 0.1), inside cycle zero")
        }
    }

    /// The pumpkins yield the spell to the telescope and the sun with the
    /// bug and the balloon — sweep an injected Halloween across hours and
    /// instants and demand the mutual exclusion.
    @Test("Floor pumpkins never share a spell with the telescope or the sun")
    func pumpkinSuppression() {
        for hour in [1, 13] {
            for step in 0..<240 {
                let t = Double(step) * 2.5
                let pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false,
                                             hourOfDay: hour, holiday: .halloween)
                if pose.stargaze > 0.001 || pose.sunPatch > 0.001 {
                    #expect(!pose.holidayGround,
                            "pumpkins under a spell at t=\(t), hour \(hour)")
                }
            }
        }
    }

    /// Ground furniture: HE is byte-identical with and without the pumpkins
    /// — `preservingExisting`-last means they can only fill empty floor.
    @Test("The pumpkins are furniture — he never changes")
    func pumpkinsAreGroundObjects() {
        var pose = CrabAnimator.pose(mood: .idle, t: 3.7, flourishes: false)
        let bare = CrabRig.render(pose)
        pose.holidayGround = true
        let furnished = CrabRig.render(pose)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where bare[x, y] != .clear {
                #expect(furnished[x, y] == bare[x, y],
                        "a pumpkin painted over him at (\(x),\(y))")
            }
        }
        #expect(cells(furnished).count > cells(bare).count, "no pumpkin appeared at all")
    }

    /// Weather writes only empty sky: leaves and snow both.
    @Test("Weather only fills clear cells")
    func weatherIsPolite() {
        for holiday in [Holiday.halloween, .winter] {
            for step in 1..<24 {
                let t = Double(step) * 0.7
                var pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false)
                let bare = CrabRig.render(pose)
                pose.holiday = holiday
                let weathered = CrabRig.render(pose)
                for y in 0..<PixelBuffer.side {
                    for x in 0..<PixelBuffer.side where bare[x, y] != .clear {
                        #expect(weathered[x, y] == bare[x, y],
                                "\(holiday) painted over him at (\(x),\(y)), t=\(t)")
                    }
                }
            }
        }
    }

    /// Winter + Arctic White must not double the snow: the render equals the
    /// white costume's own, byte for byte.
    @Test("Winter snow stands down for Arctic White")
    func noDoubleSnow() {
        for step in 1..<24 {
            let t = Double(step) * 0.9
            var pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false)
            let white = CrabRig.render(pose, costume: .white)
            pose.holiday = .winter
            let winterWhite = CrabRig.render(pose, costume: .white)
            #expect(white.cells == winterWhite.cells, "the snow doubled at t=\(t)")
        }
    }

    /// The three seasonal costumes pass the wardrobe's own standing rules via
    /// `CostumeTests`' allCases sweeps — this adds only the santa-specific
    /// fact: his shell stays terracotta, because the outfit is not a respray.
    @Test("Santa keeps his own shell")
    func santaKeepsTheShell() {
        let inks = CostumeStyle.of(.santa).inks
        #expect(inks[.body] == nil, "santa resprayed the shell")
    }
}
