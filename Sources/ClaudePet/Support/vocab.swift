import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  CLAW'D'S VOCABULARY
//
//  Everything he says lives in this one file. Edit the arrays below, rebuild
//  with ./run.sh, and he says your words instead.
//
//  Two things you can add:
//    1. LINES     — what he says in each state.             (`lines(for:)`)
//    2. RULES     — what he says when the task matches a
//                   pattern, e.g. anything about tests.     (`rules`)
//
//  WHAT WINS, when several could apply:
//
//    1. A RULE matching the current task    → "Committing the good stuff 📦"
//    2. The REAL TASK TEXT, whenever there is one
//    3. This state's LINES
//
//  Point 2 is deliberate and is the reason `working` and `cooking` lines seem
//  not to fire: while Claude is actually running something, the bubble shows
//  what it is running. A pet that hides "Running the test suite" behind a joke
//  is a worse pet. Your lines for those states fill the gaps BETWEEN tools.
//
//  Adding a whole new occasion? Add a `case` to ShoutoutOccasion and the
//  compiler will refuse to build until you give it lines — the switch below is
//  exhaustive on purpose, so a half-added occasion cannot ship silently.
//
//  Keep lines SHORT — about 29 characters. That is not a style preference, it
//  is where the bubble actually cuts off: it caps at 210pt with 8pt of padding
//  each side, and the font advances 6.62pt per character, so 194 / 6.62 ≈ 29.
//  Emoji are welcome but count roughly double, since they render about twice
//  as wide as a monospaced character.
//
//  Five lines that shipped before this was measured are longer than that and
//  are cut off on screen. They are listed in `PersonalityTests` and left as
//  written — they are the operator's words, not the renderer's business.
// ─────────────────────────────────────────────────────────────────────────────

/// When Claw'd has something to say. One per state, so any of them can carry
/// your words.
public enum ShoutoutOccasion: String, Sendable, CaseIterable {
    /// 💬 Sessions are live but Claude is between tasks.
    case idle
    /// 💭 Claude is reasoning — no tool running.
    case thinking
    /// ⚙️ A tool is in flight. Shown only in the gaps; the task text wins.
    case working
    /// 🔥 Going hard — rapid tool calls, or a fan-out of subagents.
    case cooking
    /// 👀 A plan is written and waiting for you to approve it.
    case planReady
    /// ✅ A session just finished its turn.
    case finished
    /// ‼️ A session is blocked on you — usually a permission prompt.
    case needsYou
    /// 😴 Nothing is running at all.
    case sleeping
    /// 🐛 The operator clicked the visiting floor bug and he pounced on it.
    case bugCaught
    /// 🛹 He just landed a kickflip.
    case kickflip
    /// 🛹✨ The 1-in-20 golden board just landed. Reserved lines — these are
    /// the jackpot, and the jackpot must not sound like an ordinary Tuesday.
    case goldenSkate
    /// 💛 Ten seconds of petting, held — the crescendo thank-you.
    case longPet
    /// 👋 The very first launch, ever. He introduces himself.
    case hello
}

/// A line he says when the current task matches a pattern.
///
/// Rules beat the generic lines, so `git commit …` can get a commit joke while
/// everything else falls back to the usual encouragement.
public struct VocabRule: Sendable {
    /// Case-insensitive regular expression matched against the current task or
    /// tool description.
    public let pattern: String
    /// Lines to choose from when it matches.
    public let lines: [String]

    public init(_ pattern: String, _ lines: [String]) {
        self.pattern = pattern
        self.lines = lines
    }
}

/// Claw'd's lines.
///
/// Data, not logic — the only behaviour here is picking one.
public enum Vocab {

    // ═════════════════════════════════════════════════════════════════════════
    //  ✏️  EDIT FROM HERE
    // ═════════════════════════════════════════════════════════════════════════

