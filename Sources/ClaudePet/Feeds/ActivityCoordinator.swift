import Foundation

/// Owns one `TranscriptFold` per session.
///
/// Exists so transcript reading and JSON parsing can happen off the main actor.
/// Safety: every method is only ever called from `ActivityCoordinator.queue`,
/// a serial queue, which is this type's isolation.
final class FoldStore: @unchecked Sendable {
    private var folds: [String: TranscriptFold] = [:]

    func create(_ id: String) -> TranscriptFold {
        let fold = TranscriptFold()
        folds[id] = fold
        return fold
    }

    func pump(_ id: String, url: URL) -> [ActivityEvent] {
        folds[id]?.pump(url: url) ?? []
    }

    func remove(_ id: String) {
        folds.removeValue(forKey: id)
    }

    func removeAll() {
        folds.removeAll()
    }
}

/// The single reducer. Every feed hands it `ActivityEvent`s; it owns the session
/// table and publishes one `PetState`.
///
/// Main-actor isolated on purpose: this drives the UI, the state is small, and a
/// single owner removes any question about which feed won a race.
@MainActor
public final class ActivityCoordinator {
    public private(set) var state: PetState = .sleeping
    public var onChange: ((PetState) -> Void)?
    /// Fired when a session newly needs attention or newly finishes, for sound
    /// and notifications. Not fired on every state recomputation.
    public var onAlert: ((PetMood, ClaudeSession) -> Void)?

    private var sessions: [String: ClaudeSession] = [:]
    private var transcriptWatchers: [String: FileWatcher] = [:]
    private var taskWatchers: [String: FileWatcher] = [:]
    private var sessionsWatcher: FileWatcher?
    private var hookServer: HookServer?
    private var decayTimer: Timer?

    /// Where all file reading and JSON parsing happens. Nothing touching a disk
    /// runs on the main actor.
    nonisolated let queue = DispatchQueue(label: "com.internetdialup.claude-pet.feeds")
    /// Per-session transcript readers, confined to `queue`.
    nonisolated let folds = FoldStore()

    /// How long `done` shows before decaying back to `idle`.
    ///
    /// A deliberate celebration beat. It is not new — it simply never ran,
    /// because the 2s workload poll kept `lastActivity` fresher than 6s.
    static var doneDecay: TimeInterval = 6

    /// The celebrated done: a cooking sprint that lands plays a ~10s payoff
    /// (the game-design trick — the work is finished, the reward runs longer),
    /// so the decay waits for the animation plus a beat of afterglow.
    static var celebrationDecay: TimeInterval = 12

    /// The completion badge's lifetime, and when inside it the reminder nudges
    /// fire (a wave + the banner back for a few seconds, twice). The badge
    /// itself is the view's business; these constants keep the coordinator's
    /// bubble nudges and the view's wave on one clock.
    nonisolated static let badgeLifetime: TimeInterval = 300
    nonisolated static let nudgeWindows: [TimeInterval] = [90, 210]
    nonisolated static let nudgeDuration: TimeInterval = 4

    /// How long the thinking dots may pulse without renewal before the bubble
    /// retires (the `.thinking` mood itself lives on until `staleAfter`).
    /// "Still thinking" is a claim; thirty quiet seconds is where it stops
    /// being one the pet can stand behind.
    static var dotsQuietAfter: TimeInterval = 30

    /// How long a session may sit in a *working* mood, silent, before the pet
    /// stops asserting it and falls back to `idle`.
    ///
    /// Measured rather than picked, over 79 local transcripts and ~65k
    /// intra-turn gaps: silence between a `tool_result` and the next assistant
    /// message runs p50 8s, p90 23s, p99 61s, p99.9 183s, with the longest
    /// genuine stretch of continuous reasoning at 275s. Every gap beyond ~500s
    /// is resume-shaped — a session picked up hours later. 300 therefore sits
    /// just above the observed ceiling of real thinking and misfires on roughly
    /// one gap in 3000.
    static var staleAfter: TimeInterval = 300

    /// The same, for `.working`, which has a genuinely fatter tail.
    ///
    /// `tool_use → tool_result` includes long builds and human permission
    /// waits: p99 244s, and 0.86% of calls exceed 300s. The honest p99.9 is
    /// 2909s, which is useless as a timeout, so this is a compromise rather
    /// than a measurement — 600 halves the misfire rate to 0.36% and costs only
    /// five extra minutes in the rare stranded case. The asymmetry is what
    /// makes it safe: a real tool always eventually delivers its result and
    /// snaps the pet back within one tick, whereas a stranded session never
    /// recovers on its own.
    static var workingStaleAfter: TimeInterval = 600

