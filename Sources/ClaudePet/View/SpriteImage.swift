import SwiftUI
import AppKit

/// Turns a `PixelBuffer` into an image.
///
/// The icon renderer, the GIF renderer and the contact sheet each had their own
/// copy of the same six lines — build an `ImageRenderer`, set `scale = 1` and
/// `isOpaque = false`, pull an `nsImage`, round-trip through
/// `NSBitmapImageRep` for PNG. Three copies meant three places to get the
/// transparency flag wrong.
@MainActor
public enum SpriteImage {

    /// Renders `buffer` at `pixelsPerCell` points per sprite pixel.
    ///
    /// - Parameter tint: overrides the body colour only, for rainbow mode.
    public static func cgImage(_ buffer: PixelBuffer,
                               pixelsPerCell: Int,
                               tint: Color? = nil) -> CGImage? {
        renderer(buffer, pixelsPerCell: pixelsPerCell, tint: tint).cgImage
    }

    /// PNG data, transparent background.
    public static func png(_ buffer: PixelBuffer,
                           pixelsPerCell: Int,
                           tint: Color? = nil) -> Data? {
        png(of: PixelCanvasView(buffer: buffer, bodyTint: tint)
            .frame(width: side(pixelsPerCell), height: side(pixelsPerCell)))
    }

    /// A `CGImage` for an arbitrary view — the missing twin of `png(of:)`.
    ///
    /// The composed scenes render hundreds of frames; routing each through
    /// `png(of:)` would round-trip it via TIFF and PNG only for the GIF encoder
    /// to decode it again.
    ///
    /// Draws into a context of our own rather than reading `ImageRenderer`'s
    /// `cgImage`, which builds one with the machine's text-rasterisation
    /// defaults — including the font smoothing that made `desktop.gif` differ
    /// on every run.
    ///
    /// `scale` is still set on the renderer as well as passed to `render`.
    /// Vector content only needs the context transform, but the bitmap glyphs
    /// in Apple Color Emoji are chosen by the renderer's own scale: leave it at
    /// 1 and the eyes in "Plan's ready 👀" come back rasterised for a 320-point
    /// canvas and stretched over a 640-pixel one.
    ///
    /// - Parameter isOpaque: true for a scene that fills its own frame, which
    ///   keeps the encoder off the transparent palette index entirely. The
    ///   `PixelBuffer` overload below deliberately does not expose this — it is
    ///   always transparent, and that is what keeps the committed loops
    ///   byte-identical.
    public static func cgImage(of view: some View,
                               scale: CGFloat = 1,
                               isOpaque: Bool = false) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = isOpaque

        var image: CGImage?
        renderer.render(rasterizationScale: scale) { size, draw in
            let width = Int((size.width * scale).rounded())
            let height = Int((size.height * scale).rounded())
            guard width > 0, height > 0,
                  let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: (isOpaque ? CGImageAlphaInfo.noneSkipFirst
                                          : CGImageAlphaInfo.premultipliedFirst).rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return }
            pinTextRasterisation(context)
            context.scaleBy(x: scale, y: scale)
            draw(context)
            image = context.makeImage()
        }
        return image
    }

    /// Pins the text-rasterisation switches Core Graphics would otherwise pick
    /// per context.
    ///
    /// Font smoothing is the one that bit. It is applied out of a
    /// process-global glyph cache, and a glyph's first few draws rasterise by a
    /// different route than every draw after — so a 275-frame clip crosses that
    /// boundary partway through, and *which* frame crosses it moves between
    /// processes. One frame of `desktop.gif` came out different on every run,
    /// and because the GIF quantiser builds its palette from the whole clip, a
    /// few changed edge samples spread as a palette shift across the beat.
    /// Turning it off costs nothing visible at 2× on flat colour and makes the
    /// raster independent of how many frames have already been drawn.
    ///
    /// Subpixel positioning and quantization are pinned at their current
    /// values alongside it — not because they drifted, but because they are
    /// read from the machine, and a committed asset should not depend on the
    /// operator's font settings.
    private static func pinTextRasterisation(_ context: CGContext) {
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(true)
        context.setShouldSubpixelQuantizeFonts(true)
    }

    /// PNG data for an arbitrary view, sized in points equal to target pixels.
    ///
    /// Used by the icon and contact-sheet renderers, which compose more than a
    /// bare sprite.
    public static func png(of view: some View, scale: CGFloat = 1,
                           isOpaque: Bool = false) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = isOpaque
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes PNG data to `url`, reporting failure rather than throwing — every
    /// caller here is a command-line renderer that wants a clean exit code.
    @discardableResult
    public static func write(_ data: Data?, to url: URL) -> Bool {
        guard let data else {
            FileHandle.standardError.write(Data("render failed for \(url.lastPathComponent)\n".utf8))
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            FileHandle.standardError.write(Data("write failed for \(url.path): \(error)\n".utf8))
            return false
        }
    }

    private static func side(_ pixelsPerCell: Int) -> CGFloat {
        CGFloat(PixelBuffer.side * pixelsPerCell)
    }

    private static func renderer(_ buffer: PixelBuffer,
                                 pixelsPerCell: Int,
                                 tint: Color?) -> ImageRenderer<some View> {
        let renderer = ImageRenderer(
            content: PixelCanvasView(buffer: buffer, bodyTint: tint)
                .frame(width: side(pixelsPerCell), height: side(pixelsPerCell))
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer
    }
}
