import Testing
import Foundation
@testable import ClaudePet

/// The epic cook finale: the stopwatch that decides the tier, the milestone
/// callbacks, the upscale transform, and the overlay envelope.
///
/// Registry fixtures are synthetic files under a scratch `CLAUDE_PET_HOME` in
/// `FileManager.temporaryDirectory` — nothing reads or writes the operator's
/// real `~/.claude/` (the redline).
enum FinaleFixture {

    /// Candidate redirect. `ClaudeHome.root` is a process-wide `static let`,
    /// so whichever suite's fixture touches it first pins it — either way the
    /// winner is a scratch directory, and `register` refuses the real home.
    static let redirect: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pet-finale-\(UUID().uuidString)")
        setenv("CLAUDE_PET_HOME", dir.path, 1)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Adds session files WITHOUT wiping the directory. MoodDecayTests owns
    /// the wipe-and-replace idiom; a second wiper would race it across
    /// suites. Unique ids and unique filenames make additions safe instead.
    static func register(_ ids: [String]) throws {
        _ = redirect
        let real = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        precondition(ClaudeHome.root.path != real.path,
                     "the redline: tests must never write into the real ~/.claude")
        let sessions = ClaudeHome.sessions
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        for id in ids {
            let payload: [String: Any] = [
                "pid": Int(getpid()),
                "sessionId": id,
                "cwd": ClaudeHome.root.appendingPathComponent("work").path,
                "startedAt": Date().timeIntervalSince1970 * 1000,
                "name": "finale-\(id)",
            ]
            try JSONSerialization.data(withJSONObject: payload)
                .write(to: sessions.appendingPathComponent("finale-\(id).json"))
        }
    }
}

/// A coordinator with its timer and watchers stopped, so the test owns the
/// clock. Registration and adoption happen in one synchronous main-actor
/// stretch — no await between them, so no other suite can interleave.
@MainActor
private func quietCoordinator(_ ids: [String]) throws -> ActivityCoordinator {
    try FinaleFixture.register(ids)
    let coordinator = ActivityCoordinator()
    coordinator.start()
    coordinator.stop()
    return coordinator
}

@MainActor
private func session(_ coordinator: ActivityCoordinator, _ id: String) throws -> ClaudeSession {
    try #require(coordinator.state.sessions.first { $0.id == id }, "session \(id) missing")
}

/// The stopwatch that decides the celebration tier: stamped when the cooking
/// pace first appears, immune to the thinking beat, cleared only when the
/// session is fully cold or the turn lands.
@Suite("Cook stopwatch", .serialized)
@MainActor
struct CookStopwatchTests {

    @Test("The stamp lands on the call that reaches cooking pace, and the first stamp wins")
    func stampOnSprint() throws {
        let id = "stopwatch-sprint"
        let coordinator = try quietCoordinator([id])
        let base = Date()

        // Seven rapid calls are a busy session, not yet a cooking one.
        for beat in 0..<(ActivityCoordinator.cookingToolRate - 1) {
            coordinator.ingest([ActivityEvent(
                sessionID: id, kind: .toolStarted(name: "Edit", detail: nil),
                timestamp: base.addingTimeInterval(Double(beat) * 0.01))])
        }
        #expect(try session(coordinator, id).cookingSince == nil)

        // The eighth crosses the rate; its own timestamp becomes the stamp.
        let eighth = base.addingTimeInterval(0.08)
        coordinator.ingest([ActivityEvent(
            sessionID: id, kind: .toolStarted(name: "Edit", detail: nil), timestamp: eighth)])
        #expect(try session(coordinator, id).cookingSince == eighth)

        // Later calls renew the pace but never restamp — a moved stamp would
        // shrink every duration to zero.
        coordinator.ingest([ActivityEvent(
            sessionID: id, kind: .toolStarted(name: "Edit", detail: nil),
            timestamp: base.addingTimeInterval(0.09))])
        #expect(try session(coordinator, id).cookingSince == eighth)
    }

    @Test("A subagent fan-out stamps too, and the thinking beat between tools keeps the clock")
    func stampSurvivesThinkingBeat() throws {
        let id = "stopwatch-thinking"
        let coordinator = try quietCoordinator([id])
        let start = Date()

        coordinator.ingest([ActivityEvent(sessionID: id, kind: .subagents(2), timestamp: start)])
        #expect(try session(coordinator, id).cookingSince == start)

        // The pause between tools is Claude reasoning about a result, not the
        // sprint ending. Clearing here would reset the stopwatch mid-sprint.
        coordinator.ingest([
            ActivityEvent(sessionID: id, kind: .toolFinished(name: "Task")),
            ActivityEvent(sessionID: id, kind: .thinking),
        ])
        #expect(try session(coordinator, id).cookingSince == start)
    }

