import Testing
import Foundation
@testable import ClaudePet

/// The spawn matrix: one table, every scheduled effect's odds.
///
/// The table is only worth having if it is the ONLY place the numbers live,
/// so the last test here goes and looks.
@Suite("Spawn rates")
@MainActor
struct SpawnRateTests {

    private var everySpawn: [(String, SpawnRates.Spawn)] {
        [("flourish", SpawnRates.flourish), ("skateSession", SpawnRates.skateSession),
         ("idleHeart", SpawnRates.idleHeart), ("shellGlint", SpawnRates.shellGlint),
         ("floorBug", SpawnRates.floorBug), ("stargaze", SpawnRates.stargaze),
         ("balloon", SpawnRates.balloon), ("sunPatch", SpawnRates.sunPatch),
         ("heatCascade", SpawnRates.heatCascade), ("discoTint", SpawnRates.discoTint),
         ("nearDoneGlow", SpawnRates.nearDoneGlow), ("fireBurnsLow", SpawnRates.fireBurnsLow),
         ("bubbleShimmer", SpawnRates.bubbleShimmer)]
    }

    private var everyEffect: [(String, SpawnRates.Effect)] {
        [("pumpkinFlicker", SpawnRates.pumpkinFlicker), ("turkeyStrut", SpawnRates.turkeyStrut),
         ("shuriken", SpawnRates.shuriken), ("frankensteinSparks", SpawnRates.frankensteinSparks),
         ("santaBreath", SpawnRates.santaBreath), ("gundamScan", SpawnRates.gundamScan),
         ("gundamEyeFlare", SpawnRates.gundamEyeFlare), ("sonicDash", SpawnRates.sonicDash),
         ("sonicRings", SpawnRates.sonicRings), ("retroSheen", SpawnRates.retroSheen),
         ("kickPush", SpawnRates.kickPush), ("fireworks", SpawnRates.fireworks)]
    }

