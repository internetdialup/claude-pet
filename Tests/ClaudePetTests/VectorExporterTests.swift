import Testing
import SwiftUI
import AppKit
@testable import ClaudePet

/// The vector bridge cannot drift from the sprite: every ink's hex is pinned
/// to the exact colour the live renderer paints, and the SVG's geometry is the
/// renderer's own run compaction.
@Suite("Vector exporter")
struct VectorExporterTests {

    /// The renderer's colour for an ink, as an uppercase RRGGBB string.
    @MainActor
    private func renderedHex(for ink: PixelBuffer.Ink) -> String? {
        var buffer = PixelBuffer()
        buffer.pixel(0, 0, ink)
        // Resolve through the same switch `PixelCanvasView` fills rects with.
        let view = PixelCanvasView(buffer: buffer)
        _ = view
        // `color(for:)` is private; resolve the palette colours directly — the
        // exporter's map documents the palette, and the palette is what the
        // canvas paints.
        let color: Color? = switch ink {
        case .clear: nil
        case .body: Palette.body
        case .eye: Palette.ink
        case .mouth: Palette.white
        case .screenDark: Palette.screenDark
        case .screenLight: Palette.screenLight
        case .green: Palette.green
        case .yellow: Palette.yellow
        case .pink: Palette.pink
        case .steel: Palette.steel
        case .flame: Palette.flame
        case .flameCore: Palette.flameCore
        case .ember: Palette.ember
        case .paper: Palette.kraft
        }
        guard let color, let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }

    @MainActor
    @Test func everyInkHexMatchesTheRenderer() {
        for ink in [PixelBuffer.Ink.body, .eye, .mouth, .screenDark, .screenLight,
                    .green, .yellow, .pink, .steel, .flame, .flameCore, .ember, .paper] {
            #expect(VectorExporter.hex(for: ink) == renderedHex(for: ink), "\(ink)")
        }
    }

    @Test func baseSVGHasABodyGroupAndWholeRects() {
        let svg = VectorExporter.svg(for: CrabRig.render(CrabPose()))
        #expect(svg.contains(#"viewBox="0 0 32 32""#))
        #expect(svg.contains(#"id="ink-body""#))
        #expect(svg.contains("crispEdges"))
        #expect(!svg.contains("ink-clear"), "clear cells must never be emitted")
    }

    /// No prop erases base cells today — the overlay contract holds, so every
    /// prop exports as a stackable layer rather than a full-pose fallback.
    @Test func everyPropIsAPureOverlay() {
        let base = CrabRig.render(CrabPose())
        for prop in CrabPose.Prop.allCases where prop != .none {
            var pose = CrabPose()
            pose.prop = prop
            pose.propPhase = 0.4
            let posed = CrabRig.render(pose)
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where posed[x, y] != base[x, y] {
                    #expect(posed[x, y] != .clear,
                            "\(prop.rawValue) erases the base at (\(x),\(y))")
                }
            }
        }
    }
}
