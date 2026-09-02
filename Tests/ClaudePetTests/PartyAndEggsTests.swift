import Testing
import Foundation
@testable import ClaudePet

/// The poke ladder's arithmetic — the first tests the click path has ever
/// had. `NSEvent.clickCount` → party was an untestable closure until the
/// verdict and the action became pure seams; these tables ARE the ordering
/// the closure's comments used to merely assert.
@Suite("Poke ladder")
@MainActor
struct PokeLadderTests {

    private func train(_ gaps: [TimeInterval]) -> (times: [Date], now: Date) {
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        var times: [Date] = [base]
        for gap in gaps { times.append(times.last!.addingTimeInterval(gap)) }
        return (Array(times.dropLast()), times.last!)
    }

    /// Three deliberate pokes at ~0.6s count to three — the cadence the OS
    /// click counter reads as 1, 1, 1, which was half of "rainbow never
    /// fires".
    @Test("Deliberate pokes count; ambles do not")
    func pokeVerdictTable() {
        let deliberate = train([0.6, 0.6])
        #expect(PetInstance.pokeVerdict(times: deliberate.times, now: deliberate.now) == 3)

        let amble = train([1.0, 1.0])
        #expect(PetInstance.pokeVerdict(times: amble.times, now: amble.now) == 1,
                "1.0s gaps must not chain — that is browsing, not poking")

        let brokenTrain = train([0.3, 2.0, 0.4])
        #expect(PetInstance.pokeVerdict(times: brokenTrain.times, now: brokenTrain.now) == 2,
                "a gap anywhere breaks the train behind it")

        #expect(PetInstance.pokeVerdict(times: [], now: Date()) == 1,
                "a first poke is a train of one")

        let boundary = train([PetInstance.pokeGap, PetInstance.pokeGap])
        #expect(PetInstance.pokeVerdict(times: boundary.times, now: boundary.now) == 3,
                "the gap is inclusive — exactly-on-the-beat pokes count")
    }

    /// The ladder itself: one opens the roster, two feeds him, three parties —
    /// with every gate stated.
    @Test("One roster, two shrimp, three party")
    func clickActionTable() {
        #expect(PetInstance.clickAction(verdict: 3, mood: .idle,
                                        onBody: false, snackBusy: false) == .party)
        #expect(PetInstance.clickAction(verdict: 5, mood: .working,
                                        onBody: true, snackBusy: true) == .party,
                "nothing outranks the party")
        #expect(PetInstance.clickAction(verdict: 2, mood: .idle,
                                        onBody: true, snackBusy: false) == .snack)
        #expect(PetInstance.clickAction(verdict: 2, mood: .working,
                                        onBody: true, snackBusy: false) == .pokeThenRoster,
                "he only snacks when idle — a working crab is working")
        #expect(PetInstance.clickAction(verdict: 2, mood: .idle,
                                        onBody: false, snackBusy: false) == .pokeThenRoster,
                "the shrimp needs a body cell, same as it always did")
        #expect(PetInstance.clickAction(verdict: 2, mood: .idle,
                                        onBody: true, snackBusy: true) == .pokeThenRoster,
                "no stacking snacks")
        #expect(PetInstance.clickAction(verdict: 1, mood: .idle,
                                        onBody: true, snackBusy: false) == .pokeThenRoster)
    }
}

/// The night sky's rare streak, the golden deck, and the weighted rotation.
@Suite("Sky and deck")
@MainActor
struct SkyAndDeckTests {

    // MARK: - The shooting star

