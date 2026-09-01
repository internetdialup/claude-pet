import Testing
import Foundation
@testable import ClaudePet

/// The knowledge card's typewriter.
///
/// Short facts and tips TYPE onto the card; the marquee already owns the long
/// ones. The reveal is a pure function of elapsed time, which is what makes it
/// testable here and freezable in the renderers — a committed still caught
/// mid-word would be the operator's mid-sentence complaint reincarnated, so
/// offline the view always shows the whole line (asserted by inspection of
/// `TypewriterText.body`'s frozen branch; the arithmetic is pinned below).
@Suite("Typewriter")
struct TypewriterTests {

    @Test("Nothing is typed before the line begins")
    func nothingBeforeTheStart() {
        #expect(TypewriterText.typedCount(elapsed: 0, of: 28) == 0)
        #expect(TypewriterText.typedCount(elapsed: -5, of: 28) == 0,
                "a clock skew must not reveal text early")
    }

    @Test("The reveal is monotonic and lands exactly on the full line")
    func monotonicToCompletion() {
        var last = 0
        for step in 0...60 {
            let now = TypewriterText.typedCount(elapsed: Double(step) * 0.05, of: 28)
            #expect(now >= last, "the reveal went backwards at step \(step)")
            last = now
        }
        #expect(last == 28, "three seconds in, the line is still not whole")
        #expect(TypewriterText.typedCount(elapsed: 999, of: 28) == 28,
                "the count must clamp at the line, not run past it")
    }

    /// The widest line the plain bubble can hold must finish typing with most
    /// of its dwell left for reading — typing that ate the dwell would be the
    /// truncation bug with a fancier costume.
    @MainActor
    @Test("The widest plain line types out in under a fifth of its dwell")
    func typingLeavesTimeToRead() {
        let widest = ThoughtBubble.plainColumns
        let seconds = Double(widest) / TypewriterText.charsPerSecond
        #expect(seconds < 1.25, "\(widest) columns take \(seconds)s to type")
    }

    /// Every fact and tip that routes to the plain bubble is short enough for
    /// the rule above to cover — anything longer is the marquee's, whose two
    /// full passes are pinned by `LineHoldTests`.
    @MainActor
    @Test("Every plain-routed fact and tip is covered by the typing budget")
    func everyPlainLineIsCovered() {
        let everything = FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) }
            + ClaudeTips.all
        for line in everything where ActivityCoordinator.bubbleStyle(for: line) == .plain {
            #expect(line.count <= ThoughtBubble.plainColumns,
                    "\"\(line)\" routes plain but overflows the plain bubble")
        }
    }
}
