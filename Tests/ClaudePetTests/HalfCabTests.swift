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
}