    @Test("The decay pass clears the stamp only when the session is fully cold")
    func clearsOnlyWhenCold() throws {
        let coordinator = try quietCoordinator(["stopwatch-cold", "stopwatch-fanout"])
        let past = Date().addingTimeInterval(-(ActivityCoordinator.toolRateWindow * 2))
        var started: [String] = []
        coordinator.onCookingProgress = { milestone, session in
            if milestone == .started { started.append(session.id) }
        }

        // A sprint whose calls have all aged out of the rate window. The decay
        // pass rides ingest's own recompute against the real clock, so the
        // clear happens in the same call as the stamp — the `.started`
        // callback is the proof the stamp ever landed.
        coordinator.ingest((0..<ActivityCoordinator.cookingToolRate).map { beat in
            ActivityEvent(sessionID: "stopwatch-cold",
                          kind: .toolStarted(name: "Edit", detail: nil),
                          timestamp: past.addingTimeInterval(Double(beat) * 0.01))
        })
        // The same aged sprint, but subagents still in flight.
        coordinator.ingest((0..<ActivityCoordinator.cookingToolRate).map { beat in
            ActivityEvent(sessionID: "stopwatch-fanout",
                          kind: .toolStarted(name: "Edit", detail: nil),
                          timestamp: past.addingTimeInterval(Double(beat) * 0.01))
        } + [ActivityEvent(sessionID: "stopwatch-fanout", kind: .subagents(3), timestamp: past)])

        #expect(started == ["stopwatch-cold", "stopwatch-fanout"],
                "both sprints must have stamped before the decay pass ruled")
        #expect(try session(coordinator, "stopwatch-cold").cookingSince == nil,
                "no recent calls and no subagents is cold — the clock must clear")
        #expect(try session(coordinator, "stopwatch-fanout").cookingSince != nil,
                "a live fan-out keeps the clock, however old the last tool call")
    }

    @Test("The landing turn reads the stopwatch for the tier, then resets it")
    func tierAtThreshold() throws {
        let coordinator = try quietCoordinator(["stopwatch-epic", "stopwatch-plain"])

        // Shrunk so the tier boundary can be tested without a 60s sleep.
        let threshold = ActivityCoordinator.epicCookThreshold
        ActivityCoordinator.epicCookThreshold = 0.05
        defer { ActivityCoordinator.epicCookThreshold = threshold }

        let now = Date()
        coordinator.ingest([
            ActivityEvent(sessionID: "stopwatch-epic", kind: .subagents(3),
                          timestamp: now.addingTimeInterval(-0.2)),
            ActivityEvent(sessionID: "stopwatch-epic",
                          kind: .toolStarted(name: "Edit", detail: nil),
                          timestamp: now.addingTimeInterval(-0.1)),
            ActivityEvent(sessionID: "stopwatch-epic", kind: .turnEnded, timestamp: now),
        ])
        let epic = try session(coordinator, "stopwatch-epic")
        #expect(epic.celebrating, "a landing sprint still earns the ordinary bow")
        #expect(epic.epicCelebrating, "a cook past the threshold earns the epic tier")
        #expect(epic.cookingSince == nil, "the landing resets the stopwatch")
        #expect(epic.notifiedMilestone == nil, "and the milestone ratchet with it")

        // The same landing under the real 60s threshold: celebrated, not epic.
        ActivityCoordinator.epicCookThreshold = threshold
        coordinator.ingest([
            ActivityEvent(sessionID: "stopwatch-plain", kind: .subagents(3),
                          timestamp: now.addingTimeInterval(-0.2)),
            ActivityEvent(sessionID: "stopwatch-plain",
                          kind: .toolStarted(name: "Edit", detail: nil),
                          timestamp: now.addingTimeInterval(-0.1)),
            ActivityEvent(sessionID: "stopwatch-plain", kind: .turnEnded, timestamp: now),
        ])
        let plain = try session(coordinator, "stopwatch-plain")
        #expect(plain.celebrating && !plain.epicCelebrating,
                "a short cook lands with the ordinary celebration only")
    }
}

/// The milestone callback: cook start plus each quarter crossed, once each,
/// silent during the priming replay.
@Suite("Cook milestones", .serialized)
@MainActor
struct CookMilestoneTests {