    /// The same, for `.needsAttention`.
    ///
    /// Unlike the others this is a policy choice, not a measurement, and it is
    /// deliberately long. `.needsAttention` means Claude is blocked on the
    /// human, which is precisely the state you want still flagged when you come
    /// back from lunch — decaying it on the 300s horizon would quietly drop the
    /// ‼️ during an ordinary break and lose the one thing the pet is for.
    ///
    /// It does need *some* limit: it carries the highest urgency, so a prompt
    /// answered outside the pet's view leaves a session that outranks every live
    /// one for the face, forever. Thirty minutes keeps a real block visible
    /// across any plausible break while still clearing a stale one inside the
    /// hour.
    static var attentionStaleAfter: TimeInterval = 1800

    /// No activity anywhere for this long and the crab sleeps.
    ///
    /// Raised from 300 because `staleAfter` now occupies that slot: at equal
    /// values a stranded session would skip `idle` entirely and go straight to
    /// sleep, so the idle chatter and status ticker — the thing issue #2's
    /// reporter had never once seen — would stay unreachable. 900 is also the
    /// better number on its own terms: turn-end to next human prompt has a
    /// median park of 180s and 40% of ordinary parks exceed 300s, so a 300s nap
    /// would fire during two-fifths of normal think-breaks. At 900 only 19% are
    /// longer, and those are genuine walk-aways.
    static var sleepAfter: TimeInterval = 900
    /// How long one idle line stays on screen before a new one is chosen.
    private static let chatterInterval: TimeInterval = 14
    /// How far back the tool-rate window looks.
    nonisolated static let toolRateWindow: TimeInterval = 60
    /// Tool calls within that window before he catches fire.
    ///
    /// Measured on real transcripts: an ordinary main session runs a median of 4
    /// tool calls a minute with a 90th percentile of 7, while a fanned-out
    /// workflow runs a median of 22. Eight sits in the gap, so routine work does
    /// not trip it and a genuine sprint does.
    nonisolated static let cookingToolRate = 8


    /// The idle line currently on screen, and when it was chosen.
    private var chatter: (text: String, isMarquee: Bool)?
    private var chatterChosenAt: Date = .distantPast

    public init() {}

