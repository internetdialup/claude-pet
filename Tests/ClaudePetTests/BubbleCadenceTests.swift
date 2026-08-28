import Testing
import Foundation
@testable import ClaudePet

/// The bubble's duty cycle. It used to be non-nil on every recompute for every
/// working, cooking, nudging and alerting mood — no dice, no horizon — so the
/// banner sat on his head for the whole mood with its text swapping every 14s.
/// A banner that never goes out stops being read.
@Suite("Bubble cadence")
@MainActor
struct BubbleCadenceTests {

    private let working = ActivityCoordinator.bubbleCadences[.working]!
    private let alert = ActivityCoordinator.bubbleCadences[.needsAttention]!

    /// Samples of `(elapsed, isSpeaking)` across a stretch of one mood.
    private func timeline(_ cadence: BubbleCadence, seconds: Double,
                          salt: Int = 0, step: Double = 0.5) -> [(Double, Bool)] {
        stride(from: 0.0, through: seconds, by: step).map {
            ($0, ActivityCoordinator.bubbleBurst(elapsed: $0, cadence: cadence, salt: salt) != nil)
        }
    }

    private func runs(_ samples: [(Double, Bool)], speaking: Bool) -> [Double] {
        var out: [Double] = []
        var current = 0.0
        for (index, sample) in samples.enumerated() {
            if sample.1 == speaking {
                current += index == 0 ? 0 : samples[index].0 - samples[index - 1].0
            } else if current > 0 {
                out.append(current)
                current = 0
            }
        }
        if current > 0 { out.append(current) }
        return out
    }

    // MARK: - Facts in the silence

    /// **The change this suite exists to bound.**
    ///
    /// Every one of the seventy-six facts used to live on the idle path, and a
    /// probe of the real app explained why the operator had never seen one: he
    /// focuses the most active session, so while anyone is working with Claude
    /// Code the pet is `working` too. Idle barely happens.
    ///
    /// So a fact may now fill a beat the cadence chose to silence — and ONLY
    /// such a beat, and only some of them. Filling every silent beat would
    /// rebuild the furniture this whole suite was written against, with better
    /// words but the same failure.
    @Test("A fact takes some silent working beats, and leaves most of them silent")
    func factsFillSomeSilenceAndNotAllOfIt() {
        var quiet = 0, spoken = 0, factual = 0
        for step in 0..<4000 {
            let elapsed = Double(step) * 0.5
            let seed = Int(elapsed / ActivityCoordinator.chatterInterval)
            if ActivityCoordinator.bubbleBurst(elapsed: elapsed, cadence: working, salt: 0) != nil {
                spoken += 1
                continue
            }
            quiet += 1
            // The coordinator's OWN gates, called rather than restated — a copy
            // of the arithmetic here would keep agreeing with itself long after
            // somebody changed the salt or the threshold. Both dice, and then
            // the dwell, which is the part that stops a won window becoming a
            // banner for its full fourteen seconds.
            let intoWindow = elapsed
                .truncatingRemainder(dividingBy: ActivityCoordinator.chatterInterval)
            if ActivityCoordinator.quietBeatSpeaks(seed: seed),
               ActivityCoordinator.informationalBeat(seed: seed),
               intoWindow < working.dwell { factual += 1 }
        }

        #expect(factual > 0, "no fact ever reached a working stretch — the whole point of this")
        let share = Double(factual) / Double(quiet)
        // Two dice at 0.6 and 0.5, then six seconds of dwell in a fourteen
        // second window: about an eighth of the silent beats.
        #expect(share > 0.04 && share < 0.25,
                "facts took \(Int(share * 100))% of the silent beats; the intent is about an eighth")

