import Testing
import Foundation
import AppKit
import SwiftUI
@testable import ClaudePet

/// The one invariant `docs/media` is worth anything for: the same commit
/// produces the same bytes, so a diff there means the animation changed.
///
/// `desktop.gif` could not satisfy it. Core Graphics smooths type out of a
/// process-global glyph cache, and a glyph's first two or three draws
/// rasterise by a different route than every draw after — so rendering 275
/// hero frames crossed that boundary partway through the opening beat, and
/// *which* frame crossed it moved between processes. One unstable frame was
/// enough: the GIF quantiser builds its palette from the whole clip, so a
/// handful of changed edge samples came back out as a different palette on
/// every frame of the beat. The file differed on every run, which made it
/// useless as the staleness signal it exists to be, and cost one
/// investigation before that was understood.
///
/// `SpriteImage.cgImage(of:)` now renders into a context with that switch
/// pinned. These are the tests that would have caught the drift.
@Suite("Reel determinism", .serialized)
@MainActor
struct ReelDeterminismTests {

    /// Six renders, not two. The old failure needed a *run* of them: the first
    /// two or three draws agreed with each other and every draw after
    /// disagreed with them, so a pair of renders passed while the clip came
    /// out different. Where the boundary falls depends on what the process has
    /// already drawn, so the count here is simply larger than any of them.
    private static let repeats = 6

    private func bytes(_ image: CGImage?) -> Data? {
        (image?.dataProvider?.data) as Data?
    }

    /// Renders `view` `repeats` times and reports any render that disagreed
    /// with the first.
    private func isStable(_ view: some View, _ label: String) {
        let first = bytes(SpriteImage.cgImage(of: view, scale: ReelRenderer.heroScale,
                                              isOpaque: true))
        #expect(first != nil, "\(label) did not render at all")
        for repetition in 1..<Self.repeats {
            #expect(bytes(SpriteImage.cgImage(of: view, scale: ReelRenderer.heroScale,
                                              isOpaque: true)) == first,
                    "\(label): render \(repetition + 1) differs from the first")
        }
    }

    /// The bubble alone, at the size the hero draws it — the narrowest subject
    /// that carries the type the drift lived in.
    ///
    /// First on purpose. The cache is process-global and warms per *glyph*,
    /// not per string, so only the first of these two to run meets it cold;
    /// by the time the second starts, the alphabet is warm and it agrees with
    /// itself either way. Hence `.serialized`, and hence the small subject
    /// going first: a regression should surface as the smallest failing thing
    /// rather than as a whole scene.
    @Test("A bubble full of type renders byte-identically on every repeat")
    func bubbleRepeats() {
        isStable(ThoughtBubble(text: "Same bytes, every run",
                               tool: nil, mood: .idle, style: .plain, frozenTime: 0.2)
                    .background(Palette.Ocean.deep),
                 "bubble")
    }

    /// The frames as `renderHero` actually asks for them. Warm by the time it
    /// runs, so this is the contract restated on the real subject rather than
    /// a second independent chance to catch a cold-cache regression.
    ///
    /// The opening beat rather than any other: it carries a plain bubble,
    /// whose antialiased type is the thing that moved, and the boundary sat
    /// inside it — close enough to the start that a test sampling one instant
    /// could sit either side of it.
    @Test("Every frame of the opening beat renders byte-identically on every repeat")
    func openingBeatRepeats() {
        for step in 0..<10 {
            let t = Double(step) * ReelRenderer.heroFrameDelay
            isStable(ReelRenderer.heroScene(at: t), "hero frame at t=\(t)")
        }
    }

    /// The release-page masthead. Gated where wordmark and social-preview are
    /// not because it is new — no years of byte history vouch for it — and it
    /// carries 54pt type, the largest in any committed asset, over the warm
    /// ground. Type is where the drift lived.
    @Test("The release banner renders byte-identically on every repeat")
    func bannerRepeats() {
        isStable(ReelRenderer.bannerScene(), "release banner")
    }

    /// The masthead's whole premise is the float. If someone retimes the
    /// ollie, `ollieApex` follows the animator's numbers — but a shape change
    /// (a shallower arc, a shifted window) could still quietly turn the
    /// banner into a crab barely off the ground, which is exactly how the
    /// og-image once rotted. Pin the read, not the arithmetic.
    @Test("The banner samples the ollie at full float, board under him")
    func bannerApexIsAirborne() {
        let pose = CrabAnimator.flourishPose(.ollie, at: ReelRenderer.ollieApex)
        #expect(pose.prop == .skateboardOllie)
        #expect(pose.bob <= -9)
    }

    /// The tail-tuck pin — the operator-visible fix of the polish round, and
    /// the audit proved it revertible with every test green: the old droop
    /// formula passed all 483. The tail's own column (x8, deck ink only —
    /// wheels hang further in) is read straight out of the render.
    @Test("The ollie tail tucks to his feet instead of drooping under them")
    func ollieTailTucks() {
        func tail(air: Double) -> (row: Int?, rest: Int) {
            let t = (CrabAnimator.ollieAirStart + air * CrabAnimator.ollieAirSpan)
                * CrabAnimator.Flourish.ollie.duration
            let pose = CrabAnimator.flourishPose(.ollie, at: t)
            let buffer = CrabRig.render(pose)
            for y in 0..<PixelBuffer.side where buffer[8, y] == .deck {
                return (y, 25 + pose.bob)
            }
            return (nil, 25 + pose.bob)
        }
        // Mid-float the tail rides AT or ABOVE its rest row — tucked to the
        // back foot, not drooping below it. The old formula put it below.
        let float = tail(air: 0.65)
        #expect(float.row != nil && float.row! <= float.rest - 1,
                "mid-float tail at \(String(describing: float.row)), rest \(float.rest)")
        // At both air bounds the tail is level at rest — the zero-pixel seam
        // the stance-hold depends on.
        for edge in [0.02, 0.98] {
            let bound = tail(air: edge)
            #expect(bound.row == bound.rest,
                    "tail at air \(edge): \(String(describing: bound.row)), rest \(bound.rest)")
        }
    }
}