    private func cooking(_ coordinator: ActivityCoordinator, _ id: String) {
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .subagents(1))])
    }

    @Test("Cook start fires once; quarters fire once each and never regress")
    func quartersFireOnceEach() throws {
        let id = "milestone-quarters"
        let coordinator = try quietCoordinator([id])
        var fired: [ActivityCoordinator.CookMilestone] = []
        coordinator.onCookingProgress = { milestone, _ in fired.append(milestone) }

        cooking(coordinator, id)
        #expect(fired == [.started])

        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 1, total: 4))])
        #expect(fired == [.started, .fraction(25)])

        // The same tally re-read is not a new crossing.
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 1, total: 4))])
        #expect(fired == [.started, .fraction(25)])

        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 2, total: 4))])
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 3, total: 4))])
        #expect(fired == [.started, .fraction(25), .fraction(50), .fraction(75)])

        // 100% belongs to the Done chime, not the progress card.
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 4, total: 4))])
        #expect(fired.count == 4)
    }

    @Test("A tally that jumps fires only the highest quarter crossed")
    func jumpFiresHighestOnly() throws {
        let id = "milestone-jump"
        let coordinator = try quietCoordinator([id])
        var fired: [ActivityCoordinator.CookMilestone] = []
        coordinator.onCookingProgress = { milestone, _ in fired.append(milestone) }

        cooking(coordinator, id)
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 3, total: 4))])
        #expect(fired == [.started, .fraction(75)],
                "one banner replaced in place, not a burst of three")
    }

    @Test("The gates hold: no bar under three tasks, no bar when not cooking")
    func gatesHold() throws {
        let coordinator = try quietCoordinator(["milestone-short", "milestone-idle"])
        var fired: [ActivityCoordinator.CookMilestone] = []
        coordinator.onCookingProgress = { milestone, _ in fired.append(milestone) }

        // Two tasks is the same gate the near-done glow uses — a bar over a
        // two-item list is noise.
        cooking(coordinator, "milestone-short")
        coordinator.ingest([ActivityEvent(sessionID: "milestone-short",
                                          kind: .taskProgress(completed: 1, total: 2))])
        #expect(fired == [.started])

        // A tally moving without the cooking pace is ordinary work.
        coordinator.ingest([ActivityEvent(sessionID: "milestone-idle",
                                          kind: .taskProgress(completed: 2, total: 4))])
        #expect(fired == [.started])
    }

    @Test("The landing resets the ratchet: a fresh cook re-fires from the start")
    func resetOnTurnEnded() throws {
        let id = "milestone-reset"
        let coordinator = try quietCoordinator([id])
        var fired: [ActivityCoordinator.CookMilestone] = []
        coordinator.onCookingProgress = { milestone, _ in fired.append(milestone) }

        cooking(coordinator, id)
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 1, total: 4))])
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnEnded)])
        #expect(fired == [.started, .fraction(25)])

        // The next sprint is a new story with its own card.
        cooking(coordinator, id)
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .taskProgress(completed: 1, total: 4))])
        #expect(fired == [.started, .fraction(25), .started, .fraction(25)])
    }

    @Test("The priming replay fires nothing — a stale 75% banner is the disease")
    func suppressedDuringPriming() throws {
        let id = "milestone-priming"
        let coordinator = try quietCoordinator([id])
        var fired: [ActivityCoordinator.CookMilestone] = []
        coordinator.onCookingProgress = { milestone, _ in fired.append(milestone) }

        coordinator.ingest([
            ActivityEvent(sessionID: id, kind: .subagents(1)),
            ActivityEvent(sessionID: id, kind: .taskProgress(completed: 3, total: 4)),
        ], suppressAlerts: true)
        #expect(fired.isEmpty)
    }
}

/// The upscale path through `PixelBuffer.scaled`: the epic transform grows
/// him with his feet pinned, cropping at the grid's top edge.
@Suite("The upscale grid")
struct UpscaleGridTests {

    /// A full-height single column: `.eye` as the top-row sentinel, `.body`
    /// below it.
    private func column() -> PixelBuffer {
        var buffer = PixelBuffer()
        for y in 0..<PixelBuffer.side {
            buffer[15, y] = y == 0 ? .eye : .body
        }
        return buffer
    }

    @Test("Growing keeps the feet on the ground and crops at the crown")
    func feetPinnedTopCropped() {
        let grown = column().scaled(1.2)

        // The bottom row maps to itself — he grows upward from the ground,
        // never floats off it.
        #expect(grown[15, PixelBuffer.side - 1] == .body)

        // The top-row sentinel left the grid: content that grows past row 0
        // is simply gone for the beat it is gone.
        var sentinelSurvives = false
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where grown[x, y] == .eye {
                sentinelSurvives = true
            }
        }
        #expect(!sentinelSurvives, "an upscale must crop at the grid's top edge")
    }

    @Test("The guard bounds the factor: at 2x and beyond the grid is untouched")
    func guardReturnsSelfAtTwo() {
        let original = column()
        let doubled = original.scaled(2.0)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                #expect(doubled[x, y] == original[x, y])
            }
        }
    }
}

/// The epic overlay: bounded transform, prop dissolve at the peak, tint
/// endpoints dark, and the click that dents rather than snaps.
@Suite("Epic overlay", .serialized)
@MainActor
struct EpicOverlayTests {

