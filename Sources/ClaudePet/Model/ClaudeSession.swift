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
    /// The todo list's tally, from `TaskWatcher.progress` — nil when the
    /// session has no task files.
    public var tasksCompleted: Int?
    public var tasksTotal: Int?
    /// Set when a `.cooking` sprint lands on `.done`: the payoff animation
    /// runs longer than a plain done, and the decay window stretches with it.
    public var celebrating: Bool = false
    /// When this sprint's cooking pace first appeared — the cook stopwatch.
    /// Survives the `.thinking` beats between tools; cleared when the turn
    /// lands or the session goes fully cold.
    public var cookingSince: Date?
    /// The landing sprint had been cooking a while: the done state plays the
    /// FULL finale — flash, glow, transform, rainbow.
    public var epicCelebrating: Bool = false
    /// The highest cook-progress milestone already notified (25/50/75), so a
    /// crossing fires exactly once. Dies with the session; reset per turn.
    public var notifiedMilestone: Int?
    /// When the last turn finished — the quiet completion marker. Outlives the
    /// done pose (mood decay does not clear it); consumed by new work or by
    /// its own five-minute clock.
    public var completionBadgeAt: Date?
    /// The recognisable service the current sprint is talking to, and when it
    /// was last observed. Stamped by ingest on a classify hit (single writer,
    /// like `cookingSince`), renewed on every matching tool call, and
    /// deliberately NOT cleared on toolFinished — the linger bridges the gaps
    /// between npm commands. Cleared when the turn lands or the linger
    /// expires.
    public var serviceGlyph: ServiceGlyph?
    public var serviceGlyphAt: Date?
    /// Last time anything at all changed for this session.
    public var lastActivity: Date = .distantPast

    /// What Claude Code's registry says it is doing — `busy`, `shell`, `waiting`
    /// or `idle` — on builds that write it (2.1.280 does). Nil on older builds,
    /// where the transcript inference carries on alone, as it always has.
    public var status: String?
    /// With `waiting`: what for — "permission prompt", "input needed".
    public var waitingFor: String?
    /// When the registry last changed `status`.
    public var statusUpdatedAt: Date?
    /// The Claude Code version that registered this session.
    public var claudeVersion: String?
    /// The registry file this session came from. `/clear` rewrites that file IN
    /// PLACE with a new sessionId, so the FILE — not the pid, which every test
    /// fixture shares — is what says "this is the same terminal".
    public var registryFile: String?
    /// Set when this session's transcript has broken in a way the pet can
    /// confirm — see `TranscriptFold.verdict`. Nil while every rule holds.
    public var formatProblem: FormatProblem?

    /// Last path component of `cwd` — what the roster shows as the project name.
    public var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// The transcript directory name Claude Code writes for this `cwd` — the
    /// rule read straight out of the 2.1.280 binary rather than inferred from
    /// directory listings:
    ///
    ///     kT(e) = slug.length <= 200 ? slug : slug.slice(0,200) + "-" + Le(e)
    ///     slug  = e.replace(/[^a-zA-Z0-9]/g, "-")      // e is NFC, UTF-16 units
    ///     Le(e) = Math.abs(CQ(e)).toString(36)
    ///     CQ(e) = r = (r<<5) - r + e.charCodeAt(n) | 0  // Java's String.hashCode
    ///
    /// 🔎 This doc always SAID "every character outside `[A-Za-z0-9]`", and the
    /// code kept every Unicode letter (`isLetter`) — so `~/café/…` looked
    /// for `…-café-…` while Claude Code wrote `…-caf--…`, and a
    /// path past 200 characters looked for a name Claude Code had truncated
    /// and hashed. Those sessions were never seen, and nothing said so. The two
    /// agreed for every ASCII path, which is every path this was ever tested on.
    ///
    /// The Swift details are where it breaks again if anyone "simplifies" it:
    /// NFC first, because Claude Code normalises the cwd once at startup;
    /// UTF-16 units, not Characters, because `charCodeAt` sees an emoji as two
    /// and writes two dashes; Int32 wrapping arithmetic for `| 0`; and a widen to
    /// Int64 before `abs`, because `abs(Int32.min)` traps where JavaScript
    /// answers 2147483648.
    public static func encodeProjectDirectory(_ cwd: String) -> String {
        let nfc = cwd.precomposedStringWithCanonicalMapping
        let units = Array(nfc.utf16)
        let slug = String(units.map { isASCIIAlphanumeric($0) ? Character(UnicodeScalar($0)!) : "-" })
        guard units.count > maxSlugLength else { return slug }
        return String(slug.prefix(maxSlugLength)) + "-" + projectNameHash(nfc)
    }

    /// Claude Code's `slice(0, 200)`: past this, the name is truncated and a hash
    /// of the whole cwd is appended.
    public static let maxSlugLength = 200

    /// `Math.abs(CQ(e)).toString(36)` — Java's `String.hashCode`, over UTF-16.
    static func projectNameHash(_ nfcCwd: String) -> String {
        var hash: Int32 = 0
        for unit in nfcCwd.utf16 { hash = (hash &* 31) &+ Int32(unit) }
        return String(abs(Int64(hash)), radix: 36)
    }

    private static func isASCIIAlphanumeric(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
    }

    /// Where Claude Code keeps this cwd's session files, resolved the way Claude
    /// Code resolves it: the exact name first; and for a name long enough to
    /// carry a hash, a `projects/` entry sharing its 200-character prefix —
    /// because the binary itself does not trust the suffix across runtimes (it
    /// sorts candidates by `exactName`, then takes the prefix match). Among
    /// several prefix matches, the one that holds this session's transcript wins.
    static func projectDirectory(for cwd: String, sessionID: String,
                                 in projects: URL = ClaudeHome.projects) -> URL {
        let exact = encodeProjectDirectory(cwd)
        let url = projects.appendingPathComponent(exact)
        let fm = FileManager.default
        guard exact.utf16.count > maxSlugLength, !fm.fileExists(atPath: url.path) else { return url }
        let prefix = String(exact.prefix(maxSlugLength)) + "-"
        let candidates = ((try? fm.contentsOfDirectory(atPath: projects.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }.sorted()
        let holder = candidates.first {
            fm.fileExists(atPath: projects.appendingPathComponent($0)
                .appendingPathComponent("\(sessionID).jsonl").path)
        }
        guard let match = holder ?? candidates.first else { return url }
        return projects.appendingPathComponent(match)
    }

    public var transcriptURL: URL {
        Self.projectDirectory(for: cwd, sessionID: id)
            .appendingPathComponent("\(id).jsonl")
    }

    public var tasksDirectory: URL {
        ClaudeHome.tasks.appendingPathComponent(id)
    }

    public var subagentsDirectory: URL {
        Self.projectDirectory(for: cwd, sessionID: id)
            .appendingPathComponent(id)
            .appendingPathComponent("subagents")
    }
}

/// A way Claude Code's on-disk format can break under the pet. Each case is a
/// SHAPE a rule confirmed — never "a newer version", which is not a break at
/// all: Claude Code shipped 64 releases between the CLI on the operator's PATH
/// and the desktop build, and the pet read every one of them.
public enum FormatProblem: String, Sendable, Equatable {
    /// Lines that are not JSON objects with a string `type`.
    case unreadable
    /// Valid JSON, but a long run with no `assistant` or `user` record — the
    /// record types were renamed.
    case renamed
    /// `assistant` records without `message.content` as an array.
    case reshaped
    /// Records without a string `sessionId`, so none of them can be routed.
    case unrouted
    /// The session registry itself: a live process's file that will not decode.
    case registry

    /// What broke, in words, for the menu.
    public var detail: String {
        switch self {
        case .unreadable: "The transcript isn't in a format this version can read"
        case .renamed: "The transcript's record types changed"
        case .reshaped: "Claude's replies are in a shape this version can't read"
        case .unrouted: "Transcript lines no longer say which session they belong to"
        case .registry: "The session registry is in a shape this version can't read"
        }
    }
}
