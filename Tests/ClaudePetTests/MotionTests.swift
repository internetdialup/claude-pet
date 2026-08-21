import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ClaudePet

/// The easing vocabulary's contract: envelopes hit their endpoints, rise
/// monotonically, and stay continuous across the attack→release handoff. The
/// no-snap rule is only as good as these shapes.
@Suite("Ease")
struct EaseTests {

    @Test func smoothstepEndpoints() {
        #expect(Ease.smoothstep(-1) == 0)
        #expect(Ease.smoothstep(0) == 0)
        #expect(Ease.smoothstep(1) == 1)
        #expect(Ease.smoothstep(2) == 1)
        #expect(abs(Ease.smoothstep(0.5) - 0.5) < 1e-12)
    }

    @Test func smoothstepMonotone() {
        var previous = -0.1
        for i in 0...100 {
            let v = Ease.smoothstep(Double(i) / 100)
            #expect(v >= previous)
            previous = v
        }
    }

    @Test func amountRisesAndHolds() {
        let since = 100.0
        #expect(Ease.amount(now: 99.9, since: since, endedAt: nil) == 0)
        #expect(Ease.amount(now: since + 0.35, since: since, endedAt: nil) == 1)
        #expect(Ease.amount(now: since + 10, since: since, endedAt: nil) == 1)
        let mid = Ease.amount(now: since + 0.17, since: since, endedAt: nil)
        #expect(mid > 0 && mid < 1)
    }

    @Test func amountIsContinuousAtRelease() {
        let since = 100.0
        // Release fired mid-rise: the envelope must pick up from the height it
        // had reached, not jump to 1 first.
        let endedAt = since + 0.2
        let before = Ease.amount(now: endedAt - 0.0001, since: since, endedAt: nil)
        let after = Ease.amount(now: endedAt + 0.0001, since: since, endedAt: endedAt)
        #expect(abs(before - after) < 0.01)
        // And it decays to zero within the release.
        #expect(Ease.amount(now: endedAt + 0.45, since: since, endedAt: endedAt) == 0)
    }

    @Test func squareSitsAtPolesOutsideTheSoftWindow() {
        // At the crests of the sine the eased square is pinned to its poles.
        #expect(abs(Ease.square(.pi / 2) - 1) < 1e-9)
        #expect(abs(Ease.square(3 * .pi / 2)) < 1e-9)
        // And in between it is strictly inside them.
        let edge = Ease.square(0.05)
        #expect(edge > 0 && edge < 1)
    }

    @Test func windowShape() {
        #expect(Ease.window(-0.1, duration: 10, edge: 0.6) == 0)
        #expect(Ease.window(0, duration: 10, edge: 0.6) == 0)
        #expect(Ease.window(5, duration: 10, edge: 0.6) == 1)
        #expect(Ease.window(10, duration: 10, edge: 0.6) == 0)
        let rising = Ease.window(0.3, duration: 10, edge: 0.6)
        #expect(rising > 0 && rising < 1)
    }
}

/// Continuity across mood changes: blending any mood pair at the crossfade's
/// frame rate must move every channel gradually. One-frame pops are exactly
/// what the blend exists to remove, so a pop here is a regression by
/// definition.
@Suite("Motion continuity")
struct MotionContinuityTests {

    /// Every mood pair, blended over the crossfade duration at 30fps: no Int
    /// channel may jump more than one pixel between consecutive frames, and no
    /// Double channel more than 0.15.
    @Test func blendStepsAreBounded() {
        let frames = Int((MoodClock.blendDuration * 30).rounded())   // 12
        for fromMood in PetMood.allCases {
            for toMood in PetMood.allCases where toMood != fromMood {
                let from = CrabAnimator.pose(mood: fromMood, t: 3.7)
                let to = CrabAnimator.pose(mood: toMood, t: 0)
                var previous = from
                for frame in 1...frames {
                    let u = Ease.smoothstep(Double(frame) / Double(frames))
                    let blended = CrabPose.blend(from: from, to: to, u: u)
                    #expect(abs(blended.bob - previous.bob) <= 1)
                    #expect(abs(blended.lean - previous.lean) <= 1)
                    #expect(abs(blended.squash - previous.squash) <= 1)
                    #expect(abs(blended.gazeX - previous.gazeX) <= 1)
                    #expect(abs(blended.gazeY - previous.gazeY) <= 1)
                    #expect(abs(blended.armLeft - previous.armLeft) <= 0.15)
                    #expect(abs(blended.armRight - previous.armRight) <= 0.15)
                    #expect(abs(blended.scale - previous.scale) <= 0.15)
                    previous = blended
                }
            }
        }
    }

    @Test func blendEndpointsAreExact() {
        let from = CrabAnimator.pose(mood: .working, t: 5)
        let to = CrabAnimator.pose(mood: .done, t: 0)
        #expect(CrabPose.blend(from: from, to: to, u: 0) == from)
        #expect(CrabPose.blend(from: from, to: to, u: 1) == to)
    }

