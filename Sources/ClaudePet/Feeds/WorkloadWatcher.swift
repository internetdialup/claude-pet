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

    /// Per-journal memo of the last parse, keyed by path and stamped with the
    /// size and mtime that produced it. The workload poll runs every two
    /// seconds; a journal that has not changed since the last tick is counted
    /// from the memo, not read and parsed line by line again (a real 13-agent
    /// journal is 413 KB — thirty full parses a minute per session, for the
    /// same answer). Thread-safe: the poll runs on the feed queue.
    public final class JournalCache: @unchecked Sendable {
        private struct Entry { let size: Int; let modified: Date; let inFlight: Int }
        private var entries: [URL: Entry] = [:]
        private var parseCount = 0
        private let lock = NSLock()

        public init() {}

        func cached(_ url: URL, size: Int, modified: Date) -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard let entry = entries[url], entry.size == size, entry.modified == modified else { return nil }
            return entry.inFlight
        }

        func remember(_ url: URL, size: Int, modified: Date, inFlight: Int) {
            lock.lock(); defer { lock.unlock() }
            entries[url] = Entry(size: size, modified: modified, inFlight: inFlight)
            parseCount += 1
        }

        /// How many journals have actually been parsed through this cache —
        /// the test seam that proves an unchanged file is not re-read.
        public var parses: Int { lock.lock(); defer { lock.unlock() }; return parseCount }
    }

    /// How many agents are working for this session right now.
    ///
    /// - Parameters:
    ///   - subagents: the session's `subagents/` directory.
    ///   - cache: the parse memo; nil parses every fresh journal.
    public static func agentsInFlight(subagents: URL, now: Date = Date(),
                                      cache: JournalCache? = nil) -> Int {
        let workflows = subagents.appendingPathComponent("workflows")
        let fromJournals = workflowAgentsInFlight(workflows: workflows, now: now, cache: cache)
        // Plain `Task` subagents have no journal, so fall back to counting live
        // transcripts. Whichever sees more is the honest answer.
        return max(fromJournals, liveAgentTranscripts(subagents: subagents, now: now))
    }

    /// `started` minus `result`, summed across every run whose journal is fresh.
    static func workflowAgentsInFlight(workflows: URL, now: Date,
                                       cache: JournalCache? = nil) -> Int {
        let fm = FileManager.default
        guard let runs = try? fm.contentsOfDirectory(at: workflows, includingPropertiesForKeys: nil)
        else { return 0 }

        var total = 0
        for run in runs {
            let journal = run.appendingPathComponent("journal.jsonl")
            guard let attributes = try? fm.attributesOfItem(atPath: journal.path),
                  let size = attributes[.size] as? Int, size <= maxJournalBytes,
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) < liveWindow
            else { continue }
            if let known = cache?.cached(journal, size: size, modified: modified) {
                total += known
                continue
            }
            guard let text = try? String(contentsOf: journal, encoding: .utf8) else { continue }
            let count = inFlight(inJournal: text)
            cache?.remember(journal, size: size, modified: modified, inFlight: count)
            total += count
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
