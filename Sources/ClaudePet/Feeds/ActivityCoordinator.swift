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
    /// One state per pet slot. `states[0]` is the original pet and always
    /// exists; a summoned second pet appends. Each slot is equality-gated
    /// independently.
    public private(set) var states: [PetState] = [.sleeping]
    /// Slot 0's state — the alias every single-pet consumer (the probe, the
    /// preview restore, the tests) reads.
    public var state: PetState { states[0] }
    public var onChange: ((Int, PetState) -> Void)?

    /// Grows or shrinks the derived-state table (1 or 2 pets) and publishes
    /// the new shape immediately.
    public func setSlots(_ count: Int) {
        let clamped = max(1, min(2, count))
        guard clamped != states.count else { return }
        if clamped > states.count {
            states.append(.sleeping)
            chatterCache.append(SlotChatter())
        } else {
            states.removeLast()
            chatterCache.removeLast()
        }
        recompute()
    }
    /// Fired when a session newly needs attention or newly finishes, for sound
    /// and notifications. Not fired on every state recomputation.
    public var onAlert: ((PetMood, ClaudeSession) -> Void)?

    /// A cook began, or crossed a quarter of its todo list. The OLD cooking
    /// notification path was dead code — `.cooking` is a display promotion
    /// the session record never holds, so its mood-transition alert had
    /// never once fired. This is the living replacement.
    public enum CookMilestone: Equatable, Sendable {
        case started
        case fraction(Int)   // 25, 50, 75
    }
    public var onCookingProgress: ((CookMilestone, ClaudeSession) -> Void)?

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
    /// How long a service glyph outlives its last matching tool call — long
    /// enough to bridge the thinking beat between two npm commands, short
    /// enough that the mark never outlives the story it tells. A `var` so
    /// tests can shrink it.
    static var serviceGlyphLinger: TimeInterval = 6

    /// The celebrated done: a cooking sprint that lands plays a ~10s payoff
    /// (the game-design trick — the work is finished, the reward runs longer),
    /// so the decay waits for the animation plus a beat of afterglow.
    static var celebrationDecay: TimeInterval = 12

    /// A sprint this long earns the FULL finale — flash, dual glow, the
    /// transform, the rainbow burst. Shorter sprints keep the standard bow.
    static var epicCookThreshold: TimeInterval = 60

    /// How old a replayed turn-end may be and still stamp the completion
    /// badge. The badge now lives until new work consumes it, so without this
    /// cap every launch would resurrect the last completion of every live
    /// session — a badge from days ago, pulsing. Half an hour keeps "finished
    /// while you were away" and retires the archaeology.
    nonisolated static let completionStampMaxAge: TimeInterval = 1800

    /// How long the thinking dots may pulse without renewal before the bubble
    /// retires (the `.thinking` mood itself lives on until `staleAfter`).
    /// "Still thinking" is a claim; thirty quiet seconds is where it stops
    /// being one the pet can stand behind.
    static var dotsQuietAfter: TimeInterval = 30

    /// How long idle chatter stays constant company before going intermittent.
    /// Below this the bubble rotates as always; past it, each 14s cycle rolls
    /// the dice and roughly one in three shows a line. The pet stays present;
    /// the banner stops being furniture.
    static var chatterQuietAfter: TimeInterval = 90

    /// Whether this idle-chatter cycle shows a bubble. Split dice, not
    /// `seed % 3`: the ticker chooser inside `idleChatter` already uses
    /// `seed % 3 == 2` on the SAME seed, so a modular gate here would starve
    /// the status ticker forever — and `(seed * k) % 3` degenerates straight
    /// back to `seed % 3`. The splitmix dice decorrelate properly.
    static func idleChatterShows(quietFor quiet: TimeInterval, seed: Int) -> Bool {
        quiet < chatterQuietAfter || CrabAnimator.noise(seed &* 43 &+ 13) < 1.0 / 3.0
    }

    /// When each mood is allowed to speak.
    ///
    /// The `default:` branch of `derive` used to hand back a non-nil bubble on
    /// EVERY recompute — no dice, no horizon — so for the whole length of a
    /// working or cooking mood the banner sat on his head, its text merely
    /// swapping every 14s. That is furniture, and the eye stops reading it.
    ///
    /// The resolution of the "never hide real information" rule is delivery,
    /// not silence: **a task label's first appearance is information; its
    /// four-hundredth consecutive recompute is furniture.** New words show at
    /// once and hold; after that the pose, the props and the tool glyph carry
    /// the continuous half, and he checks back in periodically. Nothing is
    /// destroyed — `PetState.bubbleContent` keeps the live text for the
    /// tooltip through every quiet stretch.
    ///
    /// A `var` so tests can shrink a 30s period into milliseconds, exactly as
    /// the decay horizons are shrunk.
    static var bubbleCadences: [PetMood: BubbleCadence] = [
        // A tool call is in flight. The label is news once; after that the
        // props and the tool glyph say it continuously, without words.
        .working: BubbleCadence(period: 30, dwell: 6, chance: 0.6,
                                newsDwell: 8, newsRefractory: 10),
        // Going hard, so a shorter gap — a sprint genuinely has more to
        // report. The refractory is what does the real work here.
        .cooking: BubbleCadence(period: 24, dwell: 6, chance: 0.75,
                                newsDwell: 8, newsRefractory: 14),
        // Idle but holding a live todo: between tools, not between tasks.
        // Backs off further than working, because nothing is moving.
        .idle: BubbleCadence(period: 40, dwell: 6, chance: 0.5,
                             newsDwell: 8, newsRefractory: 12),
        // Calls to action pulse rather than go dark. `chance: 1.0` never rolls
        // a quiet cycle, so the gap is always exactly one beat — which reads
        // as more insistent than a banner that never moves, not less. These
        // are the two states the pet exists to shout about, and today either
        // can hold a motionless bubble for half an hour.
        .nudging: BubbleCadence(period: 18, dwell: 10, chance: 1.0,
                                newsDwell: 12, newsRefractory: 6),
        .needsAttention: BubbleCadence(period: 18, dwell: 10, chance: 1.0,
                                       newsDwell: 12, newsRefractory: 6),
        // `.done` is absent on purpose: it cannot outlive `celebrationDecay`,
        // and a state that is over in twelve seconds cannot become furniture.
        // `.thinking`, `.sleeping` and bare `.idle` run their own honest gates.
    ]

    /// Which burst, if any, is on screen `elapsed` seconds after this slot's
    /// speech epoch — `nil` means quiet. The value is the burst index, which
    /// also seeds the line, so one burst says exactly one thing instead of
    /// rewriting itself mid-sentence on a 14s boundary.
    ///
    /// Measured against elapsed time rather than the 14s chatter seed on
    /// purpose: that seed only changes on 14s edges, so a 6s burst is not
    /// expressible through it and — the part that matters — a burst could not
    /// *start* at the moment the news did. `dotsQuietAfter` already works this
    /// way.
    ///
    /// Burst 0 is the news window: dice-free, and the only thing reachable at
    /// `elapsed == 0`. It exists because something CHANGED, which is a latch,
    /// not a schedule — so the frozen sentinel holds: nothing the dice
    /// invented can appear in a render frozen at zero.
    static func bubbleBurst(elapsed: TimeInterval,
                            cadence: BubbleCadence?,
                            salt: Int) -> Int? {
        // No cadence means never silenced; keep the 14s rotation, phased from
        // the epoch so fresh news still starts its own turn.
        guard let cadence else { return Int(max(0, elapsed) / chatterInterval) }
        guard elapsed >= 0 else { return 0 }
        if elapsed < cadence.newsDwell { return 0 }
        guard cadence.period > 0, cadence.dwell > 0 else { return nil }

        // The burst sits at the END of its period, not the start. Otherwise
        // the first scheduled cycle begins the instant the news window closes
        // and the two run together as one long stretch — which is the banner
        // this replaces, just shorter. Quiet has to follow news.
        let since = elapsed - cadence.newsDwell
        let cycle = Int(since / cadence.period) &+ 1        // never 0
        guard since.truncatingRemainder(dividingBy: cadence.period)
            >= cadence.period - cadence.dwell else { return nil }
        // 71+29 is unused: 19+13, 41+17, 43+11, 43+13, 53+7 and 61+3 are taken
        // by the shimmer, disco, balloon, chatter gate, bug and stargazer.
        guard CrabAnimator.noise(cycle &* 71 &+ 29 &+ salt) < cadence.chance
        else { return nil }
        return cycle
    }

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
    /// Each pet keeps his own cached sentence — two idle pets sharing one
    /// cache would trade sentences out from under each other's readers.
    private struct SlotChatter {
        var line: (text: String, isMarquee: Bool)?
        var chosenAt: Date = .distantPast
        /// The last thing that counted as news: the mood, the session, and the
        /// words themselves. A recompute that reproduces the same sentence is
        /// not news, however many times it runs.
        var lastNews: String?
        /// When that news broke — the epoch every cadence is measured from.
        var newsAt: Date = .distantPast
    }
    private var chatterCache: [SlotChatter] = [SlotChatter()]

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

    /// User pinned (or unpinned) a session from the roster (slot 0).
    public func pin(sessionID: String?) {
        pin(slot: 0, sessionID: sessionID)
    }

    /// Pin for a specific pet slot; slot 1 is the second pet's own choice.
    public func pin(slot: Int, sessionID: String?) {
        if slot == 0 {
            Preferences.shared.pinnedSessionID = sessionID
        } else {
            Preferences.shared.pet2PinnedSessionID = sessionID
        }
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
        var milestones: [(CookMilestone, ClaudeSession)] = []

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
            case .toolStarted(let name, let detail, let command):
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
                // The service glyph: latest hit wins; stamped with the EVENT
                // time, not Date(), so the priming replay's historical stamps
                // age out in the same recompute that would have shown them.
                if let glyph = ServiceGlyph.classify(tool: name, command: command) {
                    session.serviceGlyph = glyph
                    session.serviceGlyphAt = event.timestamp
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
                // The stopwatch decides the tier, then resets for the next
                // sprint.
                session.epicCelebrating = session.celebrating
                    && session.cookingSince.map {
                        event.timestamp.timeIntervalSince($0) >= Self.epicCookThreshold
                    } ?? false
                session.cookingSince = nil
                session.notifiedMilestone = nil
                // A turn end can arrive twice — the transcript fold and the
                // Stop hook — so the first stamp of this turn wins; a genuine
                // new turn always passes through thinking/working first, which
                // clears it. On the priming replay this carries a historical
                // timestamp: a RECENT completion shows the badge ("finished
                // while you were away"); anything older than the cap does not,
                // because the badge no longer expires on its own and a stamp
                // from days ago would pulse forever.
                if session.mood != .done,
                   Date().timeIntervalSince(event.timestamp) < Self.completionStampMaxAge {
                    session.completionBadgeAt = event.timestamp
                }
                session.mood = .done
                session.tool = nil
                // Clear the last tool's description too. Leaving it set meant an
                // idle session displayed "List worktree contents…" indefinitely,
                // and there was never a "no task" moment for a shout-out to fill.
                session.activity = nil
                // The landing retires the service glyph with the sprint.
                session.serviceGlyph = nil
                session.serviceGlyphAt = nil
            case .needsAttention(let reason):
                session.mood = .needsAttention
                session.activity = Self.condense(reason)
            case .activeTask(let label):
                session.activeTaskLabel = label
                if let label { session.activity = label }
            case .taskProgress(let completed, let total):
                session.tasksCompleted = completed
                session.tasksTotal = total
                // Quarter-crossings while cooking, each fired exactly once —
                // the same 3+-task gate the near-done glow uses.
                if session.cookingSince != nil, total >= 3 {
                    let pct = completed * 100 / total
                    if let crossed = [75, 50, 25].first(where: { pct >= $0 }),
                       crossed > (session.notifiedMilestone ?? 0) {
                        session.notifiedMilestone = crossed
                        milestones.append((.fraction(crossed), session))
                    }
                }
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

            // The cook stopwatch: stamped when the cooking pace first appears
            // on a real tool or subagent observation — event-side, the single
            // writer, so the per-slot derives can never double-stamp. Never
            // cleared on the thinking beat between tools; that would reset
            // the stopwatch mid-sprint.
            switch event.kind {
            case .toolStarted, .subagents:
                if session.cookingSince == nil, Self.isCooking(session, now: event.timestamp) {
                    session.cookingSince = event.timestamp
                    milestones.append((.started, session))
                }
            default:
                break
            }

            // The celebration belongs to the done pose alone; any move off it
            // takes the flag along.
            if session.mood != .done {
                session.celebrating = false
                session.epicCelebrating = false
            }

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
        // Same discipline as alerts: suppressed during the priming replay —
        // a stale 75% banner from history is exactly the disease the replay
        // suppression exists to prevent.
        for milestone in milestones where sessions[milestone.1.id] != nil {
            onCookingProgress?(milestone.0, milestone.1)
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
        // The stopwatch clears only when a session is fully cold — no tool
        // calls left in the rate window and no subagents in flight. A sprint
        // that pauses to think keeps its clock.
        for (id, var session) in sessions where session.cookingSince != nil {
            let cutoff = now.addingTimeInterval(-Self.toolRateWindow)
            if session.recentToolCalls.filter({ $0 >= cutoff }).isEmpty, session.subagentCount == 0 {
                session.cookingSince = nil
                sessions[id] = session
            }
        }

        // A service glyph nothing has renewed expires on the linger. Runs on
        // every ingest and the 2s tick, so the worst-case overshoot hides
        // inside the ease-out.
        for (id, var session) in sessions {
            guard let stamped = session.serviceGlyphAt,
                  now.timeIntervalSince(stamped) > Self.serviceGlyphLinger else { continue }
            session.serviceGlyph = nil
            session.serviceGlyphAt = nil
            sessions[id] = session
        }

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

        // Slot 0 first, so slot 1 can exclude its focus; every slot is
        // derived and gated independently.
        var slotZeroFocus: String?
        for slot in states.indices {
            let new = derive(slot: slot, excluding: slotZeroFocus, ordered: ordered, now: now)
            if slot == 0 { slotZeroFocus = new.focusedSessionID }
            publish(new, slot: slot)
        }
    }

    /// One slot's view of the world. Slot 0 is today's rule, byte-identical
    /// (its seed salt is zero). Slot 1 follows its own pin, else the busiest
    /// session slot 0 is not already showing; with no second session he naps —
    /// honestly, and still carrying the roster.
    private func derive(slot: Int, excluding excludedID: String?,
                        ordered: [ClaudeSession], now: Date) -> PetState {
        guard !ordered.isEmpty else { return .sleeping }

        // Salted per slot so two idle pets never speak in lockstep; additive,
        // so the split-dice property of the chatter gate survives.
        let seed = Int(now.timeIntervalSince1970 / Self.chatterInterval) &+ slot &* 7919

        let focusOrNil: ClaudeSession?
        if slot == 0 {
            let pinned = Preferences.shared.pinnedSessionID.flatMap { id in ordered.first { $0.id == id } }
            focusOrNil = pinned ?? ordered[0]
        } else {
            let pinned = Preferences.shared.pet2PinnedSessionID.flatMap { id in ordered.first { $0.id == id } }
            focusOrNil = pinned ?? ordered.first { $0.id != excludedID }
        }
        guard let focus = focusOrNil else {
            var napping = PetState.sleeping
            napping.sessions = ordered
            if seed % 4 == 0 { napping.bubble = Vocab.line(for: .sleeping, seed: seed) }
            return napping
        }

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
        // Whether this mood rides the burst schedule. Set by the `default:`
        // branch; the moods that run their own honest gate leave it false.
        var scheduled = false

        // Precedence, documented at the top of `vocab.swift`:
        //   1. a rule matching the current task
        //   2. the real task text, whenever there is one
        //   3. this state's own lines
        // Point 2 is why `working` and `cooking` lines appear only in the gaps:
        // a pet that hides "Running the test suite" behind a joke is worse.
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
            chatterCache[slot].line = nil

        case .sleeping:
            // Occasionally talks in his sleep. A sleeping pet that comments on
            // every frame is not asleep.
            bubble = seed % 4 == 0 ? Vocab.line(for: .sleeping, seed: seed) : nil
            chatterCache[slot].line = nil

        // A title is what a session *is*, not what it is *doing*. Gating on
        // `task == nil` meant any titled session — which is most of them — kept
        // showing its title forever and never reached the ticker.
        case .idle where focus.activeTaskLabel == nil && focus.activity == nil:
            // Nothing to report — encouragement, or a status ticker. The gate
            // sits OUTSIDE `idleChatter` on purpose: its 14s cache would
            // otherwise keep answering through cycles the gate meant to be
            // quiet, and a nil cycle must leave the cache untouched so the
            // rotation resumes where it left off.
            if Self.idleChatterShows(quietFor: now.timeIntervalSince(focus.lastActivity),
                                     seed: seed) {
                var snapshot = StatusTicker.Snapshot()
                snapshot.model = focus.model
                snapshot.branch = focus.branch
                snapshot.project = focus.projectName
                snapshot.sessionCount = ordered.count
                snapshot.activeHoursToday = focus.activeHoursToday
                let line = idleChatter(slot: slot, seed: seed, snapshot: snapshot, now: now)
                bubble = line.text
                style = line.isMarquee ? .marquee : .plain
            } else {
                bubble = nil
            }

        default:
            chatterCache[slot].line = nil
            if let task, Vocab.rule(matching: task) != nil {
                // A rule claimed this task.
                bubble = Vocab.line(for: mood.shoutoutOccasion, matching: task, seed: seed)
            } else if let task {
                bubble = Self.condense(task)
            } else {
                bubble = Vocab.line(for: mood.shoutoutOccasion, seed: seed)
            }
            scheduled = true
        }

        // Everything above chose the WORDS. This chooses whether they are on
        // screen. `.thinking`, `.sleeping` and bare `.idle` have already run
        // their own honest gates and are exempt — a second gate on the
        // thinking dots would make "still thinking" flicker, which is a worse
        // claim than a steady one.
        if scheduled {
            // News is a change in what there is to say, not a change in the
            // clock. The session id is in the fingerprint because the same
            // sentence about a different session is a different claim.
            let cadence = Self.bubbleCadences[mood]
            let news = "\(mood.rawValue)|\(focus.id)|\(bubble ?? "")"
            if news != chatterCache[slot].lastNews {
                let sinceLast = now.timeIntervalSince(chatterCache[slot].newsAt)
                chatterCache[slot].lastNews = news
                // Inside the refractory the words update in place and the
                // burst does NOT restart. This single line is what keeps a
                // cooking sprint — whose label churns every couple of seconds
                // — from pinning the bubble to his head all over again.
                if sinceLast >= (cadence?.newsRefractory ?? 0) {
                    chatterCache[slot].newsAt = now
                }
            }
            let burst = Self.bubbleBurst(
                elapsed: now.timeIntervalSince(chatterCache[slot].newsAt),
                cadence: cadence,
                salt: slot &* 7919)
            if burst == nil {
                bubble = nil
            } else if task == nil, let burst {
                // Nothing real to protect, so re-seed from the burst: one
                // burst says one thing, rather than swapping sentence
                // mid-read when the 14s seed rolls over.
                bubble = Vocab.line(for: mood.shoutoutOccasion,
                                    seed: seed &+ burst &* 101) ?? bubble
            }
        }

        // The near-done glow needs a real list behind it: three or more tasks,
        // quantised so the equality-gated publish does not churn on re-reads.
        var taskFraction: Double?
        if let done = focus.tasksCompleted, let total = focus.tasksTotal, total >= 3 {
            taskFraction = (Double(done) / Double(total) / 0.05).rounded() * 0.05
        }

        return PetState(
            mood: mood,
            bubble: bubble,
            // The live task survives every quiet stretch: the cadence decides
            // when he SPEAKS, never what is known. The same `task` the bubble
            // would have shown — real text only, never the vocabulary line,
            // so a quiet rotation cannot churn the equality-gated publish.
            bubbleContent: task.map { Self.condense($0) },
            tool: focus.tool,
            sessions: ordered,
            focusedSessionID: focus.id,
            attentionCount: ordered.filter { $0.mood == .needsAttention && $0.id != focus.id }.count,
            bubbleStyle: style,
            taskFraction: taskFraction,
            celebrating: mood == .done && focus.celebrating,
            epicCelebration: mood == .done && focus.epicCelebrating,
            completedAt: focus.completionBadgeAt,
            serviceGlyph: focus.serviceGlyph
        )
    }

    // MARK: - Idle chatter

    /// Encouragement, with an occasional scrolling status read-out.
    ///
    /// Held for `chatterInterval` rather than re-rolled on every `recompute()`
    /// — this runs on the 2s decay timer, so choosing per call would rewrite the
    /// sentence out from under the reader three times before they finished it.
    private func idleChatter(slot: Int, seed: Int,
                             snapshot: StatusTicker.Snapshot,
                             focusTask: String? = nil,
                             now: Date) -> (text: String, isMarquee: Bool) {
        if let current = chatterCache[slot].line,
           now.timeIntervalSince(chatterCache[slot].chosenAt) < Self.chatterInterval {
            return current
        }

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

        chatterCache[slot].line = next
        chatterCache[slot].chosenAt = now
        return next
    }

    private func publish(_ new: PetState, slot: Int) {
        guard new != states[slot] else { return }
        states[slot] = new
        onChange?(slot, new)
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
