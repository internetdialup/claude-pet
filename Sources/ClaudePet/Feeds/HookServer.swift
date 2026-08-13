import Foundation

/// Receives push events from the Claude Code hook shim.
///
/// The shim appends one JSON file per event into `~/.claude/claude-pet-events/`
/// and this watches that directory. A drop-directory rather than a socket,
/// deliberately: the redline requires the pet never block Claude, and a
/// failed `nc -U` to a dead socket can stall a hook, whereas a failed file write
/// cannot. The shim exits 0 unconditionally either way.
///
/// Safety: `watcher` is only assigned in `start()`/`stop()`, both called from the
/// main actor; `drain()` runs exclusively on the serial `queue`. There is no
/// shared mutable state between the two.
public final class HookServer: @unchecked Sendable {
    private var watcher: FileWatcher?
    private let queue = DispatchQueue(label: "com.internetdialup.claude-pet.hooks")
    private let onEvents: @Sendable ([ActivityEvent]) -> Void

    public init(onEvents: @escaping @Sendable ([ActivityEvent]) -> Void) {
        self.onEvents = onEvents
    }

    public func start() {
        let fm = FileManager.default
        // Creating our own drop directory is not a write to Claude's state; no
        // Claude Code file is read or modified here.
        try? fm.createDirectory(at: ClaudeHome.events, withIntermediateDirectories: true)
        drain()
        watcher = FileWatcher(url: ClaudeHome.events, queue: queue, coalesce: 0.05) { [weak self] in
            self?.drain()
        }
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
    }

    /// Consume and delete every queued event file.
    private func drain() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: ClaudeHome.events, includingPropertiesForKeys: nil)
        else { return }

        var events: [ActivityEvent] = []
        let now = Date()

        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // `.partial` scratch files belong to a shim that is still writing.
            guard url.pathExtension == "json" else {
                reapIfAbandoned(url, now: now, fileManager: fm)
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
            events.append(event)
        }
        guard !events.isEmpty else { return }
        onEvents(events)
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
    /// event. Unknown shapes are dropped rather than guessed at.
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
                ?? (input["pattern"] as? String)
                ?? (input["command"] as? String)
            return ActivityEvent(sessionID: sessionID, kind: .toolStarted(name: tool, detail: detail))
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
