import SwiftUI

/// The palette-tricks sets: Claw'd at the centre of the super-graphics
/// grounds, 4:5 portrait, doing one trick per clip — the operator's
/// marketing-feed spec. `ClaudePet --render-palette-tricks <dir>` writes two
/// sets, review material, never committed:
///
/// - `costumes/`: each ground paired with ONE costume, picked for contrast
///   (sonic pops on lemon, the gundam on violet, tiger on lilac, ninja on
///   mint, the skater's terracotta on azure), across all six tricks.
/// - `bubbles/`: basic Claw'd, a trick, and a REAL line off the skate shout
///   decks in his speech bubble — a sample that says marketing copy is a
///   sample of nothing, so every line here is one he actually says. The
///   golden-board line rides an actually-golden board: the jackpot is spent,
///   not faked.
///
/// Each clip is stance → trick → stance, the bookends repeating one fixed
/// stance instant so the loop seam is zero-pixel by construction.
@MainActor
enum PaletteTricks {

    static let frameDelay = 0.1
    /// 4:5 portrait, the operator's ratio; the sprite rides a hair under
    /// centre the way their sample sheet places him.
    static let canvas = CGSize(width: 640, height: 800)
    static let spriteSide: CGFloat = 320

    static let grounds: [(name: String, color: Color)] = [
        ("lemon", MarketingPalette.lemon),
        ("violet", MarketingPalette.violet),
        ("lilac", MarketingPalette.lilac),
        ("mint", MarketingPalette.mint),
        ("azure", MarketingPalette.azure),
    ]

    /// Ground → costume, by contrast.
    static let wardrobePairs: [(ground: (name: String, color: Color), costume: Costume)] = [
        (grounds[0], .sonic), (grounds[1], .gundam), (grounds[2], .tiger),
        (grounds[3], .ninja), (grounds[4], .skater),
    ]

    static let tricks: [CrabAnimator.Flourish] =
        [.ollie, .kickflip, .varialFlip, .manual, .shoveIt, .cruise]

    /// Trick → (line, golden). All real lines; the reserved gold line pays
    /// for itself with a genuinely golden deck.
    static let bubbleCast: [(trick: CrabAnimator.Flourish, line: String, golden: Bool)] = [
        (.ollie, "Tony Clawd 900 🦅", false),
        (.kickflip, "Do a Kickflip 🛹!", false),
        (.varialFlip, "Kowbunga 🤙!", false),
        (.manual, "Sponsor me 🛹", false),
        (.shoveIt, "Kowbunga 🤙!", false),
        (.cruise, "GOLD BOARD. No notes 🏆", true),
    ]

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        let costumesDir = root.appendingPathComponent("costumes")
        let bubblesDir = root.appendingPathComponent("bubbles")
        do {
            try FileManager.default.createDirectory(at: costumesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bubblesDir, withIntermediateDirectories: true)
        } catch { return false }

        for pair in wardrobePairs {
            for trick in tricks {
                let name = "clawd-\(trick.rawValue)-\(pair.ground.name)-\(pair.costume.rawValue).gif"
                guard clip(trick: trick, ground: pair.ground.color, costume: pair.costume,
                           line: nil, golden: false,
                           to: costumesDir.appendingPathComponent(name)) else { return false }
            }
        }
        for (index, member) in bubbleCast.enumerated() {
            let ground = grounds[index % grounds.count]
            let name = "clawd-\(member.trick.rawValue)-fact-\(ground.name).gif"
            guard clip(trick: member.trick, ground: ground.color, costume: .none,
                       line: member.line, golden: member.golden,
                       to: bubblesDir.appendingPathComponent(name)) else { return false }
        }
        print("wrote \(wardrobePairs.count * tricks.count) costume loops and \(bubbleCast.count) bubble loops to \(root.path)")
        return true
    }

    private static func clip(trick: CrabAnimator.Flourish, ground: Color, costume: Costume,
                             line: String?, golden: Bool, to url: URL) -> Bool {
        let lead = 0.6, settle = 0.9
        let seconds = lead + trick.duration + settle
        let frames = Int((seconds / frameDelay).rounded())
        let stance = CrabAnimator.flourishPose(trick, at: trick.duration + 1)
        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            var pose = local < lead || local >= lead + trick.duration
                ? stance
                : CrabAnimator.flourishPose(trick, at: local - lead)
            if golden { pose.goldenBoard = true }
            guard let image = SpriteImage.cgImage(
                of: scene(pose, on: ground, costume: costume, line: line, at: local),
                scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    @ViewBuilder
    private static func scene(_ pose: CrabPose, on ground: Color, costume: Costume,
                              line: String?, at local: Double) -> some View {
        ZStack {
            ground
            if let line {
                // The sampler's bubble-over-crab stack, doubled up to the
                // portrait canvas — the scale happens before rasterising, so
                // the type stays crisp.
                VStack(spacing: 2) {
                    ThoughtBubble(text: line, tool: nil, mood: .idle,
                                  style: ActivityCoordinator.bubbleStyle(for: line),
                                  frozenTime: local)
                    PixelCanvasView(buffer: CrabRig.render(pose, costume: costume),
                                    inkOverrides: CostumeStyle.blendedOverrides(
                                        from: costume, to: costume, u: 1),
                                    seamBleed: 0)
                        .frame(width: 160, height: 160)
                }
                .scaleEffect(2)
                .offset(y: 12)
            } else {
                PixelCanvasView(buffer: CrabRig.render(pose, costume: costume),
                                inkOverrides: CostumeStyle.blendedOverrides(
                                    from: costume, to: costume, u: 1),
                                seamBleed: 0)
                    .frame(width: spriteSide, height: spriteSide)
                    .offset(y: 34)   // a hair under centre, per the operator's sheet
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}
