import Testing
import Foundation
import CoreGraphics
import AppKit
import SwiftUI
@testable import ClaudePet

/// The sizzle reel's contract: the sums are exact, the must-shows are
/// protected, the dice bases actually fire, and the renders are
/// deterministic. No fixture touches anything real.
@Suite("Sizzle script")
@MainActor
struct SizzleScriptTests {

    @Test("The master chapters sum to exactly forty-five seconds")
    func masterSums() {
        let total = SizzleScript.Chapter.allCases
            .reduce(0.0) { $0 + (SizzleScript.masterSeconds[$1] ?? 0) }
        #expect(total == 45.0)
        #expect(SizzleScript.masterSeconds.count == SizzleScript.Chapter.allCases.count,
                "every chapter must have a master duration")
    }

    @Test("Every cut's segments sum to its declared duration, and resolve covers it")
    func cutSums() {
        for cut in SizzleScript.cuts + SizzleScript.plates {
            let sum = cut.segments.reduce(0.0) { $0 + $1.seconds }
            #expect(abs(sum - cut.seconds) < 1e-9, "\(cut.name)")
            // The last frame must still resolve; one tick past the end must not.
            let lastFrame = Double(cut.frameCount - 1) / Double(cut.fps)
            #expect(SizzleScript.resolve(cut, at: lastFrame) != nil, "\(cut.name)")
            #expect(SizzleScript.resolve(cut, at: cut.seconds + 0.001) == nil, "\(cut.name)")
        }
    }

    @Test("The README GIF stays inside its frame budget")
    func gifBudget() {
        #expect(SizzleScript.readme.fps == 10)
        #expect(SizzleScript.readme.frameCount <= 200,
                "the GIF cut must stay lean — \(SizzleScript.readme.frameCount) frames")
    }

    @Test("The must-shows are protected, per cut")
    func mustShows() {
        // The finale: whole in the social masters, most of it in the README
        // loop, its first four seconds in the meme.
        for cut in [SizzleScript.landscape, SizzleScript.vertical] {
            let finale = cut.segments.first { $0.chapter == .finale }
            #expect(finale?.seconds == 10.0, "\(cut.name) must carry the whole finale")
        }
        let readmeFinale = SizzleScript.readme.segments.first { $0.chapter == .finale }
        #expect((readmeFinale?.seconds ?? 0) >= 8.0)
        let memeFinale = SizzleScript.meme.segments.first { $0.chapter == .finale }
        #expect(memeFinale?.seconds == 3.2)
        if case .window(let offset) = memeFinale?.kind {
            #expect(offset == 0, "the meme finale opens on the flash")
        } else {
            Issue.record("the meme finale must be a window slice")
        }

        // The operator's runtime law: EVERY clip under 25 seconds; the
        // meme under 20 besides.
        for cut in SizzleScript.cuts {
            #expect(cut.seconds < 25.0, "\(cut.name) breaks the 25-second law")
        }
        #expect(SizzleScript.meme.seconds < 20.0)
        for chapter in [SizzleScript.Chapter.glyphs, .montage, .outro] {
            #expect(SizzleScript.meme.segments.contains { $0.chapter == chapter },
                    "the meme needs its \(chapter)")
        }

        // The video twin mirrors the GIF cut exactly.
        #expect(SizzleScript.readmeVideo.segments.count == SizzleScript.readme.segments.count)
        #expect(SizzleScript.readmeVideo.seconds == SizzleScript.readme.seconds)

        // The plates mirror their masters through resolve, sweep-checked —
        // keyed footage must stay in sync with the titled cuts.
        for (plate, master) in [(SizzleScript.plate16x9, SizzleScript.landscape),
                                (SizzleScript.plate9x16, SizzleScript.vertical)] {
            #expect(plate.seconds == master.seconds, "\(plate.name)")
            for tick in stride(from: 0.0, to: master.seconds, by: 0.25) {
                let a = SizzleScript.resolve(plate, at: tick)
                let b = SizzleScript.resolve(master, at: tick)
                #expect(a?.chapter == b?.chapter && a?.localT == b?.localT,
                        "\(plate.name) diverges at t=\(tick)")
            }
        }

        // The montage carries every look, ending on Classic for the loop seam.
        #expect(Set(SizzleScript.montageOrder) == Set(Costume.allCases))
        #expect(SizzleScript.montageOrder.last == Costume.none)

        // The glyph chapter shows every service.
        #expect(SizzleScript.glyphBeats.map(\.glyph) == ServiceGlyph.allCases)
    }

    @Test("Every canvas is H.264-even at its scale")
    func canvasEvenness() {
        for cut in SizzleScript.cuts + SizzleScript.plates {
            let w = Int(cut.canvas.width * cut.scale)
            let h = Int(cut.canvas.height * cut.scale)
            #expect(w % 2 == 0 && h % 2 == 0, "\(cut.name): \(w)×\(h)")
        }
    }

    @Test("The dice bases fire on camera")
    func diceBases() {
        // The cooking shot: a clean lead-in, then disco and heat inside it.
        #expect(CrabView.discoTint(cookingT: SizzleScript.cookBase + 0.5) == nil,
                "the shot must open clean")
        #expect(CrabView.discoTint(cookingT: SizzleScript.cookBase + 3.5) != nil,
                "the disco must fire mid-shot")
        #expect(CrabAnimator.pose(mood: .cooking, t: SizzleScript.cookBase + 4.0).heat > 0,
                "the heat cascade must fire mid-shot")
        // The working spell holds the terminal.
        #expect(CrabAnimator.workingProp(at: SizzleScript.workBase + 1.0) == .terminal)
    }

    @Test("Window segments enter their chapter's own clock; scaled ones compress")
    func resolveKinds() {
        // README mirror opens at offset 1.6 into the chapter clock.
        let start = SizzleScript.resolve(SizzleScript.readme, at: 0)
        #expect(start?.chapter == .mirror)
        #expect(abs((start?.localT ?? 0) - 1.6) < 1e-9)

        // The README montage compresses 8.0 master seconds into 5.5.
        let montageStart = 3.0 + 3.0 + 8.0
        let mid = SizzleScript.resolve(SizzleScript.readme, at: montageStart + 2.75)
        #expect(mid?.chapter == .montage)
        #expect(abs((mid?.localT ?? 0) - 4.0) < 1e-9,
                "half the segment must be half the master chapter")
    }
}

