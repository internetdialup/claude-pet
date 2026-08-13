import Testing
import Foundation
@testable import ClaudePet

/// Task-progress plumbing and the cooking→done celebration. Fixtures are
/// synthetic JSON in `FileManager.temporaryDirectory` — nothing reads the
/// operator's real `~/.claude/` (the redline).
@Suite("Task progress")
struct TaskProgressTests {

    private func taskDir(_ statuses: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pet-tasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, status) in statuses.enumerated() {
            let payload: [String: Any] = [
                "id": "\(index)", "subject": "task \(index)",
                "activeForm": "Doing task \(index)", "status": status,
            ]
            try JSONSerialization.data(withJSONObject: payload)
                .write(to: dir.appendingPathComponent("\(index).json"))
        }
        return dir
    }

    @Test func countsCompletedOverTotal() throws {
        let dir = try taskDir(["completed", "completed", "in_progress", "pending"])
        let progress = try #require(TaskWatcher.progress(in: dir))
        #expect(progress.completed == 2)
        #expect(progress.total == 4)
    }

    @Test func emptyDirectoryIsNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pet-tasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(TaskWatcher.progress(in: dir) == nil)
    }

    @Test func allDoneIsFullFraction() throws {
        let dir = try taskDir(["completed", "completed", "completed"])
        let progress = try #require(TaskWatcher.progress(in: dir))
        #expect(progress.completed == progress.total)
    }

    /// The tally must not count as activity — it rides the same watcher as the
    /// label, and a re-read is not Claude doing something.
    @Test func progressEventIsNotActivity() {
        let event = ActivityEvent(sessionID: "s",
                                  kind: .taskProgress(completed: 1, total: 3))
        #expect(!event.countsAsActivity)
    }
}

/// The celebration contract: only a landing sprint earns the long bow, and the
/// stretched decay is exactly the celebrated path's.
@Suite("Celebration", .serialized)
@MainActor
struct CelebrationTests {

    @Test func quietLimitStretchesOnlyWhenCelebrating() {
        #expect(ActivityCoordinator.quietLimit(for: .done) == ActivityCoordinator.doneDecay)
        #expect(ActivityCoordinator.quietLimit(for: .done, celebrating: true)
                == ActivityCoordinator.celebrationDecay)
        // No other mood cares about the flag.
        for mood in PetMood.allCases where mood != .done {
            #expect(ActivityCoordinator.quietLimit(for: mood)
                    == ActivityCoordinator.quietLimit(for: mood, celebrating: true))
        }
        #expect(ActivityCoordinator.celebrationDecay > 10,
                "the decay must outlast the 10s payoff animation")
    }

    /// The pose overlay stays inside its envelope: nothing before t=0, nothing
    /// after the cool-down, and the scale breathing never exceeds ~1.5px.
    @Test func celebrationEnvelopeIsBounded() {
        var pose = CrabAnimator.pose(mood: .done, t: 11.5)
        let before = pose
        CrabAnimator.applyCelebration(t: 11.5, to: &pose)
        #expect(pose == before, "past the envelope the overlay must do nothing")

        for t in stride(from: 0.0, through: 10.0, by: 0.25) {
            var p = CrabAnimator.pose(mood: .done, t: t)
            CrabAnimator.applyCelebration(t: t, to: &p)
            #expect(p.scale >= 0.95, "breathing too deep at t=\(t)")
            #expect(p.bob >= -3)
        }
    }

    @Test func celebrationTintCoolsToNothing() {
        // Fires somewhere in the middle…
        var lit = false
        for t in stride(from: 0.5, through: 9.0, by: 0.1) where CrabView.celebrationTint(doneT: t) != nil {
            lit = true
            break
        }
        #expect(lit)
        // …and is gone at both ends.
        #expect(CrabView.celebrationTint(doneT: 0) == nil)
        #expect(CrabView.celebrationTint(doneT: 10.5) == nil)
    }
}

/// Heat and disco schedules: deterministic, bounded, and silent at t=0.
@Suite("Heat and disco")
struct HeatAndDiscoScheduleTests {

    @Test func heatIsDeterministicAndBounded() {
        for t in stride(from: 0.0, through: 120.0, by: 0.5) {
            let a = CrabAnimator.pose(mood: .cooking, t: t)
            let b = CrabAnimator.pose(mood: .cooking, t: t)
            #expect(a.heat == b.heat)
            #expect(a.heat >= 0 && a.heat <= 1)
        }
        // The first cycle never heats (frozen sentinel).
        for t in stride(from: 0.0, through: 7.9, by: 0.2) {
            #expect(CrabAnimator.pose(mood: .cooking, t: t).heat == 0)
        }
        // And it does fire on some later cycle.
        var fired = false
        for t in stride(from: 8.0, through: 240.0, by: 0.4) where CrabAnimator.pose(mood: .cooking, t: t).heat > 0.5 {
            fired = true
            break
        }
        #expect(fired, "the cascade should hit within a few minutes of cooking")
    }

    @Test func heatRepaintsOnlyBodyCells() {
        var pose = CrabAnimator.pose(mood: .cooking, t: 2)
        pose.heat = 1
        pose.heatPhase = 0.4
        let cool = { () -> PixelBuffer in
            var p = pose
            p.heat = 0
            return CrabRig.render(p)
        }()
        let hot = CrabRig.render(pose)
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                let was = cool[x, y]
                let now = hot[x, y]
                if was != now {
                    #expect(was == .body && (now == .bodyHot || now == .bodyEmber),
                            "heat changed a non-body cell at (\(x),\(y)): \(was) → \(now)")
                }
            }
        }
    }

    @Test func discoNeverFiresEarlyAndKeepsItsGap() {
        #expect(CrabView.discoTint(cookingT: 0) == nil)
        for t in stride(from: 0.0, through: 44.9, by: 0.5) {
            #expect(CrabView.discoTint(cookingT: t) == nil, "disco in the first cycle at t=\(t)")
        }
        // Over two hours of cooking: every lit window sits inside its own 45s
        // cycle, so consecutive flashes are at least 40s apart.
        var litWindows: [Double] = []
        var t = 0.0
        while t < 7200 {
            if CrabView.discoTint(cookingT: t) != nil {
                litWindows.append(t)
                t += 6      // skip past this window
            } else {
                t += 0.5
            }
        }
        for pair in zip(litWindows, litWindows.dropFirst()) {
            #expect(pair.1 - pair.0 >= 40, "two discos \(pair.1 - pair.0)s apart")
        }
        #expect(!litWindows.isEmpty, "two hours of cooking deserves at least one disco")
    }

    @Test func nearDoneGlowNeedsARealList() {
        #expect(CrabView.nearDoneTint(cookingT: 3, fraction: nil) == nil)
        #expect(CrabView.nearDoneTint(cookingT: 3, fraction: 0.5) == nil)
        var lit = false
        for t in stride(from: 0.0, through: 3.0, by: 0.1) where CrabView.nearDoneTint(cookingT: t, fraction: 0.9) != nil {
            lit = true
            break
        }
        #expect(lit, "a 90% list should glow within one pulse period")
    }
}
