import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Exports one looping GIF per mood, for the README.
///
/// Frames come from `CrabAnimator.pose(mood:t:)` at fixed times rather than from
/// a screen recording, so the output is deterministic: the same commit produces
/// byte-identical GIFs, and a diff in the media folder means the animation
/// actually changed.
///
/// Uses ImageIO, which ships with macOS — no encoder dependency.
/// Invoked with `ClaudePet --render-gif <output-dir>`.
@MainActor
enum GifRenderer {

    /// 12fps. Claw'd moves in whole pixels on a coarse grid; a higher rate makes
    /// a much larger file without showing anything more.
    static let frameDelay = 1.0 / 12
    static let pixelsPerCell = 6      // 32×32 grid → 192×192 GIF

    /// How much of each mood's cycle to capture. Long enough to include the
    /// slowest thing each one does: the idle blink, the terminal scroll, the
    /// one-shot `done` hop.
    static func duration(for mood: PetMood) -> Double {
        switch mood {
        case .idle: 6.0          // covers a blink and a gaze dart
        case .thinking: 4.0
        case .working: 4.0
        case .done: 2.5
        case .needsAttention: 2.0
        case .sleeping: 4.0
        }
    }

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(root.path): \(error)\n".utf8))
            return false
        }

        for mood in PetMood.allCases {
            let frames = stride(from: 0.0, to: duration(for: mood), by: frameDelay).map { t in
                CrabRig.render(CrabAnimator.pose(mood: mood, t: t))
            }
            guard write(frames, to: root.appendingPathComponent("\(mood.rawValue).gif")) else {
                return false
            }
        }

        // The hover greeting, which has no mood of its own — it layers onto one.
        let hover = stride(from: 0.0, to: 3.0, by: frameDelay).map { t -> PixelBuffer in
            var pose = CrabAnimator.pose(mood: .idle, t: t)
            CrabAnimator.applyGreeting(elapsed: t, to: &pose)
            return CrabRig.render(pose)
        }
        guard write(hover, to: root.appendingPathComponent("hover.gif")) else { return false }

        print("wrote \(PetMood.allCases.count + 1) GIFs to \(root.path)")
        return true
    }

    /// Encodes buffers as an infinitely looping GIF with a transparent
    /// background, so it sits on any README theme.
    private static func write(_ frames: [PixelBuffer], to url: URL) -> Bool {
        guard !frames.isEmpty else { return false }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else {
            FileHandle.standardError.write(Data("could not open \(url.path)\n".utf8))
            return false
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
            ]
        ] as CFDictionary

        for buffer in frames {
            guard let image = cgImage(for: buffer) else { return false }
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            FileHandle.standardError.write(Data("could not finalize \(url.path)\n".utf8))
            return false
        }
        return true
    }

    private static func cgImage(for buffer: PixelBuffer) -> CGImage? {
        let side = CGFloat(PixelBuffer.side * pixelsPerCell)
        let renderer = ImageRenderer(
            content: PixelCanvasView(buffer: buffer).frame(width: side, height: side)
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }
}
