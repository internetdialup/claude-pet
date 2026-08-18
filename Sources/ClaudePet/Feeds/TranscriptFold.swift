import Foundation

/// Folds a Claude Code transcript tail into `ActivityEvent`s.
///
/// **Bounded reads are a correctness requirement, not an optimisation**
/// (the redline). Transcripts reach 85 MB; a full read is a hang, not a slow
/// path. This type keeps a byte offset and only ever reads forward from it, and
/// on first attach it seeks to the last `initialWindow` bytes.
public final class TranscriptFold {
    /// How far back to look when attaching to an already-running session.
    public static let initialWindow: UInt64 = 64 * 1024
    /// Ceiling on a single incremental read, so a burst cannot balloon memory.
    public static let maxChunk: UInt64 = 2 * 1024 * 1024

    private var offset: UInt64 = 0
    private var attached = false
    /// Partial trailing line carried to the next read.
    private var carry = Data()

    /// Tool calls seen without a matching result yet, newest last.
    ///
    /// Bounded: a tool call whose result never arrives — an interrupted turn, a
    /// session killed mid-run — would otherwise leave an entry here forever, and
    /// on a long-lived pet that is an unbounded array and a permanently skewed
    /// name for every later `toolFinished`.
    private(set) var pendingTools: [String] = []
    static let maxPendingTools = 32

    public init() {}

