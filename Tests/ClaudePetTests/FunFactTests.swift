import Testing
import Foundation
import SwiftUI
@testable import ClaudePet

/// The facts are the one thing in this app that can be *wrong*, so they get
/// their own suite. A vocabulary line is an opinion in the operator's voice; a
/// fact is a claim shipped in a binary with no citation beside it.
@Suite("Fun facts")
struct FunFactTests {

    /// Display columns, not `String.count`. An emoji is one grapheme and about
    /// two columns, and `MarqueeText.measure` inherits that mistake — the facts
    /// should not.
    private func columns(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
    }

    /// **The length guard.** A duration against a duration, so a change to the
    /// scroll speed, the gap, the viewport OR the idle dwell all fail this —
    /// which restating 6.62 here would not.
    ///
    /// Two seconds of the slot are left as margin for the bubble's 0.28s
    /// fade-in and the reducer's 2s tick landing after the seed boundary.
    @Test("Every fact finishes scrolling before its slot is up")
    func factsFinishInsideTheirSlot() {
        let budget = ActivityCoordinator.chatterInterval - 2
        for fact in FunFacts.all {
            let read = MarqueeText.readSeconds(for: fact, width: MarqueeText.viewport)
            #expect(read <= budget,
                    "\"\(fact)\" needs \(String(format: "%.1f", read))s of a \(budget)s slot")
        }
    }

    /// A reader has to join at the first word. Before `MarqueeText` learned its
    /// own start instant the offset came off the epoch, so a sentence began
    /// wherever the wall clock happened to be — survivable for a label like
    /// `MODEL · Opus 5`, useless for a sentence.
    @Test("A fact starts at its first character")
    func factsStartAtTheBeginning() {
        // At t=0 the offset is zero: the first character sits at the viewport's
        // leading edge. `readSeconds` is measured from that instant, so a
        // non-zero start would make every budget above a lie.
        #expect(MarqueeText.readSeconds(for: "", width: MarqueeText.viewport) == 0)
        let short = "MODEL · Opus 5"
        #expect(MarqueeText.readSeconds(for: short, width: MarqueeText.viewport) == 0,
                "anything narrower than the viewport needs no scroll at all")
    }

    /// **The staleness guard**, and the thing it guards is a FEELING rather
    /// than a count: how long until a line you have already read comes round
    /// again. That period is the pool's depth over its share of the mix, in
    /// draws — so a category grown on its own gets shallower relative to how
    /// often it is picked, and becomes the one you tire of first. Which is the
    /// opposite of what stating a ratio was for.
    ///
    /// **Fixed minimums did not actually say that, and were replaced on
    /// review.** `>= 10 / >= 10 / >= 30` is the 20/60/20 ratio only for as
    /// long as every pool sits exactly on its floor; add twelve Claude facts
    /// and every `>=` still passes while the sentence above it quietly goes
    /// false — the precise failure the doc comment claimed to catch. The
    /// invariant is a category's REPEAT PERIOD, depth over share, and it is
    /// MEASURED off `category(forDraw:)` rather than restated: a copy of `mix`
    /// living in the test is one more thing that can drift from the mix
    /// itself.
    ///
    /// **The review wrote that period equality as an equality, and six pools
    /// cannot hold it.** At three categories, 10 / 30 / 10 against 20/60/20
    /// puts every period on exactly 50 and the equality is free. It stopped
    /// being free when the flavours arrived: Claude keeps 60% of a
    /// twenty-five-slot mix and the five flavours take 8% each, so equality
    /// now costs either twenty-six deleted facts (every flavour pool cut to
    /// four) or forty-five more Claude facts (Claude grown to seventy-five).
    /// Those are the only two prices and neither is worth paying.
    ///
    /// So the equality relaxes to a bound on the SPREAD, and the floor below
    /// does the load-bearing work. That is not a climbdown, because the two
    /// assertions catch different things and only one of them is about harm:
    /// a period that falls is a pool coming round sooner than it used to,
    /// which is the thing you feel, and the floor catches every case of it. A
    /// period that RISES makes that pool fresher and costs no other pool
    /// anything. The spread bound is what remains of "grow them together" —
    /// it lets a pool be generously deep without letting the ratio drift so
    /// far that it has stopped meaning anything. It currently sits at 2.5x
    /// against a limit of 3x.
    @Test("The pools are deep enough, and none comes round sooner than the rest")
    func poolsAreProportional() {
        // 100 draws is four whole turns of the twenty-five-slot mix, so these
        // are exact counts and not a sample — and being out of a hundred, they
        // read directly as percentages.
        var share: [FunFacts.Category: Int] = [:]
        for draw in 0..<100 { share[FunFacts.category(forDraw: draw), default: 0] += 1 }
        for category in FunFacts.Category.allCases {
            #expect(share[category, default: 0] > 0,
                    "\(category.rawValue) never comes up in the mix at all")
        }
        // Nothing below divides by a share of zero.
        guard FunFacts.Category.allCases.allSatisfy({ share[$0, default: 0] > 0 }) else { return }

        var periods: [FunFacts.Category: Int] = [:]
        for category in FunFacts.Category.allCases {
            let depth = FunFacts.facts(in: category).count
            // `Vocab.pick` short-circuits a two-entry pool to strict
            // alternation and a one-entry pool to a constant. Proportional is
            // not the same as deep: 1/3/1 satisfies every ratio here and is
            // five facts in total.
            #expect(depth > 2, "\(category.rawValue) can only alternate")

            // Integer arithmetic throughout, so the period is an exact count
            // of draws rather than a float carrying a tolerance.
            let period = depth * 100 / share[category, default: 1]
            periods[category] = period
            #expect(period >= 50,
                    "\(category.rawValue): \(depth) facts at \(share[category, default: 0])% comes back round every \(period) draws")
        }

        let shortest = periods.values.min() ?? 0
        let longest = periods.values.max() ?? 0
        let drift = periods.sorted { $0.value < $1.value }
            .map { "\($0.key.rawValue) \($0.value)" }
            .joined(separator: ", ")
        #expect(longest <= shortest * 3,
                "the pools have drifted apart — \(shortest) draws against \(longest): \(drift)")

        #expect(Set(FunFacts.all).count == FunFacts.all.count, "a fact is duplicated")
    }

    /// The CS-101 pool's whole reason for existing: it is the one that does not
    /// scroll. A line that outgrows the plain bubble does not just look
    /// different, it gets handed to the marquee and loops — so this is the
    /// pool's contract, not a style note.
    ///
    /// Against `ThoughtBubble.plainColumns`, never a restated 29 — the ceiling
    /// belongs to the bubble's width and padding, and a test carrying its own
    /// copy would keep passing after someone widened it.
    @Test("Every CS-101 line fits the bubble without scrolling")
    func shortPoolStaysShort() {
        for fact in FunFacts.facts(in: .compSci101) {
            #expect(columns(fact) <= ThoughtBubble.plainColumns,
                    "\"\(fact)\" is \(columns(fact)) columns and would scroll")
            #expect(ActivityCoordinator.bubbleStyle(for: fact) == .plain)
        }
    }

    /// Why the short pool is worth having at all.
    ///
    /// `MarqueeText` has no "it already fits" branch — its offset advances
    /// whatever the text's width is — so a short line handed to the marquee
    /// slides out of the viewport and loops inside a single slot. This asserts
    /// that loop is real, which is the only thing that makes the routing a fix
    /// rather than a preference.
    @Test("A short line handed to the marquee would loop inside one slot")
    func shortLinesWouldLoop() {
        let short = "Binary is base two"
        #expect(columns(short) <= ThoughtBubble.plainColumns)

        let loop = Double(MarqueeText.measure(short) + MarqueeText.gap) / Double(MarqueeText.speed)
        #expect(loop < ActivityCoordinator.chatterInterval,
                "if a short line did not loop inside its slot there would be nothing to fix")
        #expect(ActivityCoordinator.bubbleStyle(for: short) == .plain)

        // Past the whole bubble's CAPACITY, not one row's width — a line
        // longer than 38 now wraps to the second line instead of scrolling.
        let long = String(repeating: "x", count: ThoughtBubble.plainCapacity + 1)
        #expect(ActivityCoordinator.bubbleStyle(for: long) == .marquee)
    }

    /// The ratio is an EQUALITY, not a tolerance. That is the whole argument
    /// for the deterministic mix over dice: dice would give 20/60/20 only in
    /// expectation, and an ordinary hour would visibly miss it.
    @Test("The mix hits its ratio exactly, every pass")
    func theMixIsExact() {
        let passes = 8
        let total = passes * FunFacts.mixLength
        let drawn = (0..<total).map { FunFacts.category(forDraw: $0) }
        for category in FunFacts.Category.allCases {
            #expect(drawn.filter { $0 == category }.count
                    == passes * FunFacts.slots(of: category),
                    "\(category.rawValue) is off over \(total) draws")
        }
        // …and per PASS, not merely in total. This is the whole argument for a
        // deterministic mix over dice: an ordinary hour must hit the ratio, not
        // just an ordinary week.
        for start in stride(from: 0, to: total, by: FunFacts.mixLength) {
            let pass = drawn[start..<start + FunFacts.mixLength]
            for category in FunFacts.Category.allCases {
                #expect(pass.filter { $0 == category }.count == FunFacts.slots(of: category),
                        "pass at \(start) is off for \(category.rawValue)")
            }
        }
    }

    /// **The invariant a future "optimisation" would break.** A category that
    /// loses a draw must not burn its counter — `LineCursor` advances only for
    /// the id it is called with, so drawing only the winner keeps every pool's
    /// place in its deck. Pre-drawing all three and discarding two would skip
    /// cards, which is the immediate-repeat bug one level up.
    @Test("A category that loses a draw keeps its place in the deck")
    func losingCategoriesKeepTheirPlace() {
        var mixed = LineCursor()
        var solo: [FunFacts.Category: LineCursor] = [:]
        var viaMix: [FunFacts.Category: [String]] = [:]
        var viaSolo: [FunFacts.Category: [String]] = [:]

        for draw in 0..<400 {
            let category = FunFacts.category(forDraw: draw)
            let pool = FunFacts.facts(in: category)
            let id = "fact:\(category.rawValue)"
            viaMix[category, default: []].append(mixed.next(pool, id: id, token: "\(draw)")!)
            var own = solo[category] ?? LineCursor()
            viaSolo[category, default: []].append(own.next(pool, id: id, token: "\(draw)")!)
            solo[category] = own
        }

        for category in FunFacts.Category.allCases {
            #expect(viaMix[category] == viaSolo[category],
                    "\(category.rawValue) lost its place in the deck")
            for (a, b) in zip(viaMix[category]!, viaMix[category]!.dropFirst()) {
                #expect(a != b, "\(category.rawValue) repeated \"\(a)\" back to back")
            }
            #expect(Set(viaMix[category]!).count == FunFacts.facts(in: category).count,
                    "\(category.rawValue) never dealt its whole pool")
        }
    }

    /// Numerical Grounding, extended. `StatusTicker`'s rule — "a confidently
    /// wrong 82% is worse than saying nothing" — was written for numbers Claude
    /// Code puts on disk. A fun fact has no file behind it at all, so it may
    /// not carry a statistic of any kind.
    @Test("No fact carries an ungrounded number")
    func factsCarryNoUngroundedNumbers() {
        for fact in FunFacts.all {
            #expect(!fact.contains("%"), "\(fact) states a percentage")
            #expect(!fact.contains("$"), "\(fact) states a figure")
        }
    }

    /// Model generations churn — `StatusTicker.knownModels` is the proof, a
    /// lookup table that has already had to grow. A fact naming one ages on
    /// exactly that schedule, and this guard reads the same list, so a future
    /// generation tightens it automatically.
    @Test("No fact names a model generation")
    func factsNameNoModelGeneration() {
        for fact in FunFacts.all {
            let lower = fact.lowercased()
            for model in StatusTicker.knownModels {
                let generation = model.name.split(separator: " ")[0].lowercased()
                #expect(!lower.contains(generation),
                        "\"\(fact)\" names \(model.name) and will age")
            }
        }
    }

    /// Superlatives are time-indexed claims wearing timeless grammar. "First"
    /// is allowed where it is a settled historical fact, so this guards only
    /// the currency words.
    @Test("No fact leans on a superlative that will move")
    func factsAvoidMovingSuperlatives() {
        let moving = ["largest", "biggest", "newest", "latest", "most advanced",
                      "state of the art", "cutting edge", "best"]
        for fact in FunFacts.all {
            let lower = fact.lowercased()
            for word in moving {
                #expect(!lower.contains(word), "\"\(fact)\" uses \"\(word)\", which moves")
            }
        }
    }
}