    @Test("The epic envelope is bounded, and outside the peak it IS the plain celebration")
    func epicEnvelopeIsBounded() {
        for t in stride(from: 0.0, through: 10.0, by: 0.25) {
            var pose = CrabAnimator.pose(mood: .done, t: t)
            CrabAnimator.applyCelebration(t: t, epic: true, to: &pose)
            #expect(pose.scale <= 1.2001, "the transform overshoots at t=\(t)")
            #expect(pose.scale >= 0.94, "breathing too deep at t=\(t)")
        }

        // The peak's support is [1.2, 3.4]; everywhere else the epic path
        // must be byte-identical to the plain one.
        for t in [0.5, 4.0, 8.0] {
            var plain = CrabAnimator.pose(mood: .done, t: t)
            var epic = plain
            CrabAnimator.applyCelebration(t: t, to: &plain)
            CrabAnimator.applyCelebration(t: t, epic: true, to: &epic)
            #expect(plain == epic, "outside the peak the tiers must agree at t=\(t)")
        }

        // Past the master envelope the overlay does nothing at either tier.
        var pose = CrabAnimator.pose(mood: .done, t: 11.5)
        let before = pose
        CrabAnimator.applyCelebration(t: 11.5, epic: true, to: &pose)
        #expect(pose == before)
    }

    @Test("The peak rises after the flash, tops out inside the window, and settles by t=4")
    func epicPeakEnvelope() {
        #expect(CrabAnimator.epicPeak(doneT: 0) == 0, "frozen sentinel: nothing at t=0")
        #expect(CrabAnimator.epicPeak(doneT: 2.3) > 0.99)
        #expect(CrabAnimator.epicPeak(doneT: 4.0) == 0, "settled back before the hops resume")
    }

    @Test("The overhead check dissolves through the transform's peak")
    func propDissolvesAtPeak() {
        var pose = CrabAnimator.pose(mood: .done, t: 2.3)
        pose.propVisibility = 1
        CrabAnimator.applyCelebration(t: 2.3, epic: true, to: &pose)
        #expect(pose.propVisibility <= 0.05,
                "a 1.2x check is a mangled fragment — absence reads better")
    }

    @Test("The epic tint fires mid-window and is dark at both ends")
    func epicTintEndpoints() {
        #expect(CrabView.epicTint(doneT: 0) == nil, "frozen sentinel")
        #expect(CrabView.epicTint(doneT: 10.5) == nil)
        var lit = false
        for t in stride(from: 0.5, through: 9.0, by: 0.1) where CrabView.epicTint(doneT: t) != nil {
            lit = true
            break
        }
        #expect(lit)
    }

    @Test("The epic adds one apex tap, and is otherwise the standard double-tap")
    func epicBlanchAddsTheApexTap() {
        #expect(CrabView.epicBlanch(doneT: 0) == 0, "frozen sentinel")
        #expect(CrabView.epicBlanch(doneT: 10.5) == 0)

        // The third tap fires at full white ON the transform's apex — the
        // loudest moment in the app gets the longest hold.
        #expect(CrabView.epicBlanch(doneT: 2.35) == 1.0)
        #expect(CrabAnimator.epicPeak(doneT: 2.35) > 0.99,
                "the apex tap must land on the peak, not beside it")

        // Everywhere outside its own tap, the epic IS the plain celebration.
        for t in [0.35, 0.74, 0.92, 5.0, 9.5] {
            #expect(CrabView.epicBlanch(doneT: t) == CrabView.celebrationBlanch(doneT: t),
                    "the tiers diverge at t=\(t)")
        }
    }

    @Test("A poke mid-transform dents the current scale instead of snapping it to 1")
    func clickComposesMultiplicatively() {
        var pose = CrabAnimator.pose(mood: .done, t: 2.3)
        pose.scale = 1.2
        // Peak compression sits at 35% of the click.
        let elapsed = 0.35 * CrabAnimator.clickDuration
        CrabAnimator.applyClick(elapsed: elapsed, to: &pose)
        #expect(abs(pose.scale - 1.2 * 0.78) < 1e-6,
                "the squash must scale what it finds, not assign over it")
    }
}

/// The text bar inside the cooking notification.
@Suite("Cook progress bar")
@MainActor
struct ProgressBarTests {

    @Test func barTracksTheQuarters() {
        #expect(AppDelegate.progressBar(25) == "▓▓░░░░░░ 25%")
        #expect(AppDelegate.progressBar(50) == "▓▓▓▓░░░░ 50%")
        #expect(AppDelegate.progressBar(75) == "▓▓▓▓▓▓░░ 75%")
        #expect(AppDelegate.progressBar(100) == "▓▓▓▓▓▓▓▓ 100%")
    }

    @Test func barClampsNonsense() {
        #expect(AppDelegate.progressBar(-10) == "░░░░░░░░ 0%")
        #expect(AppDelegate.progressBar(400) == "▓▓▓▓▓▓▓▓ 100%")
    }
}
