import Testing
import Foundation
@testable import ClaudePet

/// A scratch `CLAUDE_PET_HOME` built in `FileManager.temporaryDirectory`.
///
/// Nothing here reads or writes the operator's real `~/.claude/`
/// — the redline.
private enum DecayFixture {

    /// Redirects `ClaudeHome` before anything in the process resolves it.
    ///
    /// `ClaudeHome.root` is a `static let`, so the redirect only holds if this
    /// runs first. Every test below reads this property as its first statement.
    static let home: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pet-decay-\(UUID().uuidString)")
        setenv("CLAUDE_PET_HOME", dir.path, 1)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Writes one `<home>/sessions/<slot>.json` per id, in the shape
    /// `SessionRegistry` decodes.
    ///
    /// The PID is this test process, which is unarguably alive, and `procStart`
    /// is omitted so liveness falls back to the `kill(pid, 0)` check alone.
    static func register(_ ids: [String]) throws {
        let fm = FileManager.default
        let sessions = home.appendingPathComponent("sessions")
        if fm.fileExists(atPath: sessions.path) { try fm.removeItem(at: sessions) }
        try fm.createDirectory(at: sessions, withIntermediateDirectories: true)

        for (slot, id) in ids.enumerated() {
            let payload: [String: Any] = [
                "pid": Int(getpid()),
                "sessionId": id,
                "cwd": home.appendingPathComponent("work").path,
                "startedAt": Date().timeIntervalSince1970 * 1000,
                "name": "fixture-\(slot)",
            ]
            try JSONSerialization.data(withJSONObject: payload)
                .write(to: sessions.appendingPathComponent("\(slot).json"))
        }
    }
}

/// Regression cover for issue #2, "Message hangs when repo is not doing any
/// action".
///
/// Two independent defects produced that report. The pet's own 2-second
/// workload poll emitted a `.subagents` event for every live session, and
/// `ingest` advanced `lastActivity` on every event kind — so `now -
/// lastActivity` never exceeded the tick interval and *every* time-based
/// threshold was arithmetically unreachable, including the 6s `doneDecay` that
/// had therefore never fired in a shipped build. Underneath that, `.thinking`
/// and `.working` had no decay path at all.
///
/// The suite is `.serialized` because it mutates the decay constants, which are
/// process-global.
@Suite("Mood decay", .serialized)
@MainActor
struct MoodDecayTests {

    /// Shrinks the decay horizons so a five-minute rule can be tested in
    /// milliseconds, and restores them afterwards.
    ///
    /// The alternative is sleeping past the real 300s, which no one would run.
    private func withFastDecay(_ body: () async throws -> Void) async rethrows {
        let (done, stale, working, attention, sleep) = (ActivityCoordinator.doneDecay,
                                                        ActivityCoordinator.staleAfter,
                                                        ActivityCoordinator.workingStaleAfter,
                                                        ActivityCoordinator.attentionStaleAfter,
                                                        ActivityCoordinator.sleepAfter)
        ActivityCoordinator.doneDecay = 0.2
        ActivityCoordinator.staleAfter = 0.2
        ActivityCoordinator.workingStaleAfter = 0.2
        ActivityCoordinator.attentionStaleAfter = 0.2
        ActivityCoordinator.sleepAfter = 30
        defer {
            ActivityCoordinator.doneDecay = done
            ActivityCoordinator.staleAfter = stale
            ActivityCoordinator.workingStaleAfter = working
            ActivityCoordinator.attentionStaleAfter = attention
            ActivityCoordinator.sleepAfter = sleep
        }
        try await body()
    }

    /// `ingest` recomputes even when no event matches a known session, so this
    /// advances the reducer's clock without touching any session's state.
    private func tick(_ coordinator: ActivityCoordinator) {
        coordinator.ingest([ActivityEvent(sessionID: "not-a-session", kind: .title("tick"))])
    }

    private func session(_ coordinator: ActivityCoordinator, _ id: String) throws -> ClaudeSession {
        try #require(coordinator.state.sessions.first { $0.id == id }, "session \(id) missing")
    }

