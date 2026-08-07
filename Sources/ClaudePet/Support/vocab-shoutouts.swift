import Foundation

/// When Claw'd has something to say.
public enum ShoutoutOccasion: String, Sendable, CaseIterable {
    /// Sessions are live but Claude is not working — Claw'd cheers you on.
    case idle
    /// A session just finished its turn.
    case finished
    /// A session is blocked on the human.
    case needsYou
    /// A plan is written and waiting for the human to approve it.
    case planReady
}

/// Claw'd's vocabulary.
///
/// A keyed catalogue rather than a flat array, so a new occasion is a new key
/// rather than a new call site. Lines are data, not logic — this file holds no
/// behaviour beyond picking one.
///
/// Note on the filename: `development/swift-development.md` §1.3 names files
/// after the type they declare. Data catalogues are the documented exception to
/// that rule, added when this file was.
public enum VocabShoutouts {

    public static let catalogue: [ShoutoutOccasion: [String]] = [
        .idle: [
            "Let's build something awesome!",
            "Now we're cooking with crisco 🍳",
            "Hope you're ready to build",
            "I'm hungry for something new!",
            "Excited to see what you cook up",
            "Ooo that's a spicy idea 🌶️",
        ],
        .finished: [
            "Nailed it",
            "That's a wrap 🎬",
            "Shipped it!",
            "Chef's kiss",
            "Another one done",
        ],
        .planReady: [
            "Plan's ready 👀",
            "Take a look?",
            "Shall we?",
            "Waiting on your call",
            "Ready when you are",
        ],
        .needsYou: [
            "Psst — I need you",
            "One quick question",
            "Waiting on you!",
            "Need a hand over here",
        ],
    ]

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
        guard let lines = catalogue[occasion], !lines.isEmpty else { return nil }

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
