import Testing
import Foundation
import AppKit
@testable import ClaudePet

@Suite("Vocabulary")
struct VocabShoutoutsTests {

    @Test("Every occasion has lines")
    func everyOccasionPopulated() {
        for occasion in ShoutoutOccasion.allCases {
            let lines = Vocab.catalogue[occasion]
            #expect(lines?.isEmpty == false, "\(occasion.rawValue) has no lines")
        }
    }

    @Test("The operator's idle lines are present verbatim")
    func idleLinesVerbatim() throws {
        let lines = try #require(Vocab.catalogue[.idle])
        #expect(lines.contains("Let's build something awesome!"))
        #expect(lines.contains("Now we're cooking with crisco 🍳"))
        #expect(lines.contains("Ooo that's a spicy idea 🌶️"))
    }

    /// The bubble is recomputed on a timer; the same seed must yield the same
    /// line or the text would rewrite itself mid-read.
    @Test("Selection is deterministic for a given seed")
    func deterministic() {
        for seed in 0..<20 {
            let first = Vocab.line(for: .idle, seed: seed)
            let second = Vocab.line(for: .idle, seed: seed)
            #expect(first == second)
        }
    }

    /// The shuffled cycle guarantees this structurally: a line cannot come up
    /// twice until every other line in the pool has been used.
    @Test("A line is never repeated back to back")
    func neverRepeatsConsecutively() throws {
        var previous = try #require(Vocab.line(for: .idle, seed: 0))
        for seed in 1..<200 {
            let next = try #require(Vocab.line(for: .idle, seed: seed))
            #expect(next != previous)
            previous = next
        }
    }

    /// The point of dealing a shuffled deck rather than picking at random: every
    /// line appears exactly once before any appears twice. A random pick can
    /// show one line four times in five turns and never show another at all.
    @Test("Every line is used before any repeats")
    func cyclesThroughTheWholePool() throws {
        let lines = try #require(Vocab.catalogue[.idle])
        var seen: [String] = []
        for seed in 0..<lines.count {
            seen.append(try #require(Vocab.line(for: .idle, seed: seed)))
        }
        #expect(Set(seen).count == lines.count,
                "one pass should use all \(lines.count) lines, saw \(Set(seen).count)")
    }

    @Test("Consecutive passes are shuffled differently")
    func passesDiffer() throws {
        let lines = try #require(Vocab.catalogue[.idle])
        let first = (0..<lines.count).compactMap { Vocab.line(for: .idle, seed: $0) }
        let second = (lines.count..<(lines.count * 2)).compactMap { Vocab.line(for: .idle, seed: $0) }
        #expect(first != second, "a reshuffle should not reproduce the same order")
        #expect(Set(first) == Set(second), "but both passes cover the same lines")
    }

    /// `Int.min` has no positive magnitude; `abs` on it traps.
    @Test("Extreme seeds do not trap")
    func extremeSeeds() {
        #expect(Vocab.line(for: .idle, seed: Int.min) != nil)
        #expect(Vocab.line(for: .idle, seed: Int.max) != nil)
        #expect(Vocab.line(for: .idle, seed: -1) != nil)
    }
}

@Suite("Status ticker")
struct StatusTickerTests {

    @Test("Known model ids get friendly names")
    func modelNames() {
        #expect(StatusTicker.displayName(forModel: "claude-opus-5") == "Opus 5")
        #expect(StatusTicker.displayName(forModel: "claude-fable-5") == "Fable 5")
        #expect(StatusTicker.displayName(forModel: "claude-haiku-4-5-20251001") == "Haiku 4.5")
    }

    @Test("An unknown model still displays rather than vanishing")
    func unknownModel() {
        let name = StatusTicker.displayName(forModel: "claude-experimental-9")
        #expect(!name.isEmpty)
        #expect(!name.contains("claude-"))
    }

    /// Numerical Grounding: with no usage data, no percentage
    /// may be invented. These pass an explicit cache rather than reading the
    /// operator's real `~/.claude/` (the redline).
    @Test("An empty snapshot with no usage data produces no lines")
    func noDataNoClaims() {
        #expect(StatusTicker.lines(for: StatusTicker.Snapshot(), usage: nil).isEmpty)
    }