        // And he is still mostly quiet across the whole stretch, which is the
        // property the cadence exists to protect.
        let silent = quiet - factual
        #expect(Double(silent) / Double(quiet + spoken) > 0.5,
                "only \(silent) of \(quiet + spoken) beats are still silent — that is furniture again")
    }

    /// **Never over a call to action.**
    ///
    /// `nudging` and `needsAttention` exist to be answered. Trivia on top of
    /// "he is blocked on you" is the one place this feature would be actively
    /// harmful, so the mood set is asserted rather than left to a reader of the
    /// switch to notice.
    @Test("Facts never speak over a mood that wants an answer")
    func factsStayOutOfTheAlerts() {
        for mood in [PetMood.nudging, .needsAttention, .done, .thinking, .sleeping] {
            #expect(!ActivityCoordinator.factMoods.contains(mood),
                    "\(mood.rawValue) would let trivia sit on top of something that needs answering")
        }
        for mood in [PetMood.working, .cooking, .idle] {
            #expect(ActivityCoordinator.factMoods.contains(mood))
        }
    }

    @Test("Work speaks in bursts, not in a banner")
    func workBurstsAndGoesQuiet() {
        let samples = timeline(working, seconds: 600)
        let duty = Double(samples.filter(\.1).count) / Double(samples.count)
        #expect(duty > 0.05 && duty < 0.25, "duty \(duty) is not a burst pattern")

        // The complaint, stated as a bound: he must stop talking.
        let quiet = runs(samples, speaking: false)
        #expect(quiet.contains { $0 > 30 },
                "he never goes quiet for 30s in ten minutes — still furniture")

        // And a burst is a burst, not a shift.
        let talking = runs(samples, speaking: true)
        #expect(talking.allSatisfy { $0 <= 12 },
                "a burst ran \(talking.max() ?? 0)s — that is a banner again")
    }

    /// Genuinely new information must never wait for a scheduled slot.
    @Test("News speaks at once, for every mood that has a cadence")
    func newsSpeaksImmediately() {
        for (mood, cadence) in ActivityCoordinator.bubbleCadences {
            #expect(ActivityCoordinator.bubbleBurst(elapsed: 0, cadence: cadence, salt: 0) == 0,
                    "\(mood) sat on fresh news")
            #expect(ActivityCoordinator.bubbleBurst(elapsed: cadence.newsDwell * 0.5,
                                                    cadence: cadence, salt: 0) == 0,
                    "\(mood) dropped the news mid-window")
        }
    }

    /// The frozen sentinel: nothing the dice invented may appear at t = 0.
    /// Burst 0 is reachable there, but only because it is a latch — something
    /// actually changed — never a schedule.
    @Test("The dice never fire in cycle zero")
    func diceNeverFireAtCycleZero() {
        for (_, cadence) in ActivityCoordinator.bubbleCadences {
            for salt in 0..<200 {
                for elapsed in stride(from: 0.0, to: cadence.newsDwell, by: 0.5) {
                    #expect(ActivityCoordinator.bubbleBurst(elapsed: elapsed, cadence: cadence,
                                                            salt: salt) == 0)
                }
                // Everything past the news window is a scheduled cycle, and
                // scheduled cycles are numbered from one.
                for elapsed in stride(from: cadence.newsDwell, through: 300.0, by: 0.5) {
                    if let burst = ActivityCoordinator.bubbleBurst(
                        elapsed: elapsed, cadence: cadence, salt: salt) {
                        #expect(burst >= 1, "a scheduled burst claimed index 0")
                    }
                }
            }
        }
    }

    /// The coordinator recomputes every 2s. If the gate were not a pure
    /// function of elapsed time, the sentence would rewrite itself under the
    /// reader mid-burst.
    @Test("A burst holds its identity across resamples")
    func burstIsStableUnderResampling() {
        // Find a scheduled burst, then sample inside it three times.
        var found: Double?
        for elapsed in stride(from: working.newsDwell, through: 400.0, by: 0.25) {
            if let burst = ActivityCoordinator.bubbleBurst(elapsed: elapsed, cadence: working,
                                                          salt: 0), burst >= 1 {
                found = elapsed
                break
            }
        }
        let start = try! #require(found)
        let first = ActivityCoordinator.bubbleBurst(elapsed: start, cadence: working, salt: 0)
        for offset in [0.5, 1.0, 2.0] {
            #expect(ActivityCoordinator.bubbleBurst(elapsed: start + offset, cadence: working,
                                                    salt: 0) == first,
                    "the burst index changed \(offset)s in")
        }
    }

    /// Calls to action pulse rather than go dark. Being blocked on the human
    /// is the one thing the pet exists to tell you.
    @Test("Alerts never go dark for long")
    func alertsNeverGoDark() {
        let samples = timeline(alert, seconds: 1800, step: 0.5)
        let quiet = runs(samples, speaking: false)
        #expect(quiet.allSatisfy { $0 <= 9.5 },
                "an alert went quiet for \(quiet.max() ?? 0)s")
        #expect(!quiet.isEmpty, "it must still pulse, not sit there")
    }

    /// Two pets must not breathe in lockstep.
    @Test("Slots are decorrelated")
    func slotsDecorrelate() {
        let a = timeline(working, seconds: 600, salt: 0).map(\.1)
        let b = timeline(working, seconds: 600, salt: 1 * 7919).map(\.1)
        let agree = zip(a, b).filter { $0 == $1 }.count
        #expect(Double(agree) / Double(a.count) < 0.97,
                "both pets speak on the same schedule")
    }
}
