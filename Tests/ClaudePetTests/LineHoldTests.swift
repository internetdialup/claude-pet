import Testing
import Foundation
@testable import ClaudePet

/// Long lines get read to the end.
///
/// The operator reported a fact truncated mid-sentence. Two separate faults sat
/// underneath that, and this suite pins both:
///
/// - the sleeping branch set the bubble's TEXT and not its STYLE, so it stayed
///   `.plain` — and sixty-six of the seventy-six facts are longer than the
///   plain ceiling, because they are written to scroll;
/// - and even routed to the ticker, a line was given the mood's six-second
///   dwell against a read-through of up to 11.8 seconds, so the longest facts
///   had never once been seen to the end.
@Suite("Line hold")
@MainActor
struct LineHoldTests {

    private var viewport: CGFloat { MarqueeText.viewport }

    // MARK: - The rule

    /// A line you can see whole the instant it appears needs no extra time, and
    /// giving it some would only slow him down. The hold is for scrolling lines
    /// and nothing else.
    @Test("A line that fits the plain bubble takes no hold at all")
    func plainLinesAreNotHeld() {
        for line in ["zzz…", "Off the clock", String(repeating: "x", count: ThoughtBubble.plainColumns)] {
            #expect(ActivityCoordinator.bubbleStyle(for: line) == .plain, "\"\(line)\" should be plain")
            #expect(ActivityCoordinator.lineHold(for: line) == 0, "\"\(line)\" was held")
        }
    }

    /// One character over the ceiling is a ticker, and a ticker gets time.
    @Test("A line one column too wide starts scrolling, and starts being held")
    func theCeilingIsTheSwitch() {
        let over = String(repeating: "x", count: ThoughtBubble.plainColumns + 1)
        #expect(ActivityCoordinator.bubbleStyle(for: over) == .marquee)
        #expect(ActivityCoordinator.lineHold(for: over) > 0)
    }

    /// Three passes, which is what was asked for — until the cap.
    @Test("A held line gets three read-throughs, or the cap")
    func threeReadsOrTheCap() {
        for columns in [30, 34, 44, 55, 69] {
            let line = String(repeating: "x", count: columns)
            let read = MarqueeText.readSeconds(for: line, width: viewport)
            let hold = ActivityCoordinator.lineHold(for: line)
            #expect(hold <= ActivityCoordinator.maxLineHold + 0.001,
                    "\(columns) columns held for \(hold)s, past the cap")
            let wanted = min(read * 3, ActivityCoordinator.maxLineHold)
            #expect(abs(hold - wanted) < 0.001,
                    "\(columns) columns held \(hold)s, expected \(wanted)s")
        }
    }

    /// **The promise to the reader.** Whatever the cap does to the third pass,
    /// every line he can say must be on screen long enough to be read ONCE. A
    /// cap that cut into the first read-through would be the original bug with
    /// a bigger number.
    @Test("Every fact and tip he can say is readable at least once")
    func everythingIsReadableOnce() {
        var worst = (line: "", ratio: Double.infinity)
        for category in FunFacts.Category.allCases {
            for fact in FunFacts.facts(in: category) {
                // Gate on STYLE, not on read time. `plainColumns` is measured
                // against the plain bubble's 210pt and the viewport here is the
                // marquee's 150 — so a line can fit the plain bubble and still
                // report a read time, which means nothing because a plain line
                // never scrolls.
                guard ActivityCoordinator.bubbleStyle(for: fact) == .marquee else { continue }
                let read = MarqueeText.readSeconds(for: fact, width: viewport)
                let hold = ActivityCoordinator.lineHold(for: fact)
                let ratio = hold / read
                if ratio < worst.ratio { worst = (fact, ratio) }
                #expect(hold >= read,
                        "\"\(fact)\" needs \(read)s to read and is held \(hold)s")
            }
        }
        for tip in ClaudeTips.all {
            guard ActivityCoordinator.bubbleStyle(for: tip) == .marquee else { continue }
            let read = MarqueeText.readSeconds(for: tip, width: viewport)
            #expect(ActivityCoordinator.lineHold(for: tip) >= read,
                    "\"\(tip)\" is not held long enough to read")
        }
        #expect(worst.ratio >= 1, "tightest margin was \(worst.ratio) on \"\(worst.line)\"")
    }

    /// The cap exists so one sentence cannot own his face. Three passes of the
    /// longest fact is thirty-five seconds, which is the furniture failure
    /// `bubbleCadences` was written to prevent.
    @Test("No line can hold the bubble longer than the cap")
    func nothingOwnsHisFace() {
        let everything = FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) } + ClaudeTips.all
        for line in everything {
            #expect(ActivityCoordinator.lineHold(for: line) <= ActivityCoordinator.maxLineHold + 0.001,
                    "\"\(line)\" holds for \(ActivityCoordinator.lineHold(for: line))s")
        }
        #expect(ActivityCoordinator.maxLineHold < 30,
                "a cap this high is not a cap")
    }

    // MARK: - The regression

    /// **The bug the operator actually saw.** Sixty-six of the seventy-six
    /// facts are longer than the plain bubble, so a path that forgets to route
    /// by length truncates almost every fact it shows rather than occasionally
    /// clipping a long one.
    @Test("Most facts are written to scroll, so length routing is not optional")
    func mostFactsNeedTheTicker() {
        let all = FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) }
        let scrolling = all.filter { ActivityCoordinator.bubbleStyle(for: $0) == .marquee }
        #expect(scrolling.count > all.count / 2,
                "only \(scrolling.count) of \(all.count) facts scroll — this test's premise moved")
        for fact in scrolling {
            #expect(fact.count > ThoughtBubble.plainColumns)
        }
    }
}