    /// What he says for each occasion.
    ///
    /// A switch rather than a dictionary: adding a case to `ShoutoutOccasion`
    /// makes this stop compiling until you write its lines, which is exactly the
    /// reminder you want. A dictionary would just return nil at runtime and he
    /// would silently say nothing.
    public static func lines(for occasion: ShoutoutOccasion) -> [String] {
        switch occasion {

        // 🛹 He just landed a trick. Dealt from a cursor like the pounce is, so
        // the same one never lands twice running.
        //
        // The Hall of Meat line is 31 columns and does not fit the plain
        // bubble. It is not shortened and it is not in `knownLong`: the
        // transient bubble routes by length now, so it scrolls, and it finishes
        // scrolling well inside the window it is shown for.
        // `skateLinesFitTheirWindow` pins that.
        case .kickflip: [
            "Kowbunga 🤙!",
            "Do a Kickflip 🛹!",
            "See you at the Hall of Meat 🍖!",
            "Tony Clawd 900 🦅",
            "Sponsor me 🛹",
            "Nollie! Nose first 🛹",
        ]

        // 🛹✨ The golden board — one skate beat in twenty. The lines are
        // reserved: dealing them on an ordinary trick would spend the jackpot.
        case .goldenSkate: [
            "GOLD BOARD. No notes 🏆",
            "The 1-in-20 ride ✨🛹",
            "Midas grip tape today",
        ]

        // 💛 Ten unbroken seconds of petting. He noticed.
        case .longPet: [
            "Best. Human. Ever 💛",
            "Ten whole seconds 🥹",
            "Okay YOU get a raise",
        ]

        // 👋 The first launch, ever — the one moment a new arrival has no idea
        // what the thing on their desktop is. So every line NAMES him; a
        // friendly noise that does not introduce him wastes the only
        // introduction he gets.
        //
        // Kept comfortably under the ceiling rather than near it. These render
        // beside a wave on a first impression, and an emoji costs about two
        // columns, so there is no room here for the one-over that `knownLong`
        // forgives elsewhere.
        case .hello: [
            "Hi, I'm Claw'd 🦀",
            "👋 Hey, I'm Claw'd",
            "Oh! Hi — I'm Claw'd 🦀",
            "Hi — I'm your crab 🦀",
        ]

        // 💬 Between tasks. Encouragement, mostly.
        case .idle: [
            "Let's build something awesome!",
            "Now we're cooking with crisco 🍳",
            "Hope you're ready to build",
            "I'm hungry for something new!",
            "Excited to see what you cook up",
            "Ooo that's a spicy idea 🌶️",
            "What are we making?",
            "Mise en place, chef",
            "Give me something hard",
            "Say the word",
            "Burner's on",
        ]

        // 💭 Reasoning. Usually shown as pulsing dots instead, so these are rare.
        case .thinking: [
            "Thinking it through",
            "Give me a second",
            "Working out the shape of it",
            "Turning it over",
            "Not there yet",
            "Let me sit with this",
        ]

        // ⚙️ A tool is running. The task text wins whenever there is one, so
        // these fill the gaps rather than replacing anything useful.
        case .working: [
            "On it",
            "Making progress",
            "This is the fun part",
            "Still here",
            "Steady claws",
        ]

        // 🔥 Really going. Same rule — the task text wins when there is one.
        case .cooking: [
            "🔥",
            "Absolutely cooking 🔥",
            "Do not disturb",
            "Full send",
            "In the zone",
            "Both claws in",
            "Every burner going",
        ]

        // ✅ A turn just finished.
        case .finished: [
            "✅ 🥳 🎉",
            "Nailed it",
            "That's a wrap 🎬",
            "Shipped it!",
            "Chef's kiss",
            "Another one done",
            "Order up 🔔",
            "Plated and out",
            "Done and dusted",
            "That'll do",
        ]

        // 👀 A plan is up and he wants your verdict.
        case .planReady: [
            "Plan's ready 👀",
            "Take a look?",
            "Shall we?",
            "Waiting on your call",
            "Ready when you are",
            "Menu's up",
            "Your move",
        ]

        // ‼️ Claude is blocked on you.
        case .needsYou: [
            "Psst — I need you",
            "One quick question",
            "Waiting on you!",
            "Need a hand over here",
            "Stuck without a yes",
        ]

        // 😴 Nothing running. Shown occasionally, not on every frame — a
        // sleeping pet that talks constantly is not asleep.
        case .sleeping: [
            "zzz…",
            "Wake me when it matters",
            "Resting my claws",
            "Off the clock",
            "Burners are cold",
        ]

        // 🐛 He caught the bug. The oldest joke in the trade, four ways.
        case .bugCaught: [
            "Bug fixed 🐛✅",
            "Zero known issues",
            "It was a race condition",
            "Closed as completed",
            "Off-by-one, obviously",
            "Delicious 😋",
        ]
        }
    }

