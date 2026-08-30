import SwiftUI

/// Single-costume sample clips, for choosing what the marketing uses next.
///
/// One GIF per costume: the character on the sky, his own effect firing ON
/// CAMERA, a real line in the bubble, and one flourish. Invoked with
/// `ClaudePet --render-samples <dir>`; the output is review material, not a
/// committed asset — which is why it has no entry in the README's media set.
///
/// The costume effects ride dice on the wall of `t` (`CrabCostume`'s
/// `effectWindow`, 97-family salts), so each sample's clock does not start at
/// zero: `t0` is chosen so the effect's first reliable window lands about two
/// seconds in. Those instants were solved from the same splitmix64 the app
/// rolls — the ninja's shuriken, for one, first flies at t=90, and a clip
/// opening at zero would show a costume and no effect.
@MainActor
enum CostumeSampler {

    static let seconds = 6.0
    static let frameDelay = 0.1

    /// costume · where its clock opens · flourish and its onset within the
    /// clip · what he says. Every line is a REAL one — facts from the pools,
    /// shouts from the skate deck — because a sample that says marketing copy
    /// is a sample of nothing.
    static let cast: [(costume: Costume, t0: Double,
                       flourish: CrabAnimator.Flourish, onset: Double,
                       line: String)] = [
        (.ninja,        88.0, .wave,       3.4, "Red-teaming a model means trying hard to make it misbehave 😈"),
        (.gundam,       10.0, .wiggle,     3.6, "Anthropic's AI Safety Levels are modeled on biosafety levels"),
        (.sonic,         3.0, .scuttle,    3.4, "Claude Code launched as a coding agent in your terminal"),
        (.frankenstein, 33.0, .wiggle,     3.6, "Constitutional AI trains a model against written principles"),
        (.retroBlack,   31.0, .stretch,    3.6, "Claude is reachable by API, not only a chat window"),
        (.matrix,        4.0, .lookAround, 3.2, "A token can be a whole word or just a piece of one"),
        (.white,         4.0, .jump,       3.4, "Anthropic was founded in 2021 🧡"),
        (.tiger,         4.0, .stretch,    3.2, "Temperature controls how much a model's output varies"),
        (.arcade,        4.0, .kickflip,   1.6, "Do a Kickflip 🛹!"),
    ]

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(root.path): \(error)\n".utf8))
            return false
        }
        for member in cast {
            let frames = Int((seconds / frameDelay).rounded())
            var images: [CGImage] = []
            for frame in 0..<frames {
                let local = Double(frame) * frameDelay
                guard let image = SpriteImage.cgImage(of: scene(member, at: local),
                                                      scale: 2, isOpaque: true)
                else { return false }
                images.append(image)
            }
            let name = "sample-\(member.costume.rawValue).gif"
            guard GifRenderer.encode(images, to: root.appendingPathComponent(name),
                                     frameDelay: frameDelay) else { return false }
        }
        print("wrote \(cast.count) samples to \(root.path)")
        return true
    }

    @ViewBuilder
    private static func scene(_ member: (costume: Costume, t0: Double,
                                         flourish: CrabAnimator.Flourish, onset: Double,
                                         line: String),
                              at local: Double) -> some View {
        // The effect clock runs from t0; the flourish is spliced at its onset
        // the way the wardrobe strip does it, over the STILL idle pose so the
        // loop point does not catch a breath mid-cycle.
        let t = member.t0 + local
        let inFlourish = local >= member.onset && local < member.onset + member.flourish.duration
        let pose = inFlourish
            ? CrabAnimator.flourishPose(member.flourish, at: local - member.onset)
            : CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
        // The costume effects read `propPhase` as their clock; splicing the
        // flourish must not reset it or the sampled window walks off camera.
        var staged = pose
        let _ = { staged.propPhase = t }()

        ZStack {
            Backdrop(style: .sky)
            VStack(spacing: 0) {
                ThoughtBubble(text: member.line, tool: nil, mood: .idle,
                              style: ActivityCoordinator.bubbleStyle(for: member.line),
                              frozenTime: local)
                PixelCanvasView(
                    buffer: CrabRig.render(staged, costume: member.costume),
                    inkOverrides: CostumeStyle.blendedOverrides(from: member.costume,
                                                               to: member.costume, u: 1),
                    seamBleed: 0)
                    .frame(width: 128, height: 128)
            }
            .offset(y: 8)
        }
        .frame(width: 300, height: 200)
        .background(Palette.Ocean.abyss)
    }
}
