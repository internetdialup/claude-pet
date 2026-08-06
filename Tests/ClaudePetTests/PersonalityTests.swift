import Testing
import Foundation
import AppKit
@testable import ClaudePet

@Suite("Vocabulary")
struct VocabShoutoutsTests {

    @Test("Every occasion has lines")
    func everyOccasionPopulated() {
        for occasion in ShoutoutOccasion.allCases {
            let lines = VocabShoutouts.catalogue[occasion]
            #expect(lines?.isEmpty == false, "\(occasion.rawValue) has no lines")
        }
    }

    @Test("The operator's idle lines are present verbatim")
    func idleLinesVerbatim() throws {
        let lines = try #require(VocabShoutouts.catalogue[.idle])
        #expect(lines.contains("Let's build something awesome!"))
        #expect(lines.contains("Now we're cooking with crisco 🍳"))
        #expect(lines.contains("Ooo that's a spicy idea 🌶️"))
    }

    /// The bubble is recomputed on a timer; the same seed must yield the same
    /// line or the text would rewrite itself mid-read.
    @Test("Selection is deterministic for a given seed")
    func deterministic() {
        for seed in 0..<20 {
            let first = VocabShoutouts.line(for: .idle, seed: seed)
            let second = VocabShoutouts.line(for: .idle, seed: seed)
            #expect(first == second)
        }
    }

    @Test("A line is never repeated back to back")
    func neverRepeatsConsecutively() throws {
        var previous = try #require(VocabShoutouts.line(for: .idle, seed: 0))
        for seed in 1..<200 {
            let next = try #require(VocabShoutouts.line(for: .idle, avoiding: previous, seed: seed))
            #expect(next != previous)
            previous = next
        }
    }

    @Test("Every idle line is reachable")
    func coversTheCatalogue() throws {
        let lines = try #require(VocabShoutouts.catalogue[.idle])
        var seen = Set<String>()
        var previous: String?
        for seed in 0..<300 {
            if let line = VocabShoutouts.line(for: .idle, avoiding: previous, seed: seed) {
                seen.insert(line)
                previous = line
            }
        }
        #expect(seen.count == lines.count)
    }

    /// `Int.min` has no positive magnitude; `abs` on it traps.
    @Test("Extreme seeds do not trap")
    func extremeSeeds() {
        #expect(VocabShoutouts.line(for: .idle, seed: Int.min) != nil)
        #expect(VocabShoutouts.line(for: .idle, seed: Int.max) != nil)
        #expect(VocabShoutouts.line(for: .idle, seed: -1) != nil)
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

    /// Numerical Grounding (`Bamboo.md` §3): with no usage data, no percentage
    /// may be invented. These pass an explicit cache rather than reading the
    /// operator's real `~/.claude/` (`Bamboo.md` §5).
    @Test("No model and no usage data produces no lines")
    func noDataNoClaims() {
        #expect(StatusTicker.lines(model: nil, usage: nil).isEmpty)
    }

    @Test("A model with no usage data yields a name-only line, no percentage")
    func modelWithoutUsage() throws {
        let lines = StatusTicker.lines(model: "claude-opus-5", usage: nil)
        #expect(lines.count == 1)
        let modelLine = try #require(lines.first)
        #expect(modelLine.contains("Opus 5"))
        #expect(!modelLine.contains("%"), "no data means no percentage")
    }

    @Test("Percentages are reported when the cache supplies them")
    func percentagesFromCache() {
        let cache = StatusTicker.UsageCache(
            writtenAt: nil, fiveHourPercent: 24, sevenDayPercent: 82, contextUsedPercent: 41
        )
        let lines = StatusTicker.lines(model: "claude-fable-5", usage: cache)
        #expect(lines.contains("MODEL · Fable 5 @ 41% CONTEXT"))
        #expect(lines.contains("5-HOUR LIMIT @ 24%"))
        #expect(lines.contains("WEEKLY USAGE @ 82%"))
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