    /// Custom sentences for particular kinds of work.
    ///
    /// The first rule whose pattern matches the current task wins, so put the
    /// specific ones first. Patterns are case-insensitive regular expressions.
    /// An invalid pattern is skipped rather than crashing — a typo in your
    /// vocabulary should never take the pet down.
    public static let rules: [VocabRule] = [
        VocabRule(#"\btest(s|ing)?\b"#, [
            "Writing tests, the good kind 🧪",
            "Red, green, refactor",
            "Proving it works",
            "Red before green",
        ]),
        VocabRule(#"\b(commit|git)\b"#, [
            "Committing the good stuff 📦",
            "Writing a message you'll thank me for",
            "Sealing the jar",
            "Stamping it",
        ]),
        VocabRule(#"\b(fix|bug|debug)\b"#, [
            "On the hunt 🔍",
            "Found something suspicious",
            "Squashing it",
            "Following the smell",
            "It's always the cache",
        ]),
        VocabRule(#"\b(README|docs?|document)\b"#, [
            "Writing it down 📝",
            "Docs are a feature",
            "Explaining the why",
            "Words about the words",
        ]),

        // A build is running.
        // `build\w*` rather than an alternation of forms: the first draft listed
        // build|building|rebuild and silently missed "builds" and "rebuilding".
        VocabRule(#"\b(build\w*|rebuild\w*|compil\w*)\b"#, [
            "Warming up the oven",
            "Cross your claws",
            "Turning the crank",
        ]),

        // Pulling dependencies.
        // Bare `npm`/`yarn` are deliberately absent so `npm run build` reaches
        // the build rule above rather than being claimed here.
        VocabRule(#"\b(install\w*|dependenc\w+|node_modules|package-lock)\b"#, [
            "Fetching the ingredients",
            "Downloading the internet",
            "Groceries 🛒",
        ]),

        // A formatter or a type check.
        // `prettier` was dropped from this list: it matched "Make the header
        // prettier", which is not a formatter run.
        VocabRule(#"\b(lint\w*|eslint|swiftlint|swiftformat|gofmt|typecheck|tsc)\b"#, [
            "Making it pretty",
            "Two spaces or four",
            "The robot has opinions",
            "Whitespace patrol",
        ]),

        // Moving code without changing it.
        // `extract\w*` was dropped: it matched "Extract frames from the wink
        // GIF", which is this repo's own media work and not a refactor.
        VocabRule(#"\b(refactor\w*|renam\w*|tidy\w*|clean ?up)\b"#, [
            "Moving furniture",
            "Same dish, better recipe",
            "Same behaviour, new shape",
            "Rewiring, carefully",
        ]),

        // Making it faster.
        // `profiling|profiler`, not `profil\w+`, which matched "Add a user
        // profile page".
        VocabRule(#"\b(perf|performance|benchmark\w*|profiling|profiler|optimi[sz]\w+)\b"#, [
            "Chasing milliseconds",
            "Measure, then cut",
            "Trimming the fat",
        ]),

        // Reading a change.
        // Bare `PR` was dropped: the matcher is case-insensitive, so it fired on
        // any stray "pr".
        VocabRule(#"\b(review\w*|pull request|diff)\b"#, [
            "Reading it twice",
            "Nitpicking, professionally",
            "Looking for sharp edges",
        ]),

        // Searching the tree.
        // Deliberately narrow. `search\w*` matched "Add search to the sidebar" —
        // feature work, not searching — and for a real search the pattern IS
        // the most interesting thing on screen, so this hides as little as it can.
        VocabRule(#"\b(grep|rg|ripgrep)\b"#, [
            "Somewhere in here",
            "Pulling the thread",
            "Combing through",
        ]),
    ]

    // ═════════════════════════════════════════════════════════════════════════
    //  ⚙️  SELECTION LOGIC — you should not need to touch anything below here.
    // ═════════════════════════════════════════════════════════════════════════

    /// Every occasion and its lines, for tests and tooling.
    public static var catalogue: [ShoutoutOccasion: [String]] {
        Dictionary(uniqueKeysWithValues: ShoutoutOccasion.allCases.map { ($0, lines(for: $0)) })
    }

    /// The first rule matching `task`, if any.
    public static func rule(matching task: String) -> VocabRule? {
        rules.first { rule in
            // `NSRegularExpression` throws on a bad pattern; a typo in someone's
            // vocabulary should skip that rule, not crash the pet.
            guard let regex = try? NSRegularExpression(pattern: rule.pattern,
                                                       options: [.caseInsensitive])
            else { return false }
            let range = NSRange(task.startIndex..<task.endIndex, in: task)
            return regex.firstMatch(in: task, range: range) != nil
        }
    }

    /// Picks a line for `occasion`, optionally letting a rule override it.
    ///
    /// - Parameters:
    ///   - task: the current task text. If it matches a rule, that rule's lines
    ///     are used instead of the occasion's.
    ///   - seed: chooses the line. Seeded rather than random because the bubble
    ///     is recomputed on a timer — `Bool.random()` here would re-roll the text
    ///     out from under the reader mid-sentence.
    /// - Returns: `nil` only if there is nothing at all to say.
    public static func line(for occasion: ShoutoutOccasion,
                            matching task: String? = nil,
                            seed: Int) -> String? {
        let pool = task.flatMap { rule(matching: $0) }?.lines ?? lines(for: occasion)
        return pick(from: pool, seed: seed)
    }

    /// Walks the pool in a shuffled order, using every line before any repeats.
    ///
    /// A plain "random index" can show line 3 four times in five turns and never
    /// show line 5 at all. This deals the pool like a deck: `seed / count`
    /// selects which shuffle, `seed % count` the position in it — so consecutive
    /// seeds walk one shuffled pass, then reshuffle. Deterministic, so the
    /// bubble never rewrites itself between two renders of the same moment.
    static func pick(from pool: [String], seed: Int) -> String? {
        guard !pool.isEmpty else { return nil }
        guard pool.count > 1 else { return pool[0] }

        let safe = seed & Int.max
        // Two lines can only alternate; shuffling them is theatre, and the
        // join-fixing below cannot help when swapping also moves the last card.
        guard pool.count > 2 else { return pool[safe % 2] }

        return deck(pool, pass: safe / pool.count)[safe % pool.count]
    }

    /// The shuffled order for one pass.
    ///
    /// Shuffling alone still allows a repeat *at the join*: the last line of one
    /// pass and the first of the next are independently chosen and can match.
    /// If they would, the new pass swaps its first two entries — which for three
    /// or more lines cannot disturb its own last entry, so the fix never cascades
    /// into the following join.
    static func deck(_ pool: [String], pass: Int) -> [String] {
        var deck = shuffled(pool, seed: pass)
        guard pass > 0 else { return deck }
        if deck.first == shuffled(pool, seed: pass - 1).last { deck.swapAt(0, 1) }
        return deck
    }

    /// A deterministic Fisher-Yates shuffle. Same seed, same order, always.
    static func shuffled(_ pool: [String], seed: Int) -> [String] {
        var result = pool
        var state = UInt64(truncatingIfNeeded: seed) &+ 0x9E37_79B9_7F4A_7C15
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            // splitmix64: one input bit changes half the output bits, so
            // neighbouring seeds produce genuinely different orders.
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            result.swapAt(index, Int(z % UInt64(index + 1)))
        }
        return result
    }

    /// 🎭 What he shouts IN CHARACTER after a trick.
    ///
    /// A costume that only changes his colours is a paint job; one that
    /// changes what he says is a character. These are per-wardrobe skate
    /// decks, dealt instead of the plain one whenever he lands a trick in
    /// costume, and empty for the looks that are a palette rather than a
    /// personality — those fall back to his own voice rather than being
    /// given a forced catchphrase, because a weak line in character is
    /// worse than a good line out of it.
    ///
    /// Kept inside the plain bubble's width on purpose: these arrive on the
    /// same 3.4-second landing window the ordinary skate lines do, and
    /// `skateLinesFitTheirWindow` measures them with the rest.
    nonisolated static func skateLines(for costume: Costume) -> [String] {
        switch costume {
        case .sonic:        ["Gotta go fast 💨", "Rings everywhere 💍", "Too slow 😎"]
        case .gundam:       ["Systems nominal 🤖", "Target locked 🎯", "Full burn 🚀"]
        case .ninja:        ["You saw nothing 🥷", "Silent landing 🌑", "Smoke bomb next 💨"]
        case .tiger:        ["Claws out 🐾", "Apex predator 🛹", "Nine lives, one board"]
        case .frankenstein: ["IT'S ALIVE ⚡", "Bolts holding 🔩", "Reanimated that one"]
        case .arcade:       ["HIGH SCORE 🕹", "Insert coin 🪙", "Player one landed"]
        case .matrix:       ["There is no board 🕶", "git commit -m 'landed'", "Follow the rabbit 💻"]
        case .retroBlack:   ["Matte finish 🖤", "All black everything", "Stealth mode 🛹"]
        case .skater:       ["That's a make ✅", "Filmer got it 🎥", "Run it back 🛹"]
        case .santa:        ["Ho ho holy 🎅", "Sleigh it 🛷", "On the nice list 🎁"]
        case .pumpkin:      ["Spooky sponsored 🎃", "Gourd landing 🎃"]
        case .turkey:       ["Gobble that ledge 🦃", "Fully basted 🦃"]
        case .white:        ["Snowboard? Skateboard ❄️", "Cold landing ❄️"]
        case .none:         []
        }
    }
}


