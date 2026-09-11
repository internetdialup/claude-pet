import AppKit
import SwiftUI

/// 🍑 **The trick loop — a laser flip, the backside, and home, forever.**
///
/// The operator's note: *"what people like are that the skateboarder has
/// buttcheeks. we should make it where he does a skatetrick, then does his butt
/// jiggle for a while, then back to the same trick, a full looping gif."*
///
/// So the joke is the payload and the tricks are the punctuation. `ButtLoop`
/// already cuts the bounce on its own, but one held second has nowhere to build
/// from; this gives it a trick to arrive out of and a trick to leave by.
///
/// **No type, deliberately** — the operator sets type in Figma, and a clip that
/// carried its own would be a second draft of theirs.
///
/// **Nothing here is committed.** It writes wherever it is pointed, and the flag
/// is pointed at `build/`, which is gitignored.
///
/// 🔎 **Why a half cab and not a second laser flip.** The ask was the same trick
/// at both ends, and the rig will not have it: a body that turns while its board
/// flips is a body varial, and `TorsoTurnTests.mayTurn` is pinned to
/// `[.bigspin, .halfCab]` precisely so nothing turns alone. The half cab already
/// *is* the storyboard — a frontside 180 out, two beats of back-turned bounce at
/// 2 Hz, a half cab home — so the laser flip opens and the half cab does the
/// work it was built for.
///
/// 🔎 **Why the tail is at the END and not between the tricks.** The half cab's
/// stomp carries a dust burst across its last half second, and `dustBurst` is
/// deliberately absent from `CrabPose.blend` — an unlisted channel takes the
/// incoming pose's value whole. A dissolve laid over the stomp therefore does
/// not fade the dust, it deletes it mid-puff, which reads worse than no dust at
/// all. Running the two tricks back to back and standing him out afterwards lets
/// the burst finish on its own before anything blends.
@MainActor
enum TrickLoop {

    /// A canvas shape and the whole-cell sprite side that sits in it.
    ///
    /// Every side is a multiple of 32, so a cell is a whole number of points and
    /// nothing lands on a fractional pixel — the same rule `ButtLoop` and the
    /// demo reels keep.
    struct Format {
        let name: String
        let canvas: CGSize
        let side: CGFloat
        /// Vertical nudge in whole CELLS, so he sits on the optical centre of a
        /// tall frame rather than its arithmetic one.
        let cellsDown: Int

        var cell: CGFloat { side / CGFloat(PixelBuffer.side) }
        var offsetY: CGFloat { CGFloat(cellsDown) * cell }
    }

    /// 1:1 for a post, 4:5 for a feed, 9:16 for a reel or a story.
    ///
    /// The two tall shapes share a sprite side on purpose: 896 is 28 points a
    /// cell exactly and leaves the 92-point side margin `FeedCuts` settled on,
    /// which is what keeps him from filling the frame edge to edge like a
    /// sticker. One number across both shapes is one fewer thing to drift.
    static let formats = [
        Format(name: "square", canvas: CGSize(width: 640, height: 640), side: 576, cellsDown: -1),
        Format(name: "4x5", canvas: CGSize(width: 1080, height: 1350), side: 896, cellsDown: 1),
        Format(name: "9x16", canvas: CGSize(width: 1080, height: 1920), side: 896, cellsDown: 1),
    ]

    /// Bare Claw'd and the Skater, because the backside takes the worn
    /// colourway on its own and the two read completely differently.
    static let colourways: [(name: String, costume: Costume, ground: Color)] = [
        ("clawd", .none, MarketingPalette.cream),
        ("skater", .skater, MarketingPalette.gold),
    ]

    // MARK: - The cut

    nonisolated static let flipLength = CrabAnimator.Flourish.laserFlip.duration   // 3.2
    nonisolated static let cabLength = CrabAnimator.Flourish.halfCab.duration      // 4.0
    /// 🔎 A BAR OF HIM STANDING ON IT, and it is not padding.
    ///
    /// Two things at once. The tricks come to 7.2 seconds, which is fourteen and
    /// two fifths of a beat — off the 120 BPM house grid every other cut in this
    /// repo lands on. And a clip that wraps straight off a stomp gives the eye
    /// nowhere to come down. Eight tenths carries the clip onto the grid *and*
    /// buys the landing somewhere to land, so the tail is sized to the remainder
    /// rather than to taste. Eight seconds, sixteen whole beats.
    nonisolated static let tail = 0.8
    nonisolated static var loopLength: Double { flipLength + cabLength + tail }   // 8.0

    /// The cross-dissolve across a seam. Short — a quarter second — because what
    /// it is hiding is a board swap, not a change of subject.
    nonisolated static let seamBlend = 0.25

    /// 20 fps: what a GIF can actually store (0.05s a frame exactly), and the
    /// rate at which each of the bounce's three states holds for three or four
    /// frames rather than flickering past. A twelfth rounds to 8 centiseconds
    /// and plays 4% fast.
    nonisolated static let fps = 20
    nonisolated static let frameDelay = 0.05

    nonisolated static var frameCount: Int { Int((loopLength * Double(fps)).rounded()) }

    /// When the half cab starts, and when the tail does.
    nonisolated static var cabOpensAt: Double { flipLength }                      // 3.2
    nonisolated static var tailOpensAt: Double { flipLength + cabLength }         // 7.2

    // MARK: - The stance

