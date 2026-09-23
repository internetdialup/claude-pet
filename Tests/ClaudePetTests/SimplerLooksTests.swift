import Testing
@testable import ClaudePet

/// The operator's 2026-09-23 "simplify", held.
///
/// Four looks were cut back: the Gundam to face, fin and flank vents, the
/// Tiger to the forehead V and one slash a side, the Turkey's fan to seven
/// rows with no rim band, and the Coder's rain to two stops with no
/// code-lines under it (that last one is `MatrixCostumeTests`' to hold).
/// Each was more detail than a 32-pixel sprite can carry, and each grew there
/// one fitting at a time — so the cut is pinned as a RULE about what the look
/// may draw, not as a picture of it, and the next "just one more pixel" has
/// to argue with a test.
@Suite("Simpler looks")
@MainActor
struct SimplerLooksTests {

    private func pose(_ t: Double) -> CrabPose {
        var pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false)
        pose.bob = 0
        pose.propPhase = t
        pose.prop = .none
        pose.propVisibility = 0
        return pose
    }

    /// Fin, visor, cameras, red, his white, and blue on the flank vents only
    /// (the fitting put the vents back as his signature; the chest band that
    /// was the other blue stays cut) — and steel only on the saber rack
    /// behind his shoulders (the sortie's fitting added it) or while the scan
    /// is actually crossing him.
    ///
    /// Read as the cells a dressed render changes against the bare crab in
    /// the same pose, so the rig's own inks (shadow, face, legs) never count
    /// against the costume. Sampled through t = 40 because the scan never
    /// fires in cycle zero (the frozen-render sentinel); cycle 3 of its
    /// 12-second period is a live window, and the test demands it saw one,
    /// or the steel allowance would be passing untested.
    @Test("The Gundam wears the fin, the visor, the red, his flank vents and his saber rack — nothing else")
    func gundamIsFaceAndFin() {
        let worn: Set<PixelBuffer.Ink> = [.yellow, .costumeA, .costumeB, .costumeC, .clear, .steel]
        let flanks = { (x: Int) in x < CrabRig.bodyX + 2 || x >= CrabRig.bodyX + CrabRig.bodyW - 2 }
        // The saber rack the sortie's fitting added: one hilt behind each
        // shoulder, two cells each — and steel nowhere else outside a scan.
        let top = CrabRig.bodyY
        let rack: Set<Int> = [
            (CrabRig.bodyX + 1, top - 3), (CrabRig.bodyX + 2, top - 2),
            (CrabRig.bodyX + CrabRig.bodyW - 2, top - 3), (CrabRig.bodyX + CrabRig.bodyW - 3, top - 2),
        ].reduce(into: Set<Int>()) { $0.insert($1.1 * PixelBuffer.side + $1.0) }
        var sawScan = false
        for t in stride(from: 0.0, through: 40.0, by: 0.25) {
            let scanning = CrabCostume.effectWindow(at: t, SpawnRates.gundamScan) != nil
            sawScan = sawScan || scanning
            let allowed = scanning ? worn.union([.steel]) : worn
            let dressed = CrabRig.render(pose(t), costume: .gundam, costumeVisibility: 1)
            let plain = CrabRig.render(pose(t))
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where dressed[x, y] != plain[x, y] {
                    #expect(allowed.contains(dressed[x, y]),
                            "the Gundam drew \(dressed[x, y]) at (\(x),\(y)), t=\(t)")
                    if dressed[x, y] == .costumeA {
                        #expect(flanks(x), "blue off the flank vents at (\(x),\(y)), t=\(t)")
                    }
                    if dressed[x, y] == .steel, !scanning {
                        #expect(rack.contains(y * PixelBuffer.side + x), "steel off the rack at (\(x),\(y)), t=\(t)")
                    }
                    // The cameras are `.eye` in a yellow override, so outside
                    // a scan the only `.yellow` he paints is the fin, whose
                    // roots land on the crown row (one lower in a squash).
                    if dressed[x, y] == .yellow, !scanning {
                        #expect(y <= CrabRig.bodyY + 1, "yellow off the fin at (\(x),\(y)), t=\(t)")
                    }
                }
            }
        }
        #expect(sawScan, "no scan window in the sample — the steel allowance went untested")
    }

    /// The sortie's sister clause: pink, paper, steel and slate belong to the
    /// weapon, only while a beat is running — never to the resting look,
    /// which the test above holds to fin, visor, red and flank blue. The
    /// rifle's lock sweep is the costume's own scan, so its gold on the shell
    /// is the scan's allowance, not a new one.
    @Test("A sortie may add pink, paper, steel and slate — only while it runs")
    func aSortieMayAddPinkPaperSteelOnlyWhileItRuns() {
        let worn: Set<PixelBuffer.Ink> = [.yellow, .costumeA, .costumeB, .costumeC, .clear]
        let beat = worn.union([.pink, .paper, .steel, .slate])
        for kind in CrabPose.Sortie.Kind.allCases {
            var sawBeam = false
            let duration = CrabAnimator.sortieDuration(kind)
            for step in 0..<60 {
                var p = pose(0.5)                          // cycle 0: every die silent
                CrabAnimator.applySortie(kind, seconds: duration * (Double(step) + 0.5) / 60, to: &p)
                let dressed = CrabRig.render(p, costume: .gundam, costumeVisibility: 1)
                let plain = CrabRig.render(p)              // same claw; only the costume differs
                for y in 0..<PixelBuffer.side {
                    for x in 0..<PixelBuffer.side where dressed[x, y] != plain[x, y] {
                        #expect(beat.contains(dressed[x, y]), "\(kind) drew \(dressed[x, y]) at (\(x),\(y))")
                        #expect(plain[x, y] != .eye, "\(kind) covered an open eye at (\(x),\(y))")
                        if dressed[x, y] == .pink { sawBeam = true }
                    }
                }
            }
            #expect(sawBeam, "\(kind) never lit — the allowance went untested")
        }
        // The resting look needs no clause of its own here: `gundamIsFaceAndFin`
        // already holds his every costume cell to fin, visor, red and flank
        // blue, so pink or paper at rest fails there. (Paper alone proves
        // nothing — his catchlight is a paper cell in every look.)
    }

    /// The forehead V and one slash a side at eye level — every stripe cell
    /// on his shell lies in one of those three places, and each of the three
    /// still carries one. The tail's ticks ride off the shell's right edge
    /// and are the tail's business, not a stripe's.
    @Test("The Tiger's stripes are the V and one slash a side")
    func tigerStripesAreTheVAndTwoSlashes() {
        let buffer = CrabRig.render(pose(0), costume: .tiger, costumeVisibility: 1)
        let top = CrabRig.bodyY
        let shellColumns = CrabRig.bodyX..<(CrabRig.bodyX + CrabRig.bodyW)
        let v = (columns: 13...18, rows: top...(top + 2))
        let leftFlank = (columns: 6...9, rows: (top + 4)...(top + 6))
        let rightFlank = (columns: 22...25, rows: (top + 4)...(top + 6))
        var marks = (v: 0, left: 0, right: 0)
        for y in top..<(top + CrabRig.bodyH) {
            for x in shellColumns where buffer[x, y] == .costumeA {
                if v.columns.contains(x), v.rows.contains(y) { marks.v += 1 }
                else if leftFlank.columns.contains(x), leftFlank.rows.contains(y) { marks.left += 1 }
                else if rightFlank.columns.contains(x), rightFlank.rows.contains(y) { marks.right += 1 }
                else { Issue.record("a stripe outside the V and the two slashes at (\(x),\(y))") }
            }
        }
        #expect(marks.v > 0, "the forehead V is gone")
        #expect(marks.left > 0 && marks.right > 0, "a flank slash is gone")
    }

    /// No rim band. The band flipped the outer two cells of every wedge to
    /// its contrast colour, which put a second pattern on top of the first.
    /// Up the fan's centre line, the tip and the three cells under it all sit
    /// in the middle wedge. With the band gone they are one colour, and with
    /// it back the top two would not match the three beneath. The lowest two
    /// cells are left out, because every wedge meets at the base and they
    /// fall in the next wedge over. The seven-row height is
    /// `crownRoomIsHonest`'s to hold.
    @Test("The Turkey's fan is wedges only, no rim band")
    func turkeyFanHasNoRimBand() {
        let buffer = CrabRig.render(pose(0), costume: .turkey, costumeVisibility: 1)
        let rows = CostumeStyle.of(.turkey).crownRows
        let centre = CrabRig.bodyX + CrabRig.bodyW / 2
        let outer = (3...rows).map { buffer[centre, CrabRig.bodyY - $0] }
        #expect(Set(outer).count == 1 && outer.first != .clear,
                "the fan's centre line reads \(outer), inside out to the tip")
    }
}
