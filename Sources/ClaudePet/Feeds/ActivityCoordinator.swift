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
            chatterCache.append(SlotChatter(cursor: LineCursor(salt: chatterCache.count &* 7919)))
            // Summoning a pet IS an interaction, so he arrives awake. The
            // alternative — a second pet that is asleep on arrival — means
            // clicking "Summon a second pet" hands you a corpse.
            stirredAt.append(Date())
        } else {
            states.removeLast()
            chatterCache.removeLast()
            stirredAt.removeLast()
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
        // 71+29, plus the slot so two pets never breathe in lockstep. The
        // registry of who owns which salt is on `CrabAnimator.noise`; the copy
        // that used to be here listed six of eleven and had stopped being true.
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
    /// `nonisolated`: a plain constant with no actor affinity, and the fun-fact
    /// length guard reads it from a non-MainActor suite to compare a scroll
    /// duration against the slot that has to contain it.
    nonisolated static let chatterInterval: TimeInterval = 14
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
        var line: (text: String, style: PetState.BubbleStyle,
                   tone: PetState.BubbleTone)?
        var chosenAt: Date = .distantPast
        /// The last thing that counted as news: the mood, the session, and the
        /// words themselves. A recompute that reproduces the same sentence is
        /// not news, however many times it runs.
        var lastNews: String?
        /// When that news broke — the epoch every cadence is measured from.
        var newsAt: Date = .distantPast
        /// This slot's draw counters, one per pool. See `LineCursor`.
        var cursor: LineCursor
        /// Bumped whenever `newsAt` moves, so an old burst index reached under
        /// a NEW epoch is a new utterance rather than the same one.
        var newsEpoch = 0
        /// A line that is still being READ, and must not be replaced yet.
        ///
        /// Only scrolling lines take one. A plain line is legible the instant
        /// it appears; a marquee has to walk past, and the dwell it was given
        /// was shorter than that walk.
        var heldLine: (text: String, style: PetState.BubbleStyle, until: Date)?
        /// The seed of the last fact the 🐑 tally counted, so a fact is
        /// counted once however many recomputes show it.
        var sheepSeed: Int = .min
        /// How many facts he has muttered in his sleep — the 🐑 tally.
        ///
        /// Deliberately NOT persisted. It is a thing you notice about the
        /// session you are in; a number that survived restarts would invite
        /// being read as a statistic, and it is a joke.
        var sheep = 0
        /// How many fun facts this slot has drawn — the index into the 60/8x5
        /// mix. Per-slot for the same reason `cursor` is: two idle pets sharing
        /// one counter would interleave each other's mixes and neither would
        /// hold the ratio.
        var factDraws = 0
        /// The seed the last fact was drawn for, so a path that recomputes
        /// faster than the line changes cannot walk the deck.
        var lastFactSeed: Int?
    }
    private var chatterCache: [SlotChatter] = [SlotChatter(cursor: LineCursor())]

    /// The last thing that could hold this slot's attention: the app starting
    /// (or this pet being summoned), the focused session doing something, or
    /// the operator laying hands on him. He is awake while this is younger
    /// than `sleepAfter`.
    ///
    /// One mark rather than three special cases. Before it, there were three
    /// independent routes into sleep and two of them had no timer at all —
    /// kill your last session and he was asleep in two seconds, forever, and
    /// poking him bought nothing because no interaction has ever reached this
    /// file.
    ///
    /// **It only ever moves FORWARD**, and that is load-bearing rather than
    /// tidy. `focus.lastActivity` is monotonic, `now` is monotonic, so a
    /// running `max` of them crosses `sleepAfter` exactly once and never comes
    /// back. A plain assignment would let slot 1's focus switching to an older
    /// session drop the anchor and flap him in and out of sleep on the 2s tick.
    private var stirredAt: [Date] = [Date()]

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
    /// The operator laid hands on him — a click, a press-and-hold, a drag, or a
    /// hover he actually rested on. Pushes the wake window out.
    ///
    /// Recomputes on the spot rather than waiting for the 2s decay tick,
    /// because a poke that takes two seconds to land does not read as a poke.
    public func stir(slot: Int = 0) {
        guard slot < stirredAt.count else { return }
        stirredAt[slot] = Date()
        recompute()
    }

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

        // The tasks directory is created by the first TodoWrite, not at session
        // start, so it usually does not exist yet — the watcher waits for it.
        attachTaskWatcher(id: id, tasksURL: session.tasksDirectory)
    }

    /// Watches a session's todo directory, waiting for it to be created.
    ///
    /// This used to fall back to the SHARED `~/.claude/tasks` parent and stay
    /// there. A vnode watch on a directory fires only when that directory's own
    /// entries change, so the parent heard `<sessionId>/` being created — once,
    /// at which instant the new directory is still empty — and then never again,
    /// because every later write lands inside the child. The todo feed was
    /// therefore delivered exactly one nil for the life of the session, which
    /// quietly took the near-done glow and the cooking milestones with it.
    ///
    /// Now the watcher is aimed at the child from the start and simply waits
    /// for it (`FileWatcher` no longer requires the path to exist), so there is
    /// no parent to re-point away from and no one-shot to miss.
    private func attachTaskWatcher(id: String, tasksURL: URL) {
        taskWatchers[id] = FileWatcher(url: tasksURL, queue: queue, coalesce: 0.2) { [weak self] in
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
    /// Awake with nothing to watch.
    ///
    /// Deliberately NOT a new `PetMood`. He is the same idle crab; the only new
    /// fact is that no session sits under him, and `PetState` already says that
    /// with `focusedSessionID: nil`. A new case would force entries in
    /// `MoodStyle`, `ShoutoutOccasion`, `pose`, `urgency`, `NotificationNudge`
    /// and two renderers, all of them to say nothing.
    private func upAlone(slot: Int, seed: Int, roster: [ClaudeSession], now: Date) -> PetState {
        var up = PetState.sleeping
        up.mood = .idle
        up.sessions = roster
        // The same quiet gate the focused idle path uses — constant company for
        // the first ninety seconds, intermittent after. Measured from the mark,
        // which with no session under him IS how long he has been up.
        let quietFor = now.timeIntervalSince(stirredAt[slot])
        if Self.idleChatterShows(quietFor: quietFor, seed: seed) {
            var snapshot = StatusTicker.Snapshot()
            snapshot.sessionCount = roster.count
            let line = idleChatter(slot: slot, seed: seed, snapshot: snapshot,
                                   now: now)
            up.bubble = line.text
            up.bubbleStyle = line.style
            up.bubbleTone = line.tone
        }
        return up
    }

    /// Asleep with nothing to watch — the nap, still carrying the roster.
    private func napping(slot: Int, seed: Int, roster: [ClaudeSession]) -> PetState {
        var down = PetState.sleeping
        down.sessions = roster
        if seed % 4 == 0 {
            down.bubble = chatterCache[slot].cursor
                .line(for: .sleeping, token: "nap|\(seed)")
        }
        return down
    }

    private func derive(slot: Int, excluding excludedID: String?,
                        ordered: [ClaudeSession], now: Date) -> PetState {
        // Salted per slot so two idle pets never speak in lockstep; additive,
        // so the split-dice property of the chatter gate survives.
        let seed = Int(now.timeIntervalSince1970 / Self.chatterInterval) &+ slot &* 7919

        let focusOrNil: ClaudeSession?
        if ordered.isEmpty {
            focusOrNil = nil
        } else if slot == 0 {
            let pinned = Preferences.shared.pinnedSessionID.flatMap { id in ordered.first { $0.id == id } }
            focusOrNil = pinned ?? ordered[0]
        } else {
            let pinned = Preferences.shared.pet2PinnedSessionID.flatMap { id in ordered.first { $0.id == id } }
            focusOrNil = pinned ?? ordered.first { $0.id != excludedID }
        }

        // The focus's own clock folds into the mark, and THAT is what makes
        // this one rule instead of three. Whichever route we are on, the mark
        // is now the latest of everything that could interest this slot.
        if let focus = focusOrNil {
            stirredAt[slot] = max(stirredAt[slot], focus.lastActivity)
        }
        let awake = now.timeIntervalSince(stirredAt[slot]) <= Self.sleepAfter

        // Nobody to watch: either no sessions at all, or slot 1 with only one
        // session running. Awake he is the same idle crab with no session
        // under him; asleep he naps — either way carrying the roster, because
        // "nothing running" would be a lie whenever there is something.
        guard let focus = focusOrNil else {
            return awake ? upAlone(slot: slot, seed: seed, roster: ordered, now: now)
                         : napping(slot: slot, seed: seed, roster: ordered)
        }

        var mood = focus.mood
        if mood != .needsAttention, !awake {
            mood = .sleeping
        }

        // A plan on screen outranks the work that produced it — nothing moves
        // until the human answers.
        if focus.awaitingApproval, mood != .needsAttention, mood != .sleeping {
            mood = .nudging
        } else if mood == .working, Self.isCooking(focus, now: now) {
            mood = .cooking
        }

        // What Claude is DOING right now, if anything — and the only thing a
        // rule may claim.
        //
        // The distinction is load-bearing and its absence was a real defect.
        // `focus.title` is the session's SUBJECT: it comes from the last
        // prompt and does not change for the life of the session. Folding it
        // in here meant `.done` — which nils `activity` and `tool` — fell
        // through to the title and let a rule claim it, so a session titled
        // "fix the login bug" announced the end of its turn with
        // "It's always the cache" instead of a completion line.
        //
        // A rule's whole contract is that it replaces a label describing an
        // action in flight. A subject is not an action.
        let action = focus.activeTaskLabel ?? focus.activity
        let task = action ?? focus.title
        var bubble = task.map { Self.condense($0) }
        var style = PetState.BubbleStyle.plain
        var tone = PetState.BubbleTone.mood
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
            //
            // Some of those mutterings are FACTS. Sleep is the longest stretch
            // anybody actually watches him — the operator reported never having
            // seen a fact, and the measured reason was that the waking rate is
            // ~one per five minutes of work shown for six seconds, while the
            // hours they sit and look at him were the one place facts could not
            // reach at all.
            //
            // `informationalBeat` is reused rather than rolled fresh: it is the
            // same question ("is this a cycle he spends on something he knows")
            // and it needs no new salt, of which there are none free.
            // A line he is still part way through keeps its place, exactly as
            // on the waking path. Sleep is the longest stretch anyone watches
            // him, so it is the worst place to cut a sentence in half.
            if let held = chatterCache[slot].heldLine, now < held.until {
                bubble = held.text
                style = held.style
                tone = .knowledge   // only facts take holds
            } else if seed % 4 == 0 {
                chatterCache[slot].heldLine = nil
                if Self.informationalBeat(seed: seed), let fact = funFact(slot: slot, seed: seed) {
                    bubble = fact
                    tone = .knowledge
                    // One sheep per FACT, not per 2-second recompute — the
                    // tally ran ~1.5x hot because every tick inside a winning
                    // window counted. `funFact` steps `lastFactSeed` exactly
                    // once per seed, so "the seed just changed" is "this fact
                    // is new".
                    if chatterCache[slot].lastFactSeed == seed,
                       chatterCache[slot].sheepSeed != seed {
                        chatterCache[slot].sheepSeed = seed
                        chatterCache[slot].sheep &+= 1
                    }
                } else {
                    bubble = chatterCache[slot].cursor.line(for: .sleeping,
                                                            token: "\(focus.id)|\(seed)")
                }
                // Routed by LENGTH, like every other line that reaches the
                // bubble. Sixty-six of the seventy-six facts are longer than
                // the plain ceiling — they are written to scroll — so leaving
                // this at the `.plain` default truncated almost every one of
                // them the moment he started sleep-talking.
                if let line = bubble {
                    style = Self.bubbleStyle(for: line)
                    let hold = Self.lineHold(for: line)
                    if hold > 0 {
                        chatterCache[slot].heldLine = (line, style,
                                                       now.addingTimeInterval(hold))
                    }
                }
            } else {
                bubble = nil
                chatterCache[slot].heldLine = nil
            }
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
                let line = idleChatter(slot: slot, seed: seed, snapshot: snapshot,
                                       now: now)
                bubble = line.text
                style = line.style
                tone = line.tone
            } else {
                bubble = nil
            }

        default:
            chatterCache[slot].line = nil
            if let action, Vocab.rule(matching: action) != nil {
                // A rule claimed this action. `action`, never `task`: see the
                // note where they are derived.
                bubble = Vocab.line(for: mood.shoutoutOccasion, matching: action, seed: seed)
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
                    chatterCache[slot].newsEpoch &+= 1
                }
            }
            let burst = Self.bubbleBurst(
                elapsed: now.timeIntervalSince(chatterCache[slot].newsAt),
                cadence: cadence,
                salt: slot &* 7919)
            // Any burst — a vocab line or a real task label riding one — is
            // news, and news kills whatever fact was mid-scroll NOW. Not
            // paused, not resumed later: a resumed scroll re-creates the
            // mid-start the hold exists to prevent. This clear is what
            // replaced the old dies-with-its-cycle clamp, and it sits ABOVE
            // the branch so the task!=nil case (which falls through both
            // arms with the label already set) kills the hold too.
            if burst != nil { chatterCache[slot].heldLine = nil }

            if burst == nil {
                // The cadence chose silence. That is the one place a fact can
                // go without displacing anything, so ask — and fall back to the
                // silence it would have been.
                if let known = quietBeatFact(mood: mood, slot: slot, now: now) {
                    bubble = known
                    style = Self.bubbleStyle(for: known)
                    tone = .knowledge
                } else {
                    bubble = nil
                }
            } else if task == nil, let burst {
                // Nothing real to protect, so draw a fresh line per burst.
                //
                // The seed is gone from here on purpose. `bubbleBurst` returns
                // an index that SKIPS — the dice silence most cycles — and
                // folding it into the seed as `seed &+ burst &* 101` jumped the
                // deck's pass, which is what gave a working stretch a 33%
                // chance of saying the same thing twice in a row. The token
                // does honestly what the multiply was working around: hold one
                // line for one burst, then step by exactly one.
                bubble = chatterCache[slot].cursor.line(
                    for: mood.shoutoutOccasion,
                    token: "\(mood.rawValue)|\(focus.id)|\(chatterCache[slot].newsEpoch)|\(burst)")
                    ?? bubble
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
            bubbleTone: tone,
            sleepTalkCount: chatterCache[slot].sheep,
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
                             now: Date) -> (text: String, style: PetState.BubbleStyle,
                                            tone: PetState.BubbleTone) {
        if let current = chatterCache[slot].line,
           now.timeIntervalSince(chatterCache[slot].chosenAt) < Self.chatterInterval {
            return current
        }

        let status = StatusTicker.lines(for: snapshot, now: now)

        // Roughly every third turn is a status ticker, when one is available;
        // of what is left, a coin decides between a fun fact and a line in his
        // own voice.
        //
        // The fact die is NESTED inside the else on purpose, so the ticker's
        // behaviour on the cycles it already owns is byte-identical. And it is
        // a splitmix draw rather than another modulo: the note on
        // `idleChatterShows` explains that a second modular gate on this seed
        // starves whatever already modulos it, and that `(seed * k) % 3`
        // collapses straight back into `seed % 3`.
        let next: (String, PetState.BubbleStyle, PetState.BubbleTone)
        if !status.isEmpty, seed % 3 == 2 {
            next = (status[(seed / 3) % status.count], .marquee, .mood)
        } else if let known = factOrTip(slot: slot, seed: seed) {
            // The knowledge voice: facts and tips wear the appearance-matched
            // card, not the mood palette.
            next = (known, Self.bubbleStyle(for: known), .knowledge)
        } else {
            // The shuffled cycle guarantees no immediate repeat — but only
            // through a cursor. It is reached on a subset of ticks (this very
            // function spends every third on the ticker, and `idleChatterShows`
            // silences roughly two in three), so the raw seed skips and the
            // deck's promise evaporated. Measured at 10.4% immediate repeats
            // before the cursor; that is the "spicy idea" the operator kept
            // seeing.
            let line = chatterCache[slot].cursor.line(for: .idle, token: "\(seed)")
            next = (line ?? "Ready when you are", .plain, .mood)
        }

        chatterCache[slot].line = next
        chatterCache[slot].chosenAt = now
        return next
    }

    /// Scroll a line only if it has to scroll.
    ///
    /// `MarqueeText`'s offset advances whatever the text's width is — there is
    /// no "it already fits" branch — so a twenty-character fact slides out of
    /// the viewport and loops twice inside one fourteen-second slot. That is
    /// motion with nothing left to reveal, and it costs the short line exactly
    /// the thing that makes it worth having: you can take it in at a glance.
    ///
    /// The threshold comes from `ThoughtBubble` rather than from a number here,
    /// because it IS a rendering fact — the bubble's width, its padding and the
    /// monospaced advance are the whole of it, and a copy of that arithmetic in
    /// this file would keep agreeing with itself long after the bubble changed.
    /// `nonisolated` for the reason `chatterInterval` above is: the suite reads
    /// it from a synchronous, non-MainActor test. Verified by removing the
    /// keyword and watching the TEST target fail — the app target compiles
    /// either way, which is precisely how the last round's check proved
    /// nothing.
    nonisolated static func bubbleStyle(for line: String) -> PetState.BubbleStyle {
        line.count <= ThoughtBubble.plainColumns ? .plain : .marquee
    }

    /// The longest a single scrolling line may hold the bubble.
    ///
    /// Three read-throughs of the longest fact is thirty-five seconds, and a
    /// pet whose face is owned by one sentence for over half a minute is the
    /// furniture `bubbleCadences` exists to prevent. Twenty still buys nearly
    /// three passes of a typical fact and about 1.7 of the worst one — measured,
    /// not divided: the longest fact reads in 11.8s, and 20/11.8 is not 2.5.
    /// A backstop, not a target. The rule below asks for TWO full marquee
    /// cycles — the operator's guarantee that wherever you glance, a complete
    /// from-the-first-word pass still follows — and the longest fact in the
    /// pool needs 37.8s for that. Forty exists to catch a future 90-character
    /// fact before it can own his face for a minute, and binds on nothing
    /// that ships today.
    nonisolated static let maxLineHold: TimeInterval = 40

    /// How long a scrolling line stays up: **two whole cycles**.
    ///
    /// Zero for anything that fits the plain bubble: a line you can see whole
    /// the moment it appears needs no extra time.
    ///
    /// Two CYCLES, not two read-throughs, and the difference is the operator's
    /// actual complaint: they glanced up mid-sentence, and by the time the eye
    /// was reading, the start was gone. With two full cycles held, a glance at
    /// any moment in the first cycle is followed by a complete pass that opens
    /// on the first word. That guarantee costs 37.8s on the worst fact — which
    /// is longer than a working cadence period, so the old "a hold dies with
    /// its own cycle" invariant is replaced by a stronger one at the call
    /// site: NEWS KILLS THE HOLD, always and immediately, and it never
    /// resumes — a resumed scroll is the mid-start bug wearing a different
    /// hat.
    nonisolated static func lineHold(for line: String) -> TimeInterval {
        guard bubbleStyle(for: line) == .marquee else { return 0 }
        let cycle = Double(MarqueeText.cycle(for: line, loopSeconds: nil) / MarqueeText.speed)
        return min(cycle * 2, maxLineHold)
    }

    /// A fun fact for this cycle, or nil when the coin says it is his turn to
    /// speak in his own voice.
    ///
    /// **Only the winning category is drawn.** Pre-drawing all three and
    /// discarding two would step all three counters, and a burned counter
    /// skips a card in the deck — which is exactly the immediate-repeat bug
    /// `LineCursor` exists to kill, one level up. `next` advances only for the
    /// id it is called with, so a category that loses this cycle keeps its
    /// place for free.
    /// The informational half of an idle cycle: a fun fact, or a tip about the
    /// tool the operator is holding.
    ///
    /// **The tip die sits INSIDE this branch, not beside it**, and that is the
    /// whole design of the change. Nesting it next to the vocabulary would have
    /// paid for tips out of his own voice — the ticker already takes a third
    /// and the facts another third, so a fourth peer would have left his own
    /// lines at one turn in six, which is not a pet, it is a feed. Nested here,
    /// the vocabulary keeps every cycle it has today, byte for byte, and a tip
    /// costs a fact instead. `PersonalityTests.idleGateDoesNotRepeat` walks the
    /// real gates and needs no edit for exactly that reason.
    ///
    /// A third rather than a half, because the facts are the thing the operator
    /// asked for first and there are seventy-six of them against sixteen tips.
    /// Whether an idle cycle spends itself on something he KNOWS rather than on
    /// something he feels. The fun facts' original gate, unchanged since they
    /// shipped — named here rather than inlined so the suite can measure the
    /// real rate instead of restating the arithmetic and drifting from it.
    nonisolated static func informationalBeat(seed: Int) -> Bool {
        CrabAnimator.noise(seed &* 17 &+ 7) < 0.5
    }

    /// Whether a beat the cadence SILENCED carries a fact anyway. Named for the
    /// same reason, and separate because the two gates compound: this one, then
    /// `informationalBeat` inside `factOrTip`.
    nonisolated static func quietBeatSpeaks(seed: Int) -> Bool {
        CrabAnimator.noise(seed &* 79 &+ 23) < 0.6
    }

    private func factOrTip(slot: Int, seed: Int) -> String? {
        // Unchanged, and deliberately so: this is the gate the fun facts have
        // always answered to, so the cycles they own stay theirs.
        guard Self.informationalBeat(seed: seed) else { return nil }
        if CrabAnimator.noise(seed &* 23 &+ 19) < 0.34,
           let tip = chatterCache[slot].cursor.next(ClaudeTips.all, id: "tip",
                                                    token: "\(seed)") {
            return tip
        }
        return funFact(slot: slot, seed: seed)
    }

    private func funFact(slot: Int, seed: Int) -> String? {
        // ONCE PER SEED, not once per call — and the counter steps BEFORE the
        // category is read from it, so both are stable for the whole fourteen
        // seconds the line is on screen.
        //
        // The idle path reaches here at most once per line, because its cache
        // short-circuits first; this function's own note used to lean on that.
        // The working path has no such cache and recomputes every two seconds,
        // which would step the mix seven times inside one window — and because
        // the category is derived from the counter, the LINE would change under
        // a reader mid-sentence.
        if chatterCache[slot].lastFactSeed != seed {
            chatterCache[slot].lastFactSeed = seed
            chatterCache[slot].factDraws &+= 1
        }
        let category = FunFacts.category(forDraw: chatterCache[slot].factDraws)
        guard let fact = chatterCache[slot].cursor.next(
            FunFacts.facts(in: category),
            id: "fact:\(category.rawValue)",
            token: "\(seed)") else { return nil }
        return fact
    }

    /// The moods a fact may fill a silent beat in.
    ///
    /// Working, cooking, and idle-holding-a-todo — the three where he has
    /// something going on but nothing new to say about it. Deliberately NOT the
    /// calls to action: `nudging` and `needsAttention` exist to be answered,
    /// and trivia over the top of "he is blocked on you" is the one place this
    /// would be actively wrong. `thinking` is out too, because it shows dots
    /// rather than words and never reaches this gate at all.
    static let factMoods: Set<PetMood> = [.working, .cooking, .idle]

    /// A fact or a tip on a cycle the cadence chose to silence.
    ///
    /// **Only silent cycles.** The label has already had its moment — that is
    /// what `bubbleCadences` means by news — and `PetState.bubbleContent` keeps
    /// the live text for the tooltip whatever is on his head, so nothing real
    /// is displaced. A cycle with something new to say never gets here.
    ///
    /// A die on top, rather than every silent cycle, because filling them all
    /// rebuilds the furniture the cadence exists to prevent, just with better
    /// words. `factOrTip` carries its own even gate, so the two compound to
    /// roughly three quiet cycles in ten — a fact every three or four minutes
    /// of working, which is the rate the idle path already runs at.
    ///
    /// **The die is keyed to the CADENCE cycle, not the chatter window.** It
    /// was keyed to the 14-second seed, which re-rolled it twice per cadence
    /// period — measured over two million simulated seconds, trivia was on
    /// screen 28% of a working stretch, 2.3x more than the task label itself,
    /// against the "every three or four minutes" this comment promises. One
    /// roll per cadence period, at the period's own start, makes the
    /// arithmetic above true instead of aspirational — and kills the chaining
    /// where an expiring hold rolled straight into a fresh line, because after
    /// a hold expires the cycle's dwell window has already passed.
    private func quietBeatFact(mood: PetMood, slot: Int, now: Date) -> String? {
        guard Self.factMoods.contains(mood) else {
            // He has stopped being in a mood that says facts, so whatever was
            // scrolling is no longer his to finish.
            chatterCache[slot].heldLine = nil
            return nil
        }

        // A line still being read keeps its place, window boundaries and dice
        // included. This is the whole fix: the dwell was six seconds against a
        // read-through of up to 11.8, so the longest facts had never once been
        // seen to the end — and the seed turns over every fourteen seconds,
        // which would have swapped the sentence out from under a reader even if
        // the dwell had allowed it.
        if let held = chatterCache[slot].heldLine {
            if now < held.until { return held.text }
            chatterCache[slot].heldLine = nil
        }

        let period = Self.bubbleCadences[mood]?.period ?? 30
        let cycle = Int(now.timeIntervalSince1970 / period) &+ slot &* 7919
        guard Self.quietBeatSpeaks(seed: cycle) else { return nil }

        // …and only the FIRST part of the window it won.
        //
        // Without this the fact answers every recompute for its whole fourteen
        // seconds, so the bubble never goes out and he is pinned again — the
        // exact failure the cadence exists to prevent, just with better words.
        // `aChurningTaskLabelCannotPin…` caught it, and caught it
        // intermittently, because whether the window's single die had landed
        // decided the entire run.
        //
        // The dwell is the mood's OWN, not a new number: a fact should sit on
        // his head for exactly as long as anything else that mood says.
        let dwell = Self.bubbleCadences[mood]?.dwell ?? 6
        let intoCycle = now.timeIntervalSince1970
            .truncatingRemainder(dividingBy: period)
        guard intoCycle < dwell else { return nil }
        guard let line = factOrTip(slot: slot, seed: cycle) else { return nil }

        // A scrolling line takes a hold; a plain one is legible the moment it
        // appears and gets none, so short facts keep exactly the cadence they
        // have today.
        //
        // The hold may now OUTLIVE its cadence cycle — two full passes of the
        // longest fact need 37.8s against a 30s working period, and the
        // operator chose the guarantee. What replaced the old cycle clamp is
        // stronger: the burst path clears `heldLine` the moment the cadence
        // has anything real to say, so news still wins instantly, and a
        // cleared hold never resumes. Chaining stays dead because the die is
        // per-cycle and the dwell-start gate keeps an expiry mid-cycle quiet.
        let hold = Self.lineHold(for: line)
        if hold > 0 {
            chatterCache[slot].heldLine = (line, Self.bubbleStyle(for: line),
                                           now.addingTimeInterval(hold))
        }
        return line
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
