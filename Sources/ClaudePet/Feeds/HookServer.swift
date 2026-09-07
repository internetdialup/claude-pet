import Foundation

/// Receives push events from the Claude Code hook shim.
///
/// The shim drops one JSON file per event into `~/.claude/claude-pet-events/`
/// and this watches that directory. A drop-directory rather than a socket,
/// deliberately: the redline requires the pet never block Claude, and a
/// failed `nc -U` to a dead socket can stall a hook, whereas a failed file write
/// cannot. The shim exits 0 unconditionally either way.
///
/// Each file is the hook's whole payload — tool input and tool output included
/// — and is deleted the moment it is read. Anything over `maxEventBytes` is
/// deleted UNREAD: the redline says every read is bounded, and a complete
/// oversized file arrived by an atomic `mv`, so removing it is not a race and
/// the transcript fold covers the event it carried.
///
/// Concurrency: `watcher` is only assigned in `start()`/`stop()`, both called
/// from the main actor; every `drain()` — the launch-time backlog included —
/// runs on the serial `queue`, so a directory full of files from a session the
/// pet missed never parses on the UI thread.
public final class HookServer: @unchecked Sendable {
    /// The largest event file that will be parsed. Claude Code truncates tool
    /// output before hooks see it, so real payloads are tens of KB; this is a
    /// ceiling, not a budget.
    public static let maxEventBytes = 256 * 1024

    private var watcher: FileWatcher?
    private let queue = DispatchQueue(label: "com.internetdialup.claude-pet.hooks")
    private let events: URL
    private let onEvents: @Sendable ([ActivityEvent]) -> Void

    /// - Parameter events: the drop directory. Defaults to the live one; tests
    ///   hand it a directory under `FileManager.temporaryDirectory`.
    public init(events: URL = ClaudeHome.events,
                onEvents: @escaping @Sendable ([ActivityEvent]) -> Void) {
        self.events = events
        self.onEvents = onEvents
    }

    public func start() {
        let fm = FileManager.default
        // Creating our own drop directory is not a write to Claude's state; no
        // Claude Code file is read or modified here.
        try? fm.createDirectory(at: events, withIntermediateDirectories: true)
        queue.async { [weak self] in self?.drain() }
        watcher = FileWatcher(url: events, queue: queue, coalesce: 0.05) { [weak self] in
            self?.drain()
        }
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
    }

    /// Drains once, synchronously, on the caller's thread — the test seam.
    func drainNow() { drain() }

    /// Consume and delete every queued event file.
    private func drain() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: events,
                                                        includingPropertiesForKeys: [.fileSizeKey])
        else { return }

        var collected: [ActivityEvent] = []
        let now = Date()

        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // `.partial` scratch files belong to a shim that is still writing.
            guard url.pathExtension == "json" else {
                reapIfAbandoned(url, now: now, fileManager: fm)
                continue
            }
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
               size > Self.maxEventBytes {
                try? fm.removeItem(at: url)
                continue
            }

            let data = try? Data(contentsOf: url)
            guard let data, let event = Self.parse(data) else {
                // Do not delete on sight. An unparseable file is either garbage
                // (reap it once it is old) or a real event we raced; deleting it
                // immediately turned a race into a silently dropped event.
                reapIfAbandoned(url, now: now, fileManager: fm)
                continue
            }
            try? fm.removeItem(at: url)
            collected.append(event)
        }
        guard !collected.isEmpty else { return }
        onEvents(collected)
    }

    /// Files older than this are assumed abandoned rather than in flight.
    static let abandonedAfter: TimeInterval = 60

    /// Deletes a file only once it is old enough that no shim can still be
    /// writing it. Keeps the drop directory from filling with junk without
    /// racing a live write.
    private func reapIfAbandoned(_ url: URL, now: Date, fileManager: FileManager) {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        guard let modified, now.timeIntervalSince(modified) > Self.abandonedAfter else { return }
        try? fileManager.removeItem(at: url)
    }

    /// Hook payloads carry `hook_event_name` and `session_id`; the rest varies by
    /// event. Unknown shapes are dropped rather than guessed at. The detail that
    /// reaches the bubble has the home directory abbreviated; the raw command
    /// stays on the event for the service classifier.
    static func parse(_ data: Data) -> ActivityEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String,
              let name = object["hook_event_name"] as? String
        else { return nil }

        switch name {
        case "PreToolUse":
            let tool = object["tool_name"] as? String ?? "tool"
            let input = object["tool_input"] as? [String: Any] ?? [:]
            let detail = (input["description"] as? String)
                ?? (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? (input["pattern"] as? String).map { PathDisplay.abbreviatingHome($0) }
                ?? (input["command"] as? String).map { PathDisplay.abbreviatingHome($0) }
            return ActivityEvent(sessionID: sessionID,
                                 kind: .toolStarted(name: tool, detail: detail,
                                                    command: input["command"] as? String))
        case "PostToolUse":
            return ActivityEvent(sessionID: sessionID,
                                 kind: .toolFinished(name: object["tool_name"] as? String ?? "tool"))
        case "Stop":
            return ActivityEvent(sessionID: sessionID, kind: .turnEnded)
        case "Notification":
            let message = object["message"] as? String ?? "Claude needs you"
            return ActivityEvent(sessionID: sessionID, kind: .needsAttention(reason: message))
        case "SessionEnd":
            return ActivityEvent(sessionID: sessionID, kind: .ended)
        case "UserPromptSubmit":
            return ActivityEvent(sessionID: sessionID, kind: .thinking)
        default:
            return nil
        }
    }
}
