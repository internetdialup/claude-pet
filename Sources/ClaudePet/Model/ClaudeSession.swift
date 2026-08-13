import Foundation

/// One live Claude Code process, as advertised by `~/.claude/sessions/<pid>.json`.
///
/// The filename is the PID; liveness is `kill(pid, 0)` **plus** a `procStart` match,
/// because PIDs are recycled and a stale registry file would otherwise resurrect a
/// dead session.
public struct ClaudeSession: Sendable, Equatable, Identifiable {
    /// The Claude Code session UUID. Also the transcript filename stem.
    public var id: String
    public var pid: Int32
    /// Human label Claude Code derives, e.g. "claude-pet-47".
    public var name: String
    /// The session's working directory.
    public var cwd: String
    /// Process start string from the registry, used to detect PID reuse.
    public var procStart: String
    public var startedAt: Date

    /// Current activity, folded from the transcript tail and hook events.
    public var mood: PetMood = .idle
    /// Best available description of what Claude is doing, in preference order:
    /// todo `activeForm` › tool detail › session title.
    public var activity: String?
    /// Tool name when a call is in flight.
    public var tool: String?
    /// Session title from `custom-title` / `ai-title` / `last-prompt`.
    public var title: String?
    /// The in-progress todo's `activeForm`. Outranks tool detail in the bubble,
    /// because Claude Code already phrased it for a human.
    public var activeTaskLabel: String?
    /// Model id from the transcript, e.g. `claude-opus-5`.
    public var model: String?
    /// Git branch from the transcript, e.g. `main`.
    public var branch: String?
    /// Hours between the first and last assistant message today. Nil until at
    /// least one has been observed.
    public var activeHoursToday: Double?
    var firstActivityToday: Date?
    var lastActivityToday: Date?
    /// Number of subagents currently appending to their transcripts.
    public var subagentCount: Int = 0
    /// A plan is written and waiting on the human.
    public var awaitingApproval: Bool = false
    /// Timestamps of recent tool calls, used to measure how hard Claude is going.
    public var recentToolCalls: [Date] = []
    /// Last time anything at all changed for this session.
    public var lastActivity: Date = .distantPast

    /// Last path component of `cwd` — what the roster shows as the project name.
    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// The transcript directory Claude Code writes for this `cwd`.
    ///
    /// Claude Code encodes the path by replacing every character outside
    /// `[A-Za-z0-9]` with `-`, so `/Users/x/My Project` becomes
    /// `-Users-x-My-Project`. Verified against the real directories under
    /// `~/.claude/projects/`.
    public static func encodeProjectDirectory(_ cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    public var transcriptURL: URL {
        ClaudeHome.projects
            .appendingPathComponent(Self.encodeProjectDirectory(cwd))
            .appendingPathComponent("\(id).jsonl")
    }

    public var tasksDirectory: URL {
        ClaudeHome.tasks.appendingPathComponent(id)
    }

    public var subagentsDirectory: URL {
        ClaudeHome.projects
            .appendingPathComponent(Self.encodeProjectDirectory(cwd))
            .appendingPathComponent(id)
            .appendingPathComponent("subagents")
    }
}
