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

    static func duration(for mood: PetMood) -> Double { mood.style.clipSeconds }

    /// Large transparent assets for marketing, rendered from the rig rather than
    /// screen-captured — so they are crisp at any size and reproducible.
    ///
    /// Not committed: these run to several MB and nobody cloning the repo needs
    /// them. `build/marketing/` is gitignored.
    static func renderMarketing(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch { return false }

        let big = 12   // 32 × 12 = 384px

        // One loop per state.
        for mood in PetMood.allCases {
            let frames = stride(from: 0.0, to: duration(for: mood), by: frameDelay).map {
                CrabRig.render(CrabAnimator.pose(mood: mood, t: $0))
            }
            guard write(frames, to: root.appendingPathComponent("state-\(mood.rawValue).gif"),
                        pixelsPerCell: big) else { return false }
        }

        // One loop walking every state in sequence.
        var tour: [PixelBuffer] = []
        for mood in PetMood.allCases {
            tour += stride(from: 0.0, to: min(3.0, duration(for: mood)), by: frameDelay).map {
                CrabRig.render(CrabAnimator.pose(mood: mood, t: $0))
            }
        }
        guard write(tour, to: root.appendingPathComponent("state-tour.gif"), pixelsPerCell: big)
        else { return false }

        // The party, on its own.
        let rainbow = stride(from: 0.0, to: CrabView.rainbowDuration, by: frameDelay).map {
            CrabRig.render(CrabAnimator.pose(mood: .done, t: $0))
        }
        guard write(rainbow, to: root.appendingPathComponent("rainbow.gif"),
                    pixelsPerCell: big,
                    tint: { CrabView.rainbowTint(elapsed: Double($0) * frameDelay) })
        else { return false }

        // Stills: every state, and every prop.
        for mood in PetMood.allCases {
            guard SpriteImage.write(
                SpriteImage.png(CrabRig.render(CrabAnimator.pose(mood: mood, t: 0.4)),
                                pixelsPerCell: 24),
                to: root.appendingPathComponent("still-\(mood.rawValue).png")) else { return false }
        }
        for prop in CrabPose.Prop.allCases where prop != .none {
            var pose = CrabPose()
            pose.prop = prop
            pose.propPhase = 0.8
            guard SpriteImage.write(
                SpriteImage.png(CrabRig.render(pose), pixelsPerCell: 24),
                to: root.appendingPathComponent("prop-\(prop.rawValue).png")) else { return false }
        }

        print("wrote marketing assets to \(root.path)")
        return true
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
            CrabAnimator.applyGreeting(elapsed: t, seed: 1, to: &pose)
            return CrabRig.render(pose)
        }
        guard write(hover, to: root.appendingPathComponent("hover.gif")) else { return false }

        // Each hover variant gets its own loop, so a change to one can be seen
        // rather than inferred.
        for (index, variant) in CrabAnimator.Greeting.allCases.enumerated() {
            // Find a seed that selects this variant; the picker is a hash, so
            // scanning is simpler and more honest than inverting it.
            guard let seed = (0..<500).first(where: { CrabAnimator.greeting(forSeed: $0) == variant })
            else { continue }
            let frames = stride(from: 0.0, to: 3.0, by: frameDelay).map { t -> PixelBuffer in
                var pose = CrabAnimator.pose(mood: .idle, t: t)
                CrabAnimator.applyGreeting(elapsed: t, seed: seed, to: &pose)
                return CrabRig.render(pose)
            }
            _ = index
            guard write(frames, to: root.appendingPathComponent("hover-\(variant).gif")) else { return false }
        }

        print("wrote \(PetMood.allCases.count + 1) GIFs to \(root.path)")
        return true
    }

    /// Encodes buffers as an infinitely looping GIF with a transparent
    /// background, so it sits on any README theme.
    /// - Parameter tint: an optional body colour per frame index, for rainbow mode.
    private static func write(_ frames: [PixelBuffer],
                              to url: URL,
                              pixelsPerCell: Int = pixelsPerCell,
                              tint: ((Int) -> Color?)? = nil) -> Bool {
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

        for (index, buffer) in frames.enumerated() {
            guard let image = SpriteImage.cgImage(buffer, pixelsPerCell: pixelsPerCell,
                                                  tint: tint?(index))
            else { return false }
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            FileHandle.standardError.write(Data("could not finalize \(url.path)\n".utf8))
            return false
        }
        return true
    }
}