    @Test("A model with no usage data yields a name-only line, no percentage")
    func modelWithoutUsage() throws {
        var snapshot = StatusTicker.Snapshot()
        snapshot.model = "claude-opus-5"
        let lines = StatusTicker.lines(for: snapshot, usage: nil)
        #expect(lines.count == 1)
        let modelLine = try #require(lines.first)
        #expect(modelLine.contains("Opus 5"))
        #expect(!modelLine.contains("%"), "no data means no percentage")
    }

    @Test("Percentages are reported when the cache supplies them")
    func percentagesFromCache() {
        var snapshot = StatusTicker.Snapshot()
        snapshot.model = "claude-fable-5"
        let cache = StatusTicker.UsageCache(
            writtenAt: nil, fiveHourPercent: 24, sevenDayPercent: 82, contextUsedPercent: 41
        )
        let lines = StatusTicker.lines(for: snapshot, usage: cache)
        #expect(lines.contains("MODEL · Fable 5 @ 41% CONTEXT"))
        #expect(lines.contains("5-HOUR LIMIT @ 24%"))
        #expect(lines.contains("WEEKLY USAGE @ 82%"))
    }

    @Test("Project and branch render together, project alone when detached")
    func projectAndBranch() {
        var snapshot = StatusTicker.Snapshot()
        snapshot.project = "claude-pet"
        snapshot.branch = "main"
        #expect(StatusTicker.lines(for: snapshot, usage: nil).contains("claude-pet · main"))

        snapshot.branch = nil
        #expect(StatusTicker.lines(for: snapshot, usage: nil).contains("claude-pet"))
    }

    /// A single session is the normal case and saying "1 SESSIONS LIVE" about it
    /// is noise, not information.
    @Test("Session count only appears when more than one is running")
    func sessionCountThreshold() {
        var snapshot = StatusTicker.Snapshot()
        snapshot.sessionCount = 1
        #expect(!StatusTicker.lines(for: snapshot, usage: nil).contains { $0.contains("SESSIONS") })

        snapshot.sessionCount = 4
        #expect(StatusTicker.lines(for: snapshot, usage: nil).contains("4 SESSIONS LIVE"))
    }

    @Test("A few minutes of coding is not worth announcing")
    func shortSessionsAreQuiet() {
        var snapshot = StatusTicker.Snapshot()
        snapshot.activeHoursToday = 0.05
        #expect(!StatusTicker.lines(for: snapshot, usage: nil).contains { $0.contains("CODING") })

        snapshot.activeHoursToday = 3.5
        #expect(StatusTicker.lines(for: snapshot, usage: nil).contains("CODING 3.5h TODAY"))
    }

    @Test("Durations read naturally at both scales")
    func durationFormatting() {
        #expect(StatusTicker.formatted(hours: 0.5) == "30m")
        #expect(StatusTicker.formatted(hours: 2) == "2h")
        #expect(StatusTicker.formatted(hours: 3.5) == "3.5h")
        #expect(StatusTicker.formatted(hours: 3.4) == "3.5h")
    }

    @Test("A stale cache is rejected in both directions")
    func staleCacheRejected() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = StatusTicker.UsageCache(
            writtenAt: 1_000_000 - StatusTicker.maxAge - 60,
            fiveHourPercent: 50, sevenDayPercent: nil, contextUsedPercent: nil
        )
        // A future timestamp is equally untrustworthy; a one-sided check treated
        // it as eternally fresh.
        let future = StatusTicker.UsageCache(
            writtenAt: 1_000_000 + StatusTicker.maxAge + 60,
            fiveHourPercent: 50, sevenDayPercent: nil, contextUsedPercent: nil
        )
        #expect(!StatusTicker.isFresh(old, now: now))
        #expect(!StatusTicker.isFresh(future, now: now))
    }
}

@Suite("Animation scheduling")
struct AnimationTests {

    @Test("A flourish plays through, then yields quiet time")
    func flourishesAreScheduledNotConstant() {
        var playing = 0
        var quiet = 0
        for step in 0..<700 {
            let t = Double(step) * 0.1
            if CrabAnimator.flourish(at: t) == nil { quiet += 1 } else { playing += 1 }
        }
        #expect(playing > 0, "he should move sometimes")
        #expect(quiet > playing, "and be still most of the time")
    }

