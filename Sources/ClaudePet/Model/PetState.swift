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
public struct PetState: Sendable, Equatable {
    public var mood: PetMood
    /// Text for the thought bubble. `nil` hides the bubble entirely.
    public var bubble: String?
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
