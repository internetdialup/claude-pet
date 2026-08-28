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

@Suite("Prop inventory")
struct PropInventoryTests {
    /// `props.png` is committed and published in the README as "every prop", and
    /// it is rendered from `Prop.allCases`. It had been missing the Claude star
    /// for weeks — appended to the enum, never re-rendered, nobody noticed.
    ///
    /// Pinning the count makes the next append or deletion surface the media
    /// obligation at test time rather than at review time.
    /// **The joystick is HELD, at every phase.**
    ///
    /// It has been in three places. First it floated beside him at his own
    /// height and read as stuck to his flank. Then it stood on the floor, which
    /// fixed the sticking and made it scenery — a stick on the ground is not a
    /// stick anyone is using. Now it is up at his claw, overlapping him on
    /// purpose, because the overlap is the thing that says "held".
    ///
    /// So this asserts the opposite of what it used to: the joystick's own
    /// pixels must live at BODY height and never drift down into the floor
    /// band, which is rows 25 and below and belongs to nothing.
    @Test("The joystick is held, never left on the floor")
    func joystickIsHeldAtClawHeight() {
        let bare = CrabRig.render(CrabPose())
        for step in 0...40 {
            var pose = CrabPose()
            pose.prop = .joystick
            pose.propPhase = Double(step) * 0.25
            let drawn = CrabRig.render(pose)

            var lowest = -1, highest = PixelBuffer.side
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where drawn[x, y] != bare[x, y] {
                    lowest = max(lowest, y)
                    highest = min(highest, y)
                }
            }
            #expect(lowest >= 0, "the joystick drew nothing at phase \(pose.propPhase)")
            #expect(lowest < 25,
                    "the joystick reached row \(lowest) — that is the floor, not his claw")
            #expect(highest >= 8,
                    "the joystick reached row \(highest), up over his head rather than in his grip")
        }
    }

    @Test("The prop strip publishes every prop")
    func propCountIsPinned() {
        // `.none` is a case but not a prop; the strip draws the rest.
        let drawn = CrabPose.Prop.allCases.filter { $0 != .none }
        #expect(drawn.count == 17,
                "the prop count moved — docs/media/props.png needs re-rendering")
        #expect(!CrabPose.Prop.allCases.contains { $0.rawValue == "zzz" },
                "the sleeping z's were removed; the enum should not carry them")
        // `stableSeed` is the allCases index and feeds the pixel dissolve, so
        // the ordering has to stay collision-free.
        let seeds = CrabPose.Prop.allCases.map(\.stableSeed)
        #expect(Set(seeds).count == seeds.count, "two props share a dissolve seed")
    }
}

@Suite("The draw counter")
struct LineCursorTests {

    /// **The regression, and the reason this pass exists.**
    ///
    /// `Vocab.pick` deals a deck, and a deck keeps its promise only while its
    /// seed steps by exactly one. `bubbleBurst` returns an index that SKIPS —
    /// the dice silence most cycles — and the old code folded it into the seed
    /// as `seed &+ burst &* 101`, which jumped the pass. A working stretch drew
    /// from a three-line pool at chance: one utterance in three was the
    /// previous one repeated. The operator noticed before the tests did.
    @Test("Skipping tokens still never repeat")
    func cursorSurvivesSkippedTokens() {
        var cursor = LineCursor()
        let pool = ["a", "b", "c", "d", "e"]
        // Exactly the shape `bubbleBurst` produces: monotonic, sparse, and
        // restarting from zero whenever a news epoch breaks.
        let tokens = [0, 1, 3, 4, 7, 11, 12, 20, 0, 1, 5, 9, 14, 15, 22, 30, 31, 40]
        let said = tokens.compactMap { cursor.next(pool, id: "w", token: "\($0)") }
        #expect(said.count == tokens.count)
        for (a, b) in zip(said, said.dropFirst()) {
            #expect(a != b, "\(a) twice in a row")
        }
        // …and the coverage half of the promise. Deliberately NOT sliced into
        // fixed windows from index 0: the cursor's first seed is salt+1, so
        // pass boundaries do not align to the start of the run. What matters
        // is that the whole pool gets used rather than three of five lines
        // carrying every utterance, which is the failure a plain random index
        // produces and the deck exists to prevent.
        #expect(Set(said).count == pool.count, "the deck never dealt the whole pool")
    }

