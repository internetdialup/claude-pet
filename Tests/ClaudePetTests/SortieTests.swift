import Testing
@testable import ClaudePet

/// The Gundam's sortie — the beam saber, and the rifle that scans, locks and
/// fires — held to what the operator picked off the previews and to the
/// rig's own rules: every phase in order at its length, nothing arriving in
/// one frame but the sanctioned keys, the weapon never on his face or shell,
/// riding the claw it is held in, fading whenever he is handled or the mood
/// moves on, and live-only — no committed render can ever carry one.
@Suite("Gundam sortie")
@MainActor
struct SortieTests {
    typealias Kind = CrabPose.Sortie.Kind
    let gundam = CrabAnimator.MotionWardrobe(current: .gundam)

    /// A resting cycle-0 idle pose with a beat staged on it: every scheduled
    /// die silent, and the same `applySortie` door the preview uses.
    private func staged(_ kind: Kind, _ seconds: Double) -> CrabPose {
        var pose = CrabAnimator.pose(mood: .idle, t: 0.5, flourishes: false)
        pose.propPhase = 0.5
        pose.bob = 0
        pose.gazeX = 0
        pose.gazeY = 0
        pose.blink = 0
        CrabAnimator.applySortie(kind, seconds: seconds, to: &pose)
        return pose
    }

