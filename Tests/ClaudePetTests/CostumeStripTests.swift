import Testing
import Foundation
@testable import ClaudePet

/// The wardrobe strip — the store page's second hero.
///
/// Ten seconds, three costumes, and a loop that has to close. The same rule
/// `theSleepingClipIsOneWholeBreath` enforces for `sleeping.gif`: a clip whose
/// first and last frames disagree shows a seam every time it repeats, and this
/// one repeats forever at the top of a README.
@Suite("Costume strip")
@MainActor
struct CostumeStripTests {

    /// Exactly ten, not ten-ish. An earlier version accumulated `elapsed += 0.1`
    /// in a Double and produced 101 frames — the running total lands a hair
    /// under ten on the last pass, so the loop ran a frame long.
    @Test("The strip is exactly ten seconds")
    func exactlyTenSeconds() {
        let frames = Int((ReelRenderer.costumeSeconds / ReelRenderer.heroFrameDelay).rounded())
        #expect(frames == 100, "\(frames) frames, not 100")
        #expect(ReelRenderer.costumeSeconds <= 25,
                "past the point anyone keeps watching")
    }

    /// **The loop.** Every crab must hold the same pose at t=0 and t=10, or the
    /// strip twitches once per cycle.
    @Test("Every costume is in the same pose at both ends of the loop")
    func theLoopCloses() {
        for member in ReelRenderer.costumeCast {
            let open = ReelRenderer.costumePose(member, at: 0)
            let close = ReelRenderer.costumePose(member, at: ReelRenderer.costumeSeconds)
            // Cell by cell: `PixelBuffer` is not Equatable, and comparing the
            // POSES would miss a field that draws differently — the picture is
            // the thing that has to loop, which is the same reason
            // `theSleepingClipIsOneWholeBreath` compares rendered frames.
            let first = CrabRig.render(open, costume: member.costume)
            let last = CrabRig.render(close, costume: member.costume)
            var differing = 0
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where first[x, y] != last[x, y] { differing += 1 }
            }
            #expect(differing == 0,
                    "\(member.costume.rawValue) does not close its loop: \(differing) cells differ")
        }
    }

    /// Nothing may be mid-flourish at the origin — the frozen sentinel, applied
    /// to a clip rather than a still.
    @Test("Nobody is mid-flourish at t=0")
    func nothingInFlightAtZero() {
        for member in ReelRenderer.costumeCast {
            for onset in member.onsets {
                #expect(onset > 0, "\(member.costume.rawValue) starts a flourish at the origin")
                #expect(onset + member.flourish.duration < ReelRenderer.costumeSeconds,
                        "\(member.costume.rawValue)'s flourish at \(onset)s runs past the loop")
            }
        }
    }

    /// The kickflip is the reason the middle slot exists. It has to land inside
    /// the window rather than being cut by it.
    @Test("The middle one lands its kickflip")
    func theKickflipLands() {
        let middle = ReelRenderer.costumeCast[1]
        #expect(middle.flourish == .kickflip, "the centre of the strip is not the trick")
        let onset = try! #require(middle.onsets.first)
        let landing = onset + middle.flourish.duration
        #expect(landing < ReelRenderer.costumeSeconds - 0.5,
                "the kickflip lands at \(landing)s, too close to the loop point")

        // …and it is genuinely animating, not a still with a board on it.
        let poses = stride(from: onset, to: landing, by: 0.1)
            .map { ReelRenderer.costumePose(middle, at: $0) }
        #expect(Set(poses.map(\.bob)).count > 1, "the kickflip never leaves the ground")
    }

    /// Three, and three different ones. A wardrobe strip showing the same
    /// costume twice would be worse than showing one.
    @Test("Three distinct costumes, none of them the default")
    func threeDistinctCostumes() {
        let worn = ReelRenderer.costumeCast.map(\.costume)
        #expect(worn.count == 3)
        #expect(Set(worn).count == 3, "a costume appears twice")
        #expect(!worn.contains(.none), "the strip includes the undressed crab")
    }

    /// The outer two must not wiggle in unison — synchronised idling reads as
    /// one animation drawn three times, which is the opposite of the point.
    @Test("The outer two are on different beats")
    func theOuterTwoAreOffset() {
        let left = ReelRenderer.costumeCast[0].onsets
        let right = ReelRenderer.costumeCast[2].onsets
        for a in left {
            for b in right {
                #expect(abs(a - b) > 0.4, "both wiggle at about \(a)s")
            }
        }
    }

    /// The line above them is fixed, not dealt. A committed asset that drew
    /// from a cursor would render differently depending on what the counter had
    /// been doing, which is the one thing a byte-compared file cannot survive.
    @Test("The strip's line is a constant, and it scrolls")
    func theLineIsFixed() {
        #expect(!ReelRenderer.costumeLine.isEmpty)
        #expect(ActivityCoordinator.bubbleStyle(for: ReelRenderer.costumeLine) == .marquee,
                "a plain line would show the whole sentence in frame one and never move")
    }
}
