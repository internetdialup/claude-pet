import Testing
import Foundation
@testable import ClaudePet

/// **The Skater stands on his deck.**
///
/// The skateboard was only ever a trick's prop: dressed as the Skater he was
/// on a board for about a third of his idle time and stood on nothing for the
/// rest — under kick-push dust that implied a board that was not there. The
/// operator's ruling: on his deck about seven minutes in ten, off it for the
/// other three, in long stretches, stepping on and off with the prop dissolve
/// rather than flickering every cycle. Live-only through the wardrobe, so no
/// committed byte moves.
@MainActor
struct DeckStanceTests {

    private let skater = CrabAnimator.MotionWardrobe(current: .skater)

    /// Deck present at a coarse-cycle midpoint — asked on the flourish
    /// boundary plus a hair, so no trick is under way and the envelope has
    /// long settled.
    private func standing(cycle: Int, wardrobe: CrabAnimator.MotionWardrobe) -> Double {
        let period = SpawnRates.deckStance.period
        // 28 = 4 flourish cycles in; the fade (0.6s) is long done and no
        // session (which starts at 180k+2) or surf (300k+2) opens here.
        return CrabAnimator.deckStance(idleT: Double(cycle) * period + 28.01, wardrobe: wardrobe)
    }

    @Test("Dressed as the Skater he stands on his deck about seven stretches in ten")
    func theSkaterStandsOnHisDeckAboutSeventyPercent() {
        var on = 0
        let n = 4000
        for cycle in 1...n where standing(cycle: cycle, wardrobe: skater) > 0.999 { on += 1 }
        let share = Double(on) / Double(n)
        #expect(abs(share - SpawnRates.deckStance.chance) < 0.05,
                "he stood on the deck \(share) of the time; the table says \(SpawnRates.deckStance.chance)")
        // Cycle 0 is ON: the idle clock rebases on every idle entry, and a
        // sentinel here would cost him his board for the first minute after
        // every working spell.
        #expect(standing(cycle: 0, wardrobe: skater) == 1)
        // Every other look, and the bare wardrobe, never stand.
        for costume in Costume.allCases where costume != .skater {
            let wardrobe = CrabAnimator.MotionWardrobe(current: costume)
            for cycle in 0..<40 {
                #expect(standing(cycle: cycle, wardrobe: wardrobe) == 0, "\(costume) stood on a deck")
            }
        }
        for t in stride(from: 0.0, through: 1000, by: 3.3) {
            #expect(CrabAnimator.deckStance(idleT: t, wardrobe: .init()) == 0, "bare at \(t)")
        }
    }

    /// The envelope, not the switch: across every boundary the deck moves by
    /// at most one fade-step a frame, and where a board spell owns the
    /// boundary the fade waits for the board to leave.
    @Test("The deck never pops — not at a boundary, not under a session, not on a costume change")
    func theDeckNeverPops() {
        let period = SpawnRates.deckStance.period
        // smoothstep's steepest slope is 1.5 at its midpoint.
        let maxStep = 1.5 / (CrabAnimator.deckStanceFade * 30) + 1e-6
        // Find a boundary where the stance flips, and sweep it at 30fps.
        var flips = 0
        for cycle in 1...400 {
            let before = standing(cycle: cycle - 1, wardrobe: skater)
            let after = standing(cycle: cycle, wardrobe: skater)
            guard before != after else { continue }
            flips += 1
            var previous = CrabAnimator.deckStance(idleT: Double(cycle) * period - 1, wardrobe: skater)
            var t = Double(cycle) * period - 1
            while t < Double(cycle) * period + 25 {
                t += 1.0 / 30
                let now = CrabAnimator.deckStance(idleT: t, wardrobe: skater)
                #expect(abs(now - previous) <= maxStep,
                        "the deck jumped \(now - previous) at \(t) (cycle \(cycle))")
                previous = now
            }
        }
        #expect(flips > 50, "too few stance changes to mean anything: \(flips)")

        // A session spanning a boundary: the deck may not change until the
        // ride is over. Find one — sessions start at 180k+2 and run 18.1s;
        // 189 (= 3×63) falls inside the k=1 window when that session fires,
        // and 180k mod 63 walks through every residue over seven k.
        var checked = false
        for k in 1...400 {
            let sessionStart = Double(k) * SpawnRates.skateSession.period + 2
            let boundary = ceil(sessionStart / period) * period
            let end = sessionStart + CrabAnimator.skateSessionLength
            guard boundary < end,
                  CrabAnimator.skateSession(idleT: boundary, wardrobe: skater) != nil,
                  standing(cycle: Int(boundary / period) - 1, wardrobe: skater)
                    != standing(cycle: Int(boundary / period), wardrobe: skater)
            else { continue }
            let release = CrabAnimator.boardRelease(after: boundary, wardrobe: skater)
            #expect(abs(release - end) < 1e-6, "the release was \(release), the ride ends at \(end)")
            // Frozen at the old stance until the release, then eased.
            let held = CrabAnimator.deckStance(idleT: end - 0.5, wardrobe: skater)
            let old = standing(cycle: Int(boundary / period) - 1, wardrobe: skater)
            #expect(held == old, "the deck moved under the ride")
            checked = true
            break
        }
        #expect(checked, "no session was found spanning a stance boundary")

        // A trick starting on the boundary: the release is its landing.
        var trickChecked = false
        for cycle in 1...600 {
            let boundary = Double(cycle) * period
            guard let (kind, progress) = CrabAnimator.flourish(at: boundary, wardrobe: skater),
                  CrabAnimator.Flourish.skateBeats.contains(kind),
                  CrabAnimator.skateSession(idleT: boundary, wardrobe: skater) == nil,
                  CrabAnimator.surfSet(idleT: boundary) == nil
            else { continue }
            #expect(progress == 0)
            let release = CrabAnimator.boardRelease(after: boundary, wardrobe: skater)
            #expect(abs(release - (boundary + kind.duration)) < 1e-6,
                    "\(kind) at the boundary released at \(release), lands at \(boundary + kind.duration)")
            trickChecked = true
            break
        }
        #expect(trickChecked, "no skate trick was found starting on a stance boundary")

        // Choosing the Skater mid-stretch: the deck fades in from the change,
        // not from the next minute. Leaving him fades out the same way.
        // Inside cycle 11, at an instant when no board is riding — so the fade
        // starts at the change itself rather than at a trick's landing.
        var changeAt = 694.0
        while changeAt < 750 {
            let probe = CrabAnimator.MotionWardrobe(current: .skater, previous: .none, changedAt: changeAt)
            if CrabAnimator.boardRelease(after: changeAt, wardrobe: probe) == changeAt { break }
            changeAt += 0.25
        }
        #expect(changeAt < 750, "cycle 11 never had a board-free instant")
        let incoming = CrabAnimator.MotionWardrobe(current: .skater, previous: .none, changedAt: changeAt)
        let target = standing(cycle: 11, wardrobe: skater)
        if target == 1 {
            #expect(CrabAnimator.deckStance(idleT: changeAt - 0.01, wardrobe: incoming) == 0)
            let mid = CrabAnimator.deckStance(idleT: changeAt + 0.3, wardrobe: incoming)
            #expect(mid > 0.05 && mid < 0.95, "mid-fade was \(mid)")
            #expect(CrabAnimator.deckStance(idleT: changeAt + 1.0, wardrobe: incoming) == 1)
        }
        let outgoing = CrabAnimator.MotionWardrobe(current: .none, previous: .skater, changedAt: changeAt)
        if target == 1 {
            #expect(CrabAnimator.deckStance(idleT: changeAt - 0.01, wardrobe: outgoing) == 1)
            #expect(CrabAnimator.deckStance(idleT: changeAt + 1.0, wardrobe: outgoing) == 0)
        }
    }

    /// A board in the prop slot covers the deck, cell for cell — including a
    /// board still dissolving out of the ghost slot, and a surfboard that has
    /// only just begun to fade in.
    @Test("A board covers the deck; a fading board covers it by as much as it shows")
    func aBoardCoversTheDeck() {
        // Compared with the ground shadow set aside: the deck stands the
        // shadow down on its own rule, and one board (the nose manual) still
        // casts one — a pre-existing omission recorded in the Knob, fixed in
        // its own round because it touches a committed GIF.
        for kind in CrabAnimator.Flourish.skateBeats {
            var pose = CrabAnimator.flourishPose(kind, at: kind.duration * 0.5)
            let bare = CrabRig.render(pose)
            pose.deckUnderfoot = 1
            // A plain Bool, not the call inside `#expect`: a member call whose
            // argument is an implicit member (`.shadow`) expands to a no-op
            // check that only WARNS — the kill-test caught this pin blind.
            let covered = CrabRig.render(pose).same(as: bare, ignoring: .shadow)
            #expect(covered, "\(kind)'s board did not cover the deck")
        }
        // The ghost slot too: a trick's board dissolving out under a fact's
        // shades. Mid-float (phase 0.5), nose high — a board whose cells are
        // NOT the deck's, so a deck wrongly drawn beneath it would show.
        var ghosted = CrabPose()
        ghosted.prop = .shades
        ghosted.ghostProp = .skateboardOllie
        ghosted.ghostPropPhase = 0.5
        ghosted.ghostPropVisibility = 1
        let shaded = CrabRig.render(ghosted)
        ghosted.deckUnderfoot = 1
        let ghostCovered = CrabRig.render(ghosted).same(as: shaded, ignoring: .shadow)
        #expect(ghostCovered, "the ghost board did not cover the deck")
        // The surf: at progress 0.01 the sea is barely up (`SurfSet.sea` eases
        // from zero over 0.07), so the surfboard barely shows — and the deck
        // must still be mostly there rather than gone in one frame.
        var surf = CrabPose()
        CrabAnimator.applySurf(0.01, t: 0, to: &surf)
        #expect(surf.boardCover < 0.1, "the surfboard covers \(surf.boardCover) at its first frame")
        surf.deckUnderfoot = 1
        let deckCells = CrabRig.render(surf).count(of: .deck)
        #expect(deckCells >= 10, "only \(deckCells) of 17 deck cells survived the surf's first frame")
    }

    /// The resting form is the one the ollie, the nollie and the manual land
    /// in, less their shimmer cell. The kickflip and the varial sit their
    /// wheels one row lower — pinned so the seam is a recorded fact.
    @Test("The stance is the ollie's first frame; the kickflip's wheels sit a row lower")
    func theStanceIsTheOlliesFirstFrame() {
        // The board's cells in rows 25–30. A shimmer cell is a highlight ON a
        // wheel cell, so `.flameCore` reads back as the `.yellow` under it.
        func board(_ buffer: PixelBuffer) -> [String] {
            var cells: [String] = []
            for y in 25...30 {
                for x in 0..<PixelBuffer.side {
                    let ink = buffer[x, y] == .flameCore ? PixelBuffer.Ink.yellow : buffer[x, y]
                    if [.deck, .yellow, .screenDark].contains(ink) { cells.append("\(x),\(y),\(ink)") }
                }
            }
            return cells.sorted()
        }
        // Compared IN THE SAME FRAME: the trick's first frame rides the idle
        // breath (bob 1 at t = 0), and so does the deck, so the reference is
        // that very pose with the board swapped for the deck under it.
        for kind in [CrabAnimator.Flourish.ollie, .nollie, .manual, .backSmith] {
            let first = CrabAnimator.flourishPose(kind, at: 0)
            var resting = first
            resting.prop = .none
            resting.deckUnderfoot = 1
            let deck = board(CrabRig.render(resting))
            #expect(deck.count == 17 + 2 * 9, "the resting deck has \(deck.count) cells")
            #expect(board(CrabRig.render(first)) == deck, "\(kind)'s first frame is not the resting deck")
        }
        let kickflipPose = CrabAnimator.flourishPose(.kickflip, at: 0)
        let kickflip = CrabRig.render(kickflipPose)
        let wheelRow = 26 + kickflipPose.bob                 // the deck's own wheel row, in this frame
        #expect(kickflip.count(of: .yellow, inRow: wheelRow) == 0
                    && kickflip.count(of: .yellow, inRow: wheelRow + 1) > 0,
                "the kickflip's wheels moved — its first frame was pinned a row below the deck")
    }

    @Test("The shadow stands down under the deck")
    func theShadowStandsDown() {
        var resting = CrabPose()
        resting.deckUnderfoot = 1
        let rendered = CrabRig.render(resting)
        #expect(rendered.count(of: .shadow, inRow: 25) == 0, "grease under the wheels")
        // …and only under the deck: bare, the shadow is where it always was.
        #expect(CrabRig.render(CrabPose()).count(of: .shadow, inRow: 25) > 0)
    }

    /// The balloon takes an EMPTY hand. It wrote the mug unconditionally after
    /// the flourish branch, so a balloon whose window opened mid-kickflip
    /// replaced the airborne board with a mug.
    @Test("A balloon never takes the board out of his hands")
    func theBalloonWaitsForAnEmptyHand() {
        var found = false
        var t = 7.0
        while t < 20_000, !found {
            if CrabAnimator.idleBalloon(idleT: t) != nil,
               let (kind, _) = CrabAnimator.flourish(at: t),
               CrabAnimator.Flourish.skateBeats.contains(kind) {
                let pose = CrabAnimator.pose(mood: .idle, t: t)
                #expect(pose.prop.isBoard, "at \(t) the balloon took \(kind)'s board: prop is \(pose.prop)")
                found = true
            }
            t += 0.5
        }
        #expect(found, "no balloon ever landed on a skate beat in the sweep")
    }

    /// The frozen lock: nothing offline ever stands on a deck.
    @Test("Offline he never stands on a deck")
    func offlineNeverStands() {
        for t in stride(from: 0.0, through: 1000, by: 0.7) {
            #expect(CrabAnimator.pose(mood: .idle, t: t).deckUnderfoot == 0, "bare idle stood at \(t)")
        }
        for kind in CrabAnimator.Flourish.allCases {
            #expect(CrabAnimator.flourishPose(kind, at: 0.4).deckUnderfoot == 0)
        }
    }

    @Test("A mood blend carries the deck with the pose")
    func blendCarriesTheDeck() {
        var from = CrabPose(), to = CrabPose()
        from.deckUnderfoot = 1
        to.deckUnderfoot = 0
        #expect(abs(CrabPose.blend(from: from, to: to, u: 0.5).deckUnderfoot - 0.5) < 1e-9)
        #expect(CrabPose.blend(from: from, to: to, u: 1).deckUnderfoot == 0)
        #expect(CrabPose.blend(from: from, to: to, u: 0).deckUnderfoot == 1)
    }
}

private extension PixelBuffer {
    func same(as other: PixelBuffer, ignoring: Ink? = nil) -> Bool {
        for y in 0..<Self.side {
            for x in 0..<Self.side where self[x, y] != other[x, y] {
                if let ignoring, self[x, y] == ignoring || other[x, y] == ignoring { continue }
                return false
            }
        }
        return true
    }
    func count(of ink: Ink) -> Int {
        var n = 0
        for y in 0..<Self.side { for x in 0..<Self.side where self[x, y] == ink { n += 1 } }
        return n
    }
    func count(of ink: Ink, inRow y: Int) -> Int {
        (0..<Self.side).filter { self[$0, y] == ink }.count
    }
}
