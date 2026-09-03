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