    /// A blend across differing props carries the outgoing one as a dissolving
    /// ghost rather than deleting it.
    @Test func blendGhostsTheOutgoingProp() {
        var from = CrabAnimator.pose(mood: .nudging, t: 2)     // .plan
        from.prop = .plan
        let to = CrabAnimator.pose(mood: .done, t: 0)          // .check
        let mid = CrabPose.blend(from: from, to: to, u: 0.3)
        #expect(mid.ghostProp == .plan)
        #expect(mid.ghostPropVisibility > 0)
        #expect(mid.propVisibility < 1)
    }

    /// The working-prop re-roll dissolves across its spell boundary instead of
    /// teleporting: visibility dips into and out of the boundary, and only
    /// when the prop actually changes.
    @Test func propSwapDissolvesAtTheSpellBoundary() {
        // Find a boundary where the prop changes.
        var boundary: Double?
        for cycle in 1...40 {
            let t = Double(cycle) * 20
            if CrabAnimator.workingProp(at: t - 1) != CrabAnimator.workingProp(at: t + 1) {
                boundary = t
                break
            }
        }
        guard let boundary else {
            Issue.record("no prop change in 40 cycles — the dice are broken")
            return
        }
        let fadingOut = CrabAnimator.pose(mood: .working, t: boundary - 0.1)
        let fadingIn = CrabAnimator.pose(mood: .working, t: boundary + 0.1)
        let settled = CrabAnimator.pose(mood: .working, t: boundary + 1)
        #expect(fadingOut.propVisibility < 1)
        #expect(fadingIn.propVisibility < 1)
        #expect(settled.propVisibility == 1)
    }
}

/// The frozen sentinel: at t=0 no scheduled effect may be mid-flight. Offline
/// renderers and the debug picker freeze time at zero, so anything that fires
/// there ships in every screenshot.
@Suite("Frozen sentinel")
struct FrozenSentinelTests {

    @Test func nothingFiresAtTimeZero() {
        for mood in PetMood.allCases {
            let pose = CrabAnimator.pose(mood: mood, t: 0)
            #expect(pose.propVisibility == 1, "mood \(mood)")
            #expect(pose.ghostProp == .none, "mood \(mood)")
            #expect(pose.ghostPropVisibility == 0, "mood \(mood)")
            #expect(pose.heat == 0, "mood \(mood)")
            // Latch-driven, never scheduled — a frozen render must not carry
            // a service glyph a live latch never handed it.
            #expect(pose.serviceGlyph == nil, "mood \(mood)")
            #expect(pose.serviceGlyphVisibility == 0, "mood \(mood)")
        }
    }

    /// The first working spell never fades in — there was nothing before it to
    /// put down.
    @Test func firstSpellHasNoFadeIn() {
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(CrabAnimator.pose(mood: .working, t: t).propVisibility == 1)
        }
    }

    /// The dissolve at full visibility must be the identity — the pre-dissolve
    /// renderer byte for byte.
    @Test func fullVisibilityCompositeIsIdentity() {
        let pose = CrabAnimator.pose(mood: .working, t: 3)
        var direct = CrabRig.render(pose)
        var faded = pose
        faded.propVisibility = 1
        let rendered = CrabRig.render(faded)
        #expect(direct.runs().count == rendered.runs().count)
        for (a, b) in zip(direct.runs(), rendered.runs()) {
            #expect(a.x == b.x && a.y == b.y && a.length == b.length && a.ink == b.ink)
        }
        _ = direct
    }

    @Test("A hit holds at exactly one, and is its own frozen sentinel")
    func pulseHoldsAndSleeps() {
        #expect(Ease.pulse(0, attack: 0.09, hold: 0.12, decay: 0.28) == 0, "frozen sentinel")
        #expect(Ease.pulse(-1, attack: 0.09, hold: 0.12, decay: 0.28) == 0)
        #expect(Ease.pulse(0.5, attack: 0.09, hold: 0.12, decay: 0.28) == 0, "past the tail")
        // The plateau: anywhere inside [attack, attack + hold] is exactly 1.
        // Reaching EXACTLY 1 is the point — a hit that tops out at 0.9 is a
        // grey, and a hit that tops out at 0.4 is the peach this replaced.
        #expect(Ease.pulse(0.10, attack: 0.09, hold: 0.12, decay: 0.28) == 1)
        #expect(Ease.pulse(0.20, attack: 0.09, hold: 0.12, decay: 0.28) == 1)
        // And it ramps rather than steps on both sides.
        let rising = Ease.pulse(0.045, attack: 0.09, hold: 0.12, decay: 0.28)
        let falling = Ease.pulse(0.35, attack: 0.09, hold: 0.12, decay: 0.28)
        #expect(rising > 0.4 && rising < 0.6)
        #expect(falling > 0.05 && falling < 0.95)
    }
}

