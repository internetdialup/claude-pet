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

    static let frameDelay = 0.1

    /// A sample's length is its LINE's: long enough for one whole marquee
    /// cycle plus a beat of gap, rounded to a whole frame, and handed to the
    /// bubble as `loopSeconds` so the wrap closes seamlessly. A plain line
    /// needs no cycle and gets the six-second floor. This is the operator's
    /// "size clips to the scroll" call, applied per clip.
    static func seconds(for line: String) -> Double {
        guard ActivityCoordinator.bubbleStyle(for: line) == .marquee else { return 6.0 }
        let travel = Double(MarqueeText.measure(line) / MarqueeText.speed)
        return max(6.0, ((travel + 1.2) * 10).rounded(.up) / 10)
    }

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
            let frames = Int((seconds(for: member.line) / frameDelay).rounded())
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

    // MARK: - The solos

    /// The trick, alone: four solo kickflips, one per costume the operator
    /// named. `ClaudePet --render-solos <dir>`.
    ///
    /// A beat of stillness, the flip, the landing — and then the shout, EASED
    /// in and out. The operator chose shout-over-purity knowing a bubble pop
    /// rides the loop; the easing is what reconciles that choice with the
    /// no-snap doctrine: the bubble rises over 0.28s at the landing and is
    /// gone again by the final frame, so frame 0 and frame N are both
    /// bubble-free and the only seam is the still pose meeting itself.
    static let soloCast: [Costume] = [.none, .ninja, .retroBlack, .gundam]
    static let soloSeconds = 5.6
    static let soloShout = "Tony Clawd 900 🦅"

    static func renderSolos(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(root.path): \(error)\n".utf8))
            return false
        }
        for costume in soloCast {
            let frames = Int((soloSeconds / frameDelay).rounded())
            var images: [CGImage] = []
            for frame in 0..<frames {
                guard let image = SpriteImage.cgImage(of: soloScene(costume,
                                                                   at: Double(frame) * frameDelay),
                                                      scale: 2, isOpaque: true)
                else { return false }
                images.append(image)
            }
            guard GifRenderer.encode(images,
                                     to: root.appendingPathComponent("solo-\(costume.rawValue).gif"),
                                     frameDelay: frameDelay) else { return false }
        }
        print("wrote \(soloCast.count) solos to \(root.path)")
        return true
    }

    @ViewBuilder
    private static func soloScene(_ costume: Costume, at local: Double) -> some View {
        let flipAt = 0.6
        let landing = flipAt + CrabAnimator.Flourish.kickflip.duration   // 3.4
        let inFlip = local >= flipAt && local < landing
        let pose = inFlip
            ? CrabAnimator.flourishPose(.kickflip, at: local - flipAt)
            : CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
        // Rises at the landing, gone by 5.5 — see the doc above. `endedAt` is
        // chosen so the release (0.45s) completes before the final frame.
        let shout = Ease.amount(now: local, since: landing, endedAt: 5.0)

        ZStack {
            Backdrop(style: .sky)
            VStack(spacing: 0) {
                ThoughtBubble(text: soloShout, tool: nil, mood: .idle,
                              style: .plain, frozenTime: 0)
                    .opacity(shout)
                PixelCanvasView(
                    buffer: CrabRig.render(pose, costume: costume),
                    inkOverrides: CostumeStyle.blendedOverrides(from: costume, to: costume, u: 1),
                    seamBleed: 0)
                    .frame(width: 128, height: 128)
            }
            .offset(y: 8)
        }
        .frame(width: 280, height: 200)
        .background(Palette.Ocean.abyss)
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
                              frozenTime: local,
                              loopSeconds: seconds(for: member.line))
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
