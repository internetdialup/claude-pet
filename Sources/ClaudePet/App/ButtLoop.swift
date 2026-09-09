import AppKit
import SwiftUI

/// 🍑 **The loop — one held second, cut to repeat forever.**
///
/// The operator asked for a looping GIF of the bounce, no type, to take into
/// Figma and out to Instagram. That is a smaller thing than a reel and it gets
/// a smaller renderer: no shot list, no beat sidecar, no cuts. One window, three
/// shapes, two colourways.
///
/// **No type, deliberately** — the operator sets type in Figma, and a clip that
/// carried its own would be a second draft of theirs.
///
/// **Nothing here is committed.** It writes wherever it is pointed, and the flag
/// is pointed at `build/`, which is gitignored. The published surface of the
/// jiggle is `docs/media/flourish-halfCab.gif`, which the ordinary GIF renderer
/// already writes from `allCases`.
///
/// 🔎 **Why this window loops, and no other would.** Across `progress` 0.375 →
/// 0.625 of the half cab — the held second — `torsoTurn` is pinned at 0.5, the
/// prop is pinned at phase 0.5, the hold's own bob is a single half-sine that
/// returns to nought, and the bounce is exactly two whole cycles. So the frame
/// after the last is the first, with nothing to cross-fade and no cut to hide.
/// Take a window a beat wider in either direction and it stops being true: the
/// landing before it carries a dust burst, and the crouch after it a squash.
@MainActor
enum ButtLoop {

    /// A canvas shape and the whole-cell sprite side that sits in it.
    ///
    /// Every side is a multiple of 32, so a cell is a whole number of points and
    /// nothing lands on a fractional pixel — the same rule the demo reels keep.
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

    /// 1:1 for a post, 9:16 for a reel or a story, 16:9 for a slide.
    static let formats = [
        Format(name: "square", canvas: CGSize(width: 512, height: 512), side: 448, cellsDown: -1),
        Format(name: "vertical", canvas: CGSize(width: 540, height: 960), side: 512, cellsDown: 0),
        Format(name: "wide", canvas: CGSize(width: 640, height: 360), side: 320, cellsDown: -1),
    ]

    /// Bare Claw'd and the Skater, because the backside takes the worn
    /// colourway on its own and the two read completely differently.
    static let colourways: [(name: String, costume: Costume, ground: Color)] = [
        ("clawd", .none, MarketingPalette.cream),
        ("skater", .skater, MarketingPalette.gold),
    ]

    // MARK: - The window

    nonisolated static let openAt = 0.375
    nonisolated static let closeAt = 0.625
    /// 20 fps: what the GIF can actually store (0.05s a frame exactly), and
    /// twenty frames across the second — enough that each of the bounce's three
    /// states holds for three or four frames rather than flickering past.
    nonisolated static let fps = 20
    nonisolated static let frameDelay = 0.05

    static var frameCount: Int {
        Int(((closeAt - openAt) * CrabAnimator.Flourish.halfCab.duration
             * Double(fps)).rounded())
    }

    /// The pose at frame `index` of the loop.
    ///
    /// Half-open by construction: frame 0 is `openAt` and the last frame stops a
    /// frame short of `closeAt`, so the clip hands back to its own first frame
    /// instead of repeating it.
    static func pose(_ index: Int) -> CrabPose {
        let span = closeAt - openAt
        let progress = openAt + span * Double(index) / Double(frameCount)
        return CrabAnimator.flourishPose(.halfCab,
                                         at: progress * CrabAnimator.Flourish.halfCab.duration)
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

        let poses = (0..<frameCount).map(pose)
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

        print("wrote \(colourways.count * formats.count) looping clips "
              + "of \(frameCount) frames to \(directory)")
        return true
    }
}
