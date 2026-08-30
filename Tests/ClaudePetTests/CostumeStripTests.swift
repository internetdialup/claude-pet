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

    /// The bubble's script. Three constants rather than a cursor — a committed
    /// asset that drew from a deck would render differently depending on what
    /// the counter had been doing — and every word of it is REAL: the facts
    /// come from the pools and the shout from the skate deck, so the strip
    /// shows things he actually says rather than marketing copy shaped like
    /// them.
    @Test("The beats tile the clip, and every line is one he really says")
    func theBeatsAreReal() {
        let beats = ReelRenderer.costumeBeats
        #expect(beats.first?.from == 0)
        #expect(beats.last?.to == ReelRenderer.costumeSeconds)
        for (a, b) in zip(beats, beats.dropFirst()) {
            #expect(a.to == b.from, "a gap between \"\(a.text)\" and \"\(b.text)\"")
        }
        // The middle beat is the character moment: a real skate shout, and it
        // covers the kickflip from pop to landing.
        let shout = beats[1]
        #expect(Vocab.lines(for: .kickflip).contains(shout.text),
                "\"\(shout.text)\" is not a line he shouts after a trick")
        let trick = ReelRenderer.costumeCast[1]
        let onset = try! #require(trick.onsets.first)
        #expect(shout.from <= onset && onset + trick.flourish.duration <= shout.to,
                "the shout does not cover the kickflip")
        // The outer beats are facts from the pools, wearing their emoji.
        for beat in [beats[0], beats[2]] {
            #expect(FunFacts.all.contains(beat.text),
                    "\"\(beat.text)\" is not in the fact pools")
        }
        // A marquee beat must be long enough for its line to finish scrolling —
        // an unfinished sentence at a beat swap is the glitch this exists to
        // avoid.
        for beat in beats where ActivityCoordinator.bubbleStyle(for: beat.text) == .marquee {
            let read = MarqueeText.readSeconds(for: beat.text, width: MarqueeText.viewport)
            #expect(read <= beat.to - beat.from,
                    "\"\(beat.text)\" needs \(read)s and its beat is \(beat.to - beat.from)s")
        }
    }
}
