import Foundation

/// What the crab is doing right now. Derived from `ActivityEvent`s by `ActivityCoordinator`.
///
/// State layer: `Foundation` only, no SwiftUI — the Model layer never imports UI.
public enum PetMood: String, Sendable, Codable, CaseIterable {
    /// A live session exists but Claude is not acting — waiting on the human.
    case idle
    /// Claude is reasoning: `thinking` blocks, no tool in flight.
    case thinking
    /// A tool call is in flight.
    case working
    /// Claude is going hard: rapid tool calls, or a fan-out of live subagents.
    case cooking
    /// A plan is written and Claude is blocked waiting for the human to approve.
    case nudging
    /// Claude finished a turn recently. Transient; decays back to `idle`.
    case done
    /// A permission prompt or notification needs the human. Sticky until cleared.
    case needsAttention
    /// No live sessions at all.
    case sleeping

    /// Higher wins when several sessions compete for the crab's face.
    var urgency: Int {
        switch self {
        case .sleeping: 0
        case .idle: 1
        case .done: 2
        case .thinking: 3
        case .working: 4
        case .cooking: 5
        // Waiting on the human, but politely — it outranks work because nothing
        // is progressing until you look, and sits under the hard block of a
        // permission prompt.
        case .nudging: 6
        case .needsAttention: 7
        }
    }
}

/// The complete render input for the pet. One value, rebuilt on every change.
/// How often a mood is allowed to *say* what it is, as opposed to *be* it.
///
/// The pose is continuous; the bubble is episodic. A pet whose banner never
/// goes out stops being read at all — the eye files it as furniture and skips
/// it, which is the opposite of what a thought bubble is for.
public struct BubbleCadence: Sendable, Equatable {
    /// One burst plus the quiet after it.
    public var period: TimeInterval
    /// How long a burst that fires holds the bubble up.
    public var dwell: TimeInterval
    /// Fraction of scheduled cycles that speak at all. 1.0 is a metronome —
    /// a heartbeat that never skips, for the states that exist to get you.
    /// Below 1.0 his silences stop being predictable, which is the difference
    /// between a machine and a pet.
    public var chance: Double
    /// How long the bubble holds when the words themselves are NEW.
    /// Deterministic and dice-free: news is not something to roll for.
    public var newsDwell: TimeInterval
    /// Refractory period. New text arriving inside this window updates the
    /// words without restarting the burst — without it a cooking sprint, whose
    /// label churns every couple of seconds, re-arms the news timer forever
    /// and the bubble is exactly as permanent as it was before.
    public var newsRefractory: TimeInterval

    public init(period: TimeInterval, dwell: TimeInterval, chance: Double,
                newsDwell: TimeInterval, newsRefractory: TimeInterval) {
        self.period = period
        self.dwell = dwell
        self.chance = chance
        self.newsDwell = newsDwell
        self.newsRefractory = newsRefractory
    }
}

public struct PetState: Sendable, Equatable {
    public var mood: PetMood
    /// Text for the thought bubble. `nil` hides the bubble entirely.
    public var bubble: String?
    /// What he would say right now, whether or not the cadence has him
    /// speaking. The menu-bar tooltip reads this, so going quiet never hides
    /// the live task from someone who goes looking: **the cadence decides when
    /// he speaks, never what is known.**
    public var bubbleContent: String?
    /// Tool name when `mood == .working` — drives the glyph in the bubble.
    public var tool: String?
    /// Every live session, most-recently-active first.
    public var sessions: [ClaudeSession]
    /// The session the crab is currently mirroring.
    public var focusedSessionID: String?
    /// Number of sessions in `.needsAttention`, for the roster badge.
    public var attentionCount: Int
    /// How the bubble presents its contents.
    public var bubbleStyle: BubbleStyle = .plain
    /// Whether the bubble is his VOICE (mood colours) or his KNOWLEDGE — the
    /// facts and tips, which wear a white/near-black card that follows the
    /// system appearance instead of the mood palette. The split is semantic:
    /// what he feels stays in colour, what he knows reads like a note.
    public var bubbleTone: BubbleTone = .mood
    public enum BubbleTone: Sendable, Equatable { case mood, knowledge }
    /// How many facts he has muttered in his sleep this session — the 🐑 tally
    /// the roster shows once it is off zero. A joke, not a metric: it does not
    /// survive a restart.
    public var sleepTalkCount: Int = 0
    /// The focused session's todo completion, 0…1, quantised to 0.05 steps so
    /// the equality-gated publish does not churn on every re-read. Only set
    /// when the list is substantial enough to mean something (3+ tasks).
    public var taskFraction: Double?
    /// A `.cooking` sprint just landed — the done state plays its extended
    /// payoff instead of the plain hop.
    public var celebrating: Bool = false
    /// …and it had been cooking a while: the payoff is the full finale.
    public var epicCelebration: Bool = false
    /// The focused session's completion marker: drives the foot badge for
    /// five minutes after a turn lands, and the reminder nudges inside that
    /// window. Written once per completion, so the equality-gated publish
    /// does not churn.
    public var completedAt: Date? = nil
    /// The service the focused sprint is talking to — the npm cube, GitHub
    /// mark, Linear diamond or deploy rocket, floating beside him and
    /// badging the bubble. Display state, not an alert.
    public var serviceGlyph: ServiceGlyph? = nil

    public enum BubbleStyle: Sendable, Equatable {
        /// Text, truncated if long. The default for task descriptions.
        case plain
        /// Text scrolling as a ticker. Status read-outs (model, usage).
        case marquee
        /// No words at all — three pulsing dots. Used while Claude is
        /// reasoning, where a label would just be noise.
        case dots
    }

    public static let sleeping = PetState(
        mood: .sleeping, bubble: nil, tool: nil,
        sessions: [], focusedSessionID: nil, attentionCount: 0
    )

    public var focusedSession: ClaudeSession? {
        guard let id = focusedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }
}
