import Testing
import Foundation
@testable import ClaudePet

/// **Who gets the bubble.**
///
/// Five places used to assign `transientBubble` directly and none of them
/// looked first, which is how the operator came to watch a fun fact taken off
/// the screen mid-thought by his own small talk. The rule now lives in one
/// place — and, because that place was `private` on a `@MainActor` class,
/// nothing in the suite could reach it. It is lifted out as a pure function
/// so the rule can be stated as arithmetic rather than exercised through a
/// whole pet.
struct SpeakRuleTests {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("An empty bubble always accepts a line")
    func nothingShowingMeansSpeak() {
        #expect(PetInstance.shouldSpeak(transientUntil: nil, stateBubble: nil,
                                        tone: .mood, deliberate: false, now: now))
        #expect(PetInstance.shouldSpeak(transientUntil: nil, stateBubble: "",
                                        tone: .knowledge, deliberate: false, now: now))
    }

    /// The rule with no exceptions: two of his own lines must never fight.
    @Test("A line still being read is never interrupted, deliberate or not")
    func aLiveTransientAlwaysWins() {
        let live = now.addingTimeInterval(1.5)
        #expect(!PetInstance.shouldSpeak(transientUntil: live, stateBubble: nil,
                                         tone: .mood, deliberate: false, now: now))
        #expect(!PetInstance.shouldSpeak(transientUntil: live, stateBubble: nil,
                                         tone: .mood, deliberate: true, now: now))
        // …and the instant it expires, the slot is free again.
        #expect(PetInstance.shouldSpeak(transientUntil: now, stateBubble: nil,
                                        tone: .mood, deliberate: false, now: now))
    }

    /// The asymmetry that makes the rule usable: a fact outranks a shout that
    /// arrived on its own, and does not outrank a person's hands.
    @Test("A held fact stops an ambient shout but not a poke")
    func knowledgeStopsAmbientOnly() {
        #expect(!PetInstance.shouldSpeak(transientUntil: nil,
                                         stateBubble: "Binary is base two",
                                         tone: .knowledge, deliberate: false, now: now),
                "a skate shout took the face from a fact")
        #expect(PetInstance.shouldSpeak(transientUntil: nil,
                                        stateBubble: "Binary is base two",
                                        tone: .knowledge, deliberate: true, now: now),
                "a poke went unanswered — the chirp and the pose land either way")
    }

    /// Only KNOWLEDGE takes the face. His own chatter has no hold and needs
    /// no protecting from itself.
    @Test("His own voice does not block a shout")
    func moodLinesDoNotBlock() {
        #expect(PetInstance.shouldSpeak(transientUntil: nil,
                                        stateBubble: "Off the clock",
                                        tone: .mood, deliberate: false, now: now),
                "a mood line blocked a shout, and only knowledge should")
    }
}