/// The blanch: the channel that takes the WHOLE sprite to white, as opposed to
/// `bodyTint`, which reaches one ink by design. These are the tests that would
/// have caught the peach — a "white" flash that left black eyes and a dark
/// costume standing in the middle of it.
@Suite("The blanch")
@MainActor
struct BlanchTests {

    /// A fixture carrying every hard case at once: heat bands present, and the
    /// Gundam wardrobe, whose `costumeC` is near-black, whose eyes are
    /// overridden yellow, and whose `costumeA`/`costumeB` are saturated.
    private func hardestBuffer() -> PixelBuffer {
        var pose = CrabAnimator.pose(mood: .done, t: 0.3)
        pose.heat = 1
        pose.heatPhase = 0.4
        return CrabRig.render(pose, costume: .gundam, costumeVisibility: 1)
    }

    private func pixels(_ view: some View) throws -> NSBitmapImageRep {
        let image = try #require(SpriteImage.cgImage(of: view.frame(width: 96, height: 96)))
        return NSBitmapImageRep(cgImage: image)
    }

    @Test("At full blanch every lit cell is pure white — eyes and costume too")
    func fullBlanchIsPureWhite() throws {
        let rep = try pixels(PixelCanvasView(buffer: hardestBuffer(),
                                             inkOverrides: CostumeStyle.blendedOverrides(
                                                from: .none, to: .gundam, u: 1),
                                             seamBleed: 0,
                                             blanch: 1))
        var checked = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let colour = rep.colorAt(x: x, y: y),
                      colour.alphaComponent > 0.99 else { continue }
                checked += 1
                #expect(colour.redComponent > 0.99 && colour.greenComponent > 0.99
                        && colour.blueComponent > 0.99,
                        "an opaque cell at (\(x),\(y)) survived the flash: \(colour)")
            }
        }
        #expect(checked > 500, "the fixture should cover a real sprite, not a few cells")
    }

    @Test("Blanch zero is the identity — inert for every existing caller")
    func blanchZeroIsIdentity() throws {
        let buffer = hardestBuffer()
        let plain = SpriteImage.png(of: PixelCanvasView(buffer: buffer)
            .frame(width: 96, height: 96))
        let unlit = SpriteImage.png(of: PixelCanvasView(buffer: buffer, blanch: 0)
            .frame(width: 96, height: 96))
        #expect(plain != nil && plain == unlit)
    }

    /// The seam trap. `seamBleed` (0.5 in the live view) makes neighbouring run
    /// rects OVERLAP, so a wash filled per-run would composite white twice down
    /// every seam and paint a bright grid across a sprite whose palette forbids
    /// shading — and an even-odd fill of the union would punch transparent
    /// holes there instead. One non-zero-wound path over the union does
    /// neither. A solid block spanning many runs makes either bug visible as a
    /// pixel that differs from its neighbours.
    @Test("A partial blanch leaves no seam grid across a solid area")
    func partialBlanchHasNoSeams() throws {
        var buffer = PixelBuffer()
        for y in 8..<24 {
            for x in 8..<24 { buffer[x, y] = .body }
        }
        let rep = try pixels(PixelCanvasView(buffer: buffer, blanch: 0.5))
        // Sample well inside the block so no antialiased outer edge is caught:
        // grid cells 10…21 at 3pt per cell.
        var seen = Set<Int>()
        for x in (10 * 3)...(21 * 3) {
            for y in (10 * 3)...(21 * 3) {
                let colour = try #require(rep.colorAt(x: x, y: y))
                #expect(colour.alphaComponent > 0.99, "a hole at (\(x),\(y)) — even-odd fill?")
                seen.insert(Int((colour.redComponent * 255).rounded()))
            }
        }
        #expect(seen.count == 1,
                "uneven wash across a solid block (\(seen.sorted())) — it composited more than once somewhere")
    }

    @Test("The blanch ramps the darkest ink rather than snapping it")
    func blanchIsMonotoneNotBinary() throws {
        // Sampled on the whole sprite rather than one cell: the darkest pixel
        // in the frame has to climb with the wash, which is the property that
        // matters and the one that cannot drift with the rig's geometry.
        var previous = -1.0
        for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let rep = try pixels(PixelCanvasView(buffer: hardestBuffer(),
                                                 seamBleed: 0,
                                                 blanch: amount))
            var darkest = 1.0
            for x in 0..<rep.pixelsWide {
                for y in 0..<rep.pixelsHigh {
                    guard let colour = rep.colorAt(x: x, y: y),
                          colour.alphaComponent > 0.99 else { continue }
                    darkest = min(darkest, colour.redComponent)
                }
            }
            #expect(darkest > previous,
                    "blanch \(amount) did not lift the darkest ink past \(previous)")
            previous = darkest
        }
        #expect(previous > 0.99, "a full blanch must land the darkest ink on white")
    }
}
