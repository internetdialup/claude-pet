import Testing
import Foundation
@testable import ClaudePet

/// 📣 **Three cuts for a feed.**
///
/// No rig behaviour changes in this file's round, so what is pinned is the
/// EDIT — the arithmetic of the grid, and the handful of claims the three cuts
/// make about themselves. Above all the two the operator will judge them on:
/// that the first one comes home, and that the third one is the app rather than
/// a composition dressed up as it.
@MainActor
struct FeedCutsTests {

    private var cuts: [FeedCuts.Cut] { FeedCuts.cuts }

    @Test("Every cut is a whole number of beats, and a whole number of frames")
    func theGridHolds() {
        #expect(cuts.count == 3)
        for cut in cuts {
            let beats = cut.seconds / FeedCuts.beat
            #expect(abs(beats - beats.rounded()) < 1e-9,
                    "\(cut.name) runs \(cut.seconds)s — \(beats) beats")
            let frames = cut.seconds * Double(FeedCuts.fps)
            #expect(abs(frames - frames.rounded()) < 1e-9,
                    "\(cut.name) is \(frames) frames at \(FeedCuts.fps)fps")
            #expect(cut.frames > 0)
        }
        // A feed clip that runs long is a feed clip nobody finishes.
        for cut in cuts { #expect(cut.seconds <= 8, "\(cut.name) runs \(cut.seconds)s") }
    }

    /// 🔎 THE FIRST CUT'S WHOLE CLAIM: *"the laser flip, him going rainbow mode,
    /// then rotating back to normal"* — and both halves of "back to normal" have
    /// to be true on the same frame. The rotation lands square because the
    /// bigspin finishes its turn rather than unwinding it; the colour lands home
    /// because the party's own trapezoid is offset to end exactly there.
    @Test("The first cut comes home: square, and his own colour again")
    func theFirstCutResolves() {
        let last = FeedCuts.oneLength - 1.0 / Double(FeedCuts.fps)
        // The colour is gone by the end…
        #expect(FeedCuts.oneTint(FeedCuts.oneTricks) == nil, "the party outlives the tricks")
        #expect(FeedCuts.oneTint(last) == nil, "the party outlives the cut")
        // 🔎 …and TOGETHER, which is the word the operator used. Checking only
        // that the colour is gone by the end is blind: a party that ended a
        // second and a half early would satisfy it and leave him spinning out on
        // plain terracotta with nothing resolving. It has to still be on his
        // shell a quarter second before he lands, and off by the time he does.
        #expect(FeedCuts.oneTint(FeedCuts.oneTricks - 0.25) != nil,
                "the colour was already gone before he landed — nothing resolves together")
        #expect(FeedCuts.oneTint(FeedCuts.oneTricks - 1.0) != nil,
                "the party is not running through the spin at all")
        // …and the tail really is a tail: he stands there, square and himself.
        #expect(FeedCuts.oneTail >= 0.5, "there is no room to land on")
        // …and it was really there in the middle.
        #expect(FeedCuts.oneTint(FeedCuts.oneLength / 2 + 1) != nil, "there is no rainbow at all")
        // …and the last colour he wears on the way out is a warm one, near his
        // own shell, because the folded wheel turns round and comes back to red.
        var lastTint: SpriteTint.Tint?
        for index in 0..<cuts[0].frames {
            let t = Double(index) / Double(FeedCuts.fps)
            if let tint = CrabView.rainbowTint(elapsed: t - FeedCuts.partyOnset) { lastTint = tint }
        }
        #expect(lastTint != nil)
        if let lastTint {
            let high = max(lastTint.r, max(lastTint.g, lastTint.b))
            #expect(lastTint.r >= high - 1e-9, "he leaves on \(lastTint), which is not a warm colour")
        }
        // …and he is facing front: a whole turn, which the rig draws as none.
        let landed = FeedCuts.onePose(last)
        let turn = landed.torsoTurn - landed.torsoTurn.rounded(.down)
        #expect(turn < 0.02 || turn > 0.98, "he lands at \(landed.torsoTurn) of a turn")
    }

    /// 🔎 The seam between two flourishes is the one place a hand-cut sequence
    /// can snap, and the props are what snap: `bob` and `squash` already agree
    /// across it, the boards do not. `CrabPose.blend` carries the outgoing one
    /// as a dissolving ghost, which is what the live view does for a costume
    /// change and for exactly this reason.
    @Test("The first cut's seam dissolves rather than cutting")
    func theSeamDoesNotSnap() {
        let step = 1.0 / Double(FeedCuts.fps)
        var previous = FeedCuts.onePose(FeedCuts.flipLength - step * 3)
        var t = FeedCuts.flipLength - step * 2
        while t <= FeedCuts.flipLength + FeedCuts.seamBlend + step * 3 {
            let now = FeedCuts.onePose(t)
            #expect(abs(now.bob - previous.bob) <= 1, "bob jumped at \(t)")
            #expect(abs(now.squash - previous.squash) <= 1, "squash jumped at \(t)")
            #expect(abs(now.lean - previous.lean) <= 1, "lean jumped at \(t)")
            #expect(abs(now.tilt - previous.tilt) <= 1, "tilt jumped at \(t)")
            previous = now
            t += step
        }
        // The board really does change, and the change really is ghosted — a
        // seam with no prop change would make this test vacuous.
        let before = FeedCuts.onePose(FeedCuts.flipLength - step)
        let inside = FeedCuts.onePose(FeedCuts.flipLength + FeedCuts.seamBlend / 2)
        #expect(before.prop != inside.prop, "the two tricks share a board — this guard is vacuous")
        #expect(inside.ghostProp == before.prop,
                "the outgoing board is not being carried as a ghost")
        #expect(inside.ghostPropVisibility > 0 && inside.propVisibility < 1,
                "the two boards are not cross-dissolving")

        // 🔎 …and the SAME is true where the trick hands back to a resting
        // pose. The base carries no board, so without a dissolve the deck
        // vanishes in one frame the instant he lands — which a contact sheet
        // caught after the seam above had already been fixed. Two hand-offs in
        // this cut, and both of them are hand-offs.
        let landing = FeedCuts.onePose(FeedCuts.oneTricks + FeedCuts.seamBlend / 2)
        let settled = FeedCuts.onePose(FeedCuts.oneLength - step)
        #expect(settled.prop == .none, "the resting tail still carries a board")
        #expect(landing.ghostProp != .none, "the board is not being dissolved away on the landing")
        #expect(landing.ghostPropVisibility > 0,
                "the board vanishes in a frame when he lands")
        // …and no frame anywhere in the cut drops a visible board to nothing at
        // once, which is the defect stated rather than the mechanism.
        var wasVisible = 0.0
        for index in 0..<cuts[0].frames {
            let pose = FeedCuts.onePose(Double(index) / Double(FeedCuts.fps))
            let visible = max(pose.prop == .none ? 0 : pose.propVisibility,
                              pose.ghostProp == .none ? 0 : pose.ghostPropVisibility)
            #expect(wasVisible - visible < 0.9,
                    "the board fell from \(wasVisible) to \(visible) in one frame at index \(index)")
            wasVisible = visible
        }
    }

    /// The middle cut is `ButtLoop`'s own window, asked for rather than copied,
    /// and it has to survive being played end to end more than once.
    @Test("The middle cut is the loop, and it loops")
    func theMiddleCutLoops() {
        let jiggle = cuts[1]
        // 🔎 Against the NUMBER, not against the constant that produced it. The
        // first cut of this line compared `jiggle.frames` to
        // `ButtLoop.frameCount * FeedCuts.jigglePasses` — both sides derived
        // from the same constant, so changing that constant moved both and the
        // pin was blind. Two seconds is the claim; forty frames is the claim.
        #expect(abs(jiggle.seconds - 2.0) < 1e-9, "the jiggle cut runs \(jiggle.seconds)s, not 2")
        #expect(jiggle.frames == 40, "the jiggle cut is \(jiggle.frames) frames, not 40")
        #expect(jiggle.frames % ButtLoop.frameCount == 0,
                "the cut is not a whole number of loops")
        // Frame zero of the second pass is frame zero of the first: the seam
        // between passes is the loop's own, so there is no seam.
        let first = CrabRig.render(FeedCuts.twoPose(0))
        let again = CrabRig.render(FeedCuts.twoPose(ButtLoop.frameCount))
        #expect(first.same(as: again), "the second pass does not start where the first did")
        // …and it is not a still: something moves inside a pass.
        let middle = CrabRig.render(FeedCuts.twoPose(ButtLoop.frameCount / 4))
        #expect(!first.same(as: middle), "nothing happens inside the loop")
        // The window is the one `ButtLoop` establishes, not a second copy.
        #expect(FeedCuts.twoLength
                == (ButtLoop.closeAt - ButtLoop.openAt)
                * CrabAnimator.Flourish.halfCab.duration * Double(FeedCuts.jigglePasses))
    }

    /// 🔎 THE THIRD CUT IS THE APP, NOT A COMPOSITION. `flourishPose` never
    /// scores, so a hand-built "back smith with a trail" would mean writing
    /// `combo` in from outside — and `composedTint` says at the point it reaches
    /// for the score that *"a review that showed the trail without the rainbow
    /// would be lying about the ride."* Both halves are pinned here, because the
    /// first pass of this cut carried the ribbon on a plain terracotta crab and
    /// only a contact sheet caught it.
    @Test("The third cut carries the trail and the colour together, all the way")
    func theThirdCutIsTheRide() {
        let trail = Set(CrabRig.trailInks)
        var ribbonFrames = 0
        // By INDEX, the way the renderer walks it: stepping a Double by a
        // twentieth accumulates enough error over six and a half seconds to run
        // the loop one extra time, which had this counting 131 frames of a
        // 130-frame clip and calling it a failure.
        for index in 0..<cuts[2].frames {
            let t = Double(index) / Double(FeedCuts.fps)
            // The window lies wholly inside a real ride.
            #expect(CrabAnimator.comboRide(local: FeedCuts.rideOpensAt + t) != nil,
                    "the ride is over at \(t)")
            let pose = FeedCuts.threePose(t)
            #expect(pose.combo > 0, "the score is \(pose.combo) at \(t) — no ride, no trail")
            #expect(FeedCuts.threeTint(t) != nil, "the shell is untinted at \(t) while the trail flies")
            let buffer = CrabRig.render(pose)
            var ribbon = 0
            for y in 0..<PixelBuffer.side {
                for x in 0..<8 where trail.contains(buffer[x, y]) { ribbon += 1 }
            }
            if ribbon > 0 { ribbonFrames += 1 }
        }
        #expect(ribbonFrames == cuts[2].frames,
                "the trail is missing from \(cuts[2].frames - ribbonFrames) frames")
        // …including the very first, which is what "trail INTO the grind" means.
        var opening = 0
        let first = CrabRig.render(FeedCuts.threePose(0))
        for y in 0..<PixelBuffer.side {
            for x in 0..<8 where trail.contains(first[x, y]) { opening += 1 }
        }
        #expect(opening >= 6, "the cut opens on only \(opening) cells of trail")
    }

    /// …and it is the BACK SMITH, which is the grind the operator corrected to.
    @Test("The third cut is the back smith, on its ledge")
    func theThirdCutIsTheBackSmith() {
        // Mid-grind: the smith board, locked, with the ledge under him.
        let mid = FeedCuts.threePose(FeedCuts.threeLength * 0.55)
        #expect(mid.prop == .skateboardSmith, "mid-grind the board is \(mid.prop)")
        #expect(mid.grindSparks > 0.5, "no sparks mid-grind")
        #expect(mid.ledge > 0 && mid.ledge < 1, "the ledge is not on the grid mid-grind")
        // The ledge arrives inside the cut rather than being there all along.
        #expect(FeedCuts.threePose(0).ledge < 0.05, "the cut opens with the ledge already in")
    }

    /// Whole cells, and nothing cropped — a feed clip that clipped his claw
    /// would be a feed clip of a broken crab.
    @Test("The frame is whole-cell and nothing crops")
    func theFrameIsClean() {
        #expect(FeedCuts.spriteSide.truncatingRemainder(dividingBy: 32) == 0,
                "the sprite is \(FeedCuts.spriteSide)pt — not a whole cell")
        #expect(FeedCuts.cell == FeedCuts.cell.rounded(), "a cell is \(FeedCuts.cell)pt")
        #expect(FeedCuts.spriteSide <= min(FeedCuts.canvas.width, FeedCuts.canvas.height),
                "the sprite does not fit its canvas")
        let top = (FeedCuts.canvas.height - FeedCuts.spriteSide) / 2 + FeedCuts.offsetY
        #expect(top >= 0 && top + FeedCuts.spriteSide <= FeedCuts.canvas.height,
                "the sprite crops vertically")
        let left = (FeedCuts.canvas.width - FeedCuts.spriteSide) / 2
        #expect(left >= 0 && left + FeedCuts.spriteSide <= FeedCuts.canvas.width,
                "the sprite crops horizontally")
        // 4:5, which is the shape that was asked for.
        #expect(abs(FeedCuts.canvas.width / FeedCuts.canvas.height - 0.8) < 1e-9,
                "the canvas is \(FeedCuts.canvas), not 4:5")
    }
}

private extension PixelBuffer {
    func same(as other: PixelBuffer) -> Bool {
        for y in 0..<Self.side {
            for x in 0..<Self.side where self[x, y] != other[x, y] { return false }
        }
        return true
    }
}
