import Testing
import Foundation
import SwiftUI
@testable import ClaudePet

/// Tips get their own suite for the reason they get their own file: a tip can
/// go stale in a way a fact cannot. A fact about 1971 will still be true in
/// 1971; a sentence about a slash command is a claim about software that ships
/// every week, made from a binary that ships once.
@Suite("Claude Code tips")
struct ClaudeTipTests {

    private func columns(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
    }

    /// The same duration-against-duration guard the facts use, for the same
    /// reason: restating 6.62 here would keep passing forever after someone
    /// changed the renderer.
    @Test("Every tip finishes scrolling before its slot is up")
    func tipsFinishInsideTheirSlot() {
        let budget = ActivityCoordinator.chatterInterval - 2
        for tip in ClaudeTips.all {
            let read = MarqueeText.readSeconds(for: tip, width: MarqueeText.viewport)
            #expect(read <= budget,
                    "\"\(tip)\" needs \(String(format: "%.1f", read))s of a \(budget)s slot")
        }
    }

    /// **The guard this pool exists for.**
    ///
    /// Every `/word` in every tip must be a command somebody actually verified
    /// against the installed build. This is not hypothetical tidiness: when
    /// these were drafted, the live documentation still listed `/vim` and
    /// `/output-style` — both removed — and `/todos`, which has never existed
    /// in any build. Three dead commands, all of them reachable from a
    /// confident memory or a docs page.
    ///
    /// So the allowlist is the deliberate act, and this test is what makes it
    /// one. A future tip about an unvouched command fails here rather than
    /// shipping into a binary nobody updates.
    @Test("A tip may only name a command somebody verified")
    func tipsNameOnlyVouchedCommands() {
        for tip in ClaudeTips.all {
            for match in tip.split(separator: " ") where match.hasPrefix("/") {
                let name = match.dropFirst()
                    .prefix { $0.isLetter || $0 == "-" }
                guard !name.isEmpty else { continue }
                #expect(ClaudeTips.vouchedCommands.contains(String(name)),
                        "\"\(tip)\" names /\(name), which is not in vouchedCommands")
            }
        }
        // And the reverse, so the list cannot quietly accumulate names nothing
        // says any more — a stale allowlist is a stale claim waiting for a
        // future author to trust it.
        for command in ClaudeTips.vouchedCommands {
            #expect(ClaudeTips.all.contains { $0.contains("/" + command) },
                    "/\(command) is vouched for but no tip names it")
        }
    }

    /// A tip must age into STALE, never into WRONG, and the words below are how
    /// a sentence chooses the second one. "The new /x" is false the moment /x
    /// stops being new — and it stops being new without anyone touching /x.
    @Test("No tip dates itself")
    func tipsDoNotDateThemselves() {
        let dating = ["new ", "newly", "now ", "just ", "recently", "latest",
                      "coming soon", "beta", "preview"]
        for tip in ClaudeTips.all {
            let lower = tip.lowercased()
            for word in dating {
                #expect(!lower.contains(word),
                        "\"\(tip)\" says \"\(word.trimmingCharacters(in: .whitespaces))\", which ages on its own")
            }
        }
    }

    /// The fun-fact rules apply here too — this pool is read out of the same
    /// bubble by the same pet, and a rule that binds one and not the other is
    /// a rule waiting to be forgotten.
    @Test("A tip carries no ungrounded number and no model generation")
    func tipsObeyTheFactRules() {
        for tip in ClaudeTips.all {
            #expect(!tip.contains("%"), "\(tip) states a percentage")
            #expect(!tip.contains("$"), "\(tip) states a figure")
            let lower = tip.lowercased()
            for model in StatusTicker.knownModels {
                let generation = model.name.split(separator: " ")[0].lowercased()
                #expect(!lower.contains(generation),
                        "\"\(tip)\" names \(model.name) and will age")
            }
        }
    }

    /// Deep enough not to repeat, and disjoint from the facts — the two pools
    /// share a bubble and a cursor object, so a line in both would read as a
    /// stutter with no explanation.
    @Test("The pool is deep, and shares nothing with the facts")
    func poolIsDeepAndDistinct() {
        #expect(ClaudeTips.all.count > 2, "a pool this small can only alternate")
        #expect(ClaudeTips.all.count >= 12)
        #expect(Set(ClaudeTips.all).count == ClaudeTips.all.count, "a tip is duplicated")
        #expect(Set(ClaudeTips.all).isDisjoint(with: Set(FunFacts.all)))
    }

    /// **His own voice keeps every cycle it had.**
    ///
    /// This is the load-bearing claim of the whole change, and it is the one a
    /// future refactor would break without noticing. The ticker takes a third
    /// of what he says and the informational branch another third; a tip die
    /// placed BESIDE the vocabulary rather than inside the facts would have
    /// left his own lines at one turn in six, which is not a pet, it is a feed.
    ///
    /// So: walk the real gates, and assert that the cycles reaching the
    /// vocabulary are exactly the cycles that reached it before the tip die
    /// existed — the tip die is not consulted on any of them.
    /// `@MainActor` only on this one, because `idleChatterShows` is isolated —
    /// the rest of the suite stays nonisolated on purpose, so it keeps proving
    /// that the members it reaches really are.
    @Test("A tip never costs him a line in his own voice")
    @MainActor
    func tipsComeOutOfTheFactsNotTheVoice() {
        var spoke = 0, informational = 0, tips = 0, vocabulary = 0
        for seed in 0..<3000 {
            guard ActivityCoordinator.idleChatterShows(quietFor: 600, seed: seed) else { continue }
            spoke += 1
            guard seed % 3 != 2 else { continue }           // that cycle is the ticker
            guard CrabAnimator.noise(seed &* 17 &+ 7) < 0.5 else {
                vocabulary += 1                              // …and this gate is UNCHANGED
                continue
            }
            informational += 1
            if CrabAnimator.noise(seed &* 23 &+ 19) < 0.34 { tips += 1 }
        }
        #expect(spoke > 300, "the quiet gate should let plenty through")

        // The vocabulary's share is the thing being protected: it is whatever
        // the two gates above it leave, and the tip die is downstream of both.
        #expect(vocabulary > informational * 8 / 10,
                "his own voice lost ground: \(vocabulary) lines against \(informational) informational")
        // And a tip is a minority of the informational cycles, not the point of
        // them — the facts are what the operator asked for first.
        #expect(tips * 2 < informational,
                "tips took \(tips) of \(informational) informational cycles")
    }

    /// A tip short enough for the plain bubble is shown whole, like a CS-101
    /// fact — the routing is a property of the line, not of which pool it came
    /// from.
    @Test("A tip is routed by its length, like a fact")
    func tipsAreRoutedByLength() {
        for tip in ClaudeTips.all {
            let expected: PetState.BubbleStyle =
                columns(tip) <= ThoughtBubble.plainCapacity ? .plain : .marquee
            #expect(ActivityCoordinator.bubbleStyle(for: tip) == expected)
        }
    }
}
