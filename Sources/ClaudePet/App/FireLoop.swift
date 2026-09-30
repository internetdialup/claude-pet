import AppKit
import SwiftUI

/// 🔥 **The fire loop — he thinks, he catches fire, he cools off, forever.**
///
/// The operator, for X: *"a gif of claude pet thinking and then going on fire
/// on a nice blue bg in 16:9 ratio"* — then, off mocked stills of real frames:
/// flat cobalt, think → ignite → cool as a seamless loop, 1600×900, no type.
///
/// It is the `TrickLoop` recipe with moods instead of tricks: a pure pose
/// stream, the rig's own `CrabPose.blend` across every change of state (the
/// same machinery the live view crossfades moods with — the flame dissolves in
/// and out through the blend's prop ghost), and an opaque flat ground so the
/// encoder delta-codes only the cells that move.
///
/// **No type, deliberately** — the operator sets type in the post or in Figma.
///
/// **Nothing here is committed.** It writes wherever it is pointed, and the flag
/// is pointed at `build/`, which is gitignored.
@MainActor
enum FireLoop {

    /// 16:9 for X. The sprite side is a multiple of 32 — 24 points a cell — so
    /// no cell lands on a fractional pixel; nudged three cells down so the
    /// fire-to-feet mass sits on the frame's optical centre, not above it.
    static let canvas = CGSize(width: 1600, height: 900)
    static let side: CGFloat = 768
    static let cellsDown = 3
    static var cell: CGFloat { side / CGFloat(PixelBuffer.side) }

    /// The operator's pick off the mocks: the marketing cobalt, flat.
    static let ground = MarketingPalette.cobalt

    // MARK: - The cut

    /// Eight seconds — sixteen beats on the 120 BPM house grid every cut in
    /// this repo lands on — at 20 fps, what a GIF actually stores (0.05s a
    /// frame exactly).
    nonisolated static let loopLength = 8.0
    nonisolated static let fps = 20
    nonisolated static let frameDelay = 0.05
    nonisolated static var frameCount: Int { Int((loopLength * Double(fps)).rounded()) }

    /// Thinking until here, then the flame catches.
    nonisolated static let ignitesAt = 2.5
    /// How long the catch — and the cooling — takes: one beat, a whole second
    /// of crossfade, so the flame visibly dissolves in rather than appearing.
    nonisolated static let catchLength = 1.0
    /// On fire until here, then he cools back into thinking.
    nonisolated static let coolsAt = 6.5
    /// The heat wave up his shell: the cooking cascade's own 2.4s window and
    /// banding, driven here rather than left to its dice — which never fire in
    /// an eight-second clip — starting once the flame is fully lit.
    nonisolated static let heatAt = 3.8

    /// The thinking spell's clock at loop time `t`.
    ///
    /// 🔎 THE SEAM. The opening stretch runs on `t + 2` and the closing one on
    /// `t − 6`, so t = 8 and t = 0 are the same thinking instant and the wrap
    /// is a continuation, not a cut. Both land inside 0.5…4.5s of the thinking
    /// clock — clear of the prop's 20s sparkles-then-star swap, clear of the
    /// prop dissolve's fade-in edge, and nowhere near a cycle-0 sentinel.
    static func thinkingClock(_ t: Double) -> Double {
        t < ignitesAt + catchLength ? t + 2.0 : t - 6.0
    }

    static func thinking(_ t: Double) -> CrabPose {
        CrabAnimator.pose(mood: .thinking, t: thinkingClock(t), flourishes: false)
    }

    /// Cooking on its own clock, from the moment it starts to catch, with the
    /// heat wave laid in.
    static func cooking(_ t: Double) -> CrabPose {
        var pose = CrabAnimator.pose(mood: .cooking, t: max(0, t - ignitesAt), flourishes: false)
        let since = t - heatAt
        if since >= 0, since < 2.4 {
            pose.heat = Ease.window(since, duration: 2.4, edge: 0.4)
            pose.heatPhase = since / 1.2
        }
        return pose
    }

    /// The pose `t` seconds into the loop. Every change of state is a blend —
    /// the eyes switch at its midpoint, the arms and gaze ease, the flame
    /// dissolves through the prop ghost — so nothing arrives in one frame.
    static func pose(_ t: Double) -> CrabPose {
        if t < ignitesAt { return thinking(t) }
        if t < ignitesAt + catchLength {
            let u = Ease.smoothstep((t - ignitesAt) / catchLength)
            return CrabPose.blend(from: thinking(t), to: cooking(t), u: u)
        }
        if t < coolsAt { return cooking(t) }
        if t < coolsAt + catchLength {
            let u = Ease.smoothstep((t - coolsAt) / catchLength)
            return CrabPose.blend(from: cooking(t), to: thinking(t), u: u)
        }
        return thinking(t)
    }

    /// The pose at frame `index`, derived from the index rather than
    /// accumulated, so no float error can build across the loop.
    static func pose(frame index: Int) -> CrabPose {
        pose(Double(index) / Double(fps))
    }

    // MARK: - Composition

    @ViewBuilder
    static func scene(_ pose: CrabPose) -> some View {
        ZStack {
            ground
            PixelCanvasView(buffer: CrabRig.render(pose),
                            inkOverrides: CostumeStyle.blendedOverrides(from: .none, to: .none, u: 1),
                            seamBleed: 0)
                .frame(width: side, height: side)
                .offset(y: CGFloat(cellsDown) * cell)
        }
        .frame(width: canvas.width, height: canvas.height)
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
        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            // Opaque: a flat opaque ground lets ImageIO delta-code only the
            // cells that moved, which is what keeps a 1600×900 loop small.
            guard let image = SpriteImage.cgImage(of: scene(pose(frame: index)),
                                                  scale: 1, isOpaque: true) else {
                FileHandle.standardError.write(Data("frame \(index) failed\n".utf8))
                return false
            }
            frames.append(image)
        }
        let name = "claude-pet-fire-\(Int(canvas.width))x\(Int(canvas.height)).gif"
        guard GifRenderer.encode(frames, to: root.appendingPathComponent(name),
                                 frameDelay: frameDelay) else { return false }
        print("wrote \(name): \(frameCount) frames, \(loopLength)s, to \(directory)")
        return true
    }
}