/// A draw counter for the deck.
///
/// `Vocab.pick` deals a shuffled pass and guarantees two things — no line twice
/// in a row, and every line used before any repeats — but **only while its seed
/// advances by exactly one per draw**. Every caller in the app fed it something
/// else: wall-clock seconds, a fourteen-second tick sampled through a dice gate,
/// a burst index that skips numbers. So the guarantee held in the unit test and
/// nowhere on screen. Measured on the shipped code, the immediate-repeat rate
/// was 10.4% on the idle path and 33.4% on working bursts, against a deck that
/// promises zero — and 97.4% of any six consecutive idle draws contained a
/// duplicate. The operator noticed before the tests did.
///
/// This is the thing to hand `pick` instead. `pick` itself is unchanged and
/// still pure.
///
/// `token` names the **utterance** rather than the moment. While it is
/// unchanged the same line comes back — one burst says one thing, rather than
/// rewriting itself mid-read when the fourteen-second seed rolls over — and the
/// instant it changes the cursor steps forward by exactly one.
public struct LineCursor: Sendable {
    private struct Draw { var token: String; var seed: Int }
    private var draws: [String: Draw] = [:]
    /// Per-pet offset, so two pets never walk the same pass in lockstep. An
    /// offset and not a multiplier, because the step of one IS the invariant.
    private let salt: Int

