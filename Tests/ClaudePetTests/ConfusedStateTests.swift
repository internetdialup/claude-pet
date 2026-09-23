import Testing
import Foundation
@testable import ClaudePet

/// **"This Claw'd doesn't understand your Claude Code yet."**
///
/// The operator's ask: if Claude Code changes its format under him, he should
/// say so plainly instead of silently misbehaving — but only on a confirmed
/// break, never on a version number (Claude Code shipped 64 releases between
/// the CLI on the operator's PATH and the desktop build, and the pet read every
/// one). The whole feature lives or dies on not crying wolf, so this suite is
/// its contract in both directions: every shape Claude Code writes TODAY must
/// never trip a rule, and each way the format could break must.
///
/// All fixtures are synthetic. The live shapes were captured as keys and types
/// only; no value here came from the operator's data.
@Suite("Format verdict")
struct FormatVerdictTests {

    /// One line per record type Claude Code 2.1.280 writes, each carrying that
    /// type's full live key set (captured as keys and types only, values here
    /// are dummies). Generated from the verification capture, 19 types.
    static let everyLiveShape: [String] = [
        #"{"agentName":"x","sessionId":"S1","type":"agent-name"}"#,
        #"{"aiTitle":"x","sessionId":"S1","type":"ai-title"}"#,
        #"{"accountUuid":"x","artifacts":{},"sessionId":"S1","type":"artifact-autoreact-ledger","v":0}"#,
        #"{"artifacts":{},"sessionId":"S1","type":"artifact-comment-monitor","v":0}"#,
        #"{"advisorModel":"x","apiBlockIndex":0,"attributionMcpServer":"x","attributionMcpTool":"x","attributionPlugin":"x","attributionSkill":"x","cwd":"x","effort":"x","entrypoint":"x","error":"x","errorDetails":"x","gitBranch":"x","isApiErrorMessage":false,"isSidechain":false,"message":{"model":"claude-opus-5","role":"assistant","stop_reason":"tool_use","type":"message","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]},"parentUuid":null,"perTurnEffort":null,"quotaLimits":{},"requestId":"x","sessionId":"S1","slug":"x","timestamp":"2020-01-02T12:00:00.000Z","type":"assistant","userType":"x","uuid":"x","version":"x","wireIngestContext":{},"wireToolInputs":{}}"#,
        #"{"atis":"x","sessionId":"S1","type":"atis-latch"}"#,
        #"{"attachment":{},"cwd":"x","entrypoint":"x","gitBranch":"x","isSidechain":false,"parentUuid":null,"rendered":[],"renderedInHumanTurn":[],"sessionId":"S1","slug":"x","timestamp":"2020-01-02T12:00:00.000Z","type":"attachment","userType":"x","uuid":"x","version":"x"}"#,
        #"{"bridgeSessionId":"x","lastSequenceNum":0,"ownerAccountUuid":"x","ownerOrganizationUuid":"x","sessionId":"S1","type":"bridge-session"}"#,
        #"{"hasUnknownModelCost":false,"modelUsage":{},"sessionId":"S1","startTime":0,"totalAPIDuration":0,"totalAPIDurationWithoutRetries":0,"totalCostUSD":0,"totalDuration":0,"totalLinesAdded":0,"totalLinesRemoved":0,"totalToolDuration":0,"type":"cost-state"}"#,
        #"{"customTitle":"x","sessionId":"S1","type":"custom-title"}"#,
        #"{"backup":{},"messageId":"x","snapshotMessageId":"x","timestamp":"2020-01-02T12:00:00.000Z","trackingPath":"x","type":"file-history-delta"}"#,
        #"{"isSnapshotUpdate":false,"messageId":"x","snapshot":{},"type":"file-history-snapshot"}"#,
        #"{"artifactCount":0,"sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","type":"frame-link"}"#,
        #"{"lastPrompt":"x","leafUuid":"x","sessionId":"S1","type":"last-prompt"}"#,
        #"{"mode":"x","sessionId":"S1","type":"mode"}"#,
        #"{"prNumber":0,"prRepository":"x","prUrl":"x","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","type":"pr-link"}"#,
        #"{"content":"x","operation":"x","reason":"x","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","type":"queue-operation"}"#,
        #"{"cwd":"x","entrypoint":"x","gitBranch":"x","hasOutput":false,"hookAdditionalContext":[],"hookCount":0,"hookErrors":[],"hookInfos":[],"isSidechain":false,"level":"x","parentUuid":null,"preventedContinuation":false,"sessionId":"S1","slug":"x","stopReason":"x","subtype":"x","timestamp":"2020-01-02T12:00:00.000Z","toolUseID":"x","type":"system","userType":"x","uuid":"x","version":"x"}"#,
        #"{"classifierMetaLines":"x","cwd":"x","entrypoint":"x","gitBranch":"x","isMeta":false,"isSidechain":false,"mcpMeta":{},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"origin":{},"parentUuid":null,"permissionMode":"x","promptId":"x","promptSource":"x","queueSkipAttachments":false,"sessionId":"S1","slug":"x","sourceToolAssistantUUID":"x","timestamp":"2020-01-02T12:00:00.000Z","toolDenialKind":"x","toolUseResult":[],"turnCompanion":false,"turnOrigin":"x","type":"user","userType":"x","uuid":"x","version":"x"}"#,
    ]


