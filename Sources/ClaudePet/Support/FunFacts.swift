import Foundation

// ═════════════════════════════════════════════════════════════════════════════
//  🧠  FUN FACTS — what Claw'd reads out while he has nothing to report.
// ═════════════════════════════════════════════════════════════════════════════
//
//  Separate from `vocab.swift` on purpose, and the reason is editorial rather
//  than tidiness: **a vocabulary line cannot be wrong.** It is an opinion in
//  the operator's voice, which is why the 29-character test carries a
//  `knownLong` allowlist that explicitly refuses to rewrite it. A fact CAN be
//  wrong, and a wrong one is a shipping defect — it goes out in a binary the
//  operator may never update, with no citation, no link and no context beside
//  it. So the rules below bind harder than anything in `vocab.swift`.
//
//  The governing precedent is `StatusTicker`'s: *"a confidently wrong 82% is
//  worse than saying nothing."* That was written for numbers Claude Code puts
//  on disk. A fun fact has no file behind it at all.
//
//  ── The rules ──────────────────────────────────────────────────────────────
//
//  1. No percentages, benchmark scores or dollar figures. Nothing can ground
//     them. Enforced by test.
//  2. No model generation names. The proof they churn is two files away:
//     `StatusTicker.knownModels` is a lookup table that has already had to
//     grow. Enforced by test, against that same list, so a future generation
//     automatically tightens the guard.
//  3. No superlatives — "first ever", "largest", "newest". Those are
//     time-indexed claims wearing timeless grammar.
//  4. **The three-year test.** Every line must still be true read three years
//     from now with no code change. Origins, published papers and historical
//     firsts are durable. Product details and company facts a press release
//     could change are not.
//  5. **A source note above every fact.** Free, survives in git, and turns a
//     future audit into a `grep` rather than an excavation.
//
//  ── The length budget ──────────────────────────────────────────────────────
//
//  **69 characters.** These scroll, so they are not held to the plain bubble's
//  29 — but the ceiling is arithmetic all the same. `MarqueeText` starts a new
//  utterance at its first character (see its `began`), travels at 26pt/s
//  through a 150pt viewport at a 6.62pt advance, and the idle slot holds one
//  line for `chatterInterval`. So the last character reaches the viewport at
//  `(6.62n - 150) / 26` seconds, and 69 lands at 11.8s of a 14s slot.
//  `FunFactTests` asserts that as a DURATION against the renderer's own
//  constants rather than restating the number here.
//
public enum FunFacts {

    /// The three pools, and the mix the operator asked for: 20% computer
    /// science, 60% Claude, 20% AI.
    public enum Category: String, Sendable, CaseIterable {
        case computerScience, claude, ai
    }