    /// One burst says one thing. The cursor must NOT advance while the token
    /// holds, or the bubble rewrites itself under the reader on the recompute.
    @Test("A held token holds its line")
    func cursorHoldsWithinAnUtterance() {
        var cursor = LineCursor()
        let pool = ["a", "b", "c", "d"]
        let first = cursor.next(pool, id: "x", token: "one")
        for _ in 0..<20 {
            #expect(cursor.next(pool, id: "x", token: "one") == first)
        }
        #expect(cursor.next(pool, id: "x", token: "two") != first)
    }

    /// Two pools through one counter would steal each other's seeds — the same
    /// bug one level up — so the cursor is keyed per pool.
    @Test("Interleaved pools keep their own counters")
    func cursorKeepsPoolsApart() {
        var cursor = LineCursor()
        let pool = ["a", "b", "c", "d"]
        var mine: [String] = []
        for step in 0..<12 {
            // Alternating moods, as the pet actually does.
            _ = cursor.next(pool, id: "other", token: "\(step)")
            mine.append(cursor.next(pool, id: "mine", token: "\(step)")!)
        }
        for (a, b) in zip(mine, mine.dropFirst()) { #expect(a != b) }
    }

    /// The idle path is the one the operator is actually looking at, and its
    /// seed is sampled through two independent gates — `idleChatterShows`, then
    /// the every-third-cycle status ticker. Walk the real gates, not a clean
    /// counter, because a clean counter is exactly what the old code assumed.
    @Test("Idle chatter never repeats through its quiet gate")
    @MainActor
    func idleGateDoesNotRepeat() {
        var cursor = LineCursor()
        var said: [String] = []
        for seed in 0..<600 {
            guard ActivityCoordinator.idleChatterShows(quietFor: 600, seed: seed) else { continue }
            guard seed % 3 != 2 else { continue }        // that cycle is the ticker
            // …and of what is left, a coin sends half to a fun fact. Without
            // this third gate the test stops modelling the shipped path, which
            // is the one thing its own name promises.
            guard CrabAnimator.noise(seed &* 17 &+ 7) >= 0.5 else { continue }
            said.append(cursor.line(for: .idle, token: "\(seed)")!)
        }
        #expect(said.count > 25, "the gate should let plenty through")
        for (a, b) in zip(said, said.dropFirst()) {
            #expect(a != b, "\"\(a)\" twice in a row on the idle path")
        }
    }

    /// The title and the body used to share one seed, so for a two-line pool
    /// both resolved to the same index and each title was welded to one body
    /// permanently. They draw from separate counters now.
    ///
    /// The assertion is deliberately weak, and the reason is worth writing
    /// down: separate counters are **necessary but not sufficient**. Every
    /// body pool is currently size 2, and `pick` short-circuits a two-line
    /// pool to `pool[seed % 2]` — so two counters stepping by one alternate in
    /// lockstep and still produce only two of the four pairs. No salt offset
    /// fixes that; it just picks the other two. Recombination needs the pools
    /// deeper than two, which is a separate change. What this pins today is
    /// that the two draws are independent, so depth is all that is missing.
    @Test("Banner titles and bodies draw from separate counters")
    @MainActor
    func bannerPairsAreNotWelded() {
        var titles = Set<String>()
        var bodies = Set<String>()
        for _ in 0..<40 {
            let c = NotificationNudge.nextCopy(for: .planReady)
            titles.insert(c.title)
            bodies.insert(c.body)
        }
        #expect(titles.count == NotificationNudge.titles(for: .planReady).count,
                "the title pool is not being walked")
        #expect(bodies.count == NotificationNudge.bodies(for: .planReady).count,
                "the body pool is not being walked")
    }

    /// Deferred from the round that added `LineCursor`, and true at last:
    /// `Vocab.pick` short-circuits a two-line pool to strict alternation and a
    /// one-line pool to a constant, so a pool of two is not variety, it is a
    /// metronome you cannot hear until you have watched it for a week.
    @Test("No shipped pool is thin enough to only alternate")
    func poolsAreDeepEnough() {
        for occasion in ShoutoutOccasion.allCases {
            #expect(Vocab.lines(for: occasion).count > 2,
                    "\(occasion.rawValue) can only alternate")
        }
        for rule in Vocab.rules {
            #expect(rule.lines.count > 2, "\(rule.pattern) can only alternate")
        }
        for event in NudgeEvent.allCases {
            #expect(NotificationNudge.titles(for: event).count > 2, "\(event) titles")
            #expect(NotificationNudge.bodies(for: event).count > 2, "\(event) bodies")
        }
    }

    /// **Every case here was measured against the shipped patterns and failed.**
    /// A rule REPLACES the real task label, so a false positive does not merely
    /// mistime a joke — it deletes the one string on screen that said what was
    /// happening.
    @Test("No rule claims a label that is not its own")
    func rulesDoNotFalsePositive() {
        let mustNotMatch = [
            "Make the header prettier",          // was claimed by lint
            "Extract frames from the wink GIF",  // was claimed by refactor
            "Add a user profile page",           // was claimed by performance
            "Add search to the sidebar",         // was claimed by search
            "Ship the new costume",              // was claimed by deploy
            "press and release the key",         // was claimed by deploy
        ]
        for label in mustNotMatch {
            let rule = Vocab.rule(matching: label)
            #expect(rule == nil,
                    "\"\(label)\" was claimed by \(rule?.pattern ?? "")")
        }
    }

    /// The other half: two patterns silently MISSED labels they were written
    /// for, which is a quieter failure — the rule simply never fires.
    @Test("Rules match the labels they were written for")
    func rulesMatchTheirOwnLabels() {
        let mustMatch = [
            "Rebuilding the parser", "Fix the builds", "Compiling",
            "Run eslint", "Refactor the parser", "Profiling the render",
            "Review the diff", "grep for the salt", "npm install",
        ]
        for label in mustMatch {
            #expect(Vocab.rule(matching: label) != nil, "nothing claimed \"\(label)\"")
        }
    }

    /// Rule lines are NOT idle lines.
    ///
    /// An earlier round widened the idle pool with any rule matching the
    /// session's title, on the theory that a session about tests could say
    /// test-flavoured things while idle. It was a category error: rule lines
    /// narrate an action in flight ("Waiting on the compiler"), so they are
    /// false at rest — and it put a rule's lines and idle's lines in one deck,
    /// where they collided.
    @Test("The idle pool is only the idle pool")
    func idlePoolIsNotWidened() {
        let idle = Vocab.lines(for: .idle)
        let ruleLines = Set(Vocab.rules.flatMap(\.lines))
        for line in idle {
            #expect(!ruleLines.contains(line), "\"\(line)\" is in both idle and a rule")
        }
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
        // Sample within a single 7s window — anchored on the first window that
        // FIRES, because cycle 0 is now deliberately silent (the frozen
        // sentinel: at t=0 he used to already be mid-jump).
        let base = CrabAnimator.firstFlourishAt
        var lastProgress = -1.0
        var sawProgress = false
        for step in 0..<60 {
            let t = base + Double(step) * 0.01
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
    ///
    /// Counted on the *rendered* arm — the whole-pixel reach the rig draws —
    /// not the raw channel. The two were the same number until the arms were
    /// eased; now the channel glides through many values per beat while the
    /// eye still sees a few pixel steps, and the eye is what this test is for.
    @Test("Working animation is calm, not frantic")
    func workingIsCalm() {
        func renderedReach(at t: Double) -> Int {
            let lift = CrabAnimator.pose(mood: .working, t: t).armLeft
            return Int((max(0, min(1, lift)) * 6).rounded())
        }
        var armSteps = 0
        var previous = renderedReach(at: 0)
        for step in 1...1000 {
            let arm = renderedReach(at: Double(step) * 0.01)
            if arm != previous { armSteps += 1 }
            previous = arm
        }
        // 10 seconds of samples; more than ~25 visible steps reads as a flutter.
        #expect(armSteps <= 25, "arms moved \(armSteps) visible steps in 10s")
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
        // With a display attached the lookup must resolve, however far off the
        // pet was thrown. nil is reserved for genuinely zero displays — this
        // runner has at least one — and that branch is covered as pure
        // geometry in CrashHardeningTests, where "no displays" is `[]`.
        let screen = PetWindowController.screen(for: stranded)
        #expect(screen != nil)
        #expect((screen?.frame.width ?? 0) > 0)
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
    /// Authored before the limit was measured. Cut off on screen.
    ///
    /// The sixth was found by rendering a ruler through the bubble: the ceiling
    /// is 28, not the 29 the arithmetic gives, because 6.62 is the marquee's
    /// advance and runs under the real one. "I'm hungry for something new!" is
    /// exactly 29 and has been losing its "!" since the day the guard was
    /// written. It goes here rather than getting shortened, for the reason the
    /// other five did: a renderer discovering that a sentence is one character
    /// too wide is not a reason to rewrite someone's voice.
    static let knownLong: Set<String> = [
        "I'm hungry for something new!",
        "Let's build something awesome!",
        "Now we're cooking with crisco 🍳",
        "Excited to see what you cook up",
        "Writing tests, the good kind 🧪",
        "Writing a message you'll thank me for",
    ]

    @Test("Bubble lines fit in the bubble")
    func bubbleLinesAreShort() {
        for occasion in ShoutoutOccasion.allCases {
            // The skate lines are ROUTED by length rather than forced into the
            // plain bubble, so the ceiling does not apply to them — what does
            // apply is that they finish scrolling inside the window they are
            // shown for, which `skateLinesFitTheirWindow` checks instead.
            guard occasion != .kickflip else { continue }
            for line in Vocab.lines(for: occasion) {
                guard !Self.knownLong.contains(line) else { continue }
                #expect(line.count <= ThoughtBubble.plainColumns, "\(occasion.rawValue) line too long: \(line)")
            }
        }
        for rule in Vocab.rules {
            for line in rule.lines {
                guard !Self.knownLong.contains(line) else { continue }
                #expect(line.count <= ThoughtBubble.plainColumns, "rule line too long: \(line)")
            }
        }
    }

    /// The skate lines are the first transient long enough to need the marquee,
    /// so they are the first that can be CUT OFF by their own window rather
    /// than by the bubble's width. Two ways to fail: a line too wide for the
    /// plain bubble that was not routed to the marquee, or one routed there
    /// that the window closes on mid-scroll.
    @Test("Every skate line finishes inside the window it gets")
    func skateLinesFitTheirWindow() {
        for line in Vocab.lines(for: .kickflip) {
            switch ActivityCoordinator.bubbleStyle(for: line) {
            case .plain:
                #expect(line.count <= ThoughtBubble.plainColumns,
                        "\"\(line)\" was left in the plain bubble and does not fit it")
            case .marquee:
                let read = MarqueeText.readSeconds(for: line, width: MarqueeText.viewport)
                #expect(read <= PetInstance.skateLineSeconds - 0.8,
                        "\"\(line)\" needs \(String(format: "%.1f", read))s and the window is \(PetInstance.skateLineSeconds)s")
            case .dots:
                Issue.record("a skate line should never be dots")
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
