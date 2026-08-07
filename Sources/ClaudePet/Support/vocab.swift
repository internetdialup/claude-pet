import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  CLAW'D'S VOCABULARY
//
//  Everything he says lives in this one file. Edit the arrays below, rebuild
//  with ./run.sh, and he says your words instead.
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

/// Claw'd's lines.
///
/// Data, not logic — the only behaviour here is picking one.
public enum Vocab {

    /// ✏️  **THIS IS THE PART YOU EDIT.**
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

    // ─────────────────────────────────────────────────────────────────────────
    //  Below here is selection logic. You should not need to touch it.
    // ─────────────────────────────────────────────────────────────────────────

    /// Every occasion and its lines, for tests and tooling.
    public static var catalogue: [ShoutoutOccasion: [String]] {
        Dictionary(uniqueKeysWithValues: ShoutoutOccasion.allCases.map { ($0, lines(for: $0)) })
    }

    /// Picks a line for `occasion`.
    ///
    /// - Parameters:
    ///   - avoiding: the line currently on screen. Never returned again while
    ///     another option exists, so the bubble always visibly changes.
    ///   - seed: chooses the line. Seeded rather than random because the bubble
    ///     is recomputed on a timer — `Bool.random()` here would re-roll the text
    ///     out from under the reader mid-sentence.
    /// - Returns: `nil` only if the occasion has no lines at all.
    public static func line(for occasion: ShoutoutOccasion,
                            avoiding: String? = nil,
                            seed: Int) -> String? {
        let lines = lines(for: occasion)
        guard !lines.isEmpty else { return nil }

        // Index into the whole list, then step past a collision. Filtering the
        // avoided line out first shortens the array, and a sequential seed
        // modulo the shortened count could never land on one of the entries —
        // one line was permanently unreachable.
        // `abs` on Int.min traps, so mask off the sign bit instead of negating.
        let index = (seed & Int.max) % lines.count
        let choice = lines[index]
        guard choice == avoiding, lines.count > 1 else { return choice }
        return lines[(index + 1) % lines.count]
    }
}