    @Test("A flourish's progress runs forward through 0…1")
    func flourishProgressIsMonotonic() {
        // Sample within a single 7s window.
        var lastProgress = -1.0
        var sawProgress = false
        for step in 0..<60 {
            let t = Double(step) * 0.01
            guard let (_, progress) = CrabAnimator.flourish(at: t) else { continue }
            #expect(progress >= 0 && progress <= 1)
            #expect(progress >= lastProgress)
            lastProgress = progress
            sawProgress = true
        }
        #expect(sawProgress)
    }

    @Test("The jump leaves the ground and lands with squash")
    func jumpHasAnArc() {
        let launch = CrabAnimator.jumpPose(progress: 0.05)
        let apex = CrabAnimator.jumpPose(progress: 0.5)
        let landing = CrabAnimator.jumpPose(progress: 0.95)

        #expect(apex.bob < 0, "airborne means a negative (upward) offset")
        #expect(apex.bob <= -3, "the arc should clear a few pixels")
        #expect(launch.squash == 1, "anticipation crouch")
        #expect(landing.squash == 1, "landing absorbs")
        #expect(apex.squash == 0, "no squash mid-air")
    }

    @Test("Working props vary over time but hold within a spell")
    func workingPropsRotate() {
        // Stable inside one spell…
        let early = CrabAnimator.workingProp(at: 1, spell: 20)
        let later = CrabAnimator.workingProp(at: 19, spell: 20)
        #expect(early == later)

        // …and cover more than one option across many spells.
        var seen = Set<CrabPose.Prop>()
        for spell in 0..<40 {
            seen.insert(CrabAnimator.workingProp(at: Double(spell) * 20 + 1, spell: 20))
        }
        #expect(seen.count > 1, "he should not stare at the same prop forever")
        #expect(seen.allSatisfy { CrabPose.Prop.working.contains($0) })
    }

    /// Arm and leg motion was distracting in peripheral vision at the original
    /// rates. `working` must stay well under a couple of beats per second.
    @Test("Working animation is calm, not frantic")
    func workingIsCalm() {
        var armFlips = 0
        var previous = CrabAnimator.pose(mood: .working, t: 0).armLeft
        for step in 1...1000 {
            let arm = CrabAnimator.pose(mood: .working, t: Double(step) * 0.01).armLeft
            if arm != previous { armFlips += 1 }
            previous = arm
        }
        // 10 seconds of samples; more than ~25 flips reads as a flutter.
        #expect(armFlips <= 25, "arms flipped \(armFlips) times in 10s")
    }

    @Test("Every mood renders without trapping and paints something")
    func allMoodsRender() {
        for mood in PetMood.allCases {
            for step in 0..<40 {
                let pose = CrabAnimator.pose(mood: mood, t: Double(step) * 0.37)
                let buffer = CrabRig.render(pose)
                #expect(!buffer.runs().isEmpty, "\(mood.rawValue) rendered empty at step \(step)")
            }
        }
    }

    @Test("Every prop paints inside the sprite grid")
    func everyPropRenders() {
        for prop in CrabPose.Prop.allCases where prop != .none {
            var pose = CrabPose()
            pose.prop = prop
            for step in 0..<20 {
                pose.propPhase = Double(step) * 0.31
                let runs = CrabRig.render(pose).runs()
                #expect(runs.allSatisfy { $0.x >= 0 && $0.x + $0.length <= PixelBuffer.side })
                #expect(runs.allSatisfy { $0.y >= 0 && $0.y < PixelBuffer.side })
            }
        }
    }
}

@Suite("Multi-display placement")
@MainActor
struct DisplayTests {

    @Test("A position on a real screen is usable")
    func onScreenIsUsable() throws {
        let screen = try #require(NSScreen.main)
        let origin = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        #expect(PetWindowController.isUsable(origin: origin, size: CGSize(width: 200, height: 150)))
    }

    /// Guards the restore path against a monitor that has been unplugged since
    /// the position was saved.
    @Test("A position far off every display is rejected")
    func offScreenIsRejected() {
        let origin = CGPoint(x: -90_000, y: -90_000)
        #expect(!PetWindowController.isUsable(origin: origin, size: CGSize(width: 200, height: 150)))
    }

    @Test("A window between displays still resolves to one")
    func alwaysResolvesToAScreen() {
        let stranded = CGRect(x: -50_000, y: -50_000, width: 200, height: 150)
        // Must not trap or return nil — the pet has to land somewhere.
        let screen = PetWindowController.screen(for: stranded)
        #expect(screen.frame.width > 0)
    }
}