    public init(salt: Int = 0) { self.salt = salt }

    /// The line for `pool`, held while `token` holds.
    ///
    /// Keyed per pool, which is load-bearing: one shared counter would break
    /// the moment he alternates between two moods, because consecutive draws
    /// from either pool would then skip.
    public mutating func next(_ pool: [String], id: String, token: String) -> String? {
        if draws[id]?.token != token {
            draws[id] = Draw(token: token, seed: (draws[id]?.seed ?? salt) &+ 1)
        }
        return Vocab.pick(from: pool, seed: draws[id]?.seed ?? salt)
    }

    /// The line for a pool where every call is a new utterance — a banner
    /// posted, a bug pounced on. No token to hold on to.
    public mutating func advance(_ pool: [String], id: String) -> String? {
        let seed = (draws[id]?.seed ?? salt) &+ 1
        draws[id] = Draw(token: "", seed: seed)
        return Vocab.pick(from: pool, seed: seed)
    }

    /// `Vocab.line(for:matching:)`, dealt from a cursor.
    ///
    /// A matched rule gets its OWN cursor id: two pools interleaved through one
    /// counter would steal each other's seeds, which is this same bug one level
    /// up.
    public mutating func line(for occasion: ShoutoutOccasion,
                              matching task: String? = nil,
                              token: String) -> String? {
        let rule = task.flatMap { Vocab.rule(matching: $0) }
        return next(rule?.lines ?? Vocab.lines(for: occasion),
                    id: rule.map { "rule:\($0.pattern)" } ?? "occasion:\(occasion.rawValue)",
                    token: token)
    }


}
