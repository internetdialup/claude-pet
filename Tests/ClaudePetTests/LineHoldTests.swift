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

    /// **The glance guarantee.** Two whole marquee cycles, so a reader who
    /// looks up at ANY moment inside the first cycle still gets a complete
    /// pass that opens on the first word. This replaced three read-throughs —
    /// the operator's complaint was precisely that a glance landed
    /// mid-sentence and no clean pass followed.
    @Test("A held line gets two whole cycles, and a glance always gets a full pass")
    func twoCyclesAndTheGlance() {
        for columns in [30, 34, 44, 55, 69] {
            let line = String(repeating: "x", count: columns)
            let cycle = Double(MarqueeText.cycle(for: line, loopSeconds: nil)
                               / MarqueeText.speed)
            let hold = ActivityCoordinator.lineHold(for: line)
            #expect(abs(hold - min(cycle * 2, ActivityCoordinator.maxLineHold)) < 0.001,
                    "\(columns) columns held \(hold)s against a \(cycle)s cycle")
            // The guarantee, stated as arithmetic: any glance inside the
            // first cycle leaves at least one whole cycle of hold behind it.
            for glance in stride(from: 0.0, through: cycle, by: cycle / 7) {
                #expect(hold - glance >= cycle - 0.001,
                        "a glance at \(glance)s leaves only \(hold - glance)s")
            }
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

    /// The cap is a BACKSTOP now, not a budget: news kills any hold on the
    /// spot (the burst path clears `heldLine`), so a long hold can no longer
    /// own his face against real information — only against silence, which is
    /// the operator's explicit trade.
    @Test("No line can hold the bubble longer than the cap")
    func nothingOwnsHisFace() {
        let everything = FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) } + ClaudeTips.all
        for line in everything {
            #expect(ActivityCoordinator.lineHold(for: line) <= ActivityCoordinator.maxLineHold + 0.001,
                    "\"\(line)\" holds for \(ActivityCoordinator.lineHold(for: line))s")
        }
        // Forty, because the operator's guarantee is two whole cycles and the
        // longest fact needs 37.8s for that. The cap must clear every line
        // that ships — it exists to catch a future 90-character fact, not to
        // trim today's pool — so the real assertion is that it never binds.
        let worst = (FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) } + ClaudeTips.all)
            .filter { ActivityCoordinator.bubbleStyle(for: $0) == .marquee }
            .map { Double(MarqueeText.cycle(for: $0, loopSeconds: nil) / MarqueeText.speed) * 2 }
            .max() ?? 0
        #expect(worst <= ActivityCoordinator.maxLineHold,
                "the cap binds on a shipping line (worst 2-cycle hold \(worst)s)")
        #expect(ActivityCoordinator.maxLineHold <= 45, "a cap this high is not a cap")
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