    /// Never for the renderers (nil hour), never outside a stargaze, and a
    /// dice — some sessions get one, most nights it stays an event.
    @Test("The star keeps the stargazer's own gates, plus a die")
    func starKeepsTheGates() {
        for t in stride(from: 0.0, through: 600.0, by: 1.0) {
            #expect(CrabAnimator.shootingStar(idleT: t, hourOfDay: nil) == nil,
                    "a render (nil hour) saw the star at \(t)s")
            #expect(CrabAnimator.shootingStar(idleT: t, hourOfDay: 14) == nil,
                    "a daytime idle saw the star at \(t)s")
        }
        var sightings = 0, sessions = 0
        for cycle in 1...400 {
            let mid = Double(cycle) * 120 + 4.5
            guard CrabAnimator.stargaze(idleT: mid, hourOfDay: 2) != nil else { continue }
            sessions += 1
            if CrabAnimator.shootingStar(idleT: mid, hourOfDay: 2) != nil { sightings += 1 }
        }
        #expect(sessions > 0, "the fixture never stargazed — the sweep is broken")
        #expect(sightings > 0, "four hundred cycles and no star — the die is dead")
        #expect(sightings < sessions, "every session got a star — that is furniture, not an event")
    }

    /// Whole-pixel flight: the head advances at most one cell per 30fps
    /// frame, and he tracks it with the bug's own by-thirds gaze mapping.
    @Test("The star flies on the grid and he follows it")
    func starFliesHonestly() {
        // Find a sighting cycle first.
        guard let cycle = (1...400).first(where: {
            CrabAnimator.stargaze(idleT: Double($0) * 120 + 4.5, hourOfDay: 2) != nil
                && CrabAnimator.shootingStar(idleT: Double($0) * 120 + 4.5, hourOfDay: 2) != nil
        }) else {
            Issue.record("no sighting in 400 cycles — the die is mis-salted")
            return
        }
        let base = Double(cycle) * 120
        var lastX: Int?
        var sawTrackedThirds = Set<Int>()
        for step in stride(from: 4.0, through: 5.6, by: 1.0 / 30) {
            guard let star = CrabAnimator.shootingStar(idleT: base + step, hourOfDay: 2) else { continue }
            if let lastX {
                #expect(abs(star.x - lastX) <= 1,
                        "the head jumped \(abs(star.x - lastX)) cells at \(step)s")
            }
            lastX = star.x
            #expect(star.y >= 0 && star.y <= 8, "the star left the sky rows")
            let pose = CrabAnimator.pose(mood: .idle, t: base + step,
                                         flourishes: false, hourOfDay: 2)
            if pose.shootingStarX != nil { sawTrackedThirds.insert(pose.gazeX) }
        }
        #expect(lastX != nil, "the sighting window produced no positions")
        #expect(!sawTrackedThirds.isEmpty, "his eyes never engaged the star")
    }

    // MARK: - The golden board

    /// A dice at the stated odds, agreeing with itself between the deck that
    /// paints and the landing that shouts.
    @Test("One skate beat in about fifty is golden, everywhere at once")
    func goldenRateAndAgreement() {
        var golden = 0
        let n = 20_000
        for cycle in 1...n where CrabAnimator.skateBeatIsGolden(cycle: cycle) { golden += 1 }
        let rate = Double(golden) / Double(n)
        #expect(rate > 0.01 && rate < 0.03, "golden rate \(rate), wanted ~0.02")

        // Every landing the scheduler yields answers the same as its cycle.
        var t = 1.0
        var checked = 0
        while t < 3_000, checked < 60 {
            guard let landing = CrabAnimator.nextSkateTrickLanding(after: t) else { break }
            let cycle = Int(floor((landing - 0.01) / 7.0))
            #expect(CrabAnimator.skateLandingIsGolden(at: landing)
                    == CrabAnimator.skateBeatIsGolden(cycle: cycle),
                    "the shout and the deck disagreed at \(landing)s")
            checked += 1
            t = landing + 0.1
        }
        #expect(checked > 30, "the sweep found too few landings to mean anything")
    }

    /// The golden render inverts the board inks — gold deck, slate wheels —
    /// and the flourishPose door (every renderer's, every sampler's) can
    /// never produce it.
    @Test("Gold cannot leak into a committed byte")
    func goldNeverLeaks() {
        for t in stride(from: 0.0, through: 3.2, by: 0.2) {
            #expect(CrabAnimator.flourishPose(.kickflip, at: t).goldenBoard == false)
            #expect(CrabAnimator.flourishPose(.ollie, at: t).goldenBoard == false)
        }

        var pose = CrabAnimator.flourishPose(.kickflip, at: 1.4)   // mid-air, board fat
        let stock = CrabRig.render(pose)
        pose.goldenBoard = true
        let golden = CrabRig.render(pose)
        var stockSlate = 0, goldenYellowGain = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                if stock[x, y] == .slate { stockSlate += 1 }
                if golden[x, y] == .yellow && stock[x, y] == .slate { goldenYellowGain += 1 }
            }
        }
        #expect(stockSlate > 10, "the probe frame has no deck to measure")
        #expect(goldenYellowGain == stockSlate,
                "every slate deck cell must turn gold — got \(goldenYellowGain) of \(stockSlate)")
    }

    /// The beanie: the golden board's contract on its own dice — the stated
    /// rate, the cycle-zero sentinel, no flourishPose leak, and a render that
    /// actually wears green on the crown while standing down under a costume.
    @Test("About a skate beat in three wears the beanie, and it cannot leak")
    func beanieRateAndLeak() {
        var wears = 0
        let n = 20_000
        for cycle in 1...n where CrabAnimator.skateBeatWearsBeanie(cycle: cycle) { wears += 1 }
        let rate = Double(wears) / Double(n)
        #expect(rate > 0.27 && rate < 0.33, "beanie rate \(rate), wanted ~0.3")
        #expect(!CrabAnimator.skateBeatWearsBeanie(cycle: 0), "cycle zero must stay bare")
        for t in stride(from: 0.0, through: 3.2, by: 0.4) {
            #expect(CrabAnimator.flourishPose(.ollie, at: t).beanie == false)
        }

        // t = 0.9, not the apex: at bob −10 the crown IS the grid's top row
        // and the dome legitimately crops (the lofty pin's own ceiling), so
        // the full-hat probe sits a little earlier in the rise.
        var pose = CrabAnimator.flourishPose(.ollie, at: 0.9)
        pose.beanie = true
        let hatted = CrabRig.render(pose)
        var green = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where hatted[x, y] == .green { green += 1 }
        }
        #expect(green >= 15, "the beanie is missing from the crown — \(green) green cells")
        // Under a costume it stands down: the only green left is whatever the
        // wardrobe itself wears (the gundam's gem).
        let dressed = CrabRig.render(pose, costume: .gundam)
        var dressedGreen = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where dressed[x, y] == .green { dressedGreen += 1 }
        }
        #expect(dressedGreen < green, "the beanie must stand down under a costume")
    }

    // MARK: - The weighted rotation

    /// The operator skates: skate beats now take a bit over half the fired
    /// flourishes, each trick beats the cruise, and every flourish still
    /// appears — a weighted deck, not a takeover.
    @Test("The deck leans skate without abandoning anyone")
    func theDeckLeansSkate() {
        var counts: [CrabAnimator.Flourish: Int] = [:]
        var fired = 0
        for cycle in 1...2_000 {
            guard let (kind, _) = CrabAnimator.flourish(at: Double(cycle) * 7.0 + 0.01)
            else { continue }
            counts[kind, default: 0] += 1
            fired += 1
        }
        let skate = counts.filter { CrabAnimator.Flourish.skateBeats.contains($0.key) }
            .values.reduce(0, +)
        #expect(Double(skate) / Double(fired) >= 0.48,
                "skate share \(Double(skate) / Double(fired)) — the lean is gone")
        let cruise = counts[.cruise] ?? 0
        for trick in [CrabAnimator.Flourish.kickflip, .varialFlip, .ollie] {
            #expect((counts[trick] ?? 0) > cruise,
                    "\(trick) fired \(counts[trick] ?? 0) against cruise's \(cruise) — tricks lead")
        }
        for kind in CrabAnimator.Flourish.allCases {
            #expect((counts[kind] ?? 0) > 0, "\(kind) vanished from the rotation")
        }
    }
}