    /// Read whatever is new and return the events it implies.
    public func pump(url: URL) -> [ActivityEvent] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return [] }

        if !attached {
            attached = true
            offset = size > Self.initialWindow ? size - Self.initialWindow : 0
            carry = Data()
            // Only when we actually seeked did we land mid-line. Starting at 0
            // means the first line is whole and must not be thrown away.
            skipLeadingFragment = offset > 0
        } else if size < offset {
            // File was truncated or replaced — restart from the new end.
            offset = size > Self.initialWindow ? size - Self.initialWindow : 0
            carry = Data()
            skipLeadingFragment = offset > 0
        }

        guard size > offset else { return [] }
        let wanted = min(size - offset, Self.maxChunk)
        // If a burst exceeded the cap, skip ahead rather than fall behind forever.
        if size - offset > Self.maxChunk {
            offset = size - Self.maxChunk
            carry = Data()
        }

        try? handle.seek(toOffset: offset)
        guard let chunk = try? handle.read(upToCount: Int(wanted)), !chunk.isEmpty else { return [] }
        offset += UInt64(chunk.count)

        var buffer = carry
        buffer.append(chunk)
        carry = Data()

        var lines = buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        // The final element is either an incomplete line or empty; carry it over.
        if let last = lines.popLast() { carry = Data(last) }

        // We seeked into the middle of a line; discard that fragment.
        if skipLeadingFragment {
            skipLeadingFragment = false
            if !lines.isEmpty { lines.removeFirst() }
        }

        var events: [ActivityEvent] = []
        for line in lines where !line.isEmpty {
            events.append(contentsOf: parse(Data(line)))
        }
        return events
    }

    private var skipLeadingFragment = false
    /// Emit a `.model` event only when it actually changes — every assistant
    /// line carries the model, and republishing it per line would be noise.
    private var lastModel: String?
    /// Same rationale as `lastModel`: the branch is on every line, so only its
    /// changes are worth reporting.
    private var lastBranch: String?

    // MARK: - Line parsing

    /// Only the fields the pet needs. Anything else in the line is ignored, which
    /// keeps this resilient to Claude Code adding event types.
    private func parse(_ line: Data) -> [ActivityEvent] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String
        else { return [] }

        let sessionID = object["sessionId"] as? String ?? ""
        let timestamp = (object["timestamp"] as? String).flatMap(isoFormatter.date(from:)) ?? Date()

        switch type {
        case "custom-title":
            if let title = object["customTitle"] as? String {
                return [ActivityEvent(sessionID: sessionID, kind: .title(title), timestamp: timestamp)]
            }
        case "ai-title":
            if let title = object["aiTitle"] as? String {
                return [ActivityEvent(sessionID: sessionID, kind: .title(title), timestamp: timestamp)]
            }
        case "assistant":
            var events: [ActivityEvent] = []
            // `gitBranch` rides on every transcript line and was being discarded.
            if let branch = object["gitBranch"] as? String, !branch.isEmpty, branch != lastBranch {
                lastBranch = branch
                events.append(ActivityEvent(sessionID: sessionID, kind: .branch(branch), timestamp: timestamp))
            }
            // Every assistant line is a moment Claude was working. Collected so
            // "coding Nh today" is measured rather than guessed.
            if Calendar.current.isDateInToday(timestamp) {
                events.append(ActivityEvent(sessionID: sessionID,
                                            kind: .activityStamps([timestamp]),
                                            timestamp: timestamp))
            }
            events.append(contentsOf: parseAssistant(object, sessionID: sessionID, timestamp: timestamp))
            return events
        case "user":
            return parseUser(object, sessionID: sessionID, timestamp: timestamp)
        default:
            break
        }
        return []
    }

    private func parseAssistant(_ object: [String: Any], sessionID: String, timestamp: Date) -> [ActivityEvent] {
        guard let message = object["message"] as? [String: Any] else { return [] }
        let blocks = message["content"] as? [[String: Any]] ?? []

        var sawThinking = false
        var events: [ActivityEvent] = []

        if let model = message["model"] as? String, model != lastModel {
            lastModel = model
            events.append(ActivityEvent(sessionID: sessionID, kind: .model(model), timestamp: timestamp))
        }

        for block in blocks {
            switch block["type"] as? String {
            case "thinking":
                sawThinking = true
            case "tool_use":
                let name = block["name"] as? String ?? "tool"
                let input = block["input"] as? [String: Any] ?? [:]
                let detail = (input["description"] as? String)
                    ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? (input["pattern"] as? String)
                    ?? (input["command"] as? String)
                    ?? (input["query"] as? String)
                // An ExitPlanMode call with no result yet means Claude has
                // written a plan and is blocked on the human.
                if name == "ExitPlanMode" {
                    events.append(ActivityEvent(sessionID: sessionID,
                                                kind: .awaitingApproval(true),
                                                timestamp: timestamp))
                }
                pendingTools.append(name)
                if pendingTools.count > Self.maxPendingTools { pendingTools.removeFirst() }
                events.append(ActivityEvent(sessionID: sessionID,
                                            kind: .toolStarted(name: name, detail: detail,
                                                               command: input["command"] as? String),
                                            timestamp: timestamp))
            default:
                break
            }
        }

        if events.isEmpty {
            if message["stop_reason"] as? String == "end_turn" {
                events.append(ActivityEvent(sessionID: sessionID, kind: .turnEnded, timestamp: timestamp))
            } else if sawThinking {
                events.append(ActivityEvent(sessionID: sessionID, kind: .thinking, timestamp: timestamp))
            }
        }
        return events
    }

    private func parseUser(_ object: [String: Any], sessionID: String, timestamp: Date) -> [ActivityEvent] {
        // A tool_result closes the most recent outstanding tool call.
        guard let message = object["message"] as? [String: Any],
              let blocks = message["content"] as? [[String: Any]]
        else { return [] }

        var events: [ActivityEvent] = []
        for block in blocks where block["type"] as? String == "tool_result" {
            let name = pendingTools.isEmpty ? "tool" : pendingTools.removeFirst()
            if name == "ExitPlanMode" {
                events.append(ActivityEvent(sessionID: sessionID,
                                            kind: .awaitingApproval(false),
                                            timestamp: timestamp))
            }
            events.append(ActivityEvent(sessionID: sessionID,
                                        kind: .toolFinished(name: name),
                                        timestamp: timestamp))
        }
        return events
    }

    /// Per-instance rather than shared: `ISO8601DateFormatter` is not `Sendable`,
    /// and one fold per session means no contention anyway.
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
