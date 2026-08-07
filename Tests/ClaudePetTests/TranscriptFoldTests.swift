import Testing
import Foundation
@testable import ClaudePet

/// Fixtures are hand-built from the real transcript shapes observed under
/// `~/.claude/projects/`. Tests never read the operator's actual data
/// (`Bamboo.md` §5).
///
/// Timestamps are pinned to a fixed date in the past. The fold emits an
/// `activityStamps` event only for lines dated *today*, so fixtures carrying a
/// live date would make these counts depend on the day the suite runs.
@Suite("Transcript fold")
struct TranscriptFoldTests {

    private func temporaryFile(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fold-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let toolLine = """
    {"type":"assistant","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","message":{"model":"claude-opus-5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls","description":"List files"}}]}}
    """
    private let resultLine = """
    {"type":"user","sessionId":"S1","timestamp":"2020-01-02T12:00:01.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}}
    """
    private let endTurnLine = """
    {"type":"assistant","sessionId":"S1","timestamp":"2020-01-02T12:00:02.000Z","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Done."}]}}
    """
    private let titleLine = """
    {"type":"ai-title","aiTitle":"Build the crab","sessionId":"S1"}
    """
    private let thinkingLine = """
    {"type":"assistant","sessionId":"S1","timestamp":"2020-01-02T12:00:03.000Z","message":{"stop_reason":null,"content":[{"type":"thinking","thinking":"hmm","signature":"x"}]}}
    """

    @Test("A tool call and its result produce started then finished")
    func toolLifecycle() throws {
        let url = try temporaryFile([titleLine, toolLine, resultLine])
        defer { try? FileManager.default.removeItem(at: url) }

        let fold = TranscriptFold()
        let events = fold.pump(url: url)

        // title, model, toolStarted, toolFinished — the assistant line carries
        // the model, which is reported the first time it is seen.
        #expect(events.count == 4)
        guard case .title(let title) = events[0].kind else { Issue.record("expected title"); return }
        #expect(title == "Build the crab")
        guard case .model(let model) = events[1].kind else { Issue.record("expected model"); return }
        #expect(model == "claude-opus-5")
        guard case .toolStarted(let name, let detail) = events[2].kind else {
            Issue.record("expected toolStarted"); return
        }
        #expect(name == "Bash")
        #expect(detail == "List files")
        guard case .toolFinished(let finished) = events[3].kind else {
            Issue.record("expected toolFinished"); return
        }
        #expect(finished == "Bash")
    }

    @Test("The model is reported once, not on every assistant line")
    func modelReportedOnce() throws {
        let url = try temporaryFile([toolLine, resultLine, toolLine, resultLine])
        defer { try? FileManager.default.removeItem(at: url) }

        let events = TranscriptFold().pump(url: url)
        let modelEvents = events.filter { if case .model = $0.kind { true } else { false } }
        #expect(modelEvents.count == 1)
    }

    @Test("A thinking block with no tool yields thinking")
    func thinkingBlock() throws {
        let url = try temporaryFile([thinkingLine])
        defer { try? FileManager.default.removeItem(at: url) }
        let events = TranscriptFold().pump(url: url)
        #expect(events.count == 1)
        guard case .thinking = events[0].kind else { Issue.record("expected thinking"); return }
    }

    @Test("end_turn yields turnEnded")
    func endTurn() throws {
        let url = try temporaryFile([endTurnLine])
        defer { try? FileManager.default.removeItem(at: url) }
        let events = TranscriptFold().pump(url: url)
        #expect(events.count == 1)
        guard case .turnEnded = events[0].kind else { Issue.record("expected turnEnded"); return }
    }

    @Test("Only new bytes are read on the second pump")
    func incrementalRead() throws {
        let url = try temporaryFile([titleLine])
        defer { try? FileManager.default.removeItem(at: url) }

        let fold = TranscriptFold()
        _ = fold.pump(url: url)
        #expect(fold.pump(url: url).isEmpty, "nothing appended, so nothing new")

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((toolLine + "\n").utf8))
        try handle.close()

        let events = fold.pump(url: url)
        // model + toolStarted: this is the first assistant line this fold saw.
        #expect(events.count == 2)
        guard case .toolStarted = events[1].kind else { Issue.record("expected toolStarted"); return }
    }

