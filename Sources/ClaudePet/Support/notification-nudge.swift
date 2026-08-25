import Foundation

// ─────────────────────────────────────────────────────────────────────────────
//  WHAT THE NOTIFICATIONS SAY
//
//  The macOS banners, as opposed to `vocab.swift` which is the speech bubble on
//  his head. Same shape: an exhaustive switch returning lines, so learning one
//  file teaches the other, and adding an event fails the build until it has copy.
//
//  Banners are interruptions. Keep titles under about 40 characters and bodies
//  under about 80 — macOS truncates, and a truncated banner is worse than a
//  terse one. The session name is appended automatically, so do not repeat it.
// ─────────────────────────────────────────────────────────────────────────────

/// The moments worth interrupting someone for.
public enum NudgeEvent: String, Sendable, CaseIterable {
    /// ✅ A session finished its turn.
    case finished
    /// ‼️ A session is blocked — usually a permission prompt.
    case needsYou
    /// 👀 A plan is written and waiting on approval.
    case planReady
    /// 🔥 A session started really going. Off by default — this fires often.
    case cooking
}

/// Banner copy.
public enum NotificationNudge {

    // ═════════════════════════════════════════════════════════════════════════
    //  ✏️  EDIT FROM HERE
    // ═════════════════════════════════════════════════════════════════════════

    /// The bold first line.
    public static func titles(for event: NudgeEvent) -> [String] {
        switch event {

        // ✅ Work finished.
        case .finished: [
            "Done ✅",
            "That's a wrap 🎬",
            "Finished",
        ]

        // ‼️ Blocked on you.
        case .needsYou: [
            "Claw'd needs you ‼️",
            "Waiting on you",
            "One quick thing",
        ]

        // 👀 A plan wants a verdict.
        case .planReady: [
            "Plan's ready 👀",
            "Ready for your call",
        ]

        // 🔥 Going hard.
        case .cooking: [
            "Cooking 🔥",
            "Full send",
        ]
        }
    }

    /// The smaller second line. The session name is appended after this.
    public static func bodies(for event: NudgeEvent) -> [String] {
        switch event {

        case .finished: [
            "Your turn.",
            "Come see what changed.",
        ]

        case .needsYou: [
            "Claude is waiting on a response.",
            "Nothing moves until you look.",
        ]

        case .planReady: [
            "A plan is waiting for approval.",
            "Take a look when you can.",
        ]

        case .cooking: [
            "Tools are flying.",
            "Deep in it right now.",
        ]
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    //  ⚙️  Below here is selection. You should not need to touch it.
    // ═════════════════════════════════════════════════════════════════════════

    /// The next title and body for `event`, each dealt from its OWN counter.
    ///
    /// Separate cursors is the whole point. `copy(for:seed:)` below hands one
    /// seed to both pools, so for the two-line pools it resolved both to the
    /// same index and welded `"Plan's ready 👀"` permanently to
    /// `"A plan is waiting for approval."` — two titles and two bodies
    /// producing exactly one possible banner, forever. Drawing them
    /// independently lets them recombine.
    @MainActor private static var cursor = LineCursor()

    @MainActor
    public static func nextCopy(for event: NudgeEvent) -> (title: String, body: String) {
        (cursor.advance(titles(for: event), id: "title:\(event.rawValue)") ?? event.rawValue,
         cursor.advance(bodies(for: event), id: "body:\(event.rawValue)") ?? "")
    }

    /// A title and body for `event` at a given seed. Kept for the tests, which
    /// need a pure function; the app uses `nextCopy(for:)`.
    public static func copy(for event: NudgeEvent, seed: Int) -> (title: String, body: String) {
        let title = Vocab.pick(from: titles(for: event), seed: seed) ?? event.rawValue
        let body = Vocab.pick(from: bodies(for: event), seed: seed) ?? ""
        return (title, body)
    }

    /// The event a mood should announce, if any. Moods not listed here are not
    /// worth interrupting someone for.
    public static func event(for mood: PetMood) -> NudgeEvent? {
        switch mood {
        case .done: .finished
        case .needsAttention: .needsYou
        case .nudging: .planReady
        case .cooking: .cooking
        default: nil
        }
    }
}
