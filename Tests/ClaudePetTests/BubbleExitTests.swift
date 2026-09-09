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
/// `.serialized` because the slot tests are the suite's first that depend on
/// main-queue timers actually firing, and two of them sharing the main queue
/// would be timing each other.
@Suite(.serialized)
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
    func theSlotClearsItself() async {
        let model = PetViewModel()
        model.speak("Kowbunga 🤙!", until: Date().addingTimeInterval(0.3), mood: .idle)
        #expect(model.transientBubble?.text == "Kowbunga 🤙!")
        #expect(model.transientBubble?.mood == .idle)
        #expect(await cleared(model),
                "the slot never cleared — the box would sit until the next publish")
    }

    /// The guard on the clearing write, exercised at the door itself. Through
    /// `PetInstance.say` a second line cannot land while the first is live —
    /// `shouldSpeak` refuses it, deliberate or not — so the two deadlines can
    /// never cross that way; but the door is what makes the promise, and the
    /// door must keep it on its own.
    @MainActor
    @Test("An older deadline never clears a newer line")
    func anOlderDeadlineNeverClearsANewerLine() async {
        let model = PetViewModel()
        model.speak("first", until: Date().addingTimeInterval(0.3), mood: .idle)
        model.speak("second", until: Date().addingTimeInterval(0.9), mood: .done)
        try? await Task.sleep(for: .milliseconds(550))
        #expect(model.transientBubble?.text == "second",
                "the first line's deadline took the second line down")
        #expect(await cleared(model), "the second line never left on its own")
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

    /// Polls for the slot to empty rather than sleeping a fixed guess — the
    /// clearing write is a main-queue timer, and a fixed sleep would make
    /// this flaky by construction (the shape `FileWatcherTests` uses).
    @MainActor
    /// 🔎 Ten seconds of patience for a deadline three tenths of a second away,
    /// and the margin is not superstition. The contract under test is "the slot
    /// clears ITSELF", not "within three seconds of wall clock" — and this
    /// polls real time from a suite that runs six hundred tests in parallel,
    /// where the scheduled write can be starved well past a three-second budget.
    /// It failed exactly that way once, in a full run, and passed on its own
    /// three times immediately after. A flake in a gate is worse than a slow
    /// gate: it teaches everyone to re-run instead of to read.
    private func cleared(_ model: PetViewModel, within timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.transientBubble == nil { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
