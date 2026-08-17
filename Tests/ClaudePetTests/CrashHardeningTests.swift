import Testing
import Foundation
@testable import ClaudePet

/// The crash seams, tested the way the handoff prescribes: "no displays" is an
/// empty array, the backward clock band is a sweep, and the subscripts stay
/// deliberately partial — their totality is the seam's promise, and these are
/// the tests of the promise.
@Suite("Crash hardening")
@MainActor
struct CrashHardeningTests {

    // MARK: - The screen rule (findings 1 and 2)

    private let studio = CGRect(x: 0, y: 0, width: 2880, height: 1620)
    private let sidecar = CGRect(x: 2880, y: 0, width: 1512, height: 982)

    @Test func noDisplaysIsNilNotATrap() {
        // The regression itself: this exact question used to end in
        // NSScreen.screens[0] — a subscript of the array whose emptiness is
        // what got it there.
        #expect(PetWindowController.nearestScreenIndex(
            to: CGRect(x: 100, y: 100, width: 300, height: 170), among: []) == nil)
    }

    @Test func containmentWinsAndNearestFallsBack() {
        let inside = CGRect(x: 500, y: 500, width: 300, height: 170)
        #expect(PetWindowController.nearestScreenIndex(to: inside, among: [studio]) == 0)
        // A rect thrown far off every display still resolves, by nearest centre.
        let far = CGRect(x: -9000, y: -9000, width: 300, height: 170)
        #expect(PetWindowController.nearestScreenIndex(to: far, among: [studio]) == 0)
        // And lands on the genuinely nearer of two.
        let nearSidecar = CGRect(x: 3400, y: 400, width: 300, height: 170)
        #expect(PetWindowController.nearestScreenIndex(to: nearSidecar,
                                                       among: [studio, sidecar]) == 1)
    }

    @Test func seamTiesGoToTheEarliestIndex() {
        // Two identical displays mirrored at the same rect: every distance
        // ties. The answer must be the SAME index every time — a tie that
        // flickers moves the pet across a seam per call.
        let mirrored = [studio, studio]
        let between = CGRect(x: 1300, y: 2000, width: 300, height: 170)
        for _ in 0..<20 {
            #expect(PetWindowController.nearestScreenIndex(to: between, among: mirrored) == 0)
        }
    }

    @Test func placementDebtClearsOnlyWhenAPlacementLands() {
        var debt = PetWindowController.PlacementDebt()
        #expect(!debt.isOwed)
        debt.attempted(placed: false)
        #expect(debt.isOwed, "an unplaced launch owes a placement")
        // Reading it does not discharge it; only a landing does.
        debt.attempted(placed: false)
        #expect(debt.isOwed)
        debt.attempted(placed: true)
        #expect(!debt.isOwed)
    }

    // MARK: - The mood age (finding 5)

    @Test func ageNeverRunsBackwards() {
        let clock = MoodClock()
        let epoch = clock.epoch(for: .cooking)
        // Sweep the whole backward band a coarse render lattice can produce,
        // and further: the age is clamped, and forward of the epoch it is
        // still exactly the elapsed time.
        for offset in stride(from: -2.0, through: 6.0, by: 0.005) {
            let age = clock.age(of: .cooking, at: epoch + offset)
            #expect(age >= 0)
            // Epochs sit near 8e8 seconds, where Double addition carries
            // ~1e-7 of slack — the tolerance is about float width, not logic.
            if offset >= 0 { #expect(abs(age - offset) < 1e-6) }
        }
    }

    @Test func theFlameArithmeticSurvivesTheBand() {
        // The consumer that used to die: flameFrames[Int(phase * 6) % 3].
        // Apply its own arithmetic to what the seam now hands out and assert
        // the index is total. Deliberately NOT also guarding the subscript —
        // two guards for one invariant is how the second one drifts.
        let clock = MoodClock()
        let epoch = clock.epoch(for: .cooking)
        for offset in stride(from: -2.0, through: 6.0, by: 0.005) {
            let phase = clock.age(of: .cooking, at: epoch + offset)
            let index = Int(phase * 6) % 3
            #expect(index >= 0 && index < 3, "flame index \(index) at offset \(offset)")
        }
    }

    @Test func theClampStillRebases() {
        // A clamp that quietly stopped committing mood flips would freeze
        // every one-shot beat at the previous mood's clock.
        let clock = MoodClock()
        _ = clock.epoch(for: .working)
        let flipped = Date.timeIntervalSinceReferenceDate
        let ageAtFlip = clock.age(of: .done, at: flipped)
        #expect(ageAtFlip < 0.05, "a fresh mood starts at zero")
        #expect(abs(clock.age(of: .done, at: flipped + 1) - 1) < 0.05,
                "and is one, one second later")
    }

    // MARK: - The duration parse (finding 7)

    @Test func nonsenseDurationsAreRefused() {
        #expect(Probe.clampedDuration("nan") == nil, "NaN probes nothing and calls it success")
        #expect(Probe.clampedDuration("inf") == nil, "infinity probes forever")
        #expect(Probe.clampedDuration("-5") == nil)
        #expect(Probe.clampedDuration("0") == nil)
        #expect(Probe.clampedDuration("crab") == nil)
    }

    @Test func realDurationsPassAndTheCeilingHolds() {
        #expect(Probe.clampedDuration("3") == 3)
        #expect(Probe.clampedDuration("320") == 320)
        #expect(Probe.clampedDuration("1e30") == 3600, "finite-but-absurd clamps to the hour")
    }
}
