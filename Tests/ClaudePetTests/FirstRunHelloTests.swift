import Testing
import Foundation
@testable import ClaudePet

/// The one wave a fresh install gets.
///
/// A DMG cannot carry motion — a Finder window's background is a colour or a
/// single still, with nowhere to put a frame rate — so the first moving thing a
/// new arrival sees is this greeting, and it happens exactly once. Nothing else
/// in the app has so little margin for being wrong: there is no second take.
@Suite("First-run hello")
struct FirstRunHelloTests {

    // MARK: - Naming the reaction

    /// **The whole mechanism.** `applyGreeting` used to derive its variant from
    /// the seed alone, so a caller wanting a wave had to find a seed that
    /// happened to roll one — `GifRenderer` still does exactly that, five
    /// hundred iterations of it.
    ///
    /// Asked by name, the pose must be identical to the one that seed-hunt
    /// would have produced. Checked against seeds that resolve to something
    /// else, because a `variant:` that only worked when the seed already agreed
    /// would pass a weaker test and ship a hello that sometimes winked.
    @Test("Naming a variant beats whatever the seed would have rolled")
    func variantOverridesSeed() {
        guard let waveSeed = (0..<500).first(where: { CrabAnimator.greeting(forSeed: $0) == .wave })
        else { Issue.record("no seed in 0..<500 resolves to .wave"); return }

        let disagreeing = (0..<500).filter { CrabAnimator.greeting(forSeed: $0) != .wave }
        #expect(!disagreeing.isEmpty, "every seed rolled a wave — this test proves nothing")

        for elapsed in stride(from: 0.0, through: 2.0, by: 0.1) {
            var byName = CrabAnimator.pose(mood: .idle, t: 3, flourishes: false)
            var bySeed = byName
            CrabAnimator.applyGreeting(elapsed: elapsed, variant: .wave, to: &byName)
            CrabAnimator.applyGreeting(elapsed: elapsed, seed: waveSeed, to: &bySeed)
            #expect(byName == bySeed, "named .wave differs from the wave seed at \(elapsed)s")

            for seed in disagreeing.prefix(5) {
                var forced = CrabAnimator.pose(mood: .idle, t: 3, flourishes: false)
                CrabAnimator.applyGreeting(elapsed: elapsed, seed: seed, variant: .wave, to: &forced)
                #expect(forced == byName,
                        "seed \(seed) leaked past the named variant at \(elapsed)s")
            }
        }
    }

    /// The hover path must be exactly what it was. `variant` defaults to nil,
    /// and nil has to mean "ask the seed" and nothing else — this is the
    /// regression guard on adding a parameter to a function the pointer uses
    /// twenty times a second.
    @Test("Without a named variant the seed still decides")
    func nilVariantLeavesHoverAlone() {
        for seed in stride(from: 0, to: 120, by: 7) {
            let expected = CrabAnimator.greeting(forSeed: seed)
            for elapsed in stride(from: 0.0, through: 1.5, by: 0.25) {
                var fromSeed = CrabAnimator.pose(mood: .idle, t: 2, flourishes: false)
                var fromName = fromSeed
                CrabAnimator.applyGreeting(elapsed: elapsed, seed: seed, to: &fromSeed)
                CrabAnimator.applyGreeting(elapsed: elapsed, seed: seed,
                                           variant: expected, to: &fromName)
                #expect(fromSeed == fromName,
                        "seed \(seed) at \(elapsed)s stopped agreeing with its own variant")
            }
        }
    }

    /// Every variant has to be reachable by name, not just the one this feature
    /// happens to want. A `variant:` that only honoured `.wave` would be a
    /// coincidence rather than a parameter.
    @Test("Every greeting can be asked for by name")
    func everyVariantIsReachable() {
        for variant in CrabAnimator.Greeting.allCases {
            guard let seed = (0..<500).first(where: { CrabAnimator.greeting(forSeed: $0) == variant })
            else { Issue.record("no seed resolves to \(variant)"); continue }
            var byName = CrabAnimator.pose(mood: .idle, t: 1.5, flourishes: false)
            var bySeed = byName
            CrabAnimator.applyGreeting(elapsed: 0.8, variant: variant, to: &byName)
            CrabAnimator.applyGreeting(elapsed: 0.8, seed: seed, to: &bySeed)
            #expect(byName == bySeed, "\(variant) by name is not \(variant) by seed")
        }
    }

    // MARK: - The frozen sentinel

    /// **Nothing may be mid-wave at t=0.** Every still the renderers sample —
    /// the README's state grid, the marketing PNGs — is taken from a pose with
    /// no hello in flight, and a greeting that leaked into them would put a
    /// waving crab in pictures captioned "idle".
    ///
    /// The envelope is what enforces it: `Ease.amount` is exactly zero until
    /// after `since`, and `applyGreeting` returns untouched below 0.001.
    @Test("A hello that has not started changes nothing")
    func nothingHappensBeforeItBegins() {
        let start = 100.0
        for now in [0.0, 50.0, 99.9, start] {
            #expect(Ease.amount(now: now, since: start, endedAt: nil) == 0,
                    "the envelope was already open at \(now)")
        }
        var untouched = CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
        let before = untouched
        CrabAnimator.applyGreeting(elapsed: 0, amount: 0, variant: .wave, to: &untouched)
        #expect(untouched == before, "a zero-amount greeting still moved him")
    }

    /// It has to end on its own. The hover greeting is closed by the pointer
    /// leaving; this one has nobody to close it, so both ends are set at once
    /// and the envelope must actually fall back to nothing — otherwise
    /// `helloSince` stays set, and with it the smooth reaction frame rate, for
    /// the rest of the session.
    @Test("The hello eases out to nothing on its own")
    func itClosesItself() {
        let since = 10.0
        let endedAt = since + PetInstance.helloWaveSeconds
        #expect(Ease.amount(now: since + 0.01, since: since, endedAt: endedAt) > 0,
                "it never opened")
        #expect(Ease.amount(now: endedAt, since: since, endedAt: endedAt) > 0.9,
                "it was already fading before its end")
        let settled = Ease.amount(now: endedAt + 1.0, since: since, endedAt: endedAt)
        #expect(settled < 0.001,
                "still waving 1s past the end (\(settled)) — the clear-out would cut him off")
    }

    // MARK: - What he says

    /// Every line names him. This is the point of the feature, not decoration:
    /// it is the only moment someone has no idea what the crab on their desktop
    /// is, and a friendly noise that does not introduce him wastes it.
    @Test("Every hello introduces him by name")
    func everyLineNamesHim() {
        let lines = Vocab.lines(for: .hello)
        #expect(!lines.isEmpty, "he has nothing to say on the one occasion that matters")
        for line in lines {
            #expect(line.localizedCaseInsensitiveContains("claw'd")
                    || line.localizedCaseInsensitiveContains("crab"),
                    "\"\(line)\" greets without introducing him")
        }
    }

    /// The ceiling applies here with no exemption. Elsewhere six lines sit on
    /// `knownLong` because a renderer finding a sentence a character too wide
    /// is not a reason to rewrite someone's voice — but those are lines you
    /// meet after you already know what he is. A truncated introduction is a
    /// worse trade, so `.hello` gets no such forgiveness.
    @Test("No hello is exempt from the bubble ceiling")
    func noLineIsAllowedToOverflow() {
        for line in Vocab.lines(for: .hello) {
            #expect(!EditableCopyTests.knownLong.contains(line),
                    "\"\(line)\" is on the long-line allowlist; the introduction must fit")
            #expect(line.count <= ThoughtBubble.plainColumns,
                    "\"\(line)\" is \(line.count) columns, over \(ThoughtBubble.plainColumns)")
        }
    }

    // MARK: - Timing

    /// The line outlives the wave on purpose: he stops moving before he stops
    /// talking, so the sentence can still be read once the motion has settled.
    /// Reading `PetInstance`'s own constants rather than restating the numbers,
    /// so retuning the beat by eye cannot leave this quietly asserting the old
    /// one.
    @Test("His introduction stays up after he stops waving")
    func theLineOutlastsTheWave() {
        #expect(PetInstance.helloLineSeconds > PetInstance.helloWaveSeconds,
                "the bubble clears while he is still mid-wave")
        #expect(PetInstance.helloDelay > 0,
                "a greeting fired at t=0 is one nobody has looked at yet")
    }
}
