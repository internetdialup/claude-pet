import Testing
import Foundation
import AppKit
import SwiftUI
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

    /// Asserted at NAMED times, never by scanning for "lit somewhere". The old
    /// tint dwelled near its peak for most of ten seconds, so a scan always
    /// found it; a hard double-tap is mostly OFF, and a scan that happened to
    /// land on a plateau would be luck rather than a pin.
    @Test("The flashbang is a hard double-tap at pure white, then nothing")
    func celebrationBlanchIsAHardDoubleTap() {
        #expect(CrabView.celebrationBlanch(doneT: 0) == 0, "frozen sentinel")
        #expect(CrabView.celebrationBlanch(doneT: -1) == 0)
        #expect(CrabView.celebrationBlanch(doneT: 10.5) == 0)

        // The redline: both taps reach EXACTLY white. A partial push toward
        // white over terracotta is a peach, and the peach was the bug.
        #expect(CrabView.celebrationBlanch(doneT: 0.35) == 1.0)
        #expect(CrabView.celebrationBlanch(doneT: 0.92) == 1.0)

        // …with real terracotta between them, or it is a wash, not a double-tap.
        #expect(CrabView.celebrationBlanch(doneT: 0.74) == 0)

        // …and the nine seconds after the event are flash-free, which is the
        // whole point: the dwell WAS the washed-out monitor.
        for t in stride(from: 1.20, through: 10.0, by: 0.02) {
            #expect(CrabView.celebrationBlanch(doneT: t) == 0, "still lit at t=\(t)")
        }
    }

    @Test("No frame at the live 30fps tick jumps the blanch more than half way")
    func blanchNeverSnaps() {
        var previous = 0.0
        for step in 0...360 {
            let value = CrabView.epicBlanch(doneT: Double(step) / 30)
            #expect(value >= 0 && value <= 1, "out of contract at step \(step)")
            #expect(abs(value - previous) < 0.60,
                    "a \(abs(value - previous)) jump at step \(step) is a snap, not an attack")
            previous = value
        }
    }

    /// The README GIF samples the finale at 10fps. Every tap start on the 0.1s
    /// grid with `flashAttack < 0.10 < attack + hold` means the sample at
    /// `at + 0.10` always lands strictly inside the plateau. Break any of the
    /// three and the GIF silently starts sampling flanks — a mediocre README
    /// with no error anywhere.
    @Test("Every flash start survives the README GIF's 10fps sampling")
    func flashesSurviveTenFps() {
        for tap in CrabView.celebrationFlashes + [CrabView.epicFlash] {
            #expect(abs(tap.at * 10 - (tap.at * 10).rounded()) < 1e-9,
                    "\(tap.at) misses the 0.1s grid")
            #expect(CrabView.flashAttack < 0.10)
            #expect(tap.hold > 0.01)
            #expect(CrabView.epicBlanch(doneT: tap.at + 0.10) == 1.0,
                    "the 10fps sample after \(tap.at) missed the plateau")
        }
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

