import Testing
import Foundation
@testable import ClaudePet

/// The readable-once shield's pure arithmetic. The three behavioral proofs
/// (churn cannot kill a fact mid-read, news wins the instant the shield
/// lifts, idle facts survive the seed edge) live inside `MoodDecayTests` —
/// they mutate the process-global cadences and clocks, and that suite is the
/// serialized room where every such mutation already happens. A second
/// mutating suite ran concurrently with it exactly once, clearing the shared
/// fixture's sessions out from under it, and that was one time too many.
@Suite("Readable shield")
@MainActor
struct ReadableShieldTests {

    /// The shield can never outlive the stay, for any line either pool can
    /// deal — otherwise "news wins after the read" would have a dead zone
    /// where the fact was gone but the shield still stood.
    @Test("The readable window always fits inside the hold")
    func theShieldNeverOutlivesTheStay() {
        let knowable = FunFacts.Category.allCases.flatMap { FunFacts.facts(in: $0) }
            + ClaudeTips.all
        for line in knowable {
            let shield = ActivityCoordinator.readableWindow(for: line)
                + ActivityCoordinator.readableGrace
            #expect(shield < ActivityCoordinator.lineHold(for: line),
                    "\"\(line)\" shields \(shield)s against a \(ActivityCoordinator.lineHold(for: line))s stay")
        }
        // Reversed with the two-line bubble: a plain line is no longer
        // legible on arrival, because it types itself in. It gets a real
        // window like everything else.
        #expect(ActivityCoordinator.readableWindow(for: "zzz…") > 0,
                "a plain line types in, so it needs a window like any other")
    }
}
