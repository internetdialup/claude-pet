import Testing
import Foundation
import AppKit
@testable import ClaudePet

/// **The ticker's arithmetic, checked against the font itself.**
///
/// `MarqueeText.measure` prices a line without a layout pass, which is the
/// only way `readSeconds` can stay a pure function that tests and schedulers
/// can call. The cost of that is a constant standing in for a font metric —
/// and for the life of the ticker the constant was wrong. It said 6.62, which
/// is Menlo-Bold's advance at 11pt; the bubble draws in
/// `.AppleSystemUIFontMonospaced-Bold`, whose advance is 6.7998046875. The
/// line was therefore drawn wider than the modulus it wrapped at, and jumped
/// forward by the difference once every cycle — growing with the sentence,
/// which is exactly how the operator described it.
///
/// The bubble's own doc had already caught the discrepancy from the other
/// direction and resolved it by reading a ruler off a render rather than
/// fixing the constant, leaving the note "6.62 … runs a little under the real
/// advance" sitting above code that kept using 6.62.
///
/// So the render stops being the authority and the FONT becomes it. If a
/// future macOS changes either metric, this fails loudly instead of quietly
/// reopening the seam.
@MainActor
struct GlyphMetricTests {

    private func width(_ text: String) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    @Test("The assumed advance is the font's real advance")
    func theAdvanceIsReal() {
        // Every glyph the same, which is what makes a per-character sum legal
        // in the first place — and worth asserting, since a proportional face
        // would make `measure` meaningless rather than merely inaccurate.
        for sample in ["M", "i", " ", "W", "."] {
            #expect(abs(width(sample) - MarqueeText.advance) < 0.001,
                    "\"\(sample)\" advances \(width(sample)), not \(MarqueeText.advance)")
        }
        // And no tracking or kerning across a run, so the sum is the width.
        let sixty = String(repeating: "M", count: 60)
        #expect(abs(width(sixty) - MarqueeText.advance * 60) < 0.01,
                "60 glyphs measure \(width(sixty)), not \(MarqueeText.advance * 60)")
    }

    /// **Including the text-default ones.** The first cut of this test
    /// sampled only emoji whose Unicode `Emoji_Presentation` is true, which
    /// is exactly the set the implementation already got right — so it
    /// passed while ⚠️ was being priced as a 6.8pt letter and the status
    /// ticker, the one string the marquee still renders, was measured 18.4pt
    /// short. A gate that only covers the easy half is not a gate.
    @Test("An emoji is priced as the different face it actually is")
    func emojiAreNotMonospaced() {
        for emoji in ["🌊", "🌴", "🤙", "🦀", "🌈", "⚠️", "❄️", "🌶️", "🐛"] {
            #expect(abs(width(emoji) - MarqueeText.emojiAdvance) < 0.001,
                    "\(emoji) advances \(width(emoji)), not \(MarqueeText.emojiAdvance)")
        }
    }

    /// The whole point, end to end: `measure` agrees with what SwiftUI lays
    /// out, for mixed text — which is what makes the wrap seamless.
    @Test("measure agrees with the real layout, emoji and all")
    func measureMatchesTheLayout() {
        // Every pool, not a prefix — a sample cannot see the one line with
        // the awkward glyph in it — plus the ticker's own framed string,
        // which is not in any pool and is the only thing that still scrolls.
        let lines = Vocab.lines(for: .surf)
            + FunFacts.all
            + ClaudeTips.all
            + [ThoughtBubble.statusTicker("Psst — I need you"),
               "Sharks existed before trees did.", "Aloha 🌴", "plain ascii only"]
        for line in lines {
            #expect(abs(MarqueeText.measure(line) - width(line)) < 0.5,
                    "\"\(line)\" measures \(MarqueeText.measure(line)) but lays out at \(width(line))")
        }
    }

    /// The bubble's column count, now DERIVED rather than read off a ruler.
    /// 38 columns must fit the text area and 39 must not — the same fact the
    /// old doc comment established empirically, restated as arithmetic that
    /// only holds at the correct advance.
    @Test("The column count is the one the text area actually allows")
    func theColumnCountFits() {
        let area = ThoughtBubble.textWidth
        #expect(MarqueeText.advance * CGFloat(ThoughtBubble.plainColumns) <= area,
                "\(ThoughtBubble.plainColumns) columns do not fit \(area)pt")
        #expect(MarqueeText.advance * CGFloat(ThoughtBubble.plainColumns + 1) > area,
                "\(ThoughtBubble.plainColumns + 1) columns would also fit — the bubble is wider than it says")
    }

    /// **Capacity in POINTS, not characters.**
    ///
    /// `bubbleStyle` routes on `line.count <= plainCapacity`, i.e. 76
    /// characters — and a character is not a width. An emoji is 16pt against
    /// a letter's 6.8, so a 70-character line carrying four of them is wider
    /// than seventy-six letters and could need a third line the bubble does
    /// not have. Nothing in the pools does that today; this is the gate that
    /// keeps it that way, because the failure mode is a silently clipped
    /// sentence rather than anything that looks like a bug.
    @Test("No line he can say needs a third line")
    func everyLineFitsTwoRows() {
        let everything = FunFacts.all + ClaudeTips.all
            + ShoutoutOccasion.allCases.flatMap { Vocab.lines(for: $0) }
        let ceiling = ThoughtBubble.textWidth * CGFloat(ThoughtBubble.plainLines)
        for line in everything where ActivityCoordinator.bubbleStyle(for: line) == .plain {
            #expect(MarqueeText.measure(line) <= ceiling,
                    "\"\(line)\" is \(MarqueeText.measure(line))pt of a \(ceiling)pt bubble")
        }
    }

}