    /// The frozen stance both tricks ride, standing on a flat board.
    ///
    /// 🔎 Frozen, and it is load-bearing twice over. The two-argument
    /// `flourishPose` builds its base from the trick's own clock, so the base at
    /// the end of a trick is not the base at its start — a breathing, blinking
    /// idle would put a second seam at every boundary, on its own schedule, and
    /// over eight seconds there is easily time for a blink or a glint to fire
    /// inside the wrap. Handing one stance in closes that by construction.
    ///
    /// 🔎 And it carries a BOARD. `PaletteTricks` learned this one out loud:
    /// *"a board that despawns between tricks reads as a magic trick, not a
    /// skate clip."* Past a trick's duration `flourishPose` hands the base back
    /// whole, so without a board here he would stand through the tail on
    /// nothing. It is the laser flip's own deck, flat at phase 0, which also
    /// makes the wrap a pure figure blend with no prop to swap.
    static var stance: CrabPose {
        var stance = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false)
        stance.prop = .skateboardLaser
        stance.propVisibility = 1
        stance.propPhase = 0
        stance.gazeX = 0
        stance.gazeY = 0
        return stance
    }

    /// The pose `t` seconds into the loop.
    ///
    /// 🔎 Every seam is BLENDED, not cut. `CrabPose.blend` is the machinery the
    /// live view uses for exactly this: it holds the outgoing board in the ghost
    /// slot and dissolves it out while the incoming one dissolves in. The `1e-6`
    /// epsilons matter — `flourishPose` past a trick's duration hands back the
    /// base, so a seam sampled at exactly `duration` loses the trick's own board
    /// in a single frame, which is the snap the dissolve exists to prevent.
    static func pose(_ t: Double) -> CrabPose {
        let base = stance
        let flip = CrabAnimator.flourishPose(.laserFlip,
                                             at: min(t, flipLength - 1e-6), base: base)
        guard t >= cabOpensAt else { return flip }

        let cab = CrabAnimator.flourishPose(.halfCab,
                                            at: min(t - cabOpensAt, cabLength - 1e-6),
                                            base: base)
        // Into the cab: the laser's deck for the bigspin's.
        if t < cabOpensAt + seamBlend {
            return CrabPose.blend(from: flip, to: cab, u: (t - cabOpensAt) / seamBlend)
        }
        guard t >= tailOpensAt else { return cab }

        // Out of the cab and back onto the flat board he came in on. The stomp's
        // dust has already finished by here — that is what the tail is for.
        if t < tailOpensAt + seamBlend {
            let ending = CrabAnimator.flourishPose(.halfCab, at: cabLength - 1e-6, base: base)
            return CrabPose.blend(from: ending, to: base, u: (t - tailOpensAt) / seamBlend)
        }

        // 🔁 THE WRAP GETS NO DISSOLVE, and that is a finding rather than an
        // omission. The stance rides the laser flip's own deck, so there is no
        // board to swap across the join; what is left between standing and the
        // flip's first frame is `squash` and `bob`, one cell each. Both are
        // Ints. Easing an Int does not soften it — `blend`'s lerp rounds, so a
        // quarter-second dissolve emits the identical step a few frames earlier
        // and leaves two or three duplicate frames behind it, which is a
        // stutter bought at the price of a hold. You cannot ease below the
        // grid's own quantum; you can only choose when it lands.
        //
        // So it lands where it belongs: on frame zero, as the crouch. A skater
        // dropping into a trick squashes a cell in one frame every time he does
        // it, live and here — it is anticipation, not a snap, and it is the one
        // motion the no-snap rule has always exempted.
        return base
    }

    /// The pose at frame `index`, derived from the index rather than accumulated,
    /// so no float error can build across a hundred and sixty frames.
    static func pose(frame index: Int) -> CrabPose {
        pose(Double(index) / Double(fps))
    }

    // MARK: - Composition

    @ViewBuilder
    static func scene(_ pose: CrabPose, costume: Costume, ground: Color,
                      format: Format) -> some View {
        ZStack {
            ground
            PixelCanvasView(buffer: CrabRig.render(pose, costume: costume),
                            inkOverrides: CostumeStyle.blendedOverrides(from: costume,
                                                                        to: costume, u: 1),
                            seamBleed: 0)
                .frame(width: format.side, height: format.side)
                .offset(y: format.offsetY)
        }
        .frame(width: format.canvas.width, height: format.canvas.height)
    }

    // MARK: - Render

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(directory)\n".utf8))
            return false
        }

        // The pose stream is format- and costume-independent, so it is built
        // once and worn six ways.
        let poses = (0..<frameCount).map(pose(frame:))
        for (name, costume, ground) in colourways {
            for format in formats {
                var frames: [CGImage] = []
                frames.reserveCapacity(poses.count)
                for pose in poses {
                    // Opaque: an opaque ground lets ImageIO delta-code only the
                    // cells that moved, where transparency forces it to re-encode
                    // the whole sprite box every frame.
                    guard let image = SpriteImage.cgImage(
                        of: scene(pose, costume: costume, ground: ground, format: format),
                        scale: 1, isOpaque: true) else {
                        FileHandle.standardError.write(Data("a frame of \(name) failed\n".utf8))
                        return false
                    }
                    frames.append(image)
                }
                guard GifRenderer.encode(frames,
                                         to: root.appendingPathComponent("\(name)-\(format.name).gif"),
                                         frameDelay: frameDelay)
                else { return false }
            }
        }

        print("wrote \(colourways.count * formats.count) trick loops "
              + "of \(frameCount) frames to \(directory)")
        return true
    }
}
