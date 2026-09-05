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

    /// **Reversed by the two-line bubble.** This used to assert the opposite:
    /// a plain line was legible the instant it appeared, so it took no hold.
    /// Both halves of that stopped being true at once — the plain bubble now
    /// holds every line in the app, and a plain line is no longer instant
    /// because it types itself in. A hold of zero would have left the entire
    /// fact pool unshielded, which is the bug this round exists to fix.
    @Test("Every line takes a hold, because none of them arrive whole")
    func everyLineIsHeld() {
        for line in ["zzz…", "Off the clock",
                     String(repeating: "x", count: ThoughtBubble.plainColumns)] {
            #expect(ActivityCoordinator.bubbleStyle(for: line) == .plain,
                    "\"\(line)\" should be plain")
            #expect(ActivityCoordinator.lineHold(for: line) > 0, "\"\(line)\" was not held")
        }
    }

    /// The hold must always outlast the read it is protecting, for EVERY
    /// line — the invariant the two clocks used to break.
    @Test("The hold always outlasts the read, at every length")
    func theHoldCoversTheRead() {
        for columns in [1, 5, 12, 28, 38, 55, 69, 76] {
            let line = String(repeating: "x", count: columns)
            let read = ActivityCoordinator.readableWindow(for: line)
            let hold = ActivityCoordinator.lineHold(for: line)
            #expect(hold > read,
                    "\(columns) columns read in \(read)s but are held only \(hold)s")
            #expect(hold <= ActivityCoordinator.maxLineHold,
                    "\(columns) columns held \(hold)s, past the cap")
        }
    }

    /// One character over the ceiling is a ticker, and a ticker gets time.
    @Test("A line one column too wide starts scrolling, and starts being held")
    func theCeilingIsTheSwitch() {
        let over = String(repeating: "x", count: ThoughtBubble.plainCapacity + 1)
        #expect(ActivityCoordinator.bubbleStyle(for: over) == .marquee)
        #expect(ActivityCoordinator.lineHold(for: over) > 0)
    }

    /// **The glance guarantee.** Two whole marquee cycles, so a reader who
    /// looks up at ANY moment inside the first cycle still gets a complete
    /// pass that opens on the first word. This replaced three read-throughs —
    /// the operator's complaint was precisely that a glance landed
    /// mid-sentence and no clean pass followed.
    /// **The glance guarantee, restated for a bubble that stands still.**
    ///
    /// Two whole marquee cycles used to be the promise, because a glance could
    /// land mid-sentence and the reader needed a following pass that opened on
    /// the first word. A static two-line bubble opens on the first word at
    /// every instant, so the promise becomes the simpler thing it was always
    /// standing in for: whenever you look up, there is still time to read what
    /// is there. Pinned as arithmetic — a glance at any point up to the end of
    /// the typing leaves a full read behind it.
    @Test("A glance at any point still leaves time to read the line")
    func theGlanceStillGetsARead() {
        for columns in [30, 38, 44, 55, 69, 76] {
            let line = String(repeating: "x", count: columns)
            let hold = ActivityCoordinator.lineHold(for: line)
            let typing = Double(columns) / TypewriterText.charsPerSecond
            let read = Double(columns) / ActivityCoordinator.plainReadRate
            for glance in stride(from: 0.0, through: typing, by: max(0.05, typing / 7)) {
                #expect(hold - glance >= read,
                        "a glance at \(glance)s into \(columns) columns leaves \(hold - glance)s for a \(read)s read")
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

    /// **The premise moved, so the test did.**
    ///
    /// This used to assert that most facts scroll — sixty-six of seventy-six
    /// were longer than a 28-column bubble, which made length routing
    /// load-bearing. The two-line bubble ended that: at 38 columns over two
    /// lines the capacity is 76 characters and the longest fact is 69, so the
    /// honest assertion is now the opposite one, and it is worth pinning
    /// because it is the operator's actual requirement — he could not read a
    /// scrolling headline, so nothing he knows scrolls.
    ///
    /// The margin is stated as a number rather than left implicit: a future
    /// fact written past 76 characters fails here rather than silently
    /// becoming the only scrolling line in the app.
    @Test("No fact scrolls any more, and none is close to the ceiling")
    func noFactNeedsTheTicker() {
        let all = FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) }
        let scrolling = all.filter { ActivityCoordinator.bubbleStyle(for: $0) == .marquee }
        #expect(scrolling.isEmpty,
                "\(scrolling.count) of \(all.count) facts still scroll: \(scrolling.first ?? "")")
        let longest = all.map(\.count).max() ?? 0
        #expect(longest <= ThoughtBubble.plainCapacity,
                "the longest fact is \(longest) characters, past the \(ThoughtBubble.plainCapacity) the bubble holds")
    }

    /// `lineHold` is `nonisolated`, so it cannot read the main-actor cadence
    /// table and its floor is a hand-written constant. This is the coupling
    /// that constant depends on: a hold shorter than the longest dwell can
    /// expire inside the very cycle that dealt it, and `quietBeatFact` deals
    /// the same sentence straight back on top of itself.
    @MainActor
    @Test("The hold floor stays above every cadence's dwell")
    func theDwellFloorTracksTheCadences() {
        // Against the FACT moods only. `quietBeatFact` is the thing that can
        // double-deal, and it deals only in `factMoods` — a longer dwell on a
        // mood that never deals a fact (needsAttention pulses at 10) cannot
        // reopen the bug, and flooring every hold at its length would keep
        // "zzz…" on screen for eleven seconds for no reason at all.
        let longest = ActivityCoordinator.factMoods
            .compactMap { ActivityCoordinator.bubbleCadences[$0]?.dwell }
            .max() ?? 0
        #expect(longest > 0, "no fact mood has a cadence — the premise moved")
        #expect(ActivityCoordinator.dwellFloor > longest,
                "the floor is \(ActivityCoordinator.dwellFloor) against a \(longest)s dwell")
        // …and no line can be held for less than it.
        for columns in [1, 5, 12, 28, 76] {
            let line = String(repeating: "x", count: columns)
            #expect(ActivityCoordinator.lineHold(for: line) >= ActivityCoordinator.dwellFloor,
                    "\(columns) columns held \(ActivityCoordinator.lineHold(for: line))s")
        }
    }

}