    @Test("Every rate in the table is a rate")
    func spawnRatesAreSane() {
        for (name, spawn) in everySpawn {
            #expect(spawn.chance > 0 && spawn.chance <= 1, "\(name) chance \(spawn.chance)")
            #expect(spawn.period > 0, "\(name) period \(spawn.period)")
            #expect(spawn.perHour > 0, "\(name) never fires")
        }
        for (name, effect) in everyEffect {
            #expect(effect.chance > 0 && effect.chance <= 1, "\(name) chance \(effect.chance)")
            #expect(effect.period > 0 && effect.duration > 0, "\(name) has no window")
            #expect(effect.duration < effect.period,
                    "\(name) lasts longer than its own cycle — it would never stop")
        }
        // Every costume effect owns a distinct addend on the shared family.
        let salts = everyEffect.map(\.1.salt)
        #expect(Set(salts).count == salts.count, "two costume effects share a die")
    }

    /// The doctrine's "verify against predicted gaps, not vibes": walk the
    /// real schedulers over four hours of idle and count what actually
    /// fires. If the arithmetic and the measurement disagree, the table is
    /// decorative and the gate it claims to own has drifted from it.
    @Test("What the table promises is what the dice deliver")
    func measuredRatesMatchTheTable() {
        let hours = 4.0, span = hours * 3600
        func measure(_ name: String, _ spawn: SpawnRates.Spawn,
                     _ fires: (Double) -> Bool) {
            var count = 0
            for cycle in 1..<Int(span / spawn.period) {
                // Sweep the head of the cycle rather than probing its
                // middle: every one of these is a brief window near the
                // start, so a midpoint sample measures a flat zero and
                // "matches the table" only by accident of the slack.
                let base = Double(cycle) * spawn.period
                let reach = min(spawn.period, 25.0)
                var fired = false
                for step in stride(from: 0.0, to: reach, by: 0.25) where fires(base + step) {
                    fired = true
                    break
                }
                if fired { count += 1 }
            }
            let measured = Double(count) / hours
            let slack = spawn.perHour * 0.2 + 1
            #expect(abs(measured - spawn.perHour) <= slack,
                    "\(name): table says \(spawn.perHour)/hr, dice deliver \(measured)/hr")
        }
        measure("skateSession", SpawnRates.skateSession) {
            CrabAnimator.skateSession(idleT: $0) != nil
        }
        measure("idleHeart", SpawnRates.idleHeart) { CrabAnimator.idleHeart(idleT: $0) != nil }
        measure("shellGlint", SpawnRates.shellGlint) { CrabAnimator.shellGlint(idleT: $0) != nil }
        measure("floorBug", SpawnRates.floorBug) { CrabAnimator.bugPosition(idleT: $0) != nil }
    }

    /// A bare crab is exactly the crab he was before the wardrobe could
    /// bend anything. This is the load-bearing one: the lean reaches motion
    /// only through a value that defaults to empty, so every offline
    /// renderer, every sampler and every existing pin is untouched.
    @Test("An unworn wardrobe changes nothing at all")
    func theBareScheduleIsUnchanged() {
        let bare = CrabAnimator.MotionWardrobe()
        for step in 0...4000 {
            let t = Double(step) * 0.9
            #expect(CrabAnimator.skateSession(idleT: t)
                    == CrabAnimator.skateSession(idleT: t, wardrobe: bare))
            let a = CrabAnimator.flourish(at: t)
            let b = CrabAnimator.flourish(at: t, wardrobe: bare)
            #expect(a?.0 == b?.0 && a?.1 == b?.1, "the empty wardrobe moved the schedule at t=\(t)")
        }
        #expect(CrabAnimator.leanedDecks[.none] == CrabAnimator.flourishDeck)
    }

    /// **A costume change may not re-deal a trick he is already doing.**
    ///
    /// Every schedule the wardrobe touches rolls per cycle, so a naive
    /// costume-dependent gate would re-roll the cycle already under way and
    /// swap the move mid-air in one frame — the loudest snap a costume
    /// could cause. Each schedule latches on its OWN cycle instead, and
    /// this walks a change landing at every offset inside a flourish window
    /// to prove the one in flight is never touched.
    @Test("Changing costume never changes the move already playing")
    func aCostumeChangeCannotSnapATrick() {
        let period = 7.0
        for cycle in 1...40 {
            let cycleStart = Double(cycle) * period
            guard let (before, _) = CrabAnimator.flourish(at: cycleStart + 0.05) else { continue }
            // The change lands part-way through this very cycle.
            for offset in stride(from: 0.1, to: period, by: 0.35) {
                let wardrobe = CrabAnimator.MotionWardrobe(
                    current: .skater, previous: .none, changedAt: cycleStart + offset)
                // Everything from the change until this move ENDS still
                // belongs to what he was wearing when it began. Past its own
                // duration the window is legitimately over and both answer
                // nil, which is the schedule working rather than a swap.
                // Stopping a hair short of the end on purpose: the last
                // representable instant of a window is a floating-point
                // coin toss between "still playing" and "over", and that
                // boundary is `skateTrickLandingsAreReal`'s business. The
                // claim here is about MID-flight.
                for probe in stride(from: offset, to: before.duration - 0.05, by: 0.25) {
                    let after = CrabAnimator.flourish(at: cycleStart + probe, wardrobe: wardrobe)
                    #expect(after?.0 == before,
                            "cycle \(cycle) swapped \(before) for \(after?.0 as Any) mid-flight")
                }
            }
        }
    }

    /// The Skater actually skates more, measured rather than asserted from
    /// the table — and the Gundam, whose lean runs the other way, actually
    /// skates less. A lean that moved nothing would pass every other test
    /// here.
    @Test("The wardrobe bends the rates it says it bends")
    func theLeanIsReal() {
        func sessions(_ costume: Costume) -> Int {
            let wardrobe = CrabAnimator.MotionWardrobe(current: costume)
            var count = 0
            for cycle in 1...400 {
                let t = Double(cycle) * SpawnRates.skateSession.period + 4
                if CrabAnimator.skateSession(idleT: t, wardrobe: wardrobe) != nil { count += 1 }
            }
            return count
        }
        let bare = sessions(.none), skater = sessions(.skater), gundam = sessions(.gundam)
        #expect(skater > bare, "the skater rode \(skater) sessions against a bare \(bare)")
        #expect(gundam < bare, "the gundam rode \(gundam) sessions against a bare \(bare)")

        // The deck leans too, and nothing is ever deleted from it.
        for costume in Costume.allCases {
            let deck = CrabAnimator.leanedDecks[costume] ?? []
            for kind in CrabAnimator.Flourish.allCases {
                #expect(deck.contains(kind), "\(costume) lost \(kind) from the rotation entirely")
            }
        }
        func skateShare(_ costume: Costume) -> Double {
            let deck = CrabAnimator.leanedDecks[costume] ?? []
            let skate = deck.filter { CrabAnimator.Flourish.skateBeats.contains($0) }.count
            return Double(skate) / Double(deck.count)
        }
        #expect(skateShare(.skater) > skateShare(.none), "the skater's deck does not lean")
        #expect(skateShare(.gundam) < skateShare(.none), "the gundam's deck does not lean back")

        // And the specials double for the one look dressed for them.
        var goldBare = 0, goldSkater = 0
        for cycle in 1...4000 {
            if CrabAnimator.skateBeatIsGolden(cycle: cycle) { goldBare += 1 }
            if CrabAnimator.skateBeatIsGolden(cycle: cycle, costume: .skater) { goldSkater += 1 }
        }
        #expect(goldSkater > goldBare, "the golden board did not lean for the skater")
    }

    /// **The table is the only place the numbers live.**
    ///
    /// Reads the sources and fails on any dice gate still comparing against
    /// a bare literal. Without this the table is a suggestion: the next
    /// effect gets a magic number at its call site, nobody notices for a
    /// year, and the whole point — being able to see the rates next to each
    /// other — is quietly gone. It reads the real files off `#filePath`
    /// rather than restating them, so it cannot go stale.
    @Test("No dice gate hides its odds from the table")
    func everyRateIsNamed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ClaudePetTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/ClaudePet")
        let files = ["View/CrabView.swift", "View/CrabCostume.swift",
                     "View/CrabRig.swift", "View/ThoughtBubble.swift",
                     "Feeds/ActivityCoordinator.swift"]
        // `noise(…) < 0.42` — a threshold written where only its author can
        // see it. `< SpawnRates.something` is the shape this wants instead.
        let bare = try Regex(#"noise\([^)]*\)\s*<\s*[0-9]"#)
        var offenders: [String] = []
        for file in files {
            let url = root.appendingPathComponent(file)
            let source = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() where line.firstMatch(of: bare) != nil {
                // Doc comments explain the dice; they do not roll them.
                let text = line.trimmingCharacters(in: .whitespaces)
                guard !text.hasPrefix("///"), !text.hasPrefix("//") else { continue }
                offenders.append("\(file):\(index + 1) \(text)")
            }
        }
        let report = offenders.joined(separator: "\n")
        #expect(offenders.isEmpty,
                "these gates keep their odds to themselves — move them to SpawnRates:\n\(report)")
    }
}