    /// The cells the weapon itself paints — where the same pose without its
    /// sortie is empty — keyed by `y × side + x`.
    private func weapon(_ pose: CrabPose, costume: Costume = .gundam,
                        ghost: Costume = .none, visibility: Double = 1) -> [Int: PixelBuffer.Ink] {
        var plain = pose
        plain.sortie = nil
        let with = CrabRig.render(pose, costume: costume, ghostCostume: ghost, costumeVisibility: visibility)
        let without = CrabRig.render(plain, costume: costume, ghostCostume: ghost, costumeVisibility: visibility)
        var cells: [Int: PixelBuffer.Ink] = [:]
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where with[x, y] != without[x, y] && without[x, y] == .clear {
                cells[y * PixelBuffer.side + x] = with[x, y]
            }
        }
        return cells
    }

    /// Sample instants through a beat at `fps`, mid-frame so a phase boundary
    /// on a whole frame is never straddled by floating point.
    private func frames(_ kind: Kind, fps: Double) -> [Double] {
        // The epsilon: 53/12 × 12 is 52.999… in floating point, and a
        // counter that floors it drops the last frame of the beat.
        let count = Int((CrabAnimator.sortieDuration(kind) * fps + 1e-9).rounded(.down))
        return (0..<count).map { (Double($0) + 0.5) / fps }
    }

    // MARK: - The phases

    @Test("The saber runs its phases in order, at the approved lengths")
    func saberPhasesRunInOrder() {
        var order: [CrabAnimator.SaberPhase] = []
        var counts: [CrabAnimator.SaberPhase: Int] = [:]
        for s in frames(.saber, fps: 12) {
            guard let phase = CrabAnimator.saberPhase(at: s)?.phase else { continue }
            if order.last != phase { order.append(phase) }
            counts[phase, default: 0] += 1
        }
        #expect(order == CrabAnimator.SaberPhase.allCases)
        let approved: [CrabAnimator.SaberPhase: Int] = [
            .raise: 6, .hiltIn: 3, .ignite: 6, .hold: 8, .windUp: 2, .smear: 1,
            .follow: 3, .recover: 2, .decision: 8, .retract: 5, .hiltOut: 3, .lower: 6,
        ]
        #expect(counts == approved)
        // The phases ARE the beat: 53 committed-GIF frames, and nothing after.
        #expect(abs(CrabAnimator.sortieDuration(.saber) - 53.0 / 12) < 1e-9)
        #expect(CrabAnimator.saberPhase(at: CrabAnimator.sortieDuration(.saber)) == nil)
        #expect(CrabAnimator.saberPhase(at: -0.01) == nil)
    }

    @Test("The rifle scans, then locks, then fires — one frame of flash, one of bolt")
    func rifleScanLocksThenFires() {
        var order: [CrabAnimator.RiflePhase] = []
        var counts: [CrabAnimator.RiflePhase: Int] = [:]
        for s in frames(.rifle, fps: 12) {
            guard let phase = CrabAnimator.riflePhase(at: s)?.phase else { continue }
            if order.last != phase { order.append(phase) }
            counts[phase, default: 0] += 1
        }
        #expect(order == CrabAnimator.RiflePhase.allCases)
        #expect(counts[.fire] == 1)
        #expect(counts[.travel] == 1)
        #expect((counts[.lock] ?? 0) >= 2, "a lock nobody can see is no lock")
        // The lead-in is the costume's own scan at its own length, so it reads
        // as the same camera; and the phases sum to the beat.
        let scan = CrabAnimator.riflePhases.first { $0.phase == .scan }?.length
        #expect(scan == SpawnRates.gundamScan.duration)
        #expect(abs(CrabAnimator.sortieDuration(.rifle) - 3.25) < 1e-9)
    }

    // MARK: - Motion

    @Test("The saber arm climbs one cell at a time, at 12, 20 and 30fps")
    func sortieArmLandsOnEveryCell() {
        for fps in [12.0, 20.0, 30.0] {
            var last: Int?
            var top = 0
            for s in frames(.saber, fps: fps) {
                let pose = staged(.saber, s)
                let reach = CrabRig.armReach(pose.armRight)
                if let last {
                    #expect(abs(reach - last) <= 1, "\(fps)fps at \(s)s: reach \(last) → \(reach)")
                }
                last = reach
                top = max(top, reach)
                #expect(pose.lean == 0 && pose.bob == 0, "a sortie moves the claw and nothing else")
            }
            #expect(top == 3, "the approved reach is three cells")
            #expect(last == 0, "the beat ends with the claw at rest")
        }
    }

    @Test("The blade grows and retracts at most two rows a frame, and holds on rows 2–8")
    func bladeGrowsAtMostTwoRowsAFrame() {
        func rows(_ s: Double) -> Set<Int> {
            Set(weapon(staged(.saber, s)).filter { $0.value == .paper || $0.value == .pink }
                .map { $0.key / PixelBuffer.side })
        }
        let continuous: Set<CrabAnimator.SaberPhase> = [.hiltIn, .ignite, .hold, .decision, .retract, .hiltOut]
        for fps in [12.0, 20.0, 30.0] {
            var last: Int?
            for s in frames(.saber, fps: fps) {
                guard let phase = CrabAnimator.saberPhase(at: s)?.phase, continuous.contains(phase) else {
                    last = nil
                    continue
                }
                let count = rows(s).count
                if let last {
                    #expect(abs(count - last) <= 2, "\(fps)fps \(phase) at \(s)s: \(last) → \(count) rows")
                }
                last = count
            }
        }
        #expect(rows(1.4) == Set(2...8), "the lit blade is the approved seven rows")
    }

    @Test("The weapon rides the claw — under a hush and through a mood blend too")
    func weaponRidesTheClaw() {
        let seated: Set<CrabAnimator.SaberPhase> = [
            .ignite, .hold, .windUp, .smear, .follow, .recover, .decision, .retract,
        ]
        func hiltBottom(_ pose: CrabPose) -> Int? {
            var solid = pose
            solid.sortie?.visibility = 1       // the geometry, not the dissolve
            return weapon(solid).filter { $0.value == .steel }.map { $0.key / PixelBuffer.side }.max()
        }
        for s in frames(.saber, fps: 20) {
            guard let phase = CrabAnimator.saberPhase(at: s)?.phase, seated.contains(phase) else { continue }
            for hush in [0.0, 0.3, 0.6] {
                var pose = staged(.saber, s)
                CrabAnimator.hushSortie(hush, to: &pose)
                let clawTop = CrabRig.armY - CrabRig.armReach(pose.armRight)
                #expect(hiltBottom(pose) == clawTop - 1, "\(phase) at \(s)s, hush \(hush)")
            }
        }
        // A mood blend lowers the arm; the weapon comes down with it.
        let from = staged(.saber, 1.4)
        var to = from
        to.sortie = nil
        to.armRight = 0
        for i in 1..<10 {
            let mid = CrabPose.blend(from: from, to: to, u: Double(i) / 10)
            let clawTop = CrabRig.armY - CrabRig.armReach(mid.armRight)
            #expect(hiltBottom(mid) == clawTop - 1, "blend u=\(Double(i) / 10)")
        }
    }

    @Test("Nothing arrives in one frame except the sanctioned keys")
    func weaponNeverPops() {
        let saberKeys: Set<CrabAnimator.SaberPhase> = [.windUp, .smear, .follow, .recover]
        let rifleKeys: Set<CrabAnimator.RiflePhase> = [.fire]
        for fps in [12.0, 20.0, 30.0] {
            for kind in Kind.allCases {
                var last: [Int: PixelBuffer.Ink] = [:]
                var lastWasKey = false
                for s in frames(kind, fps: fps) {
                    let cells = weapon(staged(kind, s))
                    let isKey = kind == .saber
                        ? CrabAnimator.saberPhase(at: s).map { saberKeys.contains($0.phase) } ?? false
                        : CrabAnimator.riflePhase(at: s).map { rifleKeys.contains($0.phase) } ?? false
                    let arrived = cells.keys.filter { last[$0] == nil }.count
                    if !isKey, !lastWasKey {
                        #expect(arrived <= 6, "\(kind) \(fps)fps at \(s)s: \(arrived) cells in one frame")
                    }
                    last = cells
                    lastWasKey = isKey
                }
            }
        }
    }

    @Test("The hilt and the rifle dissolve in and out — never a frame's pop")
    func theWeaponDissolvesInAndOut() {
        let windows: [(Kind, Double, Double)] = [
            (.saber, 0.5, 0.75), (.saber, 44.0 / 12, 47.0 / 12), // hiltIn, hiltOut
            (.rifle, 0.0, 0.25), (.rifle, 3.0, 3.25),           // rifleIn, rifleOut
        ]
        for (kind, from, to) in windows {
            let rising = from < 1                                 // the in-phases open each beat
            var last: Double?
            for i in 0...30 {
                let seconds = from + (to - from) * (Double(i) + 0.5) / 31
                let d = CrabAnimator.sortieDissolve(CrabPose.Sortie(kind: kind, seconds: min(seconds, to - 1e-6)))
                if let last {
                    #expect(rising ? d >= last : d <= last, "\(kind) \(from)–\(to): \(last) → \(d)")
                }
                last = d
            }
            let first = CrabAnimator.sortieDissolve(CrabPose.Sortie(kind: kind, seconds: from + 0.001))
            let final = CrabAnimator.sortieDissolve(CrabPose.Sortie(kind: kind, seconds: to - 0.001))
            #expect(rising ? (first < 0.05 && final > 0.95) : (first > 0.95 && final < 0.05),
                    "\(kind) \(from)–\(to): \(first) … \(final)")
        }
    }

    @Test("The shot only ever travels outward, then leaves the grid")
    func boltNeverGoesBackward() {
        let muzzleRow = CrabRig.armY
        for fps in [12.0, 20.0, 30.0] {
            var lastHead: Int?
            var gone = false
            for s in frames(.rifle, fps: fps) {
                guard let phase = CrabAnimator.riflePhase(at: s)?.phase,
                      [.fire, .travel, .cool, .rifleOut].contains(phase) else { continue }
                let head = weapon(staged(.rifle, s))
                    .filter { $0.value == .paper && $0.key / PixelBuffer.side == muzzleRow }
                    .map { $0.key % PixelBuffer.side }.max()
                if let head {
                    #expect(!gone, "\(fps)fps: the shot came back after it had left")
                    if let lastHead { #expect(head >= lastHead, "\(fps)fps at \(s)s: \(lastHead) → \(head)") }
                    lastHead = head
                } else if lastHead != nil {
                    gone = true
                }
            }
            #expect(lastHead != nil && gone, "\(fps)fps: the shot must appear, then leave")
        }
    }

    @Test("The lock sweep moves at most two columns a frame at 12fps — the costume scan's own clock")
    func theSweepStaysUnderTheClock() {
        var last: Int?
        var seen = 0
        for s in frames(.rifle, fps: 12) {
            guard CrabAnimator.riflePhase(at: s)?.phase == .scan else { continue }
            let buffer = CrabRig.render(staged(.rifle, s), costume: .gundam)
            let columns = (0..<PixelBuffer.side).filter { x in
                (CrabRig.bodyY + 1...CrabRig.bodyY + CrabRig.bodyH - 1).contains { buffer[x, $0] == .yellow }
            }
            guard let column = columns.first else { last = nil; continue }
            seen += 1
            if let last { #expect(abs(column - last) <= 2, "at \(s)s: \(last) → \(column)") }
            last = column
        }
        #expect(seen > 10, "the lock sweep must actually cross him")
    }

    // MARK: - Face, shell and inks

    /// The saber rack's right-hand hilt — the one he draws.
    private var rack: Set<Int> {
        let top = CrabRig.bodyY, right = CrabRig.bodyX + CrabRig.bodyW
        return [(right - 2) + (top - 3) * PixelBuffer.side, (right - 3) + (top - 2) * PixelBuffer.side]
    }

    @Test("The drawn hilt leaves the rack for the claw, and comes back")
    func theDrawnHiltLeavesTheRack() {
        func onRack(_ pose: CrabPose) -> Int {
            let b = CrabRig.render(pose, costume: .gundam)
            return rack.filter { b[$0 % PixelBuffer.side, $0 / PixelBuffer.side] == .steel }.count
        }
        #expect(onRack(staged(.saber, 0.2)) == 2, "raising the claw: the hilt is still racked")
        #expect(onRack(staged(.saber, 1.4)) == 0, "lit: the hilt is in his claw, not on his back")
        #expect(onRack(staged(.saber, 4.2)) == 2, "lowering the claw: it is back on the rack")
        #expect(onRack(staged(.rifle, 1.0)) == 2, "the rifle leaves the rack alone")
        // Handed over, never doubled: while it moves, the rack and the claw
        // share one hilt's worth between them.
        for s in stride(from: 0.5, to: 0.75, by: 0.01) {
            let pose = staged(.saber, s)
            let inHand = CrabAnimator.sortieHiltInHand(pose.sortie!)
            #expect(inHand >= 0 && inHand <= 1)
        }
        // A hushed sortie puts the hilt back.
        var hushed = staged(.saber, 1.4)
        CrabAnimator.hushSortie(1, to: &hushed)
        #expect(onRack(hushed) == 2)
    }

    @Test("The weapon never touches his face, his shell or the badge box — nor, mid-crossfade, the look")
    func sortieNeverTouchesFaceOrShell() {
        for kind in Kind.allCases {
            for s in frames(kind, fps: 20) {
                let pose = staged(kind, s)
                var plain = pose
                plain.sortie = nil
                let with = CrabRig.render(pose, costume: .gundam)
                let without = CrabRig.render(plain, costume: .gundam)
                let scanning = kind == .rifle && CrabAnimator.riflePhase(at: s)?.phase == .scan
                for y in 0..<PixelBuffer.side {
                    for x in 0..<PixelBuffer.side where with[x, y] != without[x, y] {
                        let was = without[x, y], now = with[x, y]
                        #expect(was != .eye && was != .mouth, "\(kind) at \(s)s covered his face at (\(x),\(y))")
                        #expect(!((1...8).contains(x) && (0...7).contains(y)), "\(kind) in the badge box")
                        if was == .clear {
                            #expect([.pink, .paper, .steel, .slate].contains(now), "\(kind) painted \(now) at (\(x),\(y))")
                        } else if was == .steel, now == .clear {
                            #expect(kind == .saber && rack.contains(y * PixelBuffer.side + x),
                                    "\(kind) at \(s)s took a steel cell off at (\(x),\(y))")
                        } else {
                            #expect(scanning && was == .body && (now == .yellow || now == .steel),
                                    "\(kind) at \(s)s changed a \(was) cell at (\(x),\(y)) to \(now)")
                        }
                    }
                }
            }
        }
        // Mid-crossfade the outgoing and incoming looks are only half painted;
        // the weapon must still keep out of every cell either would own at
        // full strength. From the ninja, whose tail ribbons hang exactly where
        // the rifle is held — the case the keep-out mask exists for.
        for kind in Kind.allCases {
            for s in frames(kind, fps: 12) {
                let pose = staged(kind, s)
                var plain = pose
                plain.sortie = nil
                let gundamFull = CrabRig.render(plain, costume: .gundam)
                let ninjaFull = CrabRig.render(plain, costume: .ninja)
                for v in [0.3, 0.5, 0.8] {
                    for cell in weapon(pose, costume: .gundam, ghost: .ninja, visibility: v).keys {
                        let x = cell % PixelBuffer.side, y = cell / PixelBuffer.side
                        #expect(gundamFull[x, y] == .clear && ninjaFull[x, y] == .clear,
                                "\(kind) at \(s)s, crossfade at \(v): landed on a look at (\(x),\(y))")
                    }
                }
            }
        }
    }

    // MARK: - The schedule

    @Test("Live only: never offline, never bare or in another costume, never in cycle zero")
    func sortieIsLiveOnly() {
        var sawOne = false
        for t in stride(from: 0.0, through: 1400, by: 0.5) {
            if CrabAnimator.gundamSortie(at: t, wardrobe: gundam) != nil {
                sawOne = true
                #expect(t >= 7, "a sortie in cycle zero at \(t)s")
            }
            #expect(CrabAnimator.gundamSortie(at: t) == nil)
            #expect(CrabAnimator.gundamSortie(at: t, wardrobe: .init(current: .sonic)) == nil)
            #expect(CrabAnimator.pose(mood: .idle, t: t).sortie == nil)
            #expect(CrabAnimator.pose(mood: .idle, t: t, flourishes: false, wardrobe: gundam).sortie == nil)
        }
        #expect(sawOne, "the gate is only meaningful if the Gundam does sortie")
        // The sentinel itself: at the table's share this die misses cycle
        // zero by luck, which would hide a broken guard. With every quiet
        // cycle a sortie, only the guard stands between cycle zero and one.
        for t in stride(from: 0.0, to: 7.0, by: 0.05) {
            #expect(CrabAnimator.gundamSortie(at: t, wardrobe: gundam, share: 1) == nil, "cycle zero at \(t)s")
        }
        #expect((1...50).contains {
            CrabAnimator.gundamSortie(at: Double($0) * 7 + CrabAnimator.sortieOffset + 0.01,
                                      wardrobe: gundam, share: 1) != nil
        }, "the control: at share 1 a quiet cycle does sortie")
        for kind in CrabAnimator.Flourish.allCases {
            #expect(CrabAnimator.flourishPose(kind, at: 0.5).sortie == nil)
        }
    }

    @Test("A sortie only ever fills a quiet cycle, and both kinds come up")
    func sortieOnlyFillsQuietWindows() {
        var kinds = Set<Kind>()
        for cycle in 1...3000 {
            let start = Double(cycle) * 7
            let begin = start + CrabAnimator.sortieOffset
            guard let (kind, _) = CrabAnimator.gundamSortie(at: begin + 0.01, wardrobe: gundam) else { continue }
            kinds.insert(kind)
            let end = begin + CrabAnimator.sortieDuration(kind)
            #expect(end < start + 7, "cycle \(cycle): the beat spills into the next cycle")
            #expect(CrabAnimator.flourish(at: start) == nil, "cycle \(cycle): a sortie over a trick")
            for x in stride(from: begin, to: end, by: 0.1) {
                let clear = CrabAnimator.surfSet(idleT: x) == nil
                    && CrabAnimator.skateSession(idleT: x, wardrobe: gundam) == nil
                    && CrabAnimator.stargazeWindow(idleT: x) == nil
                    && CrabAnimator.sunPatchWindow(idleT: x) == nil
                    && CrabAnimator.idleBalloon(idleT: x) == nil
                    && CrabAnimator.bugPosition(idleT: x) == nil
                    && CrabAnimator.idleHeart(idleT: x) == nil
                    && CrabAnimator.idleShades(idleT: x) == nil
                    && CrabAnimator.shellGlint(idleT: x) == nil
                    && CrabCostume.effectWindow(at: x, SpawnRates.gundamScan) == nil
                #expect(clear, "cycle \(cycle): another idle spell inside the sortie at \(x)s")
                let pose = CrabAnimator.pose(mood: .idle, t: x, flourishes: true, wardrobe: gundam)
                #expect(pose.sortie?.kind == kind, "cycle \(cycle): the idle branch dropped the beat at \(x)s")
            }
        }
        #expect(kinds == Set(Kind.allCases))
    }

    @Test("About one sortie every two minutes of Gundam idling")
    func sortieCadence() {
        let cycles = 100_000
        var beats = 0
        for cycle in 1...cycles {
            let begin = Double(cycle) * 7 + CrabAnimator.sortieOffset
            if CrabAnimator.gundamSortie(at: begin + 0.01, wardrobe: gundam) != nil { beats += 1 }
        }
        let perHour = Double(beats) / (Double(cycles) * 7 / 3600)
        #expect(perHour > 24 && perHour < 36, "\(perHour) sorties an hour")
    }

    // MARK: - Making way

    @Test("Taking the Gundam off mid-beat hands the claw back and fades the weapon once")
    func aCostumeChangeFadesTheSortie() throws {
        // The first scheduled saber.
        let cycle = try #require((1...3000).first { cycle in
            CrabAnimator.gundamSortie(at: Double(cycle) * 7 + CrabAnimator.sortieOffset + 0.01,
                                      wardrobe: gundam)?.kind == .saber
        })
        let begin = Double(cycle) * 7 + CrabAnimator.sortieOffset
        let changedAt = begin + 1.2
        let off = CrabAnimator.MotionWardrobe(current: .none, previous: .gundam, changedAt: changedAt)
        var last: Int?
        for i in 0..<20 {                                      // the live 20fps
            let t = changedAt + Double(i) / 20
            let pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: true, wardrobe: off)
            #expect(pose.sortie != nil, "the cycle's latch finishes the beat")
            let reach = CrabRig.armReach(pose.armRight)
            if let last { #expect(abs(reach - last) <= 1, "at \(t)s: \(last) → \(reach)") }
            last = reach
        }
        #expect(last == 0, "the claw is handed back within the costume's fade")
        // The weapon fades with the Gundam's share of the crossfade — and only
        // that: gone when the Gundam is gone.
        let lit = staged(.saber, 1.4)
        let counts = [0.0, 0.5, 0.9, 1.0].map {
            weapon(lit, costume: .none, ghost: .gundam, visibility: $0).count
        }
        #expect(counts[0] > counts[1] && counts[1] >= counts[2] && counts[3] == 0, "\(counts)")
    }

    @Test("A mood change mid-beat dissolves the weapon, frozen where it was")
    func sortieFadesOnAMoodChange() {
        let from = staged(.saber, 1.4)
        var to = from
        to.sortie = nil
        to.armRight = 0
        var lastVisibility = 1.0
        for i in 1..<20 {
            let mid = CrabPose.blend(from: from, to: to, u: Double(i) / 20)
            #expect(mid.sortie?.seconds == 1.4, "the beat is frozen, never averaged")
            let visibility = mid.sortie?.visibility ?? 0
            #expect(visibility <= lastVisibility + 1e-12)
            lastVisibility = visibility
        }
        #expect(lastVisibility < 0.05)
        #expect(CrabPose.blend(from: from, to: to, u: 1).sortie == nil)
    }

    @Test("A hover, a pet or a poke hushes it — the claw comes down a cell at a time")
    func sortieHushesUnderHoverPetAndClick() {
        let lit = staged(.saber, 1.4)
        var hushed = lit
        CrabAnimator.hushSortie(1, to: &hushed)
        #expect(hushed.sortie?.visibility == 0)
        #expect(CrabRig.armReach(hushed.armRight) == 0)
        // A poke and a hover, at the live reaction tier (30fps).
        let envelopes: [(String, (Double) -> Double)] = [
            ("poke", { CrabAnimator.clickHush(elapsed: $0) }),
            ("hover", { Ease.amount(now: $0, since: 0, endedAt: nil) }),
            ("pet", { Ease.amount(now: $0, since: 0, endedAt: 0.6) }),
        ]
        for (name, hush) in envelopes {
            var last: Int?
            for i in 0..<45 {
                var pose = lit
                CrabAnimator.hushSortie(hush(Double(i) / 30), to: &pose)
                let reach = CrabRig.armReach(pose.armRight)
                if let last { #expect(abs(reach - last) <= 1, "\(name) at frame \(i): \(last) → \(reach)") }
                last = reach
            }
        }
        // The rifle's lock sweep is the beat's too: hushed, it dissolves with
        // the rifle instead of sticking as a frozen gold bar.
        func shellGold(_ pose: CrabPose) -> Int {
            let b = CrabRig.render(pose, costume: .gundam)
            var gold = 0
            for y in (CrabRig.bodyY + 1)..<(CrabRig.bodyY + CrabRig.bodyH) {
                for x in 0..<PixelBuffer.side where b[x, y] == .yellow { gold += 1 }
            }
            return gold
        }
        let scanning = staged(.rifle, 1.15)
        var quiet = scanning
        CrabAnimator.hushSortie(0.95, to: &quiet)
        #expect(shellGold(scanning) > 0, "the control: the lock sweep is crossing him")
        #expect(shellGold(quiet) < shellGold(scanning), "a hushed sortie left its sweep at full strength")
        // A pose with no sortie is never touched — every hover he ever did.
        var calm = CrabAnimator.pose(mood: .idle, t: 3, flourishes: false)
        calm.armRight = 0.8
        let before = calm
        CrabAnimator.hushSortie(1, to: &calm)
        #expect(calm == before)
    }

    @Test("The standalone scan stands down while a sortie runs")
    func theScanStandsDownDuringASortie() {
        var lit = CrabAnimator.pose(mood: .idle, t: 0.5, flourishes: false)
        lit.propPhase = 36.9                                   // inside a live scan window
        func shellGold(_ pose: CrabPose) -> Int {
            let b = CrabRig.render(pose, costume: .gundam)
            var gold = 0
            for y in (CrabRig.bodyY + 1)..<(CrabRig.bodyY + CrabRig.bodyH) {
                for x in 0..<PixelBuffer.side where b[x, y] == .yellow { gold += 1 }
            }
            return gold
        }
        #expect(shellGold(lit) > 0, "the control: the scan is crossing him")
        var armed = lit
        CrabAnimator.applySortie(.saber, seconds: 1.4, to: &armed)
        #expect(shellGold(armed) == 0)
    }

    @Test("A preview rests first, and released mid-beat it finishes the beat, then stops")
    func aDeselectedPreviewFinishesItsBeat() {
        let cases: [(CrabAnimator.PreviewEffect, Kind)] = [(.beamSaber, .saber), (.beamRifle, .rifle)]
        for (effect, kind) in cases {
            let rest = CrabAnimator.sortiePreviewRest
            let beat = CrabAnimator.sortieDuration(kind)
            #expect(effect.releaseDuration == rest + beat)
            #expect(effect.wardrobe == .gundam)
            let endedT = rest + beat / 2                        // let go mid-beat
            func sortie(at t: Double) -> CrabPose.Sortie? {
                var pose = CrabAnimator.pose(mood: .idle, t: 5, flourishes: false)
                CrabAnimator.applyPreview(CrabAnimator.PreviewFrame(effect: effect, t: t, endedT: endedT),
                                          to: &pose)
                return pose.sortie
            }
            #expect(sortie(at: rest / 2) == nil, "\(effect): the rest comes first")
            #expect(sortie(at: rest + beat * 0.75)?.kind == kind, "\(effect): the beat in flight finishes")
            #expect(sortie(at: rest + beat + rest + 0.5) == nil, "\(effect): no new pass after the release")
        }
    }
}
