import Testing
import Foundation
@testable import ClaudePet

/// 🍑 **The half cab, and the backside it exists to show.**
///
/// A frontside 180 that leaves him riding switch with his back to you, two
/// beats of holding it, and a half cab back to regular. As skating those are
/// exactly the two tricks for the job: a frontside 180 puts you switch, a half
/// cab puts you back. The joke and the skating agree.
///
/// What is pinned here is the arithmetic the trick is built on — the turn never
/// unwinds, the board never lags him, nothing lands off the beat — and the mark
/// on his back: where it is, what inks it is made of, and that it is nowhere to
/// be seen on a flank.
@MainActor
struct HalfCabTests {

    private let duration = CrabAnimator.Flourish.halfCab.duration
    private func frame(_ p: Double) -> CrabPose {
        CrabAnimator.flourishPose(.halfCab, at: p * duration)
    }
    /// The phase seams, as fractions of the trick.
    private let pop = 0.125, land = 0.25, hold = 0.375
    private let cabCrouch = 0.625, cab = 0.75, stomp = 0.875

    @Test("Eight beats, and every seam is a whole one")
    func theTrickIsOnTheGrid() {
        let beat = 0.5
        #expect(duration == 8 * beat, "the trick runs \(duration)s")
        for seam in [pop, land, hold, cabCrouch, cab, stomp] {
            let beats = seam * duration / beat
            #expect(abs(beats - beats.rounded()) < 1e-9,
                    "the seam at progress \(seam) lands on beat \(beats)")
        }
        // The operator asked for two beats of him facing away, and the hold is
        // where that promise lives. (He is already switch through the landing
        // before it, which is a bonus, not the promise.)
        #expect(abs((cabCrouch - hold) * duration - 2 * beat) < 1e-9,
                "the hold is \((cabCrouch - hold) * duration)s, not two beats")
    }

    /// 🔎 THE RULE THE BIGSPIN WAS BUILT ON, and this trick inherits: he may
    /// only rotate if the board rotates WITH him, the same way, by at least as
    /// much. The bigspin honours it at two to one; a 180 is one to one, which
    /// is what makes it a 180 and not a bigspin.
    @Test("The board never lags him, and neither of them ever unwinds")
    func theTurnIsMonotoneAndLed() {
        var previousBody = -1.0, previousBoard = -1.0
        // 0..<600, not 0...600: at progress exactly 1 the trick is OVER and
        // `flourishPose` hands back the base, whose turn is zero. That is the
        // hand-off working, not the trick unwinding — and it is only harmless
        // because the frame before it is a whole turn, which the rig draws
        // identically. The pin for that is the landing check below.
        for step in 0..<600 {
            let pose = frame(Double(step) / 600)
            #expect(pose.torsoTurn >= previousBody - 1e-9,
                    "his body unwound at step \(step): \(pose.torsoTurn) after \(previousBody)")
            #expect(pose.propPhase >= previousBoard - 1e-9,
                    "the board unwound at step \(step)")
            #expect(pose.propPhase >= pose.torsoTurn - 1e-9,
                    "at step \(step) he turned \(pose.torsoTurn) over a board at \(pose.propPhase)")
            previousBody = pose.torsoTurn
            previousBoard = pose.propPhase
        }
        // …and it lands on a WHOLE turn, which the rig draws as the identity —
        // so the hand-off to the idle pose, which carries no turn at all, is
        // not a hundred-and-eighty-degree snap in one frame.
        let landed = frame(0.999)
        #expect(abs(landed.torsoTurn - 1) < 0.02, "he landed on turn \(landed.torsoTurn)")
        #expect(abs(landed.propPhase - 1) < 0.02, "the board landed on phase \(landed.propPhase)")
    }

    /// The pose the whole trick exists for: a full second and a half of switch,
    /// back to the camera, with the board reversed under him.
    @Test("Through the hold he is exactly half round, on a reversed board")
    func theHoldIsSwitch() {
        for p in stride(from: land + 0.005, to: cabCrouch, by: 0.005) {
            let pose = frame(p)
            #expect(pose.torsoTurn == 0.5, "at p=\(p) he is \(pose.torsoTurn) round, not half")
            #expect(pose.propPhase == 0.5, "at p=\(p) the deck is at \(pose.propPhase)")
        }
        // 🔎 The deck is reversed, and that is what riding switch looks like.
        // `propPhase = 0` runs at the top of the case every frame, so a branch
        // that forgets to overwrite it freezes the board broadside — which is
        // silent, because at yaw 0 and yaw π the deck is the same width.
        let buffer = CrabRig.render(frame(0.5))
        var deckRow = -1, deckLeft = 99, deckRight = -1, nose = -1
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where buffer[x, y] == .deck {
                deckRow = y; deckLeft = min(deckLeft, x); deckRight = max(deckRight, x)
            }
        }
        #expect(deckRight - deckLeft >= 12, "the deck is only \(deckRight - deckLeft + 1) wide — not flat on")
        for x in 0..<PixelBuffer.side where buffer[x, deckRow] == .paper { nose = x }
        #expect(nose >= 0, "the deck has no nose mark at all")
        #expect(Double(nose) < Double(deckLeft + deckRight) / 2,
                "the nose is at \(nose), on the RIGHT of a deck spanning \(deckLeft)…\(deckRight) — he is not switch")
    }

    // MARK: - 🍑

    /// The cheeks' own columns and rows, derived the way the rig derives them:
    /// four rows above his feet, four cells either side of a two-cell crack,
    /// centred on the MIRROR's axis rather than on the mapping axis.
    private var crack: [Int] { [15, 16] }
    private var cheekColumns: [Int] { [11, 12, 13, 14, 17, 18, 19, 20] }
    /// 🔎 The four columns the FLANK SLAB can never reach at a partial turn.
    ///
    /// Counting `.body` across all eight is only honest at a half turn, where
    /// `sideHalf` is zero and there is no slab. Away from it the slab is
    /// `.body` on one side of 0.5 and `.bodyShade` on the other, so a naive
    /// count reads eight extra cells at turn 0.66 and none at 0.34 and calls
    /// the fade lopsided when it is not. These four sit inside the slab's
    /// reach at every turn this file samples.
    private var innerCheeks: [Int] { [13, 14, 17, 18] }
    private var buttRows: [Int] { [17, 18, 19, 20] }

    private func cheekCells(_ turn: Double, columns: [Int]? = nil) -> Int {
        var pose = CrabPose()
        pose.torsoTurn = turn
        let buffer = CrabRig.render(pose)
        var n = 0
        for y in buttRows {
            for x in columns ?? cheekColumns where buffer[x, y] == .body { n += 1 }
        }
        return n
    }

    /// 🔎 THE CRACK IS NEGATIVE SPACE. The turned back is `.bodyShade`
    /// everywhere but the ridge, so the cheeks go one step UP to `.body` and
    /// the seam between them is dark for free — no third ink, no new palette
    /// entry, and the mark inherits whatever colourway the costume put on the
    /// shell. A third ink would also fail `theFlankIsOneFlatStep` outright.
    @Test("His back has two cheeks and a two-cell crack, in the shell's own two inks")
    func theBacksideIsThere() {
        var pose = CrabPose()
        pose.torsoTurn = 0.5
        let buffer = CrabRig.render(pose)
        // Every cheek cell present, and the whole crack dark.
        #expect(cheekCells(0.5) == 28, "the cheeks drew \(cheekCells(0.5)) cells, not 28")
        for y in buttRows {
            for x in crack {
                #expect(buffer[x, y] == .bodyShade,
                        "the crack is \(buffer[x, y]) at (\(x),\(y)) — it has closed up")
            }
        }
        // Rounded, not two bricks: the outermost column drops on the top and
        // bottom rows.
        for y in [17, 20] {
            #expect(buffer[11, y] != .body && buffer[20, y] != .body,
                    "row \(y) still has square corners")
        }
        // Symmetric about the mirror's axis — `x_src = 2·axis − 1 − x` reflects
        // column 6 onto 25, so the figure's centre is 15.5 and so is the
        // crack's. An asymmetric backside also quietly breaks
        // `theSpinMirrorsInTime`, which compares the turn against its mirror.
        for y in buttRows {
            for x in 6...25 {
                #expect((buffer[x, y] == .body) == (buffer[31 - x, y] == .body),
                        "the backside is lopsided at (\(x),\(y))")
            }
        }
        // …and it is ON him: nothing outside the shell's own columns.
        for y in buttRows {
            for x in 0..<PixelBuffer.side where cheekColumns.contains(x) {
                #expect(buffer[x, y] != .clear, "a cheek cell hangs in the air at (\(x),\(y))")
            }
        }
    }

    /// 🔎 A QUARTER TURN IS HIS FLANK, and a flank with a backside on it is
    /// just wrong. The mark is gated on how far round he is — not on which
    /// trick is playing — and it fades in on the house's static dither rather
    /// than switching on, because a one-frame appearance is the snap the rig
    /// bans everywhere else.
    @Test("The backside is nowhere to be seen on a flank, and arrives by fading")
    func theBacksideIsGatedOnFacing() {
        // Dead on the flanks, both of them.
        #expect(cheekCells(0.25) == 0, "a backside on his right flank")
        #expect(cheekCells(0.30) == 0, "a backside at barely a third round")
        // …and monotone in from there.
        var previous = 0
        for turn in [0.34, 0.38, 0.42, 0.46, 0.5] {
            let now = cheekCells(turn)
            #expect(now >= previous, "the fade went backwards at turn \(turn)")
            previous = now
        }
        #expect(cheekCells(0.42) > 0 && cheekCells(0.42) < 28,
                "turn 0.42 is not a partial fade: \(cheekCells(0.42)) cells")
        // Even in `-c`, so the way in and the way out are the same ramp —
        // measured on the columns no flank slab reaches (see `innerCheeks`).
        for turn in [0.34, 0.38, 0.42, 0.46] {
            #expect(cheekCells(turn, columns: innerCheeks)
                    == cheekCells(1 - turn, columns: innerCheeks),
                    "the fade is lopsided in time at turn \(turn)")
        }
        // The other flank is covered where it can be measured at all: at a
        // quarter turn either way `edgeOnIsSixWide` already pins every shell
        // row to a single pure ink, which a cheek would break outright.
    }

    /// The back was one step down with a single lit ridge before this, and it
    /// has to stay that way: the cheeks are a mark on a dark carapace, not a
    /// second lit band that turns his back inside out.
    @Test("The cheeks do not out-light the back they sit on")
    func theBackIsStillDark() {
        var pose = CrabPose()
        pose.torsoTurn = 0.5
        let buffer = CrabRig.render(pose)
        var body = 0, shade = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                if buffer[x, y] == .body { body += 1 }
                if buffer[x, y] == .bodyShade { shade += 1 }
            }
        }
        #expect(shade > body, "his back is lighter than it is dark: \(shade) shade, \(body) body")
        #expect(body > 8, "his back has no lit ridge at all")
    }

    // MARK: - The roster

    /// The bare deck is the one the README's idle clip deals from, and its
    /// first pick only re-deals past sixty. Every trick added since has been
    /// weighed against that number rather than around it.
    @Test("The new trick leads without re-dealing the idle clip")
    func theDeckStaysUnderSixty() {
        let bare = CrabAnimator.Flourish.allCases
            .reduce(0) { $0 + (CrabAnimator.flourishWeights[$1] ?? 1) }
        #expect(bare == 51, "the bare deck is \(bare)")
        #expect(bare < 60, "the bare deck is \(bare) — the README's idle clip re-deals its pick")
        #expect(CrabAnimator.flourishWeights[.halfCab] == 4, "the newest trick does not lead")
        #expect(CrabAnimator.Flourish.skateBeats.contains(.halfCab),
                "the half cab is not a skate beat — the shout, the steeze and the deck stance all skip it")
        // Appended, never inserted: the live dice index `allCases` by position.
        #expect(CrabAnimator.Flourish.allCases.last == .halfCab,
                "the half cab is no longer last — something was inserted before it")
    }

    // MARK: - 🍑 The bounce

    private func cheeks(_ jiggle: Double, turn: Double = 0.5) -> [(x: Int, y: Int)] {
        var pose = CrabPose()
        pose.torsoTurn = turn
        pose.buttJiggle = jiggle
        let buffer = CrabRig.render(pose)
        // Rows 16…20 and columns 8…23, which is the backside's whole reach and
        // nothing else's: his legs are `.body` from row 21 down, his arms are
        // `.body` on rows 14-16 but only outside column 8, and the lit ridge is
        // row 13. A window that took row 21 would count shins as cheeks — which
        // is exactly what the first cut of this helper did.
        var cells: [(Int, Int)] = []
        for y in 16...20 {
            for x in 8...23 where buffer[x, y] == .body { cells.append((x, y)) }
        }
        return cells
    }

    /// 🔎 A SQUASH-AND-STRETCH, not a sine wave — which is the whole difference
    /// between "the Duolingo jiggle" and "a block moves up". Down is not
    /// available: row 20 is the shell's last, row 21 is his legs, and a cheek
    /// row on his shins is deleted by the pass's own mask, so the block would
    /// appear to lose a row rather than move. A bounce needs a floor and he has
    /// one, so the two halves are UP and WIDER.
    @Test("The bounce lifts a row one way and spreads a column the other")
    func theBounceSquashesAndStretches() {
        let rest = cheeks(0), aloft = cheeks(1), squash = cheeks(-1)
        #expect(rest.count == 28, "at rest the backside is \(rest.count) cells, not 28")
        // ALOFT: same mass, one row higher.
        #expect(aloft.count == rest.count, "the lift changed the mass: \(aloft.count) against \(rest.count)")
        #expect((aloft.map(\.y).min() ?? 0) == (rest.map(\.y).min() ?? 0) - 1,
                "the lift did not move a row up")
        #expect((aloft.map(\.y).max() ?? 0) == (rest.map(\.y).max() ?? 0) - 1)
        // SQUASH: same rows, MORE mass — a compressed soft body spreads, it
        // does not shrink. Losing a row instead would cost 8 of 28 cells in one
        // frame and read as the mark half-vanishing.
        #expect(squash.map(\.y).min() == rest.map(\.y).min(), "the squash left the floor")
        #expect(squash.map(\.y).max() == rest.map(\.y).max())
        #expect(squash.count > rest.count,
                "the squash lost mass: \(squash.count) against \(rest.count)")
        #expect((squash.map(\.x).min() ?? 0) < (rest.map(\.x).min() ?? 0),
                "the squash did not spread outward")
        #expect((squash.map(\.x).max() ?? 0) > (rest.map(\.x).max() ?? 0))
    }

    /// 🔎 THE CRACK IS THE ENTIRE IDENTITY OF THE MARK. Both cheeks grow away
    /// from centre, so the two dark columns between them are the same two at
    /// every state — a squash that closed the crack would just be a wider bum.
    @Test("The crack never moves, in any state")
    func theCrackIsInvariant() {
        for jiggle in [0.0, 1.0, -1.0, 0.6, -0.6, 2.0, -2.0] {
            var pose = CrabPose()
            pose.torsoTurn = 0.5
            pose.buttJiggle = jiggle
            let buffer = CrabRig.render(pose)
            for y in 16...20 {
                for x in crack {
                    #expect(buffer[x, y] != .body,
                            "at jiggle \(jiggle) the crack closed at (\(x),\(y))")
                }
            }
            // …and the whole mark stays symmetric about the mirror's axis.
            for y in 16...20 {
                for x in 6...25 {
                    #expect((buffer[x, y] == .body) == (buffer[31 - x, y] == .body),
                            "at jiggle \(jiggle) the backside is lopsided at (\(x),\(y))")
                }
            }
        }
    }

    /// The floor holds however hard he is pushed: an amplitude far past anything
    /// the animator writes must never put a cheek on his legs, and must never
    /// climb over the lit ridge at the top of the carapace.
    @Test("Nothing ever leaves the shell, at any amplitude")
    func theFloorAndTheRidgeHold() {
        for jiggle in [-8.0, -2.0, -1.0, 0.0, 1.0, 2.0, 8.0] {
            let cells = cheeks(jiggle)
            #expect(!cells.isEmpty, "the backside vanished at jiggle \(jiggle)")
            #expect(cells.allSatisfy { $0.y <= 20 }, "a cheek reached his legs at jiggle \(jiggle)")
            #expect(cells.allSatisfy { $0.y >= 16 }, "a cheek climbed the ridge at jiggle \(jiggle)")
        }
    }

    /// The bounce's own arithmetic: four cycles across the two seconds his back
    /// is turned, at rest at both ends, and never past a cell either way.
    @Test("Four bounces across the turned window, resting at both seams")
    func theBounceIsOnTheGrid() {
        // The seams: `torsoTurn` is pinned at 0.5 from the landing through the
        // hold to the cab's crouch, and the bounce covers exactly that.
        #expect(abs(frame(land).buttJiggle) < 1e-9, "the bounce does not start at rest")
        #expect(abs(frame(cab).buttJiggle) < 1e-9, "the bounce does not end at rest")
        #expect(frame(0.2).buttJiggle == 0 && frame(0.8).buttJiggle == 0,
                "the bounce leaked outside the window his back is turned")
        var previous = 0.0, reversals = 0, peak = 0.0
        for step in 0...1000 {
            let p = land + (cab - land) * Double(step) / 1000
            let now = frame(p).buttJiggle
            peak = max(peak, abs(now))
            if step > 1, (now - previous) * previous < 0 { }
            if step > 0, previous != now,
               (now > previous) != (frame(p - (cab - land) / 1000 * 2).buttJiggle < previous) {
                reversals += 1
            }
            previous = now
        }
        #expect(abs(peak - 1) < 0.01, "the bounce peaks at \(peak), not one cell")
        // Four whole cycles: the value crosses zero eight times inside the window.
        var crossings = 0
        var last = frame(land + 1e-6).buttJiggle
        for step in 1...2000 {
            let now = frame(land + (cab - land) * Double(step) / 2000).buttJiggle
            if last * now < 0 { crossings += 1 }
            last = now
        }
        #expect(crossings == 7, "the bounce crossed zero \(crossings) times — that is not four cycles")
    }

    /// 🔎 It SQUASHES BEFORE IT LIFTS — anticipation first, which is what
    /// separates a cartoon bounce from a block sliding up and down.
    @Test("Every cycle winds up before it pops")
    func theBounceAnticipates() {
        let cycle = (cab - land) / 4
        for n in 0..<4 {
            let start = land + cycle * Double(n)
            let early = frame(start + cycle * 0.25).buttJiggle
            let late = frame(start + cycle * 0.75).buttJiggle
            #expect(early < -0.9, "cycle \(n) did not squash first: \(early)")
            #expect(late > 0.9, "cycle \(n) did not lift second: \(late)")
        }
    }

    /// At the rate the committed GIF is written, a whole cycle is six frames and
    /// each state change has a rest frame beside it — so no frame ever moves the
    /// row and the width at once. One whole-pixel step at a time is the grid's
    /// own quantum, and the only motion the no-snap rule exempts.
    @Test("At the GIF's own rate the cycle reads as three states, never two at once")
    func theCycleReadsAtTwelveFrames() {
        var states: [String] = []
        let cycle = (cab - land) / 4
        for frameIndex in 0..<6 {
            let p = land + cycle * Double(frameIndex) / 6
            let v = frame(p).buttJiggle
            states.append(v.rounded() == -1 ? "squash" : v.rounded() == 1 ? "aloft" : "rest")
        }
        #expect(states == ["rest", "squash", "squash", "rest", "aloft", "aloft"],
                "the twelve-frame cycle reads \(states)")
    }

    /// The bounce belongs to this trick alone. The bigspin is the only other
    /// flourish allowed to turn him and it passes through facing-away in a
    /// fraction of a second, where a jiggle would flicker — and would move
    /// `docs/media/flourish-bigspin.gif` for nothing.
    @Test("No other flourish jiggles")
    func nothingElseBounces() {
        for kind in CrabAnimator.Flourish.allCases where kind != .halfCab {
            for step in 0...120 {
                let pose = CrabAnimator.flourishPose(kind, at: Double(step) * kind.duration / 120)
                #expect(pose.buttJiggle == 0, "\(kind) jiggles at step \(step)")
            }
        }
        // …and a bare pose, which is what every committed still is built from.
        #expect(CrabPose().buttJiggle == 0)
    }

    /// The held second is what the marketing loop is cut from, so it has to
    /// LOOP: the pose at its end must match the pose at its start in every
    /// channel the backside reads.
    @Test("The held second loops")
    func theHoldLoops() {
        // The window is half-open: the LAST frame of the hold, not the first
        // frame of the crouch that follows it, which carries its own squash.
        let open = frame(hold), close = frame(cabCrouch - 1e-9)
        // A hair's breadth, not exactly: `close` is sampled a nanosecond inside
        // the window, so the sine has advanced by that much and no more.
        #expect(abs(open.buttJiggle - close.buttJiggle) < 1e-6,
                "the bounce does not come home: \(open.buttJiggle) against \(close.buttJiggle)")
        #expect(open.torsoTurn == close.torsoTurn && open.bob == close.bob
                && open.propPhase == close.propPhase && open.prop == close.prop,
                "the hold does not return to its own first frame")
        // …and it is not loop-clean by being static: something moves inside it.
        let middle = frame((hold + cabCrouch) / 2 - (cabCrouch - hold) / 8)
        #expect(abs(middle.buttJiggle) > 0.9, "nothing happens inside the loop")
    }

}