    /// A switch rather than a dictionary, for the reason `Vocab.lines(for:)`
    /// is one: adding a category should stop the build until it has facts,
    /// not return nil at runtime and go quietly missing.
    public static func facts(in category: Category) -> [String] {
        switch category {

        // 💻 Computer science.
        case .computerScience: [
            // Harvard Mark II log, 9 Sept 1947; the moth is at the Smithsonian.
            // NOT "the first computer bug": "bug" was engineering slang decades
            // earlier, which is exactly why the log entry makes the joke.
            "A moth in a 1947 logbook: 'first actual case of bug being found'",
            // Note G of her translation of Menabrea, 1843. Says what she
            // demonstrably published — "the first algorithm" is contested, since
            // Babbage wrote programs for the engine in the 1830s.
            "Ada Lovelace's 1843 notes include a program for Babbage's engine",
            // "On Computable Numbers", 1936. It defines an abstract universal
            // machine; the stored-program architecture came later, via the 1945
            // EDVAC draft, so this must not say "the modern computer".
            "Turing defined the universal computing machine in 1936, on paper",
            // NATO Software Engineering Conference, Garmisch, 1968. POPULARIZED,
            // not coined — the title was chosen because it was provocative,
            // which presupposes the term already existed.
            "A 1968 NATO conference popularized 'software engineering'",
            // Kernighan's Bell Labs tutorial for the language B. The year is
            // cited variously as 1972 and 1973, so it is left out.
            "'hello, world' comes from Kernighan's Bell Labs B tutorial",
            // "A Mathematical Theory of Communication", 1948.
            "Claude Shannon founded information theory in a 1948 paper",
        ]

        // 🤖 AI, mostly its history — the part that will still be true later.
        case .ai: [
            // McCarthy coined it in the WRITTEN PROPOSAL, dated August 1955, for
            // the workshop held in 1956. The phrase predates the meeting.
            "'Artificial intelligence' was coined in the 1955 Dartmouth proposal",
            // 1958 is Rosenblatt's paper and an IBM 704 simulation; the custom
            // Mark I hardware came later. Both halves, neither welded.
            "The perceptron was a 1958 paper, then real hardware: the Mark I",
            // Weizenbaum's ELIZA, 1966, and his alarm at how people responded.
            "By 1966 people confided in ELIZA, which understood nothing",
            // "Computing Machinery and Intelligence", 1950.
            "Turing proposed the imitation game in 1950",
            // "Attention Is All You Need", 2017.
            "The transformer arrived in a 2017 paper about attention",
            // Described in the 1970s (Linnainmaa, Werbos), popularized by
            // Rumelhart, Hinton & Williams in 1986.
            "Backpropagation was described in the 1970s, popularized in 1986",
        ]

        // 🧡 Claude and Anthropic. The riskiest pool — rule 4 especially.
        case .claude: [
            // Anthropic's own public description.
            "Anthropic is a public benefit corporation",
            "Anthropic was founded in 2021",
            "Anthropic's founders included former OpenAI researchers",
            // The Constitutional AI paper, 2022.
            "Constitutional AI trains a model against written principles",
            // Past tense: there have been successive versions, so the present
            // tense would assert one current definitive document.
            "Anthropic has published Claude's constitution",
            // The document's actual name is the UNIVERSAL Declaration of Human
            // Rights. "cites" rather than "draws on" — it is quoted, not merely
            // influenced.
            "Claude's constitution cites the Universal Declaration of Human Rights",
            // MCP, open-sourced by Anthropic.
            "Anthropic open-sourced the Model Context Protocol",
            // MCP's own documentation.
            "MCP is an open standard for connecting models to tools and data",
            // Past tense on purpose: it launched in the terminal and has since
            // reached other surfaces, so a present-tense claim would age.
            "Claude Code launched as a coding agent in your terminal",
            // Anthropic's Responsible Scaling Policy.
            "Anthropic publishes a Responsible Scaling Policy",
            // The RSP's AI Safety Levels. "Modeled on", not "named after" —
            // the tiered scheme was borrowed, not the name.
            "Anthropic's AI Safety Levels are modeled on biosafety levels",
            // Anthropic's published interpretability research.
            "Anthropic's interpretability team studies what models learn",
            // Cards accompany model releases, not everything Anthropic ships.
            "Anthropic publishes model cards for the models it releases",
            // General and durable — true of every model with a context window.
            "Context windows are measured in tokens, not words",
            // General and durable.
            "A system prompt is read before anything you type",
            // Tool use: the model emits a structured request, the host runs it.
            "Claude can call tools by asking for them in a structured way",
            // General AI-safety usage of the term.
            "Red-teaming a model means trying hard to make it misbehave",
            // This repo's README and LICENSE. It says only what those say —
            // an earlier draft asserted the crab was Anthropic's intellectual
            // property, which is not something this project can vouch for.
            "Claw'd is unofficial fan art, not affiliated with Anthropic",
        ]
        }
    }

    /// Every fact, for the tests and the length guard. Mirrors `Vocab.catalogue`.
    public static var all: [String] { Category.allCases.flatMap { facts(in: $0) } }

    /// The ten-slot mix: exactly two computer-science, six Claude, two AI.
    ///
    /// Deterministic rather than diced, and that is a deliberate choice. Dice
    /// give 20/60/20 only in EXPECTATION: at a fact every couple of minutes an
    /// hour is about thirty draws, so the computer-science count would be
    /// Binomial(30, 0.2) — mean six, standard deviation 2.1. A perfectly
    /// ordinary hour would show three of them, or ten. This gives the ratio as
    /// an equality per ten draws instead.
    private static let mix: [Category] = [
        .computerScience, .claude, .claude, .ai, .claude,
        .claude, .computerScience, .claude, .ai, .claude,
    ]

    /// Which category the `draw`-th fact comes from.
    ///
    /// `Vocab.shuffled` and deliberately **not** `Vocab.deck`: the deck's
    /// join-fix compares a pass's first entry against the previous pass's last
    /// and swaps to avoid a repeat. With six identical `.claude` slots that
    /// would fire constantly and mean nothing — two Claude facts in a row is
    /// what sixty percent *is*.
    public static func category(forDraw draw: Int) -> Category {
        let safe = draw & Int.max
        let names = mix.map(\.rawValue)
        let slot = Vocab.shuffled(names, seed: safe / names.count)[safe % names.count]
        return Category(rawValue: slot) ?? .claude
    }
}
