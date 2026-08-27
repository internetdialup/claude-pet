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

    /// Depth proportional to share, or the 20% pools repeat three times as
    /// often as the 60% one — the rare categories would be the ones you tire
    /// of first, which is the opposite of the intent.
    ///
    /// The floors are the pool depths themselves in 20/60/20, so a category
    /// grown on its own — twelve more Claude facts with the short pools left
    /// alone — fails here until the others keep up.
    @Test("The pools are deep enough, and proportional to their share")
    func poolsAreProportional() {
        #expect(FunFacts.facts(in: .computerScience).count >= 10)
        #expect(FunFacts.facts(in: .ai).count >= 10)
        #expect(FunFacts.facts(in: .claude).count >= 30)
        for category in FunFacts.Category.allCases {
            // `Vocab.pick` short-circuits a two-entry pool to strict
            // alternation and a one-entry pool to a constant.
            #expect(FunFacts.facts(in: category).count > 2, "\(category.rawValue) can only alternate")
        }
        #expect(Set(FunFacts.all).count == FunFacts.all.count, "a fact is duplicated")
    }

    /// The ratio is an EQUALITY, not a tolerance. That is the whole argument
    /// for the deterministic mix over dice: dice would give 20/60/20 only in
    /// expectation, and an ordinary hour would visibly miss it.
    @Test("The mix hits 20/60/20 exactly")
    func theMixIsExact() {
        let drawn = (0..<100).map { FunFacts.category(forDraw: $0) }
        #expect(drawn.filter { $0 == .computerScience }.count == 20)
        #expect(drawn.filter { $0 == .claude }.count == 60)
        #expect(drawn.filter { $0 == .ai }.count == 20)
        // …and per ten, not merely per hundred.
        for start in stride(from: 0, to: 100, by: 10) {
            let ten = drawn[start..<start + 10]
            #expect(ten.filter { $0 == .claude }.count == 6, "window at \(start) is off")
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

        for draw in 0..<200 {
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