    /// A coordinator with its own timer and watchers stopped, so the test owns
    /// the clock.
    private func quietCoordinator(_ ids: [String]) throws -> ActivityCoordinator {
        _ = DecayFixture.home
        try DecayFixture.register(ids)
        let coordinator = ActivityCoordinator()
        coordinator.start()
        coordinator.stop()
        return coordinator
    }

    // MARK: - The report

    @Test("A session left in .working or .thinking decays to .idle")
    func workingAndThinkingDecay() async throws {
        try await withFastDecay {
            let (working, thinking, done) = ("s-working", "s-thinking", "s-done")
            let coordinator = try quietCoordinator([working, thinking, done])
            #expect(coordinator.state.sessions.count == 3)

            // A tool in flight, a reasoning pause, and a finished turn — then the
            // session goes quiet, as it does when Claude is waiting on the human
            // with the tab still open.
            coordinator.ingest([
                ActivityEvent(sessionID: working,
                              kind: .toolStarted(name: "Bash", detail: "git commit -m 'ship it'")),
                ActivityEvent(sessionID: thinking, kind: .thinking),
                ActivityEvent(sessionID: done, kind: .turnEnded),
            ])
            #expect(try session(coordinator, working).mood == .working)
            #expect(try session(coordinator, thinking).mood == .thinking)
            #expect(try session(coordinator, done).mood == .done)

            try await Task.sleep(for: .milliseconds(400))
            tick(coordinator)

            #expect(try session(coordinator, done).mood == .idle)
            #expect(try session(coordinator, working).mood == .idle,
                    "a quiet .working session must not narrate a finished commit forever")
            #expect(try session(coordinator, thinking).mood == .idle,
                    "a quiet .thinking session must not pulse dots forever")
        }
    }

    @Test("The pet's own 2s workload poll does not count as session activity")
    func workloadPollIsNotActivity() async throws {
        try await withFastDecay {
            let id = "s-heartbeat"
            let coordinator = try quietCoordinator([id])

            coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnEnded)])
            #expect(try session(coordinator, id).mood == .done)

            // Exactly what `refreshWorkload()` puts on the wire for every live
            // session, count unchanged at zero. This is the whole bug: it used to
            // renew `lastActivity` and hold off every decay indefinitely.
            for _ in 0..<4 {
                try await Task.sleep(for: .milliseconds(120))
                coordinator.ingest([ActivityEvent(sessionID: id, kind: .subagents(0))])
            }

            #expect(try session(coordinator, id).mood == .idle,
                    "silence punctuated only by the pet's own poll is still silence")
        }
    }

    @Test("A live coordinator reaches .idle after a turn ends")
    func liveCoordinatorGoesIdle() async throws {
        try await withFastDecay {
            let id = "s-live"
            _ = DecayFixture.home
            try DecayFixture.register([id])

            // Deliberately NOT stopped — the 2s timer runs. The bug was invisible
            // to any test that stubbed it out, because the timer was the cause.
            let coordinator = ActivityCoordinator()
            coordinator.start()
            defer { coordinator.stop() }

            coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnEnded)])
            try await Task.sleep(for: .seconds(3))

            #expect(try session(coordinator, id).mood == .idle,
                    "with the real timer running, a finished turn must still settle to idle")
        }
    }

    // MARK: - The guard against over-correcting

    @Test("Work still in progress is never called idle")
    func realWorkIsNeverCalledIdle() async throws {
        let id = "s-busy"
        let coordinator = try quietCoordinator([id])
        ActivityCoordinator.workingStaleAfter = 0.5
        defer { ActivityCoordinator.workingStaleAfter = 600 }

        // A tool call every 150ms, comfortably inside the limit. This is the
        // constraint that matters: a pet that goes idle while Claude is genuinely
        // working is worse than the bug this file exists for.
        for _ in 0..<5 {
            coordinator.ingest([ActivityEvent(sessionID: id,
                                              kind: .toolStarted(name: "Bash", detail: "swift build"))])
            try await Task.sleep(for: .milliseconds(150))
            tick(coordinator)
            #expect(try session(coordinator, id).mood == .working,
                    "active work was mistaken for silence")
        }
    }

    // MARK: - The bubble, not just the pose

    @Test("Decay clears the stale bubble, the tool, and a pending approval")
    func decayClearsTheWholeAssertion() async throws {
        try await withFastDecay {
            let id = "s-stale"
            let coordinator = try quietCoordinator([id])

            coordinator.ingest([
                ActivityEvent(sessionID: id, kind: .toolStarted(name: "Bash", detail: "git commit")),
                ActivityEvent(sessionID: id, kind: .activeTask("Ship the release")),
                ActivityEvent(sessionID: id, kind: .awaitingApproval(true)),
            ])

            try await Task.sleep(for: .milliseconds(400))
            tick(coordinator)

            let s = try session(coordinator, id)
            #expect(s.mood == .idle)
            // Miss any one of these and the pose relaxes while the words hang.
            #expect(s.tool == nil)
            #expect(s.activity == nil)
            #expect(s.activeTaskLabel == nil, "activeTaskLabel outranks everything in the bubble")
            #expect(s.awaitingApproval == false, "a stale flag re-pins the display to .nudging")
            #expect(coordinator.state.mood != .nudging)
        }
    }

    @Test("A titled session reaches the status ticker instead of freezing on its title")
    func titledSessionReachesTheTicker() async throws {
        try await withFastDecay {
            let id = "s-titled"
            let coordinator = try quietCoordinator([id])

            coordinator.ingest([
                ActivityEvent(sessionID: id, kind: .title("Ship the v1.2.1 release")),
                ActivityEvent(sessionID: id, kind: .turnEnded),
            ])

            try await Task.sleep(for: .milliseconds(400))
            tick(coordinator)

            #expect(coordinator.state.mood == .idle)
            // A title is what a session *is*, not what it is *doing*. Gating idle
            // on `task == nil` let the title stand in for a live task forever.
            #expect(coordinator.state.bubble != "Ship the v1.2.1 release",
                    "the session title froze in the bubble instead of yielding to idle")
        }
    }

    // MARK: - The table itself

    @Test("Only moods that can strand have a quiet limit")
    func quietLimitTable() {
        // Active assertions expire.
        #expect(ActivityCoordinator.quietLimit(for: .done) != nil)
        #expect(ActivityCoordinator.quietLimit(for: .working) != nil)
        #expect(ActivityCoordinator.quietLimit(for: .thinking) != nil)
        #expect(ActivityCoordinator.quietLimit(for: .cooking) != nil)
        #expect(ActivityCoordinator.quietLimit(for: .needsAttention) != nil)

        // These expire on nothing: idle is the floor, and sleeping and nudging
        // are derived at display time rather than stored.
        #expect(ActivityCoordinator.quietLimit(for: .idle) == nil)
        #expect(ActivityCoordinator.quietLimit(for: .sleeping) == nil)
        #expect(ActivityCoordinator.quietLimit(for: .nudging) == nil)

        // Sleep must sit above the stale horizons, or a stranded session skips
        // idle entirely and the status ticker stays unreachable.
        #expect(ActivityCoordinator.sleepAfter > ActivityCoordinator.staleAfter)
        #expect(ActivityCoordinator.sleepAfter > ActivityCoordinator.workingStaleAfter)

        // "Claude is blocked on you" must outlast an ordinary break, or the pet
        // drops the one signal it exists to carry.
        #expect(ActivityCoordinator.attentionStaleAfter > ActivityCoordinator.sleepAfter)
        #expect(ActivityCoordinator.attentionStaleAfter >= 1800)
    }

    @Test("Stale thinking dots retire long before the mood does")
    func staleDotsRetire() async throws {
        let stored = ActivityCoordinator.dotsQuietAfter
        ActivityCoordinator.dotsQuietAfter = 0.15
        defer { ActivityCoordinator.dotsQuietAfter = stored }

        let id = "s-dots"
        let coordinator = try quietCoordinator([id])
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .thinking)])
        #expect(coordinator.state.bubble == "…")
        #expect(coordinator.state.bubbleStyle == .dots)

        try await Task.sleep(for: .milliseconds(300))
        tick(coordinator)

        // The bubble is gone; the pose still thinks (the 300s decay is a
        // separate, much later question).
        #expect(coordinator.state.mood == .thinking)
        #expect(coordinator.state.bubble == nil,
                "dots pulsing over a quiet session are a stale claim")

        // Fresh reasoning brings them straight back.
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .thinking)])
        #expect(coordinator.state.bubble == "…")
    }
}