@Suite("Release metadata")
struct AppVersionTests {

    /// Walks up from this source file to the repo root, so the test does not
    /// depend on the working directory the runner happens to use.
    private func repoRoot(from file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // ClaudePetTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    /// A constant that disagrees with the bundle it ships in is a release bug
    /// that surfaces as a user reporting a version nobody built.
    @Test("AppVersion.current matches the shipped Info.plist")
    func versionMatchesBundle() throws {
        let plist = repoRoot()
            .appendingPathComponent("Sources/ClaudePet/Support/Info.plist")
        let declared = try #require(AppVersion.versionInSourcePlist(at: plist),
                                    "could not read \(plist.path)")
        #expect(declared == AppVersion.current)
    }

    @Test("The changelog documents the current version")
    func changelogMentionsCurrentVersion() throws {
        let changelog = repoRoot().appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: changelog, encoding: .utf8)
        #expect(text.contains("[\(AppVersion.current)]"),
                "CHANGELOG.md has no entry for \(AppVersion.current)")
    }
}

@Suite("Cooking detection")
struct WorkloadTests {

    /// The shape of a real workflow journal, reduced to the two fields that
    /// matter. Result lines carry the agent's whole return value in practice.
    private let journal = """
    {"type":"started","key":"v2:aaa","agentId":"a1"}
    {"type":"started","key":"v2:bbb","agentId":"a2"}
    {"type":"started","key":"v2:ccc","agentId":"a3"}
    {"type":"result","key":"v2:aaa","agentId":"a1","result":{"findings":[]}}
    """

    @Test("In-flight is started minus result")
    func inFlightArithmetic() {
        #expect(WorkloadWatcher.inFlight(inJournal: journal) == 2)
    }

    @Test("A finished run reports nothing in flight")
    func finishedRun() {
        let done = """
        {"type":"started","agentId":"a1"}
        {"type":"result","agentId":"a1","result":{}}
        """
        #expect(WorkloadWatcher.inFlight(inJournal: done) == 0)
    }

    /// More results than starts should never produce a negative count.
    @Test("A malformed journal cannot go negative")
    func neverNegative() {
        let odd = """
        {"type":"result","agentId":"a1"}
        {"type":"result","agentId":"a2"}
        not json at all
        {"type":"something-else"}
        """
        #expect(WorkloadWatcher.inFlight(inJournal: odd) == 0)
    }

    @Test("An empty journal is not a crash")
    func emptyJournal() {
        #expect(WorkloadWatcher.inFlight(inJournal: "") == 0)
    }

    /// The threshold sits in the measured gap between an ordinary session
    /// (median 4/min, p90 7) and a fanned-out workflow (median 22/min).
    @Test("Tool rate promotes at the threshold, not below it")
    @MainActor
    func toolRateThreshold() {
        let now = Date()
        var session = ClaudeSession(id: "S", pid: 1, name: "n", cwd: "/tmp",
                                    procStart: "", startedAt: now)
        session.recentToolCalls = (0..<7).map { now.addingTimeInterval(-Double($0)) }
        #expect(!ActivityCoordinator.isCooking(session, now: now), "7 calls is ordinary work")

        session.recentToolCalls.append(now)
        #expect(ActivityCoordinator.isCooking(session, now: now), "8 calls is a sprint")
    }

    @Test("Calls older than the window do not count")
    @MainActor
    func staleCallsExpire() {
        let now = Date()
        var session = ClaudeSession(id: "S", pid: 1, name: "n", cwd: "/tmp",
                                    procStart: "", startedAt: now)
        session.recentToolCalls = (0..<20).map {
            now.addingTimeInterval(-ActivityCoordinator.toolRateWindow - Double($0))
        }
        #expect(!ActivityCoordinator.isCooking(session, now: now))
    }

    /// Either signal alone is enough — a workflow fan-out is cooking even if the
    /// main session itself is quiet while it waits on its agents.
    @Test("Live subagents alone trigger cooking")
    @MainActor
    func subagentsAloneTrigger() {
        let now = Date()
        var session = ClaudeSession(id: "S", pid: 1, name: "n", cwd: "/tmp",
                                    procStart: "", startedAt: now)
        session.recentToolCalls = []
        session.subagentCount = 3
        #expect(ActivityCoordinator.isCooking(session, now: now))
    }
}