    private static func assistant(_ i: Int) -> String {
        #"{"type":"assistant","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","message":{"model":"m","stop_reason":"end_turn","content":[{"type":"text","text":"\#(i)"}]}}"#
    }
    private static func user(_ i: Int) -> String {
        #"{"type":"user","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","message":{"content":"prompt \#(i)"}}"#
    }
    private static let queueOperation = #"{"type":"queue-operation","operation":"enqueue","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","content":"x","sessionEpoch":0}"#
    /// ~10 KiB of attachment, so 22 of them weigh what the calibration saw.
    private static let bigAttachment = #"{"type":"attachment","sessionId":"S1","attachment":{"content":""#
        + String(repeating: "a", count: 10_300) + #""}}"#

    /// A fold that has already made its first read — the backlog — so every
    /// line appended afterwards is judged. Returns the verdict after reading.
    private func judge(_ appended: [String]) throws -> FormatProblem? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verdict-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try (Self.assistant(0) + "\n").write(to: url, atomically: true, encoding: .utf8)
        let fold = TranscriptFold()
        _ = fold.pump(url: url)                       // the backlog: never judged
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        // Several reads, as a live transcript grows — each under maxChunk.
        for chunk in stride(from: 0, to: appended.count, by: 50) {
            let slice = appended[chunk..<min(chunk + 50, appended.count)]
            try handle.write(contentsOf: Data((slice.joined(separator: "\n") + "\n").utf8))
            _ = fold.pump(url: url)
        }
        try handle.close()
        return fold.verdict
    }

    /// 🔎 THE CONTRACT, negative half. Every record shape on disk today, the
    /// 429 and interruption records, and the two worst healthy runs the
    /// calibration found — 95 lines with no user or assistant record, and 22
    /// lines weighing 226 KiB — interleaved as a session would write them,
    /// three times over. No rule may fire.
    @Test("Everything Claude Code writes today is readable — no rule fires")
    func todayNeverCriesWolf() throws {
        var session: [String] = []
        for cycle in 0..<3 {
            session += Self.everyLiveShape
            session.append(Self.user(cycle))
            session += Array(repeating: Self.queueOperation, count: 95)
            session.append(Self.assistant(cycle))
            session += Array(repeating: Self.bigAttachment, count: 22)
            session.append(#"{"type":"assistant","sessionId":"S1","isApiErrorMessage":true,"apiErrorStatus":"429","message":{"model":"<synthetic>","stop_reason":"stop_sequence","content":[{"type":"text","text":"x"}]}}"#)
            session.append(#"{"type":"assistant","sessionId":"S1","message":{"model":"<synthetic>","stop_reason":"stop_sequence","content":[{"type":"text","text":"x"}]}}"#)
            session.append(Self.user(cycle + 10))
        }
        let verdict = try judge(session)
        #expect(verdict == nil, "today's format tripped \(String(describing: verdict))")
    }

    /// THE CONTRACT, positive half: each way the format could break, fires.
    @Test("Garbage lines read as unreadable")
    func garbageIsUnreadable() throws {
        let verdict = try judge(Array(repeating: "<<not json>>", count: FoldRule.unreadable))
        #expect(verdict == .unreadable)
    }

    @Test("A renamed record type reads as renamed")
    func renamedTypes() throws {
        let renamed = Self.assistant(1).replacingOccurrences(of: #""type":"assistant""#, with: #""type":"model-turn""#)
        let verdict = try judge(Array(repeating: renamed, count: FoldRule.renamed))
        #expect(verdict == .renamed)
    }

    @Test("Replies without a content array read as reshaped")
    func contentAsObject() throws {
        let reshaped = Self.assistant(1).replacingOccurrences(of: #""content":["#, with: #""content":{"blocks":["#)
            .replacingOccurrences(of: "]}}", with: "]}}}")
        let verdict = try judge(Array(repeating: reshaped, count: FoldRule.reshaped))
        #expect(verdict == .reshaped)
    }

    @Test("Records without a session id read as unrouted")
    func renamedSessionKey() throws {
        let unrouted = Self.assistant(1).replacingOccurrences(of: #""sessionId""#, with: #""session_id""#)
        let verdict = try judge(Array(repeating: unrouted, count: FoldRule.unrouted))
        #expect(verdict == .unrouted)
    }

    /// 🔎 The thresholds ARE the rule, so they are pinned as numbers. The tests
    /// around this read them from the fold, which proves the mechanism — and a
    /// kill test showed what that misses: raising `renamedAfter` to 500,000 made
    /// the detector useless and every one of them still passed, because each
    /// simply wrote 500,000 lines. Changing a number here means re-running the
    /// calibration (53,464 real lines, nine Claude Code versions), not only the
    /// suite: the healthy maxima were 95 lines with no user or assistant record,
    /// and zero for every other rule.
    @Test("The calibrated thresholds hold their calibration")
    func calibratedThresholds() {
        #expect(TranscriptFold.unreadableAfter == 50)
        #expect(TranscriptFold.renamedAfter == 500, "5.3× the 95-line healthy maximum — re-calibrate first")
        #expect(TranscriptFold.reshapedAfter == 20)
        #expect(TranscriptFold.unroutedAfter == 20)
        // Whatever the numbers become, the margin the calibration bought stays.
        let margin = TranscriptFold.renamedAfter >= 95 * 3
        #expect(margin, "within 3× of a healthy run — it would cry wolf")
    }

    /// Short of each threshold nothing fires — the thresholds are the rule.
    @Test("One line short of every threshold, nothing fires")
    func shortOfTheThreshold() throws {
        #expect(try judge(Array(repeating: "<<not json>>", count: FoldRule.unreadable - 1)) == nil)
        #expect(try judge(Array(repeating: Self.queueOperation, count: FoldRule.renamed - 1)) == nil)
    }

    /// The backlog is history. A transcript whose FIRST read is nothing but
    /// garbage says nothing about the format being written now.
    @Test("The backlog replayed on attach is never judged")
    func backlogIsNotJudged() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backlog-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try (Array(repeating: "<<not json>>", count: 600).joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let fold = TranscriptFold()
        _ = fold.pump(url: url)
        #expect(fold.verdict == nil)
    }

    @Test("One well-formed record clears the verdict")
    func recovers() throws {
        var lines = Array(repeating: "<<not json>>", count: FoldRule.unreadable)
        lines.append(Self.assistant(9))
        #expect(try judge(lines) == nil, "a readable record should clear it")
    }
}

/// The thresholds, read from the fold rather than restated.
private enum FoldRule {
    static let unreadable = TranscriptFold.unreadableAfter
    static let renamed = TranscriptFold.renamedAfter
    static let reshaped = TranscriptFold.reshapedAfter
    static let unrouted = TranscriptFold.unroutedAfter
}

/// The state, through the coordinator: sticky, persistent, and honest about
/// what broke. Files go under the scratch `CLAUDE_PET_HOME`, never ~/.claude.
@Suite("Confused state", .serialized)
@MainActor
struct ConfusedStateTests {

    private func coordinator(_ id: String, version: String? = "2.1.999") throws -> ActivityCoordinator {
        _ = FinaleFixture.redirect
        var payload: [String: Any] = [
            "pid": Int(getpid()), "sessionId": id,
            "cwd": ClaudeHome.root.appendingPathComponent("work").path, "name": "confused-\(id)",
        ]
        if let version { payload["version"] = version }
        try FileManager.default.createDirectory(at: ClaudeHome.sessions, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: ClaudeHome.sessions.appendingPathComponent("confused-\(id).json"))
        let coordinator = ActivityCoordinator()
        coordinator.start()
        coordinator.stop()
        return coordinator
    }

    private func session(_ coordinator: ActivityCoordinator, _ id: String) -> ClaudeSession? {
        coordinator.state.sessions.first { $0.id == id }
    }

    @Test("A broken transcript makes him confused, and nothing guesses past it")
    func confusedIsSticky() throws {
        let id = "confused-sticky"
        let coordinator = try coordinator(id)
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .formatProblem(.renamed))])
        #expect(session(coordinator, id)?.mood == .confused)
        // Neither a registry status nor a stray tool record may overwrite it.
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .registryStatus("busy"), timestamp: Date())])
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .toolStarted(name: "Edit", detail: "x"))])
        let still = session(coordinator, id)
        #expect(still?.mood == .confused, "a later event guessed past the break: \(String(describing: still?.mood))")
        #expect(still?.activity == nil)
        // A readable window clears it.
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .formatProblem(nil))])
        #expect(session(coordinator, id)?.mood != .confused)
    }

    /// Persistent by the operator's ruling: it does not decay, does not sleep,
    /// and the bubble stays, naming the version and what broke. Derived for
    /// exactly this session — the first draft asserted on "whatever is
    /// focused", and another suite's waiting session outranks confused, so the
    /// bubble checks would have skipped themselves in a full run.
    @Test("The confused bubble names the version and never goes out")
    func bubblePersists() throws {
        let id = "confused-bubble"
        let coordinator = try coordinator(id)
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .formatProblem(.reshaped))])
        for later in [0.0, 600, 4_000, 86_400] {
            coordinator.recompute(now: Date().addingTimeInterval(later))
            let current = try #require(session(coordinator, id))
            #expect(current.mood == .confused, "it decayed after \(later)s")
            let state = coordinator.derive(slot: 0, excluding: nil, ordered: [current],
                                           now: Date().addingTimeInterval(later))
            #expect(state.mood == .confused, "it slept or changed after \(later)s")
            #expect(state.bubble == "This Claw'd doesn't understand Claude Code 2.1.999 yet",
                    "the bubble went out after \(later)s")
            #expect(state.unsupported == FormatProblem.reshaped.detail)
        }
    }

    /// The registry case, end to end. The broken file is named for this
    /// process's own pid, so it counts as live — and it is removed before the
    /// test returns, inside one main-actor stretch no other suite can enter.
    @Test("A live registry file that stays broken makes the whole pet confused, and he recovers")
    func brokenRegistryConfuses() throws {
        let coordinator = try coordinator("confused-registry")
        let broken = ClaudeHome.sessions.appendingPathComponent("\(getpid()).json")
        defer { try? FileManager.default.removeItem(at: broken) }
        try Data("{\"pid\": ".utf8).write(to: broken)            // a half-written file
        coordinator.refreshSessions()
        coordinator.recompute(now: Date().addingTimeInterval(1))
        #expect(coordinator.state.mood != .confused, "one unreadable read is a torn write, not a format")
        coordinator.recompute(now: Date().addingTimeInterval(ActivityCoordinator.registryBreakAfter + 1))
        #expect(coordinator.state.mood == .confused)
        #expect(coordinator.state.unsupported == FormatProblem.registry.detail)
        try FileManager.default.removeItem(at: broken)
        coordinator.refreshSessions()
        coordinator.recompute(now: Date().addingTimeInterval(ActivityCoordinator.registryBreakAfter + 2))
        #expect(coordinator.state.mood != .confused, "he should recover once the file reads")
    }

    @Test("The line names the version when it knows it, and stays honest when it doesn't")
    func theLine() {
        #expect(Vocab.unsupported(version: "2.1.280") == "This Claw'd doesn't understand Claude Code 2.1.280 yet")
        #expect(Vocab.unsupported(version: nil) == "This Claw'd doesn't understand your Claude Code yet")
        #expect(Vocab.unsupported(version: "") == "This Claw'd doesn't understand your Claude Code yet")
        let fits = Vocab.unsupported(version: "2.1.280").count <= ThoughtBubble.plainCapacity
        #expect(fits, "the line must fit the two-line bubble")
    }

    @Test("It is a failure state, not a feature: the README renders never show it")
    func showcaseLeavesItOut() {
        #expect(!PetMood.showcase.contains(.confused))
        #expect(PetMood.showcase.count == PetMood.allCases.count - 1)
        #expect(PetMood.allCases.last == .confused,
                "appended last, or the party's mood walk moves party.gif and rainbow.gif")
    }
}

/// The registry's own check, as the pure rule it is: one unreadable read is a
/// torn write; a live process's file unreadable across the window is a format.
@Suite("Registry format check")
struct RegistryFormatCheckTests {

    @Test("One read is a torn write; the same file broken past the window is a format")
    func windowDecides() {
        let first = Date(timeIntervalSince1970: 1_000)
        let since = ["123.json": first]
        let within = ActivityCoordinator.registryBroken(since, now: first.addingTimeInterval(3))
        let past = ActivityCoordinator.registryBroken(since, now: first.addingTimeInterval(4))
        #expect(!within)
        #expect(past)
        let none = ActivityCoordinator.registryBroken([:], now: first.addingTimeInterval(60))
        #expect(!none)
    }
}