    public func start() {
        refreshSessions()

        sessionsWatcher = FileWatcher(url: ClaudeHome.sessions, queue: queue, coalesce: 0.25) { [weak self] in
            Task { @MainActor in self?.refreshSessions() }
        }

        hookServer = HookServer { [weak self] events in
            Task { @MainActor in self?.ingest(events) }
        }
        hookServer?.start()

        // Re-evaluates decay (done → idle, idle → sleeping), reaps dead PIDs, and
        // refreshes the subagent count that drives the cooking state.
        decayTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reapDeadSessions()
                self.refreshWorkload()
                self.recompute()
            }
        }
    }

    public func stop() {
        sessionsWatcher?.cancel()
        transcriptWatchers.values.forEach { $0.cancel() }
        taskWatchers.values.forEach { $0.cancel() }
        transcriptWatchers.removeAll()
        taskWatchers.removeAll()
        hookServer?.stop()
        decayTimer?.invalidate()
        queue.async { [folds] in folds.removeAll() }
    }

    /// User pinned (or unpinned) a session from the roster.
    public func pin(sessionID: String?) {
        Preferences.shared.pinnedSessionID = sessionID
        recompute()
    }

    // MARK: - Session table

    private func refreshSessions() {
        let live = SessionRegistry.liveSessions()
        let liveIDs = Set(live.map(\.id))

        for session in live where sessions[session.id] == nil {
            var new = session
            new.lastActivity = Date()
            sessions[session.id] = new
            attachFeeds(to: new)
        }

        for id in sessions.keys where !liveIDs.contains(id) {
            detachFeeds(from: id)
            sessions.removeValue(forKey: id)
        }

        recompute()
    }

    private func reapDeadSessions() {
        let dead = sessions.values.filter { !SessionRegistry.isAlive(pid: $0.pid, procStart: $0.procStart) }
        guard !dead.isEmpty else { return }
        for session in dead {
            detachFeeds(from: session.id)
            sessions.removeValue(forKey: session.id)
        }
    }

    private func attachFeeds(to session: ClaudeSession) {
        let transcriptURL = session.transcriptURL
        let id = session.id

        // Prime from whatever is already on disk so a session started before the
        // pet still shows a title and a current tool immediately. On the feed
        // queue: with ten sessions this used to be ten transcript reads plus ten
        // task-directory enumerations on the main thread before the first frame.
        //
        // Alerts are suppressed for this pass — the tail almost always contains a
        // finished turn, and replaying it would chirp and post a notification for
        // work that completed before the pet even launched.
        let tasksDirectory = session.tasksDirectory
        queue.async { [weak self] in
            guard let self else { return }
            _ = self.folds.create(id)
            var events = self.folds.pump(id, url: transcriptURL)
            if let active = TaskWatcher.activeTask(in: tasksDirectory) {
                events.append(ActivityEvent(sessionID: id, kind: .activeTask(active)))
            }
            if let progress = TaskWatcher.progress(in: tasksDirectory) {
                events.append(ActivityEvent(sessionID: id,
                                            kind: .taskProgress(completed: progress.completed,
                                                                total: progress.total)))
            }
            guard !events.isEmpty else { return }
            Task { @MainActor in self.ingest(events, suppressAlerts: true) }
        }

        // The parse runs on the feed queue; only the resulting events cross to
        // the main actor. Doing `fold.pump` inside `Task { @MainActor }` meant a
        // 2 MB read plus per-line JSON parsing blocked the UI — measured at
        // 38-50ms per burst, which is three dropped frames while he animates.
        // Each fold is owned by exactly one session and only touched here, so
        // the serial queue is its isolation.
        transcriptWatchers[id] = FileWatcher(url: transcriptURL, queue: queue) { [weak self] in
            guard let self else { return }
            let events = self.folds.pump(id, url: transcriptURL)
            guard !events.isEmpty else { return }
            Task { @MainActor in self.ingest(events) }
        }

        let tasksURL = session.tasksDirectory
        // Watch the parent when the tasks directory does not exist yet, so a
        // session that has not created todos still gets picked up later. Waiting
        // for it to exist at attach time was a one-shot race the session usually
        // lost.
        let watchURL = FileManager.default.fileExists(atPath: tasksURL.path) ? tasksURL : ClaudeHome.tasks
        taskWatchers[id] = FileWatcher(url: watchURL, queue: queue, coalesce: 0.2) { [weak self] in
            guard let self else { return }
            let label = TaskWatcher.activeTask(in: tasksURL)
            let progress = TaskWatcher.progress(in: tasksURL)
            Task { @MainActor in
                var events = [ActivityEvent(sessionID: id, kind: .activeTask(label))]
                if let progress {
                    events.append(ActivityEvent(sessionID: id,
                                                kind: .taskProgress(completed: progress.completed,
                                                                    total: progress.total)))
                }
                self.ingest(events)
            }
        }
    }

    private func detachFeeds(from id: String) {
        transcriptWatchers.removeValue(forKey: id)?.cancel()
        taskWatchers.removeValue(forKey: id)?.cancel()
        queue.async { [folds] in folds.remove(id) }
    }

    // MARK: - Reduction

    public func ingest(_ events: [ActivityEvent], suppressAlerts: Bool = false) {
        guard !events.isEmpty else { return }
        var alerts: [(PetMood, ClaudeSession)] = []

        for event in events {
            guard var session = sessions[event.sessionID] else { continue }
            let previousMood = session.mood
            // Only Claude's own doings advance the clock. The 2s workload poll
            // emits for every session whether or not the count moved, and
            // counting it kept `lastActivity` permanently fresh — see
            // `ActivityEvent.countsAsActivity`.
            if event.countsAsActivity {
                session.lastActivity = max(session.lastActivity, event.timestamp)
            }

            switch event.kind {
            case .thinking:
                session.mood = .thinking
                session.tool = nil
                session.completionBadgeAt = nil     // new work consumes the marker
            case .toolStarted(let name, let detail):
                session.mood = .working
                session.tool = name
                session.completionBadgeAt = nil     // new work consumes the marker
                // A rolling window of recent calls — how *hard* he is going.
                session.recentToolCalls.append(event.timestamp)
                let cutoff = event.timestamp.addingTimeInterval(-Self.toolRateWindow)
                session.recentToolCalls.removeAll { $0 < cutoff }
                if session.activeTaskLabel == nil {
                    session.activity = detail.map { Self.condense($0) } ?? name
                }
            case .toolFinished:
                // Between tools Claude is reasoning about the result.
                if session.mood == .working { session.mood = .thinking }
                session.tool = nil
            case .turnEnded:
                // A sprint that lands earns a longer bow: the celebration flag
                // stretches the done pose's decay and unlocks its payoff
                // animation. `.cooking` is a display-time promotion — the
                // session record itself never stores it — so the edge is
                // detected the same way the promotion is: was he working at a
                // cooking pace when the turn ended?
                session.celebrating = session.mood == .working
                    && Self.isCooking(session, now: event.timestamp)
                // A turn end can arrive twice — the transcript fold and the
                // Stop hook — so the first stamp of this turn wins; a genuine
                // new turn always passes through thinking/working first, which
                // clears it. On the priming replay this carries a historical
                // timestamp: launching the pet within five minutes of an old
                // completion shows the badge, which is the feature ("finished
                // while you were away"), not an accident.
                if session.mood != .done {
                    session.completionBadgeAt = event.timestamp
                }
                session.mood = .done
                session.tool = nil
                // Clear the last tool's description too. Leaving it set meant an
                // idle session displayed "List worktree contents…" indefinitely,
                // and there was never a "no task" moment for a shout-out to fill.
                session.activity = nil
            case .needsAttention(let reason):
                session.mood = .needsAttention
                session.activity = Self.condense(reason)
            case .activeTask(let label):
                session.activeTaskLabel = label
                if let label { session.activity = label }
            case .taskProgress(let completed, let total):
                session.tasksCompleted = completed
                session.tasksTotal = total
            case .title(let title):
                session.title = title
            case .subagents(let count):
                session.subagentCount = count
            case .model(let model):
                session.model = model
            case .awaitingApproval(let waiting):
                session.awaitingApproval = waiting
            case .branch(let branch):
                session.branch = branch
            case .activityStamps(let stamps):
                // Span from the first to the last assistant message today. A
                // measured window, not a sum of guessed session lengths.
                for stamp in stamps {
                    session.firstActivityToday = min(session.firstActivityToday ?? stamp, stamp)
                    session.lastActivityToday = max(session.lastActivityToday ?? stamp, stamp)
                }
                if let first = session.firstActivityToday, let last = session.lastActivityToday {
                    session.activeHoursToday = last.timeIntervalSince(first) / 3600
                }
            case .ended:
                detachFeeds(from: session.id)
                sessions.removeValue(forKey: session.id)
                continue
            }

            // The celebration belongs to the done pose alone; any move off it
            // takes the flag along.
            if session.mood != .done { session.celebrating = false }

            sessions[session.id] = session
            // Only moods that `NotificationNudge` knows how to announce, and
            // only on a real transition — not on every recomputation.
            if session.mood != previousMood,
               NotificationNudge.event(for: session.mood) != nil {
                alerts.append((session.mood, session))
            }
        }

        recompute()
        guard !suppressAlerts else { return }
        // Only alert for sessions that still exist — one could have ended later
        // in the same batch.
        for alert in alerts where sessions[alert.1.id] != nil {
            onAlert?(alert.0, alert.1)
        }
    }

    /// How long `mood` may go unrenewed before the pet stops asserting it.
    ///
    /// `nil` means the mood expires on nothing:
    /// - `.idle` is already the floor — there is nowhere below it to decay to.
    /// - `.sleeping` is derived at display time from `lastActivity`, not stored.
    /// - `.nudging` is likewise derived, from `awaitingApproval`; it clears when
    ///   the mood underneath it decays and takes the flag with it.
    static func quietLimit(for mood: PetMood, celebrating: Bool = false) -> TimeInterval? {
        switch mood {
        // A celebrated done holds for the whole payoff animation (~10s) plus a
        // beat of afterglow; a plain done keeps its quick exit.
        case .done: celebrating ? celebrationDecay : doneDecay
        case .working: workingStaleAfter
        case .needsAttention: attentionStaleAfter
        case .thinking, .cooking: staleAfter
        case .idle, .nudging, .sleeping: nil
        }
    }

    private func recompute() {
        let now = Date()

        // Decay. A mood is an assertion about what Claude is doing right now,
        // and an assertion nothing has renewed eventually stops being true.
        //
        // This is deliberately one route-independent rule rather than a special
        // case per way-of-getting-stuck. The known strandings — an ESC'd tool,
        // a turn whose end marker fell outside the bounded tail, a session
        // adopted mid-turn at launch — all leave a mood nothing will ever
        // clear, and the list is certainly incomplete. A timeout recovers from
        // the ones nobody has found yet.
        for (id, var session) in sessions {
            guard let limit = Self.quietLimit(for: session.mood, celebrating: session.celebrating),
                  now.timeIntervalSince(session.lastActivity) > limit else { continue }
            session.mood = .idle
            session.celebrating = false
            // The mood alone is not the assertion — the bubble is. Leaving any
            // of these set keeps stale text on screen after the pose relaxes:
            // `activeTaskLabel` outranks everything when the bubble is chosen,
            // and a stale `awaitingApproval` re-pins the display to `.nudging`
            // no matter what the mood says.
            session.tool = nil
            session.activity = nil
            session.activeTaskLabel = nil
            session.awaitingApproval = false
            sessions[id] = session
        }

        let ordered = sessions.values.sorted { lhs, rhs in
            if lhs.mood.urgency != rhs.mood.urgency { return lhs.mood.urgency > rhs.mood.urgency }
            return lhs.lastActivity > rhs.lastActivity
        }

        guard !ordered.isEmpty else {
            publish(.sleeping)
            return
        }

        // A pin wins; otherwise the most urgent-then-recent session gets the face.
        let pinned = Preferences.shared.pinnedSessionID.flatMap { id in ordered.first { $0.id == id } }
        let focus = pinned ?? ordered[0]

        var mood = focus.mood
        if mood != .needsAttention,
           now.timeIntervalSince(focus.lastActivity) > Self.sleepAfter {
            mood = .sleeping
        }

        // A plan on screen outranks the work that produced it — nothing moves
        // until the human answers.
        if focus.awaitingApproval, mood != .needsAttention, mood != .sleeping {
            mood = .nudging
        } else if mood == .working, Self.isCooking(focus, now: now) {
            mood = .cooking
        }

        let task = focus.activeTaskLabel ?? focus.activity ?? focus.title
        var bubble = task.map { Self.condense($0) }
        var style = PetState.BubbleStyle.plain

        // Precedence, documented at the top of `vocab.swift`:
        //   1. a rule matching the current task
        //   2. the real task text, whenever there is one
        //   3. this state's own lines
        // Point 2 is why `working` and `cooking` lines appear only in the gaps:
        // a pet that hides "Running the test suite" behind a joke is worse.
        let seed = Int(now.timeIntervalSince1970 / Self.chatterInterval)

        switch mood {
        case .thinking:
            // No honest label exists for "reasoning", so show pulsing dots
            // rather than repeating the last thing he did — but only while
            // the claim is fresh. The mood itself decays on `staleAfter`
            // (300s), and dots pulsing over a quiet session for minutes are
            // exactly the lingering banner the quiet-done round removed:
            // after 30 unrenewed seconds the bubble retires and the pose
            // (sparkles, scanning eyes) carries the state; the next
            // transcript write brings the dots straight back.
            let fresh = now.timeIntervalSince(focus.lastActivity) < Self.dotsQuietAfter
            bubble = fresh ? "…" : nil
            style = fresh ? .dots : .plain
            chatter = nil

        case .sleeping:
            // Occasionally talks in his sleep. A sleeping pet that comments on
            // every frame is not asleep.
            bubble = seed % 4 == 0 ? Vocab.line(for: .sleeping, seed: seed) : nil
            chatter = nil

        // A title is what a session *is*, not what it is *doing*. Gating on
        // `task == nil` meant any titled session — which is most of them — kept
        // showing its title forever and never reached the ticker.
        case .idle where focus.activeTaskLabel == nil && focus.activity == nil:
            // Nothing to report — encouragement, or a status ticker.
            var snapshot = StatusTicker.Snapshot()
            snapshot.model = focus.model
            snapshot.branch = focus.branch
            snapshot.project = focus.projectName
            snapshot.sessionCount = ordered.count
            snapshot.activeHoursToday = focus.activeHoursToday
            let line = idleChatter(snapshot: snapshot, now: now)
            bubble = line.text
            style = line.isMarquee ? .marquee : .plain

        default:
            chatter = nil
            if let task, Vocab.rule(matching: task) != nil {
                // A rule claimed this task.
                bubble = Vocab.line(for: mood.shoutoutOccasion, matching: task, seed: seed)
            } else if let task {
                bubble = Self.condense(task)
            } else {
                bubble = Vocab.line(for: mood.shoutoutOccasion, seed: seed)
            }
        }

        // The near-done glow needs a real list behind it: three or more tasks,
        // quantised so the equality-gated publish does not churn on re-reads.
        var taskFraction: Double?
        if let done = focus.tasksCompleted, let total = focus.tasksTotal, total >= 3 {
            taskFraction = (Double(done) / Double(total) / 0.05).rounded() * 0.05
        }

        // The reminder nudge: inside the badge's five minutes, twice, the
        // banner pops back with a finished line for a few seconds (the view
        // waves on the same clock). Idle-only, so a plan awaiting a verdict
        // or a blocked session always outranks a reminder. Slotted after the
        // mood switch so `idleChatter`'s cache is untouched and the ticker
        // resumes cleanly when the window closes. The seed is derived from
        // the completion instant, not the chatter clock — a window that
        // straddles a chatter re-roll must not swap its sentence mid-air.
        if mood == .idle, let completedAt = focus.completionBadgeAt {
            let age = now.timeIntervalSince(completedAt)
            for (index, windowStart) in Self.nudgeWindows.enumerated()
            where age >= windowStart && age < windowStart + Self.nudgeDuration {
                bubble = Vocab.line(for: .finished,
                                    seed: Int(completedAt.timeIntervalSince1970) + index)
                style = .plain
            }
        }

        publish(PetState(
            mood: mood,
            bubble: bubble,
            tool: focus.tool,
            sessions: ordered,
            focusedSessionID: focus.id,
            attentionCount: ordered.filter { $0.mood == .needsAttention && $0.id != focus.id }.count,
            bubbleStyle: style,
            taskFraction: taskFraction,
            celebrating: mood == .done && focus.celebrating,
            completedAt: focus.completionBadgeAt
        ))
    }

    // MARK: - Idle chatter

    /// Encouragement, with an occasional scrolling status read-out.
    ///
    /// Held for `chatterInterval` rather than re-rolled on every `recompute()`
    /// — this runs on the 2s decay timer, so choosing per call would rewrite the
    /// sentence out from under the reader three times before they finished it.
    private func idleChatter(snapshot: StatusTicker.Snapshot,
                             focusTask: String? = nil,
                             now: Date) -> (text: String, isMarquee: Bool) {
        if let current = chatter, now.timeIntervalSince(chatterChosenAt) < Self.chatterInterval {
            return current
        }

        let seed = Int(now.timeIntervalSince1970 / Self.chatterInterval)
        let status = StatusTicker.lines(for: snapshot, now: now)

        // Roughly every third turn is a status ticker, when one is available.
        let next: (String, Bool)
        if !status.isEmpty, seed % 3 == 2 {
            next = (status[(seed / 3) % status.count], true)
        } else {
            // The shuffled cycle already guarantees no immediate repeat, so
            // `avoiding` is gone; `task` lets a rule claim the line instead.
            let line = Vocab.line(for: .idle, matching: focusTask, seed: seed)
            next = (line ?? "Ready when you are", false)
        }

        chatter = next
        chatterChosenAt = now
        return next
    }

    private func publish(_ new: PetState) {
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    /// Recount in-flight subagents for every live session.
    ///
    /// Runs on the feed queue — it touches the filesystem, and nothing that
    /// touches a disk belongs on the main actor. This finally constructs the
    /// `.subagents` event, which the model has always consumed but which nothing
    /// had ever emitted, leaving `subagentCount` permanently zero.
    private func refreshWorkload() {
        let targets = sessions.values.map { (id: $0.id, directory: $0.subagentsDirectory) }
        guard !targets.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let counts = targets.map {
                ($0.id, WorkloadWatcher.agentsInFlight(subagents: $0.directory, now: now))
            }
            let events = counts.map {
                ActivityEvent(sessionID: $0.0, kind: .subagents($0.1), timestamp: now)
            }
            Task { @MainActor in self.ingest(events) }
        }
    }

    /// Is this session going hard right now?
    ///
    /// Either signal is enough: a rapid burst of tool calls, or a live fan-out of
    /// subagents. They catch different shapes of intensity — a tight edit loop
    /// versus a workflow — and neither implies the other.
    nonisolated static func isCooking(_ session: ClaudeSession, now: Date) -> Bool {
        if session.subagentCount > 0 { return true }
        let cutoff = now.addingTimeInterval(-toolRateWindow)
        return session.recentToolCalls.filter { $0 >= cutoff }.count >= cookingToolRate
    }

    /// Squeeze a shell command or long description into bubble-sized text.
    /// Pure string work — no actor state, so it needs no isolation.
    nonisolated static func condense(_ raw: String, limit: Int = 46) -> String {
        let flat = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)) + "…"
    }
}
