import Foundation

/// Counts the subagents a session currently has in flight.
///
/// This is what proves Claude is *fanning out* rather than merely working, and
/// it is the on-disk signature of an "ultracode" run — that keyword is simply the
/// trigger for a dynamic workflow, and leaves no field of its own anywhere.
///
/// Measured against a live run while building this: a workflow's journal read
/// 3 started / 0 result while three agents were genuinely working.
public enum WorkloadWatcher {

    /// Ceiling on a journal read. Reading one whole is a deliberate, bounded
    /// exception to the tail-only rule — the in-flight count
    /// needs both ends of the file, so a tail cannot answer it — and this cap is
    /// what keeps the exception enforceable rather than a promise.
    ///
    /// Sized against reality, not assumption: a real 13-agent journal on this
    /// machine measured **413 KB**, because every `result` line embeds that
    /// agent's entire return value. An earlier 256 KB cap would have skipped
    /// precisely the long fan-outs this is meant to catch.
    static let maxJournalBytes = 8 * 1024 * 1024

    /// An agent transcript touched more recently than this counts as alive.
    /// Generous because an agent goes quiet while a long tool call runs.
    static let liveWindow: TimeInterval = 180

    /// How many agents are working for this session right now.
    ///
    /// - Parameter subagents: the session's `subagents/` directory.
    public static func agentsInFlight(subagents: URL, now: Date = Date()) -> Int {
        let workflows = subagents.appendingPathComponent("workflows")
        let fromJournals = workflowAgentsInFlight(workflows: workflows, now: now)
        // Plain `Task` subagents have no journal, so fall back to counting live
        // transcripts. Whichever sees more is the honest answer.
        return max(fromJournals, liveAgentTranscripts(subagents: subagents, now: now))
    }

    /// `started` minus `result`, summed across every run whose journal is fresh.
    static func workflowAgentsInFlight(workflows: URL, now: Date) -> Int {
        let fm = FileManager.default
        guard let runs = try? fm.contentsOfDirectory(at: workflows, includingPropertiesForKeys: nil)
        else { return 0 }

        var total = 0
        for run in runs {
            let journal = run.appendingPathComponent("journal.jsonl")
            guard let attributes = try? fm.attributesOfItem(atPath: journal.path),
                  let size = attributes[.size] as? Int, size <= maxJournalBytes,
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) < liveWindow,
                  let text = try? String(contentsOf: journal, encoding: .utf8)
            else { continue }
            total += inFlight(inJournal: text)
        }
        return total
    }

    /// Parses a journal's body. Split out so it is testable without a filesystem.
    static func inFlight(inJournal text: String) -> Int {
        var started = 0
        var finished = 0
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }
            if type == "started" { started += 1 }
            if type == "result" { finished += 1 }
        }
        return max(0, started - finished)
    }

    /// Recently-written agent transcripts, searched **recursively**.
    ///
    /// A non-recursive listing of `subagents/` reports zero live agents while
    /// three are running: workflow agents sit one directory deeper.
    static func liveAgentTranscripts(subagents: URL, now: Date) -> Int {
        let fm = FileManager.default
        guard let walker = fm.enumerator(
            at: subagents,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var live = 0
        for case let url as URL in walker {
            let name = url.lastPathComponent
            guard name.hasPrefix("agent-"), name.hasSuffix(".jsonl") else { continue }
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { continue }
            if now.timeIntervalSince(modified) < liveWindow { live += 1 }
        }
        return live
    }
}