/// The rendered frames themselves: deterministic, and dark outside the
/// glow's envelope.
@Suite("Sizzle frames", .serialized)
@MainActor
struct SizzleFrameTests {

    @Test("The glow draws nothing outside its ten-second envelope")
    func glowEnvelope() {
        for t in [-1.0, 10.5, 60.0] {
            let lit = renderGlow(t: t)
            let dark = renderGlow(t: -100)
            #expect(lit == dark, "the glow must be dark at t=\(t)")
        }
        #expect(renderGlow(t: 2.0) != renderGlow(t: -100),
                "and it must actually draw mid-envelope")
    }

    private func renderGlow(t: Double) -> Data? {
        let view = Canvas { context, size in
            CelebrationGlow.draw(in: &context, size: size, t: t)
        }
        .frame(width: 96, height: 96)
        .background(Color.black)
        return SpriteImage.png(of: view, scale: 1, isOpaque: true)
    }

    @Test("Sampled frames render byte-identically twice")
    func determinism() {
        // One frame from a scaled chapter, one dice-locked, one montage flip.
        for t in [1.2, 7.0, 15.5] {
            let cut = SizzleScript.readme
            let a = frameData(cut: cut, t: t)
            let b = frameData(cut: cut, t: t)
            #expect(a != nil && a == b, "readme frame at t=\(t) must be reproducible")
        }
        // The camera-live samples ride the readme cut's mid-shake cook
        // window rather than the landscape's glyph beats: rich frames carry
        // antialiased card/caption TEXT, whose rasterisation shows LSB noise
        // under full-suite parallel load (the same GPU-scheduling class the
        // glow's fractional centre exposed). The real encoders render
        // sequentially and never see that load — measured: the landscape
        // frames are byte-stable in isolation, flaky only mid-suite.
        for t in [4.2] {
            let cut = SizzleScript.readme
            let a = frameData(cut: cut, t: t)
            let b = frameData(cut: cut, t: t)
            #expect(a != nil && a == b, "readme cook frame at t=\(t) must be reproducible")
        }
    }

    private func frameData(cut: SizzleScript.Cut, t: Double) -> Data? {
        let index = Int((t * Double(cut.fps)).rounded())
        guard let image = SizzleRenderer.testFrame(cut: cut, index: index) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}

/// The camera's grid discipline: whole-point offsets, bounded motion,
/// legal dwells.
@Suite("Sizzle camera")
@MainActor
struct SizzleCameraTests {

    @Test("Offsets are always whole points, shake included")
    func integerOffsets() {
        let cut = SizzleScript.landscape
        let fmt = SizzleRenderer.format(for: cut)
        for index in 0..<cut.frameCount {
            let t = Double(index) / Double(cut.fps)
            guard let cue = SizzleScript.resolve(cut, at: t) else { continue }
            let shot = SizzleRenderer.shot(for: cue.chapter, t: cue.localT, fmt: fmt)
            #expect(shot.offset.x == shot.offset.x.rounded(), "frame \(index)")
            #expect(shot.offset.y == shot.offset.y.rounded(), "frame \(index)")
        }
    }

