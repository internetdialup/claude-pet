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
        /// The in-progress todo changed. `activeForm`, e.g. "Refactoring the parser".
        case activeTask(String?)
        /// The todo list's completion count moved, e.g. 4 of 5 done.
        case taskProgress(completed: Int, total: Int)
        /// Session title changed.
        case title(String)
        /// Subagent count changed.
        case subagents(Int)
        /// The model answering this session, e.g. `claude-opus-5`.
        case model(String)
        /// The git branch the session is working on.
        case branch(String)
        /// Timestamps of assistant activity, for the "coding today" figure.
        case activityStamps([Date])
        /// A plan is on screen awaiting the human's verdict.
        case awaitingApproval(Bool)
        /// The session process went away.
        case ended
    }

    public var sessionID: String
    public var kind: Kind
    public var timestamp: Date

    /// Does this event mean *Claude* did something?
    ///
    /// `lastActivity` drives every time-based decay, so anything that bumps it
    /// keeps the session looking busy. `.subagents` is the pet's own 2-second
    /// poll, emitted for every live session whether or not the count changed —
    /// counting it was the pet talking to itself and calling it work, which
    /// pinned `lastActivity` to within 2s of now forever and made both the 6s
    /// `doneDecay` and the 300s sleep threshold arithmetically unreachable.
    ///
    /// Everything else here is a genuine observation of Claude and does count,
    /// including `.title` and `.branch`: those only change because something
    /// happened in the session.
    public var countsAsActivity: Bool {
        switch kind {
        // `.taskProgress` rides the same watcher as `.activeTask` but is a
        // derived tally, not a fresh observation of Claude doing something —
        // counting it would re-pin `lastActivity` on every re-read.
        case .subagents, .taskProgress: false
        default: true
        }
    }

    public init(sessionID: String, kind: Kind, timestamp: Date = Date()) {
        self.sessionID = sessionID
        self.kind = kind
        self.timestamp = timestamp
    }
}
