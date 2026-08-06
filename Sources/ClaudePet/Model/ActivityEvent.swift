import Foundation

/// A single observation about a session. Every feed emits these; `ActivityCoordinator`
/// is the only thing that folds them into `PetState`.
public struct ActivityEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Claude produced a `thinking` block with no tool call.
        case thinking
        /// A tool call started. `detail` is `input.description` / `file_path` / `pattern`.
        case toolStarted(name: String, detail: String?)
        /// The matching `tool_result` arrived.
        case toolFinished(name: String)
        /// Turn ended (`stop_reason == "end_turn"`, or a `Stop` hook).
        case turnEnded
        /// A permission prompt or idle notification wants the human.
        case needsAttention(reason: String)
        /// The in-progress todo changed. `activeForm`, e.g. "Forking Bamboo doctrine".
        case activeTask(String?)
        /// Session title changed.
        case title(String)
        /// Subagent count changed.
        case subagents(Int)
        /// The model answering this session, e.g. `claude-opus-5`.
        case model(String)
        /// The session process went away.
        case ended
    }

    public var sessionID: String
    public var kind: Kind
    public var timestamp: Date

    public init(sessionID: String, kind: Kind, timestamp: Date = Date()) {
        self.sessionID = sessionID
        self.kind = kind
        self.timestamp = timestamp
    }
}
