import SwiftUI
import AppKit

/// The visual riff, rendered: one frozen mid-kickflip Claw'd and one fact
/// bubble, composed against every candidate background × bubble treatment.
///
/// `ClaudePet --render-comps <dir>` writes twelve labeled tiles; a board
/// assembles them outside. Art direction happens by looking at comps, not by
/// trading adjectives — the operator picks, and the winner gets baked across
/// the marketing set in a follow-up round. Nothing here is committed media.
///
/// Background B is the operator's original wallpaper UNQUANTISED — blurred,
/// darkened, vignetted — read from the `COMP_BG` environment variable so the
/// repo carries no path into anyone's home directory. Unset, B renders a
/// labeled placeholder rather than failing the run.
@MainActor
enum CompBoard {

    static let fact = "Anthropic has published Claude's constitution 📜"

    static let bubbles: [(tag: String, fill: Color?, text: Color?)] = [
        ("green", nil, nil),                                  // today's idle green
        ("slate", Palette.slate, .white),
        ("kraft", Palette.kraft, Palette.slate),
    ]

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch { return false }

        let wallpaper = ProcessInfo.processInfo.environment["COMP_BG"]
            .flatMap { NSImage(contentsOfFile: $0) }

        let backgrounds: [(tag: String, view: AnyView)] = [
            ("A-sky", AnyView(Backdrop(style: .sky))),
            ("B-rich", wallpaper.map { image in
                AnyView(ZStack {
                    Image(nsImage: image).resizable().scaledToFill()
                        .blur(radius: 16)
                    Color.black.opacity(0.38)
                    RadialGradient(colors: [.clear, .black.opacity(0.42)],
                                   center: .center, startRadius: 60, endRadius: 300)
                })
            } ?? AnyView(ZStack { Color.gray; Text("COMP_BG unset") })),
            ("C-gradient", AnyView(LinearGradient(
                colors: [Color(red: 0.04, green: 0.10, blue: 0.24),
                         Color(red: 0.13, green: 0.33, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing))),
            ("D-flat", AnyView(Palette.Ocean.abyss)),
        ]

        var pose = CrabAnimator.flourishPose(.kickflip, at: 1.4)
        pose.propPhase = 0

        for bg in backgrounds {
            for bubble in bubbles {
                let tile = ZStack {
                    bg.view
                    VStack(spacing: 0) {
                        ThoughtBubble(text: fact, tool: nil, mood: .idle,
                                      style: .marquee, frozenTime: 0,
                                      fillOverride: bubble.fill,
                                      textOverride: bubble.text)
                        PixelCanvasView(buffer: CrabRig.render(pose), seamBleed: 0)
                            .frame(width: 128, height: 128)
                    }
                    .offset(y: 6)
                }
                .frame(width: 340, height: 230)
                .clipped()
                let name = "comp-\(bg.tag)-\(bubble.tag).png"
                guard SpriteImage.write(SpriteImage.png(of: tile, scale: 2, isOpaque: true),
                                        to: root.appendingPathComponent(name)) else { return false }
            }
        }
        print("wrote \(backgrounds.count * bubbles.count) comps to \(root.path)")
        return true
    }
}