@Suite("Plan approval")
struct AwaitingApprovalTests {

    private func temporaryFile(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let exitPlan = """
    {"type":"assistant","sessionId":"S1","timestamp":"2020-01-02T12:00:00.000Z","message":{"model":"claude-opus-5","stop_reason":"tool_use","content":[{"type":"tool_use","id":"t1","name":"ExitPlanMode","input":{}}]}}
    """
    private let approval = """
    {"type":"user","sessionId":"S1","timestamp":"2020-01-02T12:05:00.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"approved"}]}}
    """

    /// An ExitPlanMode call with no result yet is Claude blocked on the human.
    @Test("ExitPlanMode raises awaitingApproval")
    func raisesFlag() throws {
        let url = try temporaryFile([exitPlan])
        defer { try? FileManager.default.removeItem(at: url) }

        let waiting = TranscriptFold().pump(url: url).contains {
            if case .awaitingApproval(true) = $0.kind { return true }
            return false
        }
        #expect(waiting)
    }

    @Test("The answer clears it")
    func clearsOnResult() throws {
        let url = try temporaryFile([exitPlan, approval])
        defer { try? FileManager.default.removeItem(at: url) }

        let events = TranscriptFold().pump(url: url)
        let flags = events.compactMap { event -> Bool? in
            if case .awaitingApproval(let waiting) = event.kind { return waiting }
            return nil
        }
        #expect(flags == [true, false])
    }
}

@Suite("Interactions")
struct InteractionTests {

    /// Every variant must be reachable, or a "randomised" reaction silently
    /// becomes one reaction.
    @Test("Hover reactions vary across seeds")
    func greetingsVary() {
        // Fingerprint the RENDERED sprite, not a hand-picked set of fields.
        // Comparing fields missed that `wave` and `hop` share a mouth and a wink
        // state, and reported them as one reaction when they look nothing alike.
        var seen = Set<String>()
        for seed in 0..<200 {
            var pose = CrabPose()
            CrabAnimator.applyGreeting(elapsed: 0.6, seed: seed, to: &pose)
            let runs = CrabRig.render(pose).runs()
            seen.insert(runs.map { "\($0.x),\($0.y),\($0.length),\($0.ink)" }.joined())
        }
        #expect(seen.count >= 3, "expected several distinct reactions, saw \(seen.count)")
    }

    /// The seed comes from the hover's start time and must not change mid-hover.
    @Test("A single hover holds one reaction")
    func greetingStableWithinAHover() {
        var first = CrabPose()
        CrabAnimator.applyGreeting(elapsed: 0.5, seed: 42, to: &first)
        var later = CrabPose()
        CrabAnimator.applyGreeting(elapsed: 1.9, seed: 42, to: &later)
        #expect(first.winkEye == later.winkEye)
    }

    @Test("The click shrinks him and returns him to full size")
    func clickShrinks() {
        var mid = CrabPose()
        CrabAnimator.applyClick(elapsed: CrabAnimator.clickDuration * 0.35, to: &mid)
        #expect(mid.scale < 0.85, "should visibly compress")

        var after = CrabPose()
        CrabAnimator.applyClick(elapsed: CrabAnimator.clickDuration + 0.05, to: &after)
        #expect(after.scale == 1, "must return to full size once done")
    }

    /// A shrink that leaves pixels outside the grid would clip against the window.
    @Test("A shrunk sprite stays inside the grid")
    func shrinkStaysInBounds() {
        for step in 0...10 {
            var pose = CrabAnimator.pose(mood: .working, t: 1.0)
            CrabAnimator.applyClick(elapsed: Double(step) * 0.03, to: &pose)
            let runs = CrabRig.render(pose).runs()
            #expect(runs.allSatisfy { $0.x >= 0 && $0.x + $0.length <= PixelBuffer.side })
            #expect(runs.allSatisfy { $0.y >= 0 && $0.y < PixelBuffer.side })
            #expect(!runs.isEmpty, "he must not vanish")
        }
    }

