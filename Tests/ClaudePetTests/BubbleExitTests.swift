import Testing
import Foundation
@testable import ClaudePet

/// **The empty bubble.**
///
/// A spoken line — a skate shout, a surf line, the first-run hello — lives in
/// one slot with a deadline, and for four weeks nothing cleared it: the view
/// filtered it against `Date()` in its body, and a body only re-runs when
/// something publishes. On 2026-09-04 the typewriter learned to fade its ink
/// over the last 0.45s, on the display link, and the latent bug became a
/// visible one — the words gone at the deadline, the green box waiting for a
/// change that on a quiet desk could be half a minute away.
///
/// Two rules close it, and both are pinned here: the exit belongs to the
/// WHOLE bubble, on one clock; and the slot clears itself at its deadline.
///
/// 🔎 The slot tests used to wait on the real main-queue timer, polling the
/// clock for up to ten seconds — and under a full parallel run at a load
/// average of 20 they failed anyway, at 22.7 s, because the polling loop needed
/// the same main thread the stalled timer did. Widening the window had been
/// tried twice. They now take the booking through `PetViewModel.scheduleClear`
/// and fire it: what they prove is that the clear is booked for exactly the
/// deadline and that the right write takes the right line down, which is the
/// contract — not that this machine happened to be fast enough.
struct BubbleExitTests {

    /// **One clock, not two.** The fade once took a remaining DURATION
    /// computed in `PetRootView.body` — which re-runs on any published write —
    /// while the typewriter measured elapsed time from its own mount. Two
    /// origins: substituting them, the fade's argument is
    /// `(2x - D + 0.45)/0.45`, which reaches 1 the moment `x` passes half the
    /// line's life and never comes back. The line blanked halfway through and
    /// stayed blank.
    ///
    /// Taking an INSTANT fixes it by construction, and this pins the shape:
    /// solid for the whole life, easing only over the last `exitSeconds`, and
    /// never fading in a frozen render. It lived on `TypewriterText` while
    /// the fade was the text's; the fade is the bubble's now, and so is this.
    @MainActor
    @Test("The exit only happens at the end, and only when live")
    func theExitIsOnOneClock() {
        let expiry = 1000.0
        // Solid right up to the exit window.
        for now in [900.0, 980.0, 999.0, expiry - ThoughtBubble.exitSeconds - 0.01] {
            #expect(ThoughtBubble.exitLevel(now: now, expiresAt: expiry, frozen: false) == 0,
                    "left early at \(expiry - now)s remaining")
        }
        // Monotonic through the window, and fully gone at the end.
        var previous = 0.0
        for step in 0...20 {
            let now = expiry - ThoughtBubble.exitSeconds
                + ThoughtBubble.exitSeconds * Double(step) / 20
            let level = ThoughtBubble.exitLevel(now: now, expiresAt: expiry, frozen: false)
            #expect(level >= previous - 1e-9, "the exit reversed at \(now)")
            previous = level
        }
        #expect(ThoughtBubble.exitLevel(now: expiry, expiresAt: expiry, frozen: false) == 1)
        // …and stays gone: a body run late for the deadline must not find a
        // half-visible box.
        #expect(ThoughtBubble.exitLevel(now: expiry + 30, expiresAt: expiry, frozen: false) == 1)
        // Frozen renders never fade — a still of a half-faded bubble is the
        // same defect as a still of a half-typed one.
        #expect(ThoughtBubble.exitLevel(now: expiry, expiresAt: expiry, frozen: true) == 0)
        // …and no expiry means solid forever.
        #expect(ThoughtBubble.exitLevel(now: expiry, expiresAt: nil, frozen: false) == 0)
    }

    /// The slot's doc said "Cleared by its own deadline" from the day it was
    /// born, and no code ever did it. This is that sentence, as a test.
    @MainActor
    @Test("A spoken line clears its own slot at the deadline")
    func theSlotClearsItself() {
        let model = PetViewModel()
        var booked: [(at: Date, fire: @MainActor () -> Void)] = []
        model.scheduleClear = { booked.append(($0, $1)) }
        let deadline = Date().addingTimeInterval(0.3)
        model.speak("Kowbunga 🤙!", until: deadline, mood: .idle)
        #expect(model.transientBubble?.text == "Kowbunga 🤙!")
        #expect(model.transientBubble?.mood == .idle)
        // The booking IS the deadline — the write that clears the slot is
        // scheduled for exactly `until`, and speaking books exactly one.
        #expect(booked.map { $0.at } == [deadline],
                "speaking must book one clearing write, at the line's own deadline")
        booked.first?.fire()
        #expect(model.transientBubble == nil,
                "the slot never cleared — the box would sit until the next publish")
    }

    /// The guard on the clearing write, exercised at the door itself. Through
    /// `PetInstance.say` a second line cannot land while the first is live —
    /// `shouldSpeak` refuses it, deliberate or not — so the two deadlines can
    /// never cross that way; but the door is what makes the promise, and the
    /// door must keep it on its own.
    ///
    /// It used to sleep 550 ms and bet the first timer had fired and the second
    /// had not — the opposite timing bet from the test above, so a slow machine
    /// failed it with a misleading message. Firing the bookings in order makes
    /// the bet unnecessary.
    @MainActor
    @Test("An older deadline never clears a newer line")
    func anOlderDeadlineNeverClearsANewerLine() throws {
        let model = PetViewModel()
        var booked: [(at: Date, fire: @MainActor () -> Void)] = []
        model.scheduleClear = { booked.append(($0, $1)) }
        model.speak("first", until: Date().addingTimeInterval(0.3), mood: .idle)
        model.speak("second", until: Date().addingTimeInterval(0.9), mood: .done)
        try #require(booked.count == 2)
        booked[0].fire()                       // the first line's deadline arrives
        #expect(model.transientBubble?.text == "second",
                "the first line's deadline took the second line down")
        booked[1].fire()
        #expect(model.transientBubble == nil, "the second line never left on its own")
    }

    /// A blank line is not a line. Drawn, it would be a box of padding with
    /// no words in it — the exact picture this suite exists to prevent, by a
    /// different road.
    @Test("A blank line is not a line")
    func aBlankLineIsNotShown() {
        #expect(PetRootView.showable(nil) == nil)
        #expect(PetRootView.showable("") == nil)
        #expect(PetRootView.showable("  \n\t ") == nil)
        #expect(PetRootView.showable("Kowbunga 🤙!") == "Kowbunga 🤙!")
        #expect(PetRootView.showable(" a ") == " a ", "a line with words in it is shown as written")
    }
}
