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

                Text("service")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: labelHeight, alignment: .leading)
                ForEach(Array(ServiceGlyph.allCases.enumerated()), id: \.offset) { _, glyph in
                    HStack(spacing: 6) {
                        ServiceGlyphPreview(glyph: glyph)
                            .frame(width: cell, height: cell)
                            .background(Color.white.opacity(0.04))
                        Text(glyph.rawValue)
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

            // The wardrobe, worn across contrasting moods — a costume that only
            // works standing still is not finished.
            VStack(alignment: .leading, spacing: 6) {
                Text("costumes")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(height: labelHeight, alignment: .leading)
                let costumes = Costume.allCases.filter { $0 != .none }
                ForEach(Array(costumes.enumerated()), id: \.offset) { _, costume in
                    HStack(spacing: 6) {
                        ForEach(Array([(PetMood.idle, 0.36), (.working, 3.0),
                                       (.done, 0.05), (.sleeping, 0.6)].enumerated()),
                                id: \.offset) { _, sample in
                            CostumePreview(costume: costume, mood: sample.0, t: sample.1)
                                .frame(width: cell, height: cell)
                                .background(Color.white.opacity(0.04))
                        }
                        Text(costume.rawValue)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
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

/// One service glyph at full presence on a neutral pose — the art-review row.
private struct ServiceGlyphPreview: View {
    let glyph: ServiceGlyph

    var body: some View {
        var pose = CrabPose()
        pose.serviceGlyph = glyph
        pose.serviceGlyphVisibility = 1
        return PixelCanvasView(buffer: CrabRig.render(pose))
    }
}

/// One costume on a mood pose, worn at full strength — the settled state, not
/// the dissolve.
private struct CostumePreview: View {
    let costume: Costume
    let mood: PetMood
    let t: Double

    var body: some View {
        PixelCanvasView(buffer: CrabRig.render(CrabAnimator.pose(mood: mood, t: t),
                                               costume: costume),
                        inkOverrides: CostumeStyle.blendedOverrides(from: costume,
                                                                    to: costume,
                                                                    u: 1))
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
