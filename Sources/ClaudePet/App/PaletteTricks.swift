import SwiftUI

/// The palette-tricks set: Claw'd alone at the centre of each super-graphics
/// ground, doing one trick per clip, no text — the operator's 4:5 portrait
/// spec for the marketing feed. `ClaudePet --render-palette-tricks <dir>`
/// writes every (ground × trick) pairing. Review material, never committed.
///
/// Each clip is stance → trick → stance: the bookend frames repeat ONE fixed
/// stance instant (not a breathing idle), so the loop seam is zero-pixel by
/// construction — the solo sampler's rule, bought the cheap way.
@MainActor
enum PaletteTricks {

    static let frameDelay = 0.1
    /// 4:5 portrait, the operator's ratio. The sprite is 320pt — cells stay
    /// whole at every scale in play — centred, riding a hair above middle
    /// the way their sample sheet places him.
    static let canvas = CGSize(width: 640, height: 800)
    static let spriteSide: CGFloat = 320

    static let grounds: [(name: String, color: Color)] = [
        ("lemon", MarketingPalette.lemon),
        ("violet", MarketingPalette.violet),
        ("lilac", MarketingPalette.lilac),
        ("mint", MarketingPalette.mint),
        ("azure", MarketingPalette.azure),
    ]

    static let tricks: [CrabAnimator.Flourish] =
        [.ollie, .kickflip, .varialFlip, .manual, .shoveIt, .cruise]

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch { return false }

        for ground in grounds {
            for trick in tricks {
                let lead = 0.6, settle = 0.9
                let seconds = lead + trick.duration + settle
                let frames = Int((seconds / frameDelay).rounded())
                // One fixed stance instant for both bookends — past the
                // trick's own window, so it is the plain standing pose.
                let stance = CrabAnimator.flourishPose(trick, at: trick.duration + 1)
                var images: [CGImage] = []
                for frame in 0..<frames {
                    let local = Double(frame) * frameDelay
                    let pose: CrabPose
                    if local < lead || local >= lead + trick.duration {
                        pose = stance
                    } else {
                        pose = CrabAnimator.flourishPose(trick, at: local - lead)
                    }
                    guard let image = SpriteImage.cgImage(of: scene(pose, on: ground.color),
                                                          scale: 1, isOpaque: true)
                    else { return false }
                    images.append(image)
                }
                let name = "clawd-\(trick.rawValue)-\(ground.name).gif"
                guard GifRenderer.encode(images, to: root.appendingPathComponent(name),
                                         frameDelay: frameDelay) else { return false }
            }
        }
        print("wrote \(grounds.count * tricks.count) palette-trick loops to \(root.path)")
        return true
    }

    @ViewBuilder
    private static func scene(_ pose: CrabPose, on ground: Color) -> some View {
        ZStack {
            ground
            PixelCanvasView(buffer: CrabRig.render(pose), seamBleed: 0)
                .frame(width: spriteSide, height: spriteSide)
                .offset(y: 34)   // he sits a hair under centre, per the operator's sheet
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}
