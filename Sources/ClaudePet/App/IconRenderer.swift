import SwiftUI
import AppKit

/// Renders the app icon, and the DMG's window background, from the same rig the
/// app animates.
///
/// Drawing the icon separately would let it drift from the character — change
/// Claw'd's proportions and a hand-drawn icon silently becomes a picture of an
/// older pet. This composites `CrabRig.render` directly, so they cannot diverge.
///
/// Invoked with `ClaudePet --render-icon <output-dir>`.
@MainActor
enum IconRenderer {

    /// The backdrop, and the DMG window background. Chosen by the operator.
    static let backgroundHex: UInt32 = 0x262E38

    /// Sizes an `.iconset` needs. macOS wants each at 1× and 2×.
    static let iconSizes = [16, 32, 128, 256, 512]

    /// Fraction of the canvas the rounded square occupies. macOS icons since Big
    /// Sur sit inside their box with a margin rather than bleeding to the edge;
    /// filling the canvas makes an icon look oversized next to its neighbours.
    private static let plateFraction: CGFloat = 0.82

    /// Writes `AppIcon.iconset/` plus a standalone 1024px preview, and the DMG
    /// background. Returns false if any write fails.
    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        let iconset = root.appendingPathComponent("AppIcon.iconset")

        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(iconset.path): \(error)\n".utf8))
            return false
        }

        for size in iconSizes {
            for scale in [1, 2] {
                let pixels = size * scale
                let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
                guard write(plate(side: CGFloat(pixels)),
                            pixelWidth: pixels,
                            to: iconset.appendingPathComponent(name)) else { return false }
            }
        }

        // A big standalone copy, for reviewing the art and for READMEs.
        guard write(plate(side: 1024), pixelWidth: 1024,
                    to: root.appendingPathComponent("icon-1024.png")) else { return false }

        // The DMG window background: the same flat colour, no artwork, so the
        // app and the Applications symlink read clearly on top of it.
        let background = Rectangle().fill(Color(hex: backgroundHex)).frame(width: 640, height: 400)
        guard write(AnyView(background), pixelWidth: 1280,
                    to: root.appendingPathComponent("dmg-background.png")) else { return false }

        print("wrote \(iconset.path), icon-1024.png, dmg-background.png")
        return true
    }

    /// Claw'd on the rounded plate.
    private static func plate(side: CGFloat) -> AnyView {
        var pose = CrabPose()
        // No prop. The icon is the character, and the flame belongs to the
        // cooking state rather than to his identity.
        pose.mouth = .smile

        let plateSide = side * plateFraction
        // Apple's icon grid uses a corner radius near a quarter of the plate.
        let corner = plateSide * 0.235

        return AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(hex: backgroundHex))
                    .frame(width: plateSide, height: plateSide)

                PixelCanvasView(buffer: CrabRig.render(pose))
                    // Scaled against the plate, not the canvas, or he swims in
                    // whitespace. Raised from 0.78 now the flame is gone: that
                    // figure existed only to keep his shoulder clear of the
                    // plate edge while the burst occupied the grid's flank.
                    .frame(width: plateSide * 0.88, height: plateSide * 0.88)
            }
            .frame(width: side, height: side)
        )
    }

    /// Renders a view at an exact pixel width and writes it as PNG.
    ///
    /// The views above are sized in points equal to their target pixels, so
    /// rendering at scale 1 yields exactly `pixelWidth` pixels.
    private static func write(_ view: AnyView, pixelWidth: Int, to url: URL) -> Bool {
        SpriteImage.write(SpriteImage.png(of: view), to: url)
    }
}