    /// The load-bearing guarantee from `Bamboo.md` §5. A transcript larger than
    /// the attach window must not be read whole, and must not emit the history
    /// that predates the pet.
    @Test("Attaching to a large file reads only the tail window")
    func boundedInitialRead() throws {
        let filler = String(repeating: "x", count: 200)
        var lines: [String] = []
        for index in 0..<2_000 {
            lines.append("""
            {"type":"system","sessionId":"S1","subtype":"noise","index":\(index),"pad":"\(filler)"}
            """)
        }
        lines.append(toolLine)

        let url = try temporaryFile(lines)
        defer { try? FileManager.default.removeItem(at: url) }

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > Int(TranscriptFold.initialWindow), "fixture must exceed the attach window")

        let fold = TranscriptFold()
        let events = fold.pump(url: url)

        // Everything before the window is invisible; only the trailing tool call
        // survives, preceded by its model announcement.
        #expect(events.count == 2)
        guard case .toolStarted(let name, _) = events[1].kind else {
            Issue.record("expected toolStarted"); return
        }
        #expect(name == "Bash")
    }

    @Test("A truncated or replaced file re-attaches instead of throwing")
    func truncationRecovers() throws {
        let url = try temporaryFile([titleLine, toolLine])
        defer { try? FileManager.default.removeItem(at: url) }

        let fold = TranscriptFold()
        _ = fold.pump(url: url)

        try "".write(to: url, atomically: true, encoding: .utf8)
        #expect(fold.pump(url: url).isEmpty)

        try endTurnLine.appending("\n").write(to: url, atomically: true, encoding: .utf8)
        let events = fold.pump(url: url)
        #expect(events.count == 1)
    }
}

@Suite("Transcript metadata")
struct TranscriptMetadataTests {

    private func temporaryFile(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func assistantLine(branch: String?, timestamp: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let branchField = branch.map { "\"gitBranch\":\"\($0)\"," } ?? ""
        return """
        {"type":"assistant","sessionId":"S1",\(branchField)"timestamp":"\(formatter.string(from: timestamp))",\
        "message":{"model":"claude-opus-5","stop_reason":"end_turn","content":[{"type":"text","text":"hi"}]}}
        """
    }

    @Test("gitBranch is surfaced once, and only when it changes")
    func branchIsReported() throws {
        let past = Date(timeIntervalSince1970: 1_577_000_000)
        let url = try temporaryFile([
            assistantLine(branch: "main", timestamp: past),
            assistantLine(branch: "main", timestamp: past),
            assistantLine(branch: "feature/pet", timestamp: past),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let branches = TranscriptFold().pump(url: url).compactMap { event -> String? in
            if case .branch(let name) = event.kind { return name }
            return nil
        }
        #expect(branches == ["main", "feature/pet"])
    }

    @Test("A line with no branch reports none")
    func noBranchNoEvent() throws {
        let past = Date(timeIntervalSince1970: 1_577_000_000)
        let url = try temporaryFile([assistantLine(branch: nil, timestamp: past)])
        defer { try? FileManager.default.removeItem(at: url) }

        let hasBranch = TranscriptFold().pump(url: url).contains {
            if case .branch = $0.kind { return true }
            return false
        }
        #expect(!hasBranch)
    }

    /// The "coding Nh today" figure must be measured from today's messages only.
    @Test("Activity stamps are emitted for today and withheld for older lines")
    func activityStampsAreTodayOnly() throws {
        let past = Date(timeIntervalSince1970: 1_577_000_000)
        let old = try temporaryFile([assistantLine(branch: nil, timestamp: past)])
        defer { try? FileManager.default.removeItem(at: old) }
        #expect(!TranscriptFold().pump(url: old).contains {
            if case .activityStamps = $0.kind { return true }
            return false
        })

        let today = try temporaryFile([assistantLine(branch: nil, timestamp: Date())])
        defer { try? FileManager.default.removeItem(at: today) }
        #expect(TranscriptFold().pump(url: today).contains {
            if case .activityStamps = $0.kind { return true }
            return false
        })
    }
}
