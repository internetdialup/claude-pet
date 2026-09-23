import Testing
import Foundation
@testable import ClaudePet

/// **A turn that fails is over; a turn that ends twice still celebrates.**
///
/// A 429 is written as an assistant record Claude Code composes itself —
/// `isApiErrorMessage`, `apiErrorStatus`, model `<synthetic>`, stop reason
/// `stop_sequence` — and in live transcripts the turn really does stop there:
/// the next record is a queue operation and then a NEW user prompt. The fold
/// ended turns on `end_turn` alone, so after a rate limit he sat in "working"
/// until the ten-minute decay, with `MODEL · <Synthetic>` on the ticker.
///
/// Record shapes use the keys Claude Code 2.1.280 writes. Nothing here reads
/// the operator's data — the redline.
///
/// Every membership check goes through a `let` first: `#expect(xs.contains(.a))`
/// is a member call with an implicit-member argument, and Swift Testing expands
/// that into a closure whose result is unused — a check that always passes.
@Suite("Turn endings")
struct TurnEndingTests {

    private func pump(_ lines: [String]) throws -> [ActivityEvent.Kind] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("turns-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return TranscriptFold().pump(url: url).map(\.kind)
    }

    private static let past = "2020-01-02T12:00:00.000Z"
    /// Today, so a REAL record would carry an activity stamp — which is what
    /// makes the synthetic record's lack of one a finding rather than a given.
    private static var today: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
    private static let toolContent = #"[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]"#

    private func assistant(model: String, stop: String?, error: Bool = false,
                           content: String = #"[{"type":"text","text":"x"}]"#,
                           at timestamp: String = past) -> String {
        let stopJSON = stop.map { "\"\($0)\"" } ?? "null"
        let errorKeys = error ? #","isApiErrorMessage":true,"apiErrorStatus":"429""# : ""
        return #"{"type":"assistant","sessionId":"S1","timestamp":"\#(timestamp)""# + errorKeys
            + #","message":{"model":"\#(model)","stop_reason":\#(stopJSON),"content":\#(content)}}"#
    }

    @Test("A 429 ends the turn quietly — no model, no activity stamp")
    func rateLimitAbortsTheTurn() throws {
        let kinds = try pump([assistant(model: "<synthetic>", stop: "stop_sequence",
                                        error: true, at: Self.today)])
        #expect(kinds == [.turnAborted], "a 429 produced \(kinds)")

        // The control: the same record from the model, today, IS activity.
        let real = try pump([assistant(model: "claude-opus-5", stop: "end_turn", at: Self.today)])
        let stamped = real.contains { if case .activityStamps = $0 { return true } else { return false } }
        #expect(stamped, "precondition: a real record dated today carries a stamp")
    }

    /// The error flag is Claude Code's explicit signal and the `<synthetic>` model
    /// is incidental — so an error record that names a REAL model must abort the
    /// turn too. The first draft of this suite only ever sent both together, and
    /// a kill test that deleted the flag check passed: nothing tested the flag.
    @Test("An error record naming a real model still aborts, and names no model")
    func errorFlagAloneAborts() throws {
        let kinds = try pump([assistant(model: "claude-opus-5", stop: "stop_sequence", error: true)])
        #expect(kinds == [.turnAborted], "an error record with a real model produced \(kinds)")
    }

    @Test("An interruption carries the synthetic model without the error flag, and ends the same way")
    func interruptionAbortsTheTurn() throws {
        let kinds = try pump([assistant(model: "<synthetic>", stop: "stop_sequence")])
        #expect(kinds == [.turnAborted], "an interruption produced \(kinds)")
    }

    @Test("A model change on the ending record no longer swallows the ending")
    func modelChangeKeepsTheEnding() throws {
        let kinds = try pump([assistant(model: "claude-opus-5-5", stop: "end_turn")])
        #expect(kinds == [.model("claude-opus-5-5"), .turnEnded], "got \(kinds)")
    }

