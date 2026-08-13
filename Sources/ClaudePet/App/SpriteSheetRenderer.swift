import SwiftUI
import AppKit

/// Renders every mood to a single PNG contact sheet.
///
/// Exists because "the animation looks right" is not a claim you can make from
/// reading code — screenshots prove rendering. Invoked with `ClaudePet --render-sheet <path.png>`.
@MainActor
enum SpriteSheetRenderer {

    /// Sampled at several points in each mood's cycle, so a still sheet shows
    /// motion rather than one arbitrary frame.
    private static let sampleTimes: [Double] = [0.0, 0.18, 0.36, 0.55]

    static func renderSheet(to path: String, scale: CGFloat = 4) -> Bool {
        let moods = PetMood.allCases
        let cell = CGFloat(PixelBuffer.side)
        let labelHeight: CGFloat = 16

        let sheet = HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(moods, id: \.self) { mood in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mood.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(height: labelHeight, alignment: .leading)
                        HStack(spacing: 6) {
                            ForEach(Array(sampleTimes.enumerated()), id: \.offset) { _, t in
                                CrabView(mood: mood, frozenTime: t)
                                    .frame(width: cell, height: cell)
                                    .background(Color.white.opacity(0.04))
                            }
                        }
                    }
                }
            }

            // Every prop, and the jump sampled across its arc. Both are new
            // enough that reviewing them as an image is the only real check.
            VStack(alignment: .leading, spacing: 6) {
                Text("props")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: labelHeight, alignment: .leading)
                let props = CrabPose.Prop.allCases.filter { $0 != .none }
                ForEach(Array(props.enumerated()), id: \.offset) { _, prop in
                    HStack(spacing: 6) {
                        ForEach([0.4, 1.1], id: \.self) { phase in
                            PropPreview(prop: prop, phase: phase)
                                .frame(width: cell, height: cell)
                                .background(Color.white.opacity(0.04))
                        }
                        Text(prop.rawValue)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Text("jump")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: labelHeight, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach([0.02, 0.2, 0.45, 0.7, 0.88], id: \.self) { progress in
                        JumpPreview(progress: progress)
                            .frame(width: cell, height: cell)
                            .background(Color.white.opacity(0.04))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: 0x1A1A19))

        return SpriteImage.write(SpriteImage.png(of: sheet, scale: scale),
                                 to: URL(fileURLWithPath: path))
    }
}

/// One prop on a neutral idle pose, so the prop itself is what is being judged.
private struct PropPreview: View {
    let prop: CrabPose.Prop
    let phase: Double

    var body: some View {
        var pose = CrabPose()
        pose.prop = prop
        pose.propPhase = phase
        return PixelCanvasView(buffer: CrabRig.render(pose))
    }
}

/// The jump flourish at a given point in its arc.
private struct JumpPreview: View {
    let progress: Double

    var body: some View {
        // `flourish(at:)` picks by cycle, so drive `apply` through the same
        // shape the animator uses rather than re-deriving the arc here.
        let pose = CrabAnimator.jumpPose(progress: progress)
        return PixelCanvasView(buffer: CrabRig.render(pose))
    }
}
