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

    /// Frame-exact and seam-closed. The length itself is derived from the
    /// gundam fact's scroll — the clip must contain one WHOLE marquee cycle,
    /// or the sentence is decapitated at every wrap, which was the operator's
    /// "jarring cut".
    @Test("The strip is frame-exact, scroll-closed, and under the ceiling")
    func theClockContainsTheScroll() {
        let seconds = ReelRenderer.costumeSeconds
        let frames = (seconds / ReelRenderer.heroFrameDelay)
        #expect(frames == frames.rounded(), "\(seconds)s is not a whole number of frames")
        #expect(seconds <= 25, "past the point anyone keeps watching")

        // Every scrolling line in the cast must complete its travel inside
        // the clip, so `loopSeconds` has slack to absorb rather than a
        // collision to hide.
        for member in ReelRenderer.costumeCast {
            guard let line = member.line,
                  ActivityCoordinator.bubbleStyle(for: line) == .marquee else { continue }
            let natural = Double(MarqueeText.measure(line) / MarqueeText.speed)
            #expect(natural < seconds - member.lineFrom,
                    "\"\(line)\" travels \(natural)s inside \(seconds - member.lineFrom)s")
        }
    }

    /// The seam itself, in points: a marquee given the clip as its loop puts
    /// the text at the same offset at 0 and at the clip's end — the clamp
    /// refuses a cycle shorter than the text rather than overlapping it.
    @Test("loopSeconds closes the wrap and refuses to collide")
    func theLoopCloses_marquee() {
        let line = "Anthropic has published Claude's constitution 📜"
        let cycle = MarqueeText.cycle(for: line, loopSeconds: ReelRenderer.costumeSeconds)
        let travel = { (t: Double) -> CGFloat in
            CGFloat(t * Double(MarqueeText.speed)).truncatingRemainder(dividingBy: cycle)
        }
        #expect(abs(travel(0) - travel(ReelRenderer.costumeSeconds)) < 0.001,
                "the wrap does not close")
        // Natural behaviour is untouched when no loop is asked for…
        #expect(MarqueeText.cycle(for: line, loopSeconds: nil)
                == MarqueeText.measure(line) + MarqueeText.gap)
        // …and a loop shorter than the text degrades to natural, not to a
        // second copy driving over the first.
        #expect(MarqueeText.cycle(for: line, loopSeconds: 2.0)
                == MarqueeText.measure(line) + MarqueeText.gap)
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

    /// The mascot leads, flanked by two distinct costumes.
    ///
    /// This test used to FORBID `.none` — "the strip includes the undressed
    /// crab" — and the operator overruled it: the strip is the brand's second
    /// hero, and the brand is the orange crab. So the contract flips: the
    /// centre must be Claw'd himself, and the wardrobe lives on his flanks.
    @Test("Claw'd holds the centre, two distinct costumes flank him")
    func theMascotLeads() {
        let worn = ReelRenderer.costumeCast.map(\.costume)
        #expect(worn.count == 3)
        #expect(worn[1] == Costume.none, "the centre slot belongs to the mascot")
        #expect(worn[0] != .none && worn[2] != .none, "a flank is undressed")
        #expect(worn[0] != worn[2], "both flanks wear the same costume")
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

    /// Each crab speaks for himself, and every word is REAL.
    ///
    /// Constants rather than cursors — a committed asset that drew from a deck
    /// would render differently depending on what a counter had been doing.
    /// The facts come from the pools, the shout from the skate deck, and the
    /// ninja says nothing at all on purpose: his bubble is the thinking dots.
    @Test("The cast's lines are real, and the shout follows the landing")
    func theCastSpeaksForItself() {
        let cast = ReelRenderer.costumeCast

        // Claw'd lands the kickflip and THEN shouts — that is the order a
        // shout happens in, and the operator asked for exactly this staging.
        let clawd = cast[1]
        let shout = try! #require(clawd.line)
        #expect(Vocab.lines(for: .kickflip).contains(shout),
                "\"\(shout)\" is not a line he shouts after a trick")
        let landing = try! #require(clawd.onsets.first) + clawd.flourish.duration
        #expect(clawd.lineFrom >= landing - 0.001,
                "the shout at \(clawd.lineFrom)s precedes the landing at \(landing)s")

        // Gundam reads a pool fact, and it finishes scrolling inside the clip.
        let gundam = cast[0]
        let fact = try! #require(gundam.line)
        #expect(FunFacts.all.contains(fact), "\"\(fact)\" is not in the pools")
        if ActivityCoordinator.bubbleStyle(for: fact) == .marquee {
            #expect(MarqueeText.readSeconds(for: fact, width: MarqueeText.viewport)
                    <= ReelRenderer.costumeSeconds - gundam.lineFrom,
                    "the fact cannot finish scrolling inside the clip")
        }

        // The ninja thinks. nil line IS the dots, and a test that let someone
        // hand him a sentence would un-ninja him.
        #expect(cast[2].line == nil, "the ninja does not explain himself")
    }

    /// The pack has depth: the mascot stands larger and in front, the flanks
    /// smaller — and every side is a whole multiple of the 32-cell grid at
    /// heroScale, so no cell lands on a fractional device pixel.
    @Test("Claw'd is the front of the pack")
    func theMascotIsInFront() {
        let cast = ReelRenderer.costumeCast
        #expect(cast[1].side > cast[0].side && cast[1].side > cast[2].side,
                "the centre is not the largest")
        for member in cast {
            let cells = member.side * ReelRenderer.heroScale / 32
            #expect(cells == cells.rounded(),
                    "\(member.costume.rawValue) at \(member.side)pt puts cells on fractional pixels")
        }
    }
}