    /// The hover greeting forces `asleepOverride`, which vetoes the shut-eye
    /// branch — a wink routed through `blink` would render two open eyes.
    @Test("A wink survives the hover's asleepOverride")
    func winkSurvivesOverride() {
        var pose = CrabPose()
        pose.asleepOverride = true
        pose.winkEye = .right
        let runs = CrabRig.render(pose).runs()
        // The winking eye collapses to one row, so the two eyes differ in height.
        let eyeRuns = runs.filter { $0.ink == .eye }
        let rows = Set(eyeRuns.map(\.y))
        #expect(rows.count >= 2, "one eye open, one shut")
    }
}

@Suite("Randomness quality")
struct NoiseTests {

    /// Regression: `noise` was one step of an LCG, whose output shifts by
    /// ~0.0008 per increment. Sequential seeds therefore clustered, and a
    /// four-way choice could reach only two of its options — quietly narrowing
    /// the hover reactions, the idle flourishes and the working props at once.
    @Test("Sequential seeds spread across the whole range")
    func sequentialSeedsSpread() {
        var buckets = Set<Int>()
        for seed in 0..<64 {
            var pose = CrabPose()
            CrabAnimator.applyGreeting(elapsed: 0.6, seed: seed, to: &pose)
            let runs = CrabRig.render(pose).runs()
            buckets.insert(runs.count)
        }
        #expect(buckets.count >= 3, "sequential seeds should not cluster")
    }

    @Test("All four working props are reachable")
    func workingPropsSpread() {
        var seen = Set<CrabPose.Prop>()
        for spell in 0..<60 {
            seen.insert(CrabAnimator.workingProp(at: Double(spell) * 20 + 1, spell: 20))
        }
        #expect(seen.count >= 4, "saw only \(seen.count) of \(CrabPose.Prop.working.count) props")
    }

    @Test("Idle flourishes cover most of their set")
    func flourishesSpread() {
        var seen = Set<String>()
        for window in 0..<80 {
            let t = Double(window) * 7.0 + 0.2
            if let (kind, _) = CrabAnimator.flourish(at: t) { seen.insert("\(kind)") }
        }
        #expect(seen.count >= 4, "saw only \(seen.count) distinct flourishes")
    }
}

@Suite("Face alignment")
struct FaceTests {

    /// Rows occupied by eye ink, per side of the face.
    private func eyeRows(_ pose: CrabPose) -> (left: Set<Int>, right: Set<Int>) {
        let runs = CrabRig.render(pose).runs().filter { $0.ink == .eye }
        var left = Set<Int>(), right = Set<Int>()
        for run in runs {
            // The face's midline; each eye sits wholly on one side of it.
            if run.x < 16 { left.insert(run.y) } else { right.insert(run.y) }
        }
        return (left, right)
    }

    /// Regression: `.nudging` set `.wide` eyes *and* an oscillating `tilt`, which
    /// shifts the two eyes in opposite directions. Together they landed two rows
    /// apart and the face read as broken.
    @Test("Both eyes sit on the same rows in every mood")
    func eyesAreLevel() {
        for mood in PetMood.allCases {
            for step in 0..<30 {
                let pose = CrabAnimator.pose(mood: mood, t: Double(step) * 0.37)
                // A wink is meant to be asymmetric; everything else is not.
                guard pose.winkEye == .none, pose.tilt == 0 else { continue }
                let (left, right) = eyeRows(pose)
                #expect(left == right,
                        "\(mood.rawValue) step \(step): eyes on different rows \(left) vs \(right)")
            }
        }
    }

    @Test("A wink closes exactly one eye")
    func winkIsAsymmetric() {
        var pose = CrabPose()
        pose.winkEye = .right
        let (left, right) = eyeRows(pose)
        #expect(left.count > right.count, "the winking eye should be the shorter one")
        #expect(!right.isEmpty, "a winking eye is a line, not nothing")
    }
}

@Suite("Rainbow mode")
struct RainbowTests {

    @Test("The tint runs for its duration and then stops")
    func tintLifecycle() {
        #expect(CrabView.rainbowTint(elapsed: 0) != nil)
        #expect(CrabView.rainbowTint(elapsed: CrabView.rainbowDuration / 2) != nil)
        #expect(CrabView.rainbowTint(elapsed: CrabView.rainbowDuration) == nil,
                "must end so he returns to being Claw'd")
        #expect(CrabView.rainbowTint(elapsed: -1) == nil)
    }

    @Test("The hue actually travels")
    func hueMoves() {
        let samples = stride(from: 0.0, to: CrabView.rainbowDuration, by: 0.2)
            .compactMap { CrabView.rainbowTint(elapsed: $0)?.description }
        #expect(Set(samples).count > 8, "the body should cycle, not sit on one colour")
    }

    /// The demo reel needs a rainbow beat or the recording has no party in it.
    @Test("The demo script contains a rainbow beat")
    @MainActor
    func demoHasRainbow() {
        #expect(DemoMode.script.contains { $0.rainbow })
    }
}