    @Test("Refusals and context-window stops end a turn; pauses and tool calls do not")
    func terminalStopReasons() throws {
        for stop in ["end_turn", "stop_sequence", "refusal", "model_context_window_exceeded"] {
            let kinds = try pump([assistant(model: "m", stop: stop)])
            let ended = kinds.last == .turnEnded
            #expect(ended, "\(stop) should end the turn, got \(kinds)")
        }
        for stop in ["pause_turn", "compaction", "tool_use"] {
            let kinds = try pump([assistant(model: "m", stop: stop)])
            let ended = kinds.contains(.turnEnded)
            #expect(!ended, "\(stop) must not end the turn, got \(kinds)")
        }
        let calling = try pump([assistant(model: "m", stop: "end_turn", content: Self.toolContent)])
        let ended = calling.contains(.turnEnded)
        #expect(!ended, "a record that calls a tool never ends the turn")
    }

    @Test("After a synthetic record the real model is not announced again")
    func syntheticRecordKeepsTheModel() throws {
        let kinds = try pump([
            assistant(model: "claude-opus-5", stop: "end_turn"),
            assistant(model: "<synthetic>", stop: "stop_sequence", error: true),
            assistant(model: "claude-opus-5", stop: "end_turn"),
        ])
        #expect(kinds == [.model("claude-opus-5"), .turnEnded, .turnAborted, .turnEnded],
                "got \(kinds)")
    }

    @Test("Opus 5.5 is named as itself, not as Opus 5")
    func opusFivePointFiveIsNamed() {
        #expect(StatusTicker.displayName(forModel: "claude-opus-5-5") == "Opus 5.5")
        #expect(StatusTicker.displayName(forModel: "claude-opus-5") == "Opus 5")
    }
}

/// The same two endings, through the coordinator that turns them into a mood.
@Suite("Turn endings, in the coordinator", .serialized)
@MainActor
struct TurnEndingCoordinatorTests {

    private func coordinator(_ id: String) throws -> ActivityCoordinator {
        try FinaleFixture.register([id])
        let coordinator = ActivityCoordinator()
        coordinator.start()
        coordinator.stop()
        return coordinator
    }

    private func session(_ coordinator: ActivityCoordinator, _ id: String) throws -> ClaudeSession {
        try #require(coordinator.state.sessions.first { $0.id == id }, "session \(id) missing")
    }

    @Test("A failed turn goes to idle — no completion badge, no party")
    func abortedTurnIsQuiet() throws {
        let id = "turns-aborted"
        let coordinator = try coordinator(id)
        let now = Date()
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .toolStarted(name: "Edit", detail: nil),
                                          timestamp: now)])
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnAborted,
                                          timestamp: now.addingTimeInterval(1))])
        let after = try session(coordinator, id)
        #expect(after.mood == .idle, "a 429 left him \(after.mood)")
        #expect(after.completionBadgeAt == nil, "a failed turn earned a completion badge")
        #expect(!after.celebrating)
    }

    @Test("A turn that ends twice still celebrates")
    func secondEndingKeepsTheParty() throws {
        let id = "turns-twice"
        let coordinator = try coordinator(id)
        let base = Date()
        for beat in 0..<ActivityCoordinator.cookingToolRate {
            coordinator.ingest([ActivityEvent(sessionID: id, kind: .toolStarted(name: "Edit", detail: nil),
                                              timestamp: base.addingTimeInterval(Double(beat) * 0.01))])
        }
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnEnded,
                                          timestamp: base.addingTimeInterval(0.2))])
        let first = try session(coordinator, id).celebrating
        #expect(first, "precondition: a cooking sprint that lands celebrates")
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnEnded,
                                          timestamp: base.addingTimeInterval(0.3))])
        let second = try session(coordinator, id).celebrating
        #expect(second, "the second ending cancelled the party the first one started")
    }
}
