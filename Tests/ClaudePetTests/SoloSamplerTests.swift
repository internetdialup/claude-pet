import Testing
import Foundation
@testable import ClaudePet

/// The drip-feed solo matrix — the first tests the sampler has ever had,
/// bought by the variant axis: four ollie flavors whose whole design is a set
/// of promises (zero-pixel seams, shade only mid-air, mirrors that really
/// mirror) that are exactly the kind of thing that rots silently.
///
/// Pure pose and buffer arithmetic throughout: nothing here encodes a GIF,
/// touches a directory, or reads a default.
@Suite("Solo sampler")
@MainActor
struct SoloSamplerTests {

    /// Every clip in the matrix has its own name, and the names the operator
    /// has already pulled keep pointing at the same clips.
    @Test("Suffixes are unique and the legacy names hold")
    func suffixesAreUniqueAndLegacyNamesHold() {
        let suffixes = SoloVariant.allCases.map(\.suffix)
        #expect(Set(suffixes).count == suffixes.count, "two variants share a filename tail")
        #expect(SoloVariant.kickflip.suffix.isEmpty,
                "the kickflip's unsuffixed names are the operator's existing files")
        #expect(SoloVariant.varial.suffix == "-varial")

        var names = Set<String>()
        for costume in CostumeSampler.soloCast {
            for variant in CostumeSampler.soloVariants {
                for shout in CostumeSampler.soloShouts {
                    names.insert(CostumeSampler.soloFileName(costume: costume,
                                                             variant: variant,
                                                             slug: shout.slug))
                }
            }
        }
        #expect(names.count == CostumeSampler.soloCast.count
                * CostumeSampler.soloVariants.count
                * CostumeSampler.soloShouts.count,
                "a filename collision would silently overwrite a clip")
    }

    /// **The seam.** Frame 0, the final frame, and the straight trick's
    /// stance frame must be the SAME picture for every variant — the operator
    /// called the alternative "the jarring cut", and the variants' envelopes
    /// promise it survives them.
    @Test("Every variant holds the zero-pixel seam")
    func everyVariantHoldsTheZeroSeam() {
        for variant in CostumeSampler.soloVariants {
            let line = CostumeSampler.soloShouts[0].line
            let seconds = CostumeSampler.soloSeconds(for: line, trick: variant.trick)
            let last = Double(Int((seconds / CostumeSampler.frameDelay).rounded()) - 1)
                * CostumeSampler.frameDelay
            let open = CrabRig.render(CostumeSampler.soloPose(variant: variant, at: 0))
            let close = CrabRig.render(CostumeSampler.soloPose(variant: variant, at: last))
            let stance = CrabRig.render(CrabAnimator.flourishPose(variant.trick, at: 0))
            #expect(open.cells == close.cells,
                    "\(variant) does not close its loop")
            #expect(open.cells == stance.cells,
                    "\(variant)'s stance hold is not the trick's own stance")
        }
    }

    /// The frozen-sentinel promise, restated for the shade: no ground frame —
    /// pre-roll, crouch instant, landing, roll-away — carries a single cell
    /// of it.
    @Test("Ground frames carry no shade")
    func groundFramesCarryNoShade() {
        let landing = CostumeSampler.soloLanding(for: .ollie)
        for variant in [SoloVariant.ollieFrontside, .ollieBackside] {
            for local in [0.0, CostumeSampler.soloLead - 0.1,
                          CostumeSampler.soloLead + 0.05,   // crouch, pre-air
                          landing - 0.05,                    // stomp, post-air
                          landing, landing + 0.5] {
                let pose = CostumeSampler.soloPose(variant: variant, at: local)
                let buffer = CrabRig.render(pose)
                var shaded = 0
                for y in 0..<PixelBuffer.side {
                    for x in 0..<PixelBuffer.side
                    where buffer[x, y] == .bodyShade { shaded += 1 }
                }
                #expect(shaded == 0,
                        "\(variant) shows \(shaded) shade cells at \(local)s — on the ground")
            }
        }
    }

    /// Mid-air, the shade is an edge band and nothing else: every shaded cell
    /// hugs the outermost columns of that frame's body span, and none sits in
    /// an eye window.
    @Test("The shade hugs the edge and never the eyes")
    func shadeHugsTheEdgeAndNeverTheEyes() {
        for variant in [SoloVariant.ollieFrontside, .ollieBackside] {
            var sawAny = false
            for step in stride(from: CostumeSampler.soloLead,
                               to: CostumeSampler.soloLanding(for: .ollie), by: 0.1) {
                let pose = CostumeSampler.soloPose(variant: variant, at: step)
                guard pose.torsoShadeAmount > 0.001 else { continue }
                let buffer = CrabRig.render(pose)
                let squash = max(0, pose.squash)
                let left = CrabRig.bodyX + pose.lean - squash
                let right = CrabRig.bodyX + CrabRig.bodyW - 1 + pose.lean + squash
                for y in 0..<PixelBuffer.side {
                    for x in 0..<PixelBuffer.side where buffer[x, y] == .bodyShade {
                        sawAny = true
                        let onEdge = variant == .ollieFrontside
                            ? x >= right - 1 : x <= left + 1
                        #expect(onEdge, "\(variant) shades column \(x) — not an edge")
                        #expect(!((10...12).contains(x) || (19...21).contains(x)),
                                "\(variant) shades an eye window column at \(step)s")
                    }
                }
            }
            #expect(sawAny, "\(variant) never shaded a single cell — the turn is invisible")
        }
    }

    /// The backside IS the frontside in a mirror: shade cells map under
    /// x → 31−x, the gaze flips, and the balance arms swap.
    @Test("The turn variants mirror each other")
    func turnVariantsMirror() {
        for step in stride(from: CostumeSampler.soloLead,
                           to: CostumeSampler.soloLanding(for: .ollie), by: 0.1) {
            let front = CostumeSampler.soloPose(variant: .ollieFrontside, at: step)
            let back = CostumeSampler.soloPose(variant: .ollieBackside, at: step)
            #expect(front.torsoShade == -back.torsoShade)
            #expect(abs(front.torsoShadeAmount - back.torsoShadeAmount) < 0.001)

            // The board is stripped for the geometry compare: the nose slab
            // never mirrors (a mirrored ollie still rides nose-right), and at
            // apex height it legitimately occludes a frontside shade cell the
            // backside keeps. The mirror under test is the SHADE's, and the
            // shell it lands on is symmetric once the one asymmetric occluder
            // steps out of the frame.
            var bareFront = front, bareBack = back
            bareFront.prop = .none
            bareBack.prop = .none
            let frontCells = shadeCells(CrabRig.render(bareFront))
            let backCells = shadeCells(CrabRig.render(bareBack))
            #expect(Set(frontCells.map { Cell(x: 31 - $0.x, y: $0.y) }) == Set(backCells),
                    "the mirror breaks at \(step)s")

            if front.torsoShadeAmount > 0.001, front.gazeX == 1 {
                #expect(back.gazeX == -1, "the backside gaze does not flip at \(step)s")
                #expect(abs(front.armRight - back.armLeft) < 0.001
                        && abs(front.armLeft - back.armRight) < 0.001,
                        "the balance arms do not swap at \(step)s")
            }
        }
    }

    /// "Lofty" is TIME, not height. The apex is pinned at −10 for both — the
    /// shell's top row is already on the grid's row zero there, and one more
    /// pixel of "higher" would silently crop — while the summed airborne lift
    /// must be strictly greater: the hang, measured.
    @Test("Lofty hangs longer at the same pinned apex")
    func loftyHangsLonger() {
        var straightPeak = 0, loftyPeak = 0
        var straightSum = 0, loftySum = 0
        for step in stride(from: CostumeSampler.soloLead,
                           to: CostumeSampler.soloLanding(for: .ollie),
                           by: CostumeSampler.frameDelay) {
            let straight = CostumeSampler.soloPose(variant: .ollie, at: step)
            let lofty = CostumeSampler.soloPose(variant: .ollieLofty, at: step)
            straightPeak = max(straightPeak, -straight.bob)
            loftyPeak = max(loftyPeak, -lofty.bob)
            straightSum += max(0, -straight.bob)
            loftySum += max(0, -lofty.bob)
        }
        #expect(straightPeak == 10, "the straight apex moved — re-derive the crop ceiling")
        #expect(loftyPeak == 10, "the lofty apex left the grid-top pin")
        #expect(loftySum > straightSum,
                "lofty (\(loftySum)) does not out-hang straight (\(straightSum))")
    }

    /// Every shell's shade steps DOWN from that shell — the whole reason the
    /// ink consults overrides. Measured as WCAG relative luminance, the same
    /// arithmetic `PaletteContrastTests` trusts.
    @Test("The shade inks sit one step below their shells")
    func shadeInksSitOneStepBelowTheirShells() {
        #expect(luminance(0xB8674B) < luminance(0xCE7B5C),
                "the bare shade is not below the terracotta")
        for costume in CostumeSampler.soloCast where costume != .none {
            let inks = CostumeStyle.of(costume).inks
            guard let shade = inks[.bodyShade], let body = inks[.body] else {
                Issue.record("\(costume.rawValue) has no shade step for its shell")
                continue
            }
            #expect(luminance(shade) < luminance(body),
                    "\(costume.rawValue)'s shade is not below its shell")
        }
    }

    // MARK: - Helpers

    private struct Cell: Hashable { let x: Int, y: Int }

    private func shadeCells(_ buffer: PixelBuffer) -> [Cell] {
        var cells: [Cell] = []
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where buffer[x, y] == .bodyShade {
                cells.append(Cell(x: x, y: y))
            }
        }
        return cells
    }

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8)
            + 0.0722 * channel(hex)
    }

    private func luminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g)
            + 0.0722 * channel(color.b)
    }
}
