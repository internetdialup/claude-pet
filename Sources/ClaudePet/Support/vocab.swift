import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  CLAW'D'S VOCABULARY
//
//  Everything he says lives in this one file. Edit the arrays below, rebuild
//  with ./run.sh, and he says your words instead.
//
//  Two things you can add:
//    1. LINES     — what he says for each occasion.        (`lines(for:)`)
//    2. RULES     — what he says when the task matches a
//                   pattern, e.g. anything about tests.    (`rules`)
//
//  Adding a whole new occasion? Add a `case` to ShoutoutOccasion and the
//  compiler will refuse to build until you give it lines — the switch below is
//  exhaustive on purpose, so a half-added occasion cannot ship silently.
//
//  Keep lines SHORT. The bubble truncates past roughly 46 characters, and a
//  line that gets cut off reads worse than a shorter one. Emoji are welcome.
// ─────────────────────────────────────────────────────────────────────────────

/// When Claw'd has something to say.
public enum ShoutoutOccasion: String, Sendable, CaseIterable {
    /// 💬 Sessions are live but Claude is between tasks.
    case idle
    /// ✅ A session just finished its turn.
    case finished
    /// 👀 A plan is written and waiting for you to approve it.
    case planReady
    /// ‼️ A session is blocked on you — usually a permission prompt.
    case needsYou
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

        // 💬 Between tasks. Encouragement, mostly.
        case .idle: [
            "Let's build something awesome!",
            "Now we're cooking with crisco 🍳",
            "Hope you're ready to build",
            "I'm hungry for something new!",
            "Excited to see what you cook up",
            "Ooo that's a spicy idea 🌶️",
        ]

        // ✅ A turn just finished.
        case .finished: [
            "Nailed it",
            "That's a wrap 🎬",
            "Shipped it!",
            "Chef's kiss",
            "Another one done",
        ]

        // 👀 A plan is up and he wants your verdict.
        case .planReady: [
            "Plan's ready 👀",
            "Take a look?",
            "Shall we?",
            "Waiting on your call",
            "Ready when you are",
        ]

        // ‼️ Claude is blocked on you.
        case .needsYou: [
            "Psst — I need you",
            "One quick question",
            "Waiting on you!",
            "Need a hand over here",
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
        ]),
        VocabRule(#"\b(commit|git)\b"#, [
            "Committing the good stuff 📦",
            "Writing a message you'll thank me for",
        ]),
        VocabRule(#"\b(fix|bug|debug)\b"#, [
            "On the hunt 🔍",
            "Found something suspicious",
            "Squashing it",
        ]),
        VocabRule(#"\b(README|docs?|document)\b"#, [
            "Writing it down 📝",
            "Docs are a feature",
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
}