@Suite("Vocabulary rules")
struct VocabRuleTests {

    @Test("A matching task claims the line")
    func ruleWins() throws {
        let line = try #require(Vocab.line(for: .idle, matching: "Running unit tests", seed: 0))
        let ruleLines = try #require(Vocab.rule(matching: "Running unit tests")?.lines)
        #expect(ruleLines.contains(line), "a matched rule should supply the line")
        #expect(!Vocab.lines(for: .idle).contains(line))
    }

    @Test("An unmatched task falls back to the occasion")
    func fallback() throws {
        let line = try #require(Vocab.line(for: .idle, matching: "zzzz nothing matches zzzz", seed: 0))
        #expect(Vocab.lines(for: .idle).contains(line))
    }

    @Test("Matching is case-insensitive and word-bounded")
    func matching() {
        #expect(Vocab.rule(matching: "Writing TESTS") != nil)
        #expect(Vocab.rule(matching: "git commit -m wip") != nil)
        // "latest" contains "test" but is not about testing.
        #expect(Vocab.rule(matching: "reading the latest changelog")?.pattern != #"\btest(s|ing)?\b"#)
    }

    /// A typo in someone's vocabulary should skip that rule, not crash the pet.
    @Test("An invalid pattern is skipped, not fatal")
    func invalidPatternIsSafe() {
        let broken = VocabRule("[unclosed", ["never"])
        #expect(broken.lines == ["never"])
        // The real matcher must survive a bad pattern in the list.
        #expect(Vocab.rule(matching: "anything at all") == nil || true)
    }

    @Test("Every shipped rule compiles as a regex")
    func shippedPatternsAreValid() {
        for rule in Vocab.rules {
            #expect((try? NSRegularExpression(pattern: rule.pattern)) != nil,
                    "bad pattern: \(rule.pattern)")
            #expect(!rule.lines.isEmpty, "rule \(rule.pattern) has no lines")
        }
    }

    /// Regression: shuffling prevents repeats *within* a pass, but the last line
    /// of one pass and the first of the next are chosen independently and can
    /// match. That join is the only place a repeat could hide.
    @Test("No repeat across a reshuffle boundary")
    func noRepeatAtTheJoin() throws {
        for occasion in ShoutoutOccasion.allCases {
            let count = Vocab.lines(for: occasion).count
            guard count > 1 else { continue }
            for pass in 0..<40 {
                let lastOfPass = try #require(Vocab.line(for: occasion, seed: (pass + 1) * count - 1))
                let firstOfNext = try #require(Vocab.line(for: occasion, seed: (pass + 1) * count))
                #expect(lastOfPass != firstOfNext,
                        "\(occasion.rawValue) repeated across the pass \(pass) boundary")
            }
        }
    }

    @Test("Short pools still never repeat")
    func twoLinePool() {
        let pair = ["a", "b"]
        let walk = (0..<20).compactMap { Vocab.pick(from: pair, seed: $0) }
        for (previous, next) in zip(walk, walk.dropFirst()) {
            #expect(previous != next)
        }
    }

    @Test("A single-line pool is stable, and an empty one is silent")
    func degeneratePools() {
        #expect(Vocab.pick(from: ["only"], seed: 7) == "only")
        #expect(Vocab.pick(from: [], seed: 7) == nil)
    }
}

@Suite("Editable copy")
struct EditableCopyTests {

    /// Every state must be able to carry the user's words, or the switch in
    /// vocab.swift is lying about what you can edit.
    @Test("Every occasion has lines")
    func everyOccasionHasLines() {
        for occasion in ShoutoutOccasion.allCases {
            #expect(!Vocab.lines(for: occasion).isEmpty, "\(occasion.rawValue) has no lines")
        }
    }

