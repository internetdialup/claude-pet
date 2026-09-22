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
//  **76 columns — `ThoughtBubble.plainCapacity`, 38 across two rows.** Nothing
//  in this file scrolls any more, and that is a change from how it was written:
//  facts used to be held to a scrolling deadline because a line past one row
//  went to the marquee. The bubble grew a second row, so every fact now sits
//  still in the plain bubble and the ceiling is simply the bubble's.
//
//  Count COLUMNS, not characters — an emoji is two. `FunFactTests` asserts the
//  capacity against `ThoughtBubble`'s own constant, and separately asserts the
//  premise that nothing scrolls, so the scrolling guard cannot quietly become a
//  gate on an empty set.
//
//  ── What the 2026 audit found ──────────────────────────────────────────────
//
//  Every claim here was checked against a source in September 2026. Sixty-six
//  of seventy-six stood. Three were imprecise from the start. **Four had simply
//  DECAYED** — true when written, overtaken since: MCP moved to the Linux
//  Foundation, the constitution was rewritten and dropped a citation, the
//  temperature parameter was retired, and "model card" became "system card".
//
//  Nothing had been careless. The world moved and the file did not, which is
//  the failure mode a deck about a live company has and a deck about 1843 does
//  not. Rules 4 and 5 already existed to prevent it; what was missing was the
//  SOURCE on each line, so an audit is a `grep` rather than an excavation.
//  That is now there. Re-run it when a fact starts to feel dated.
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
    /// `compSci101` used to be the odd one: its lines were cut to fit ONE row
    /// of the bubble, back when a longer line was handed to the marquee and
    /// scrolled. The bubble now runs 38 columns over TWO rows, so nothing in
    /// the deck scrolls — and one row was exactly what made that pool read as
    /// a glossary. It takes the same budget as the rest now. The pool stays
    /// because the MIX is the point, not because its lines are short.
    public enum Category: String, Sendable, CaseIterable {
        case computerScience, compSci101, claude, ai, aiEngineering, vibeCoding
    }

    /// A switch rather than a dictionary, for the reason `Vocab.lines(for:)`
    /// is one: adding a category should stop the build until it has facts,
    /// not return nil at runtime and go quietly missing.
    public static func facts(in category: Category) -> [String] {
        switch category {

        // 💻 Computer science.
        // ────────────────────────────────────────────────────────────────────
        // MARK: 💻  COMPUTER SCIENCE
        // ────────────────────────────────────────────────────────────────────
        case .computerScience: [
            // Relay #70, Panel F of Harvard's Mark II, 9 Sept 1947, 15:45. The
            // log and the moth are both in the Smithsonian (NMAH 334663).
            // NOT "the first computer bug": "bug" was engineering slang decades
            // earlier, which is exactly why the log entry makes the joke — it
            // was the first LITERAL one. Hopper was on the team but almost
            // certainly did not write the entry, so she is not named.
            // Source: Computer History Museum, This Day in History, 9 Sept.
            "In 1947 a moth jammed Harvard's Mark II — it's still taped in the log 🐛",
            // Note G of her 1843 translation of Menabrea: a 25-operation
            // procedure for Bernoulli numbers, loops and all. Says what she
            // demonstrably published — "the first algorithm" is contested,
            // since Babbage wrote programs for the engine in the 1830s.
            // Source: Bodleian Library Ada Lovelace blog; Note G facsimile.
            "In 1843 Ada Lovelace wrote a Bernoulli-number program for Babbage's engine",
            // "On Computable Numbers", received 28 May 1936. It defines an
            // abstract universal machine; the first stored-program computers
            // ran in 1948, which is the point the new wording makes — it must
            // not say "the modern computer".
            // Source: Proc. London Mathematical Society s2-42, pp. 230-265.
            "Turing described a universal machine in 1936, years before one existed",
            // NATO Software Engineering Conference, Garmisch, 7-11 Oct 1968,
            // ~50 attendees, proceedings edited by Naur and Randell. CAUGHT ON,
            // not coined — the title was chosen because it was provocative,
            // which presupposes the term already existed.
            // Source: Naur & Randell (eds.), NATO Science Committee report.
            "'Software engineering' caught on at a NATO conference in Garmisch, 1968",
            // Kernighan's 1972 Bell Labs memo "A Tutorial Introduction to the
            // Language B" — the earliest known one, printed four characters at
            // a time because a B character constant held only four. The Jargon
            // File's 1967 BCPL claim is undocumented, so it is not repeated.
            // Source: Kernighan, Bell Laboratories, 1972.
            "Kernighan's 1972 B tutorial at Bell Labs first printed 'hello, world' 👋",
            // "A Mathematical Theory of Communication", Bell System Technical
            // Journal, July and October 1948. Names Bell Labs rather than the
            // word "bit": Shannon put it in print but credited Tukey for it.
            // Source: BSTJ 27 (1948), pp. 379-423 and 623-656.
            "Claude Shannon founded information theory in one 1948 Bell Labs paper",
            // The Fall Joint Computer Conference, San Francisco, 9 Dec 1968 —
            // the Mother of All Demos. "in public" is load-bearing and was
            // missing before: Engelbart and English built the thing in 1964, so
            // an undated 1968 reads as the invention date and is out by four
            // years.
            // Source: SRI, "The computer mouse and interactive computing".
            "Engelbart demoed the first mouse in public on 9 December 1968",
            // POSIX: seconds since 1970-01-01 00:00:00 UTC. The old line said
            // NON-LEAP seconds, which is exact and the densest jargon in the
            // deck — a caveat a speech bubble cannot pay off. Dropping it omits
            // detail without stating anything false.
            // Source: POSIX.1-2017 §4.16; MDN glossary, "Unix time".
            "Computers count seconds since 1 January 1970 — the Unix epoch",
            // Dijkstra's own account in the 2001 Frana interview (CACM, Aug
            // 2010): about twenty minutes, no pencil, a cafe terrace in
            // Amsterdam, 1956, designed to show off the ARMAC. Published 1959.
            // Source: CACM 53(8); Charles Babbage Institute oral history OH 330.
            "In 1956 Dijkstra designed his shortest-path algorithm in 20 minutes",
            // BBN, late 1971: two PDP-10s standing next to each other whose
            // only link was the ARPANET, about fifteen feet apart. No exact day
            // is confirmed — Tomlinson called the test messages forgettable —
            // so this dates to the year only. Pinned to him and to that network
            // on purpose: mail between users of ONE time-shared machine
            // predates it (CTSS, 1965), so a bare "the first email" is false.
            // Source: Internet Hall of Fame biography of Raymond Tomlinson.
            "Tomlinson's 1971 email crossed ARPANET to the machine beside him",
        ]

        // 🤖 AI, mostly its history — the part that will still be true later.
        // ────────────────────────────────────────────────────────────────────
        // MARK: 🤖  AI
        // ────────────────────────────────────────────────────────────────────
        case .ai: [
            // McCarthy coined it in the WRITTEN PROPOSAL, dated 31 Aug 1955,
            // for the workshop held in summer 1956 — the phrase predates the
            // meeting. He picked it partly to stay clear of "cybernetics" and
            // Wiener's orbit. Names him, because the old line had no human in
            // it at all.
            // Source: AI Magazine 27(4) reprint of the 1955 proposal.
            "John McCarthy coined 'artificial intelligence' in a 1955 grant proposal",
            // Three dates, not one: a January 1957 Cornell Aeronautical Lab
            // report, the famous 1958 Psychological Review paper, and the Mark
            // I hardware shown publicly on 23 June 1960. Its eye was a 20x20
            // grid of cadmium-sulfide photocells — 400 pixels, which is the
            // concrete image the old "then real hardware" clause lacked.
            // Source: Psych. Review 65(6):386-408; Mark I Perceptron records.
            "Rosenblatt's 1958 perceptron ran on a 1960 machine that saw 400 pixels",
            // Weizenbaum's ELIZA, CACM January 1966, and his alarm at how
            // people responded. The secretary who asked him to leave the room
            // KNEW what it was, which is the whole point — the old line
            // asserted "understood nothing" without showing why that mattered.
            // Source: Weizenbaum, CACM 9(1); the ELIZA effect literature.
            "Weizenbaum's 1966 ELIZA only echoed you — his secretary wanted privacy",
            // "Computing Machinery and Intelligence", Mind LIX(236), Oct 1950.
            // Says what the game IS: "proposed the imitation game" is a label
            // unless you unpack it, and the unpacking fits.
            // Source: Mind LIX(236), pp. 433-460.
            "Turing's 1950 imitation game: could a machine pass for human by text?",
            // arXiv:1706.03762, 12 June 2017, NeurIPS 2017. Names the paper —
            // "a 2017 paper about attention" is the vaguest possible way to
            // refer to the most cited paper in the field.
            // Source: arXiv:1706.03762.
            "The 2017 paper 'Attention Is All You Need' gave us transformers 🤖",
            // Reverse-mode autodiff is in Linnainmaa's 1970 master's thesis;
            // Werbos proposed applying it to nets in 1974; it became famous
            // through Rumelhart, Hinton & Williams, Nature 323:533-536, 1986.
            // Source: Nature 323 (1986); Schmidhuber's annotated history.
            "Backprop hid in a 1970 thesis until Rumelhart's 1986 Nature paper",
            // The New York rematch, sealed when Kasparov resigned after 19
            // moves on 11 May 1997. "champion Kasparov" rather than "the world
            // champion": the title was split at the time and Karpov held
            // FIDE's, so the definite article would be wrong.
            // Source: IBM's Deep Blue history; match records.
            "Deep Blue beat champion Kasparov in May 1997, 3.5-2.5 over six games 🏆",
            // The same silicon, thirteen years apart: NVIDIA's GeForce 256
            // shipped in October 1999 for 3D games, and AlexNet won ImageNet in
            // 2012 after about six days on two consumer GTX 580s. The old line
            // was true but dateless and abstract, which was the complaint.
            // Source: Krizhevsky, Sutskever & Hinton, NeurIPS 2012.
            "AlexNet's 2012 breakthrough ran on two GeForce cards meant for gaming",
            // The two commonly cited winters, dated. The first followed the
            // 1973 Lighthill report and DARPA's 1974 cuts; the second the
            // collapse of the Lisp-machine market around 1987-88. An earlier
            // draft ended "not in ideas" — a flourish stated as fact, and the
            // half that is arguably false. Dates make it a fact rather than a
            // glossary entry, which is what the old line had become.
            // Source: Actuaries Institute, "History of AI Winters".
            "The AI winters: funding dried up in 1974-1980 and again in 1987-1993",
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
            //
            // Re-cut as a sentence rather than a citation stub — "Name, year:"
            // reads as a footnote. The scoping survives intact in "one
            // perceptron layer".
            // Source: Minsky & Papert, Perceptrons, MIT Press 1969.
            "In 1969 Minsky and Papert proved one perceptron layer can't learn XOR",
        ]

        // 🧡 Claude and Anthropic. The riskiest pool — rule 4 especially.
        // ────────────────────────────────────────────────────────────────────
        // MARK: 🧡  CLAUDE & ANTHROPIC
        //  Needs THIRTY facts. It owns 60% of the mix, and the suite fails if any
        //  category comes round sooner than every 50 draws — remove one without
        //  replacing it and `poolsAreProportional` goes red.
        // ────────────────────────────────────────────────────────────────────
        case .claude: [
            // Delaware PBC; its board is elected by stockholders and the
            // Long-Term Benefit Trust. The old line stated a legal status
            // without saying what the status obliges, which is the hanging
            // kind. Still current as of 2026.
            // Source: Anthropic company page.
            "Anthropic is a public benefit corporation, chartered to benefit humanity",
            // Incorporated 26 January 2021; the public launch coverage is May
            // 2021. The month costs eight characters and buys a dated fact.
            "Anthropic was founded in January 2021 🧡",
            // "Included former OpenAI researchers" undersold it — every named
            // co-founder came from OpenAI. Names Dario and his title rather
            // than a head count: Wikipedia's prose says seven ex-OpenAI
            // employees while its infobox lists eight founders, and a number
            // nobody agrees on is not worth spending.
            "Dario Amodei led research at OpenAI before founding Anthropic in 2021",
            // "Constitutional AI: Harmlessness from AI Feedback", arXiv
            // 2212.08073, December 2022. Says the MECHANISM — self-critique
            // and revision against a written list — rather than describing the
            // idea in the abstract.
            // Source: arXiv:2212.08073.
            "Constitutional AI, from 2022: the model critiques itself against rules",
            // First published 9 May 2023; wholly rewritten and republished at
            // roughly 79 pages on 21 January 2026. The rewrite is the news, so
            // it is worth the characters.
            // Source: anthropic.com, "Claude's Constitution".
            "Anthropic published a new constitution for Claude in January 2026 📜",
            // 🔎 DECAYED, and anchored to fix it. The 2023 post says the
            // constitution "draws from a range of sources including the UN
            // Declaration of Human Rights" — but the January 2026 rewrite
            // dropped that framing, and Oxford's review notes the new document
            // does not explicitly reference human rights. Undated, this line
            // now describes a document that no longer says it. "Drew on",
            // past tense, because Anthropic said "draws from" and not "cites".
            // Source: anthropic.com 2023 constitution post; Oxford review,
            // March 2026.
            "Claude's 2023 constitution drew on the UN Declaration of Human Rights",
            // 🔎 DECAYED. Anthropic open-sourced MCP on 25 November 2024 and
            // then DONATED it to the Linux Foundation's Agentic AI Foundation
            // on 9 December 2025, alongside Block and OpenAI. "Anthropic
            // open-sourced MCP" is still historically true but is no longer a
            // statement about who owns it, and the handover is the better fact.
            // Source: anthropic.com, MCP donation announcement.
            "Anthropic gave MCP away to the Linux Foundation in December 2025 🔌",
            // Anthropic's own image, which is punchier than any definition:
            // MCP is "like a USB-C port for AI applications". Borrowed rather
            // than paraphrased.
            // Source: Claude docs glossary.
            "Anthropic calls MCP a USB-C port for AI apps — one plug, any tool",
            // Research preview 24 February 2025, generally available May 2025
            // alongside Claude 4. The preview date is the interesting half.
            "Claude Code began as a February 2025 research preview in the terminal",
            // Version 1.0 published 19 September 2023. The version number is
            // deliberately LEFT OUT: the policy has been revised nine times
            // and is on 3.4 as of July 2026, so naming a version would date
            // the line the next time it moves. The origin is permanent.
            // Source: anthropic.com, Responsible Scaling Policy.
            "Anthropic first published its Responsible Scaling Policy in Sept 2023",
            // The RSP says ASLs are "modeled after the US government's
            // biosafety level (BSL) standards". "Lab biosafety levels" just
            // makes clear which kind is meant — the bare phrase was one of the
            // hard, hanging descriptions.
            "Anthropic's AI Safety Levels are modeled on lab biosafety levels",
            // "Studies what models learn" could describe any research team
            // anywhere. The result instead: on 21 May 2024 the interpretability
            // team extracted millions of features from a middle layer of a
            // production model — the first detailed look inside one. The model
            // is unnamed because rule 2 bans generation names, and that is what
            // keeps the line true after the next release.
            // Source: anthropic.com, "Mapping the Mind of a Large Language
            // Model", May 2024.
            "In 2024 Anthropic mapped millions of concepts inside a live model",
            // 🔎 DECAYED, mildly. The practice is real but the TERM moved:
            // Anthropic's page is "Model System Cards" and early releases used
            // "model card" only through Claude 3. Claude 2, July 2023, is the
            // earliest listed.
            // Source: anthropic.com/system-cards.
            "Every Claude model since 2023 has shipped with a public system card",
            // The tokens-not-words half is the permanent part, so it is all
            // that survives here. A draft carried the current flagship window
            // as a number; rule 4 caught it — a context size is exactly the
            // product detail a press release changes, and rule 3 caught
            // "largest" on top of it. The docs' own framing, "working memory",
            // does the work the number was doing.
            "A context window is a model's working memory, counted in tokens",
            // In the Messages API `system` is a top-level parameter, separate
            // from the messages array — there is no "system" role in input.
            // The old line ended on "anything you type", which trails off;
            // naming what the prompt DOES closes the sentence.
            "A system prompt sets Claude's role before your first word arrives",
            // "In a structured way" was exactly the hard, hanging phrase.
            // The mechanism: each tool carries a name, a description and an
            // `input_schema` that is a JSON schema, and Claude emits input
            // matching it.
            "To use a tool, Claude fills in a JSON schema you wrote for it",
            // "Red Teaming Language Models to Reduce Harms", arXiv 2209.07858,
            // August 2022: "We release our dataset of 38,961 red team attacks".
            // Publishing your own attack log is a better fact than defining
            // the term, and the number is the whole point.
            // Source: arXiv:2209.07858.
            "Anthropic's 2022 red team published all 38,961 of its attacks 😈",
            // Announced 14 August 2024 in public beta. Anthropic publishes
            // cost and latency figures for it, and they are deliberately NOT
            // here: rule 1 bans percentages outright because nothing in the
            // binary can ground one, and the rule is right even when the
            // number is the vendor's own.
            "Prompt caching, from August 2024, lets a long prompt be read once",
            // The nuance is the good part, and "as well as" buried it: in the
            // 2022 paper the split is deliberate — helpfulness still comes
            // from human feedback, harmlessness from AI-generated preferences
            // (RLAIF). The only human oversight on the harmlessness side is
            // the written list of principles itself.
            "In Constitutional AI, the harmlessness feedback comes from AI, not people",
            // Announced 26 July 2023 by Anthropic, Google, Microsoft and
            // OpenAI. That the other three are direct competitors is what
            // makes it a fun fact rather than an org chart.
            "Anthropic co-founded the Frontier Model Forum with three rivals, 2023",
            // Since August 2024, in the release notes for the web, iOS and
            // Android apps, updated with each model release — a practice
            // rather than the one-off event the old line implied.
            "Since 2024 Claude's app system prompts ship in public release notes",
            // Image input arrived with the Claude 3 family, 4 March 2024
            // (Haiku on the 13th). The old line was true but timeless.
            "Claude has read images as well as text since Claude 3, March 2024 👀",
            // The docs glossary supplies the number that makes this digestible:
            // "a token approximately represents 3.5 English characters, though
            // the exact number can vary depending on the language used".
            "A token is about 3.5 English characters — a word, or a piece of one",
            // Released 25 November 2024, spec 2024-11-05, with Python and
            // TypeScript SDKs. Stays about the RELEASE — ownership moved to
            // the Linux Foundation in December 2025, which is the entry above.
            "MCP was released on 25 November 2024, with Python and TypeScript SDKs",
            // The old line stated the mechanism but not the consequence, which
            // is why it read as a hanging description. Crossing a threshold is
            // what triggers stricter safety, security and operational measures.
            "Cross a capability threshold and Anthropic's RSP demands more safeguards",
            // Polysemanticity. "Toy Models of Superposition", September 2022:
            // networks store more features than they have dimensions, so
            // neurons respond to seemingly unrelated combinations of inputs.
            // "Several features" was technically right and bloodless.
            "Neurons are polysemantic: one can hold several unrelated ideas at once",
            // Served through the Messages API, and via Bedrock and Vertex. The
            // old "not only a chat window" is a negation that leaves the
            // listener waiting for the rest of the sentence.
            "Claude runs behind an API, so apps can call it without a chat window",
            // 21 July 2023: Amazon, Anthropic, Google, Inflection, Meta,
            // Microsoft and OpenAI. Eight more signed that September, so the
            // count is pinned to the July date it belongs to.
            "Anthropic was one of seven firms at the White House AI pledge, 2023",
            // "Published a usage policy" was the flattest line in the deck —
            // barely a fact. The rename is dateable: the Acceptable Use Policy
            // became the Usage Policy effective 6 June 2024.
            "Anthropic's Acceptable Use Policy became the Usage Policy in June 2024",
            // 🔎 DECAYED, and the sharpest case. The general description is
            // fine — temperature controls randomness — but the Messages API
            // now marks it "Deprecated. Models released after Claude Opus 4.6
            // do not support setting temperature", and later models reject it
            // outright. Undated, this line described a dial that has been
            // removed. Past tense fixes it; the cutoff MODEL cannot be named
            // here because rule 2 bans generation names, and "has since" is
            // true regardless of which release did it.
            // Source: platform.claude.com Messages API deprecation notice.
            "Temperature dials a model's randomness — Claude has since retired it",
        ]

        // 🎓 Computer science 101 — the short ones.
        //
        // Every line here fits the plain bubble, which is the whole point of
        // the pool: it appears whole and holds still for its fourteen seconds
        // instead of scrolling past. A line that outgrows the ceiling does not
        // belong here — it belongs in `computerScience`, which scrolls.
        // ────────────────────────────────────────────────────────────────────
        // MARK: 📗  COMPUTER SCIENCE 101
        // ────────────────────────────────────────────────────────────────────
        case .compSci101: [
            // 🔎 THIS POOL WAS THE WHOLE COMPLAINT, and the cause was
            // mechanical. Every line here was cut to fit ONE row of the bubble,
            // back when a longer one was handed to the marquee and scrolled.
            // The bubble has since been widened to 38 columns over TWO rows, so
            // nothing in the deck scrolls any more — and one row was exactly
            // what made these read as glossary entries rather than facts. They
            // now get the same 76-column budget as every other pool, and each
            // one keeps the hedge it was hedged for.
            //
            // Eight bits is a CONVENTION with live exceptions: 6- and 9-bit
            // bytes were ordinary in the 1960s, C guarantees only CHAR_BIT >= 8,
            // and TI's C2000 DSPs ship 16-bit chars today. The System/360 is
            // what made eight the default, which is the fact worth having.
            // Source: IBM System/360 architecture; ISO/IEC 80000-13.
            "Bytes weren't always 8 bits: IBM's System/360 settled that in 1964",
            // Leibniz, "Explication de l'Arithmétique Binaire", Mémoires de
            // l'Académie Royale des Sciences, 1703. "Binary is base two" was
            // definitional and said nothing; the date is the fact.
            // Source: Mémoires de l'Académie Royale des Sciences, 1703.
            "Leibniz published base-two arithmetic in 1703, using only 0 and 1",
            // The name still says it (hexa- + decimal), but the useful part is
            // the relationship to a byte: two digits, 0x00 to 0xFF, 0 to 255.
            "Two hex digits make one byte: 0x00 is 0 and 0xFF is 255",
            // LIFO is the stack ADT's defining discipline, not an
            // implementation detail. Turing's 1946 ACE report called the two
            // operations BURY and UNBURY, which is both true and the only
            // memorable thing about a definition everyone already knows.
            // Source: Turing, Proposed Electronic Calculator (ACE), 1946.
            "Stacks are last in, first out — Turing called it 'bury' and 'unbury'",
            // FIFO likewise; priority queues and deques are named variants, so
            // they are not counterexamples. Erlang's 1909 work on Copenhagen
            // telephone exchanges is where the maths of waiting lines starts.
            // Source: A. K. Erlang, "The Theory of Probabilities and Telephone
            // Conversations", 1909.
            "First in, first out: Erlang founded queueing theory on 1909 phone lines",
            // "Usually" was load-bearing and is preserved by naming the
            // argument rather than the exception: Fortran, MATLAB, R, Lua and
            // Julia index from one, and Pascal and Ada take arbitrary bounds.
            // EWD831 is Dijkstra arguing the case, not a standard settling it.
            // Source: Dijkstra, EWD831, 1982.
            "Arrays start at zero — Dijkstra argued why in his 1982 note EWD831",
            // C11 6.2.5: a pointer's value is the address of an object or
            // function. Lawson introduced the pointer in PL/I while at
            // Standard Electric Lorenz; IEEE gave him the Computer Pioneer
            // Award for it in 2000.
            // Source: IEEE Computer Society Computer Pioneer Award, 2000.
            "Harold Lawson invented the pointer in 1964 — IEEE gave him a medal",
            // Big-O is an asymptotic UPPER bound — f is O(g) iff
            // f(n) <= c*g(n) beyond some n0 — and unqualified "bounds" reads as
            // tight, which is Theta's job. The history dodges the ambiguity
            // entirely and is the better hook: Bachmann used the symbol in
            // number theory in 1894, Landau extended it in 1909, and Knuth
            // brought Omega and Theta to algorithm analysis in 1976.
            // NOT "big omicron" — it is a capital letter O.
            // Source: Bachmann, Analytische Zahlentheorie, 1894; Knuth, SIGACT
            // News, 1976.
            "Big-O predates computers: Bachmann used it in number theory in 1894",
            // The space-time tradeoff, in the right direction: storage spent to
            // avoid a slower fetch. Wilkes' 1965 paper proposed it and called
            // it a "slave memory" — the word "cache" came afterwards.
            // Source: Wilkes, IEEE Trans. Electronic Computers, 1965.
            "Maurice Wilkes proposed the cache in 1965 and called it slave memory",
            // Deliberately unspecific about the target: "compiles to machine
            // code" would be false of every bytecode compiler and every
            // transpiler. Hopper's A-0 (1952) is where the WORD comes from,
            // which is the part worth saying.
            // Source: Hopper, "The Education of a Computer", ACM 1952.
            "Grace Hopper finished the A-0 in 1952 and coined the word 'compiler'",
        ]

        // 🛠️ AI and prompt engineering. Papers, mostly — the durable class.
        // ────────────────────────────────────────────────────────────────────
        // MARK: 🔧  AI ENGINEERING
        // ────────────────────────────────────────────────────────────────────
        case .aiEngineering: [
            // Wei et al., arXiv 2201.11903, 28 Jan 2022, all at Google;
            // NeurIPS 2022. Says what the technique IS — "arrived in a 2022
            // paper" dated it without describing it.
            // Source: arXiv:2201.11903.
            "Chain-of-thought, from Google in 2022: models reason better out loud",
            // Kojima et al., arXiv 2205.11916, 24 May 2022 — Zero-shot-CoT,
            // one template with no worked examples, which is what separates it
            // from the entry above. Named, because an anonymous "2022 paper"
            // is the hanging kind.
            // Source: arXiv:2205.11916.
            "'Let's think step by step' — Kojima's May 2022 one-liner",
            // Brown et al., arXiv 2005.14165, 28 May 2020. ARRIVED WITH, not
            // invented — in-context examples predate it; the abstract's own
            // claim is "without any gradient updates or fine-tuning".
            // Source: arXiv:2005.14165.
            "Few-shot prompting arrived with GPT-3, Tom Brown's May 2020 paper",
            // Lewis et al., arXiv 2005.11401, 22 May 2020, FAIR/UCL/NYU. The
            // old line said a naming happened without saying what was named.
            // Source: arXiv:2005.11401.
            "RAG, named by Patrick Lewis in 2020: look things up, then answer",
            // Yao et al., arXiv 2210.03629, 6 Oct 2022. Dated to the PREPRINT;
            // anyone citing the conference will say ICLR 2023 instead.
            // Source: arXiv:2210.03629.
            "ReAct, October 2022: Shunyu Yao had models think, act, then think again",
            // Still true of every embedding model there is, now with a date to
            // hold. "Made them famous", not invented — vector word
            // representations predate word2vec by decades.
            // Source: Mikolov et al., arXiv:1301.3781, 16 Jan 2013.
            "Embeddings turn text into numbers — word2vec made them famous in 2013 🧠",
            // Willison proposed the name on 12 Sept 2022, crediting Goodside's
            // demonstrations and drawing the SQL parallel himself. It is now
            // OWASP's LLM01. The analogy carries "this is security, not a
            // typo" better than asserting it did.
            // Source: simonwillison.net, 12 Sept 2022; OWASP LLM01:2025.
            "Simon Willison named prompt injection in 2022, after SQL injection",
            // 🔎 REPLACED, not reworded. "Evals tell a better prompt from a
            // lucky one" is a maxim — true enough, but nothing authoritative
            // says it and "a lucky one" is exactly the hanging phrase this
            // round exists to remove. The event next door is dated and real.
            // Source: OpenAI, GPT-4 research post, 14 Mar 2023.
            "OpenAI shipped Evals with GPT-4 in March 2023 so anyone could benchmark",
            // The distinction that survives every generation of model, with
            // verbs that carry it: fine-tuning updates parameters, prompting
            // leaves the model frozen.
            // Source: arXiv:2005.14165 abstract.
            "Fine-tuning rewrites the weights; prompting leaves them untouched",
            // Definitional: argmax at every step. Adds the consequence — no
            // sampling, so no randomness — without adding a claim.
            // Source: Hugging Face, "How to generate text".
            "Greedy decoding takes the likeliest next token, never rolling dice",
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
        // ────────────────────────────────────────────────────────────────────
        // MARK: 🎧  VIBE CODING
        // ────────────────────────────────────────────────────────────────────
        case .vibeCoding: [
            // Karpathy's X post, 2 February 2025. The coinage is uncontested;
            // the day and the form are what the old line left out.
            // Source: x.com/karpathy/status/1886192184808149383.
            "Andrej Karpathy coined 'vibe coding' in a tweet on 2 February 2025 ⚡",
            // Attributed on purpose, and now QUOTED rather than paraphrased.
            // The DICTIONARY sense (Collins, Merriam-Webster) is just prompting
            // an AI in natural language and does not require skipping the read;
            // not-reading is the coiner's stricter original sense, and it
            // survives only with his name on it. His words, verbatim.
            // Source: the same 2 Feb 2025 post.
            "Karpathy's own rule: 'I Accept All always, I don't read the diffs'",
            // Announced 6 November 2025. Runners-up included clanker,
            // broligarchy and taskmasking. The date turns a claim into a
            // citation.
            // Source: Collins Dictionary, Word of the Year 2025 announcement.
            "Collins named 'vibe coding' word of the year on 6 November 2025 📖",
            // Fixed history, anchored. Karpathy later called it "a shower of
            // thoughts throwaway tweet that I just fired off" — "a post, not a
            // paper" asked the listener to supply the context themselves.
            // Source: Karpathy's own retrospective post.
            "It began as one throwaway tweet in February 2025, not a paper or a spec",
            // "Called", not "coined": Software 2.0 went up on Medium on 11
            // November 2017, and nothing establishes he was first to say the
            // words — it is a generic version-number phrase. The claim is the
            // ESSAY's, which the old line never stated.
            // Source: karpathy.medium.com/software-2-0-a64152b37c35.
            "Karpathy called neural nets 'Software 2.0' in a 2017 essay, pre-ChatGPT",
            // 🔎 Was "names a workflow, not a language" — a correction of an
            // error nobody was making, defining by negation. Collins' own
            // published definition says what it IS, and is quotable.
            // Source: Collins Dictionary, Word of the Year 2025.
            "Collins defines it as using AI, prompted in plain English, to write code",
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