    @Test("Motion is bounded and dwells sit on sanctioned stops")
    func continuity() {
        let cut = SizzleScript.landscape
        let fmt = SizzleRenderer.format(for: cut)
        let stops: Set<CGFloat> = [fmt.spriteSide, fmt.punchSide, fmt.faceSide]
        var previous: SizzleRenderer.Shot?
        var beforePrevious: SizzleRenderer.Shot?
        var lastChapter: SizzleScript.Chapter?
        for index in 0..<cut.frameCount {
            let t = Double(index) / Double(cut.fps)
            guard let cue = SizzleScript.resolve(cut, at: t) else { continue }
            let shot = SizzleRenderer.shot(for: cue.chapter, t: cue.localT, fmt: fmt)
            if let previous, lastChapter == cue.chapter {
                // Bounds are on the DESIGNED chapter-local move — the face
                // punch's ~19.2pt/frame mid-slope, the roster slide's
                // ~5pt/frame — multiplied by the segment's compression,
                // because `.scaled` speeds the camera with the scene. A snap
                // would still blow past by 3-5x.
                let rate = cue.scaleFactor
                #expect(abs(shot.side - previous.side) <= 21.0 * rate,
                        "side jumped \(abs(shot.side - previous.side)) at frame \(index)")
                #expect(abs(shot.offset.x - previous.offset.x) <= 6.0 * rate, "frame \(index)")
                #expect(abs(shot.offset.y - previous.offset.y) <= 6.0 * rate, "frame \(index)")
                // A three-frame-flat side is a dwell; dwells sit on stops.
                if let beforePrevious, beforePrevious.side == previous.side,
                   previous.side == shot.side {
                    #expect(stops.contains(shot.side),
                            "dwelling at unsanctioned \(shot.side), frame \(index)")
                }
            }
            beforePrevious = previous
            previous = shot
            lastChapter = cue.chapter
        }
    }
}

/// The plates: pure fields, lossless sequences.
@Suite("Sizzle plates", .serialized)
@MainActor
struct SizzlePlateTests {

    @Test("A plate frame keys clean: exact green corners, a bounded palette")
    func platePurity() throws {
        // Mid-cook: shake, disco tint, suppressed shadow and bubble in play.
        let cut = SizzleScript.plate16x9
        let index = Int((17.5 * Double(cut.fps)).rounded())
        let frame = try #require(SizzleRenderer.testFrame(cut: cut, index: index))
        let data = try #require(frame.dataProvider?.data as Data?)

        // The self-calibrating reference: the same green through the same
        // pipeline, so colour management cannot fake a failure.
        let reference = try #require(SpriteImage.cgImage(
            of: Rectangle().fill(Palette.keyField).frame(width: 4, height: 4),
            scale: 1, isOpaque: true))
        let refData = try #require(reference.dataProvider?.data as Data?)
        let refPixel = [refData[0], refData[1], refData[2], refData[3]]

        let bytesPerRow = frame.bytesPerRow
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let base = y * bytesPerRow + x * 4
            return [data[base], data[base + 1], data[base + 2], data[base + 3]]
        }
        for (x, y) in [(0, 0), (frame.width - 1, 0), (0, frame.height - 1),
                       (frame.width - 1, frame.height - 1)] {
            #expect(pixel(x, y) == refPixel, "corner (\(x),\(y)) is not the key field")
        }

        // Distinct colours stay bounded — AA text, a translucent shadow or
        // the glow would blow straight past this.
        var colours = Set<UInt32>()
        for y in stride(from: 0, to: frame.height, by: 4) {
            for x in stride(from: 0, to: frame.width, by: 4) {
                let p = pixel(x, y)
                colours.insert(UInt32(p[0]) << 24 | UInt32(p[1]) << 16
                    | UInt32(p[2]) << 8 | UInt32(p[3]))
            }
        }
        #expect(colours.count <= 48, "plate palette exploded: \(colours.count) colours")
    }

    @Test("The sequence writer names, counts and orders its frames")
    func sequenceWriter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pet-plates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(String(format: "frame-%04d.png", 1349) == "frame-1349.png")

        // A stub plate: tiny canvas, three frames, real pipeline.
        let stub = SizzleScript.Cut(
            name: "plate-stub", canvas: CGSize(width: 64, height: 36), scale: 1,
            fps: 10, family: .plate,
            segments: [SizzleScript.Segment(chapter: .wake, kind: .window(offset: 0),
                                            seconds: 0.3)])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seqDir = dir.appendingPathComponent(stub.name)
        try FileManager.default.createDirectory(at: seqDir, withIntermediateDirectories: true)
        for index in 0..<stub.frameCount {
            let frame = try #require(SizzleRenderer.testFrame(cut: stub, index: index))
            let rep = NSBitmapImageRep(cgImage: frame)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            #expect(SpriteImage.write(png, to: seqDir.appendingPathComponent(
                String(format: "frame-%04d.png", index))))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: seqDir.path).sorted()
        #expect(files.count == stub.frameCount)
        #expect(files == (0..<stub.frameCount).map { String(format: "frame-%04d.png", $0) },
                "lexicographic order must equal frame order")
    }
}