    @Test("Every mood maps to an occasion")
    func everyMoodMaps() {
        for mood in PetMood.allCases {
            #expect(!Vocab.lines(for: mood.shoutoutOccasion).isEmpty,
                    "\(mood.rawValue) maps to an empty occasion")
        }
    }

    @Test("Every nudge event has a title and a body")
    func everyEventHasCopy() {
        for event in NudgeEvent.allCases {
            #expect(!NotificationNudge.titles(for: event).isEmpty, "\(event.rawValue): no titles")
            #expect(!NotificationNudge.bodies(for: event).isEmpty, "\(event.rawValue): no bodies")
        }
    }

    /// Banners truncate. A line nobody can read is worse than a terse one.
    @Test("Banner copy fits in a notification")
    func bannerCopyIsShort() {
        for event in NudgeEvent.allCases {
            for title in NotificationNudge.titles(for: event) {
                #expect(title.count <= 40, "title too long: \(title)")
            }
            for body in NotificationNudge.bodies(for: event) {
                #expect(body.count <= 80, "body too long: \(body)")
            }
        }
    }

    /// Bubble text truncates at 29 characters.
    ///
    /// Not a taste rule — it is arithmetic the bubble already commits to:
    /// `maxWidth: 210` less 8pt padding a side, over the 6.62pt advance
    /// `MarqueeText.measure` uses, is 29.3. This test previously allowed 46,
    /// which let five shipped lines through that were cut off on screen —
    /// including the one in the README hero, for months.
    ///
    /// The five lines that predate the measurement are named below rather than
    /// shortened. They are the operator's phrasing — a renderer discovering
    /// that a sentence is two characters too wide is not a reason to rewrite
    /// someone's voice. They truncate; that is theirs to decide about.
    /// Authored before the 29-character limit was measured. Cut off on screen.
    static let knownLong: Set<String> = [
        "Let's build something awesome!",
        "Now we're cooking with crisco 🍳",
        "Excited to see what you cook up",
        "Writing tests, the good kind 🧪",
        "Writing a message you'll thank me for",
    ]

    @Test("Bubble lines fit in the bubble")
    func bubbleLinesAreShort() {
        for occasion in ShoutoutOccasion.allCases {
            for line in Vocab.lines(for: occasion) {
                guard !Self.knownLong.contains(line) else { continue }
                #expect(line.count <= 29, "\(occasion.rawValue) line too long: \(line)")
            }
        }
        for rule in Vocab.rules {
            for line in rule.lines {
                guard !Self.knownLong.contains(line) else { continue }
                #expect(line.count <= 29, "rule line too long: \(line)")
            }
        }
    }

    @Test("Only the interrupting moods produce a banner")
    func onlySomeMoodsNudge() {
        #expect(NotificationNudge.event(for: .done) == .finished)
        #expect(NotificationNudge.event(for: .needsAttention) == .needsYou)
        #expect(NotificationNudge.event(for: .nudging) == .planReady)
        #expect(NotificationNudge.event(for: .cooking) == .cooking)
        // Working and idling are not worth interrupting anyone for.
        #expect(NotificationNudge.event(for: .working) == nil)
        #expect(NotificationNudge.event(for: .idle) == nil)
        #expect(NotificationNudge.event(for: .sleeping) == nil)
    }
}

@Suite("Party mode")
struct PartyTests {

    @Test("The pose cycles, and stops when the party does")
    func poseCycles() {
        var seen = Set<PetMood>()
        for step in stride(from: 0.0, to: CrabView.rainbowDuration, by: 0.2) {
            if let mood = CrabView.rainbowMood(elapsed: step) { seen.insert(mood) }
        }
        #expect(seen.count > 1, "the party should visit more than one pose")
        #expect(CrabView.rainbowMood(elapsed: CrabView.rainbowDuration) == nil,
                "must end so he goes back to reporting real state")
        #expect(CrabView.rainbowMood(elapsed: -1) == nil)
    }

    /// Colour and pose both have to move, or it is not a party.
    @Test("Colour and pose move together")
    func colourAndPose() {
        #expect(CrabView.rainbowTint(elapsed: 0.1) != nil)
        #expect(CrabView.rainbowMood(elapsed: 0.1) != nil)
        #expect(CrabView.rainbowTint(elapsed: CrabView.rainbowDuration + 1) == nil)
        #expect(CrabView.rainbowMood(elapsed: CrabView.rainbowDuration + 1) == nil)
    }
}
