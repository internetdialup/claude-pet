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

    /// The pools, and the mix the operator asked for.
    ///
    /// Claude keeps the 60% it was given in the first round. The 40% left over
    /// used to be two pools at 20% and is now five at 8%, because the operator
    /// asked for three more flavours rather than for a different balance — so
    /// the flavours divide the remainder instead of taking a bite out of
    /// Claude's share.
    ///
    /// `compSci101` is the odd one, and the difference is mechanical rather
    /// than editorial: its lines are short enough to sit still in the plain
    /// bubble. `ActivityCoordinator.bubbleStyle(for:)` says why that matters.
    public enum Category: String, Sendable, CaseIterable {
        case computerScience, compSci101, claude, ai, aiEngineering, vibeCoding
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
            "A moth in a 1947 logbook: 'first actual case of bug being found' 🐛",
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
            "'hello, world' comes from Kernighan's Bell Labs B tutorial 👋",
            // "A Mathematical Theory of Communication", 1948.
            "Claude Shannon founded information theory in a 1948 paper",
            // Engelbart's demo at the Fall Joint Computer Conference, San
            // Francisco, 9 December 1968. "in public", not "first" — the mouse
            // itself dates to 1963-64.
            "The mouse was demonstrated in public in 1968",
            // POSIX defines it as seconds since the Epoch, 1970-01-01 00:00:00
            // UTC — and NON-LEAP seconds, which is why it already trails
            // physically elapsed time by about half a minute.
            "Unix time counts non-leap seconds since 1970-01-01 UTC",
            // Dijkstra's own account, given decades later (the 2001 Frana
            // interview, in CACM): about twenty minutes, no pencil, a cafe
            // terrace in Amsterdam, 1956. "said he" because the only source for
            // the twenty minutes is the man himself.
            "Dijkstra said he designed his shortest-path algorithm in 20 minutes",
            // Tomlinson's own account of BBN in 1971: two PDP-10s standing next
            // to each other whose only link was the ARPANET. Pinned to him and
            // to that network on purpose — mail between users of ONE
            // time-shared machine predates it (CTSS, 1965), so a bare "the
            // first email" is false and takes the joke down with it.
            "In 1971 Tomlinson's ARPANET email went between machines side by side",
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
            "The transformer arrived in a 2017 paper about attention 🤖",
            // Described in the 1970s (Linnainmaa, Werbos), popularized by
            // Rumelhart, Hinton & Williams in 1986.
            "Backpropagation was described in the 1970s, popularized in 1986",
            // The 1997 rematch in New York: Deep Blue took it 3.5-2.5 from
            // Garry Kasparov. "a reigning world champion", indefinite, because
            // the title was split at the time — Karpov held FIDE's.
            "Deep Blue beat a reigning world chess champion in 1997 🏆",
            // Fixed history: the hardware existed to rasterize triangles long
            // before anyone ran a network on it.
            "GPUs were built for graphics before they trained networks",
            // The definitional claim, which is durable. An earlier draft ended
            // "not in ideas" — a flourish stated as fact, and the half that is
            // arguably false: the Lighthill report and the expert-system bust
            // took the confidence along with the money.
            "The AI winters were collapses in AI funding and interest",
            // Minsky and Papert, "Perceptrons", 1969. The book's RESULT, not
            // the folklore around it: it is routinely credited with stalling
            // the field for a decade, but funding was thinning before it landed
            // and Amari, Grossberg, Fukushima and Werbos all worked on through
            // the 1970s.
            //
            // **Scoped to the perceptron on review, and the reviewer was
            // right.** "one layer can't compute XOR" reads as a theorem about
            // any one-layer architecture; the actual result is narrower and
            // sharper — a single-layer perceptron draws one hyperplane and XOR
            // is not linearly separable. A multilayer perceptron computes it
            // fine, which is the whole reason the field went that way. The line
            // is displayed WITHOUT this comment, so the qualifier has to be in
            // the sentence.
            "Minsky and Papert, 1969: a single-layer perceptron can't do XOR",
        ]

        // 🧡 Claude and Anthropic. The riskiest pool — rule 4 especially.
        case .claude: [
            // Anthropic's own public description.
            "Anthropic is a public benefit corporation",
            "Anthropic was founded in 2021 🧡",
            "Anthropic's founders included former OpenAI researchers",
            // The Constitutional AI paper, 2022.
            "Constitutional AI trains a model against written principles",
            // Past tense: there have been successive versions, so the present
            // tense would assert one current definitive document.
            "Anthropic has published Claude's constitution 📜",
            // The document's actual name is the UNIVERSAL Declaration of Human
            // Rights. "cites" rather than "draws on" — it is quoted, not merely
            // influenced.
            "Claude's constitution cites the Universal Declaration of Human Rights",
            // MCP, open-sourced by Anthropic.
            "Anthropic open-sourced the Model Context Protocol 🔌",
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
            "Red-teaming a model means trying hard to make it misbehave 😈",
            // Anthropic's prompt-caching API. Says what the feature does and
            // nothing about what it costs or how long a cache lives, both of
            // which are the sort of thing that dates a fact within a year.
            // This slot was the fan-art disclaimer, which moved to the README
            // where a disclaimer belongs — the pool owes `.claude` thirty
            // facts to keep it from coming round sooner than every fifty
            // draws, so the slot had to be refilled rather than left empty.
            "Prompt caching lets a model reuse a prefix it has already read",
            // The Constitutional AI paper, 2022 — subtitled "Harmlessness from
            // AI Feedback". "as well as", because human preference data still
            // supplies helpfulness.
            "Constitutional AI uses AI feedback as well as human feedback",
            // The Forum's founding announcement, July 2023.
            "Anthropic co-founded the Frontier Model Forum in 2023",
            // Perfect tense, and scoped to the apps: what appears in the release
            // notes is the Claude app system prompts — not Claude Code's, and
            // not the API's, which has no default system prompt at all. A
            // present-tense claim about a practice ages the day it changes.
            "Anthropic has published the system prompts for its Claude apps",
            // Multimodal input. General and durable.
            "Claude reads images as well as text 👀",
            // The correction of the popular retelling: in a BPE vocabulary
            // common words like "the" and "and" ARE whole tokens, and a token
            // can just as easily be punctuation or whitespace. "a piece of a
            // word, not a whole one" is simply false.
            "A token can be a whole word or just a piece of one",
            // MCP's own announcement, November 2024.
            "The Model Context Protocol was released in 2024",
            // The RSP's actual mechanism, which an earlier draft had backwards:
            // capability thresholds are what trigger a required safeguard
            // standard, not the other way round.
            "Anthropic's Responsible Scaling Policy sets capability thresholds",
            // Superposition, stated generally rather than as a claim about what
            // a whole field does — plenty of interpretability work studies
            // single neurons, and the durable published finding is that one
            // neuron carries several features at once.
            "In neural nets, one neuron can encode several features",
            // Durable: the API is the older of the two surfaces.
            "Claude is reachable by API, not only a chat window",
            // July 2023, in the first group of companies. "joined", not
            // "signed": the White House announced them as VOLUNTARY
            // commitments, not an instrument with signatories.
            "Anthropic joined the 2023 White House voluntary AI commitments",
            // **Past tense on review, and the reviewer was right.** "is
            // public" is a present-tense claim about a document a company can
            // rename, restrict or withdraw — precisely what rule 4 excludes,
            // and it would go false inside binaries already shipped. That a
            // policy WAS published is historical and cannot be taken back.
            "Anthropic published a usage policy for Claude",
            // A decoding parameter, not a product detail — the same knob exists
            // wherever a model samples. It stands in for a cut line claiming
            // Claude "was trained to say when it does not know", which asserts
            // an outcome no primary source states and the model does not always
            // deliver.
            "Temperature controls how much a model's output varies",
        ]

        // 🎓 Computer science 101 — the short ones.
        //
        // Every line here fits the plain bubble, which is the whole point of
        // the pool: it appears whole and holds still for its fourteen seconds
        // instead of scrolling past. A line that outgrows the ceiling does not
        // belong here — it belongs in `computerScience`, which scrolls.
        case .compSci101: [
            // Hedged deliberately. Eight bits is a CONVENTION with live
            // exceptions, not a definition: 6- and 9-bit bytes were ordinary in
            // the 1960s, C guarantees only CHAR_BIT >= 8, and TI's C2000 DSPs
            // ship 16-bit chars today. ISO/IEC 80000-13 only *recommends*
            // reserving "byte" for eight — which is why "octet" exists at all.
            "A byte is usually eight bits",
            // Definitional.
            "Binary is base two",
            // Definitional; the name says it (hexa- + decimal).
            "Hexadecimal is base sixteen",
            // LIFO is the stack ADT's defining discipline, not an
            // implementation detail.
            "A stack: last in, first out",
            // FIFO likewise. Priority queues and deques are named variants, so
            // they are not counterexamples.
            "A queue: first in, first out",
            // "Usually" is load-bearing: Fortran, MATLAB, R, Lua and Julia
            // index from one, and Pascal and Ada take arbitrary bounds.
            "Arrays usually start at zero",
            // C11 6.2.5: a pointer's value is the address of an object or
            // function.
            "A pointer holds an address",
            // "Bounds", not "measures". Big-O is an asymptotic UPPER bound —
            // f is O(g) iff f(n) <= c*g(n) beyond some n0. The tight one is
            // Theta, and an earlier draft said "measures", which claims
            // Theta's job for it.
            "Big-O bounds growth rates",
            // The space-time tradeoff, in the right direction: storage spent
            // to avoid a slower fetch or a recomputation.
            "Caches trade space for time",
            // Deliberately unspecific. "Compiles to machine code" would be
            // false of every bytecode compiler and every transpiler.
            "A compiler translates code",
        ]

        // 🛠️ AI and prompt engineering. Papers, mostly — the durable class.
        case .aiEngineering: [
            // Wei et al., "Chain-of-Thought Prompting Elicits Reasoning in
            // Large Language Models", 2022. "Arrived in", not "was invented
            // by": the paper is what the field dates it from.
            "Chain-of-thought prompting arrived in a 2022 paper",
            // Kojima et al., "Large Language Models are Zero-Shot Reasoners",
            // 2022 — the zero-shot chain-of-thought trigger phrase.
            "'Let's think step by step' came from a 2022 paper",
            // Brown et al., "Language Models are Few-Shot Learners", 2020.
            // DEMONSTRATED, not invented — in-context examples predate it.
            "Few-shot prompting was demonstrated in the 2020 GPT-3 paper",
            // Lewis et al., 2020, which is where the name comes from.
            "Retrieval-augmented generation was named in a 2020 paper",
            // Yao et al., "ReAct: Synergizing Reasoning and Acting in Language
            // Models", 2022.
            "ReAct interleaved reasoning and tool use in a 2022 paper",
            // General and durable — true of every embedding model there is.
            "An embedding turns text into a list of numbers 🧠",
            // The settled framing: untrusted text reaching a model is an
            // injection, not a mistake in the wording.
            "Prompt injection is a security problem, not a typo",
            // What an eval is FOR, stated as a mechanism rather than a boast.
            "Evals tell a better prompt from a lucky one",
            // The distinction that survives every generation of model.
            "Fine-tuning changes the weights; prompting does not",
            // Definitional: greedy decoding is argmax at every step.
            "Greedy decoding always takes the likeliest next token",
        ]

        // 🎲 Vibe coding. The youngest pool and the thinnest, ON PURPOSE.
        //
        // Ten were drafted and four cut, all for the same reason: they were
        // aphorisms wearing a fact's grammar ("the bug you did not write is
        // still your bug"). Those belong in `vocab.swift`, in the operator's
        // voice, where a line cannot be wrong. What survives here is the term's
        // origin, its dating and its dictionary recognition — the only parts of
        // a practice this young that a compiled binary can still vouch for in
        // three years.
        case .vibeCoding: [
            // Karpathy's post, February 2025. The coinage is uncontested.
            "Andrej Karpathy coined 'vibe coding' in February 2025 ⚡",
            // Attributed on purpose. The DICTIONARY sense (Collins,
            // Merriam-Webster) is just prompting an AI in natural language and
            // does not require skipping the read; not-reading is the coiner's
            // stricter original sense, and it survives only with his name on it.
            "As Karpathy defined it, you accept the code without reading it",
            // Collins Dictionary's word of the year for 2025.
            "Collins made 'vibe coding' its word of the year for 2025",
            // Fixed history about where the phrase came from.
            "The phrase 'vibe coding' started as a post, not a paper",
            // "Published his essay", not "coined": Software 2.0 went up on
            // Medium on 11 November 2017, and nothing establishes he was first
            // to say the words — it is a generic version-number phrase.
            "Karpathy published his 'Software 2.0' essay back in 2017",
            // A category correction that stays true whatever the tooling does.
            "'Vibe coding' names a workflow, not a language",
        ]
        }
    }

    /// Every fact, for the tests and the length guard. Mirrors `Vocab.catalogue`.
    public static var all: [String] { Category.allCases.flatMap { facts(in: $0) } }

    /// The twenty-five-slot mix: fifteen Claude, and two of each of the five
    /// flavours — 60 / 8 / 8 / 8 / 8 / 8.
    ///
    /// Deterministic rather than diced, and that is a deliberate choice. Dice
    /// give the ratio only in EXPECTATION: at a fact every couple of minutes an
    /// hour is about thirty draws, so a 20% pool's count would be
    /// Binomial(30, 0.2) — mean six, standard deviation 2.1. A perfectly
    /// ordinary hour would show three of them, or ten. This gives the ratio as
    /// an equality per pass instead.
    ///
    /// It grew from ten slots to twenty-five when the flavours arrived, because
    /// 8% cannot be written in tenths. The five groups below are each three
    /// Claude and two flavours, so a pass reads as a rotation rather than as a
    /// block of Claude with a tail — though `shuffled` reorders every pass
    /// anyway, so this is legibility for whoever reads the file, not a
    /// guarantee about what he says.
    private static let mix: [Category] = [
        .claude, .computerScience, .claude, .compSci101, .claude,
        .claude, .ai, .claude, .aiEngineering, .claude,
        .claude, .vibeCoding, .claude, .computerScience, .claude,
        .claude, .compSci101, .claude, .ai, .claude,
        .claude, .aiEngineering, .claude, .vibeCoding, .claude,
    ]

    /// How many of the mix's slots this category owns, and how many slots there
    /// are. Derived from `mix` rather than written down beside it: a slot moved
    /// is a share moved, and two numbers that have to agree by hand eventually
    /// do not.
    ///
    /// Integers, not a fraction, because the staleness guard divides by this to
    /// get a repeat period and wants an exact answer — 30 / 0.6 is not reliably
    /// 50 in binary floating point, and a guard that trips on the last bit of a
    /// double is a guard nobody trusts.
    public static func slots(of category: Category) -> Int {
        mix.filter { $0 == category }.count
    }
    public static var mixLength: Int { mix.count }

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
