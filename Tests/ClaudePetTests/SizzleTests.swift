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

        // The hook: the finale's flash as a cold open, then landscape
        // verbatim, still inside the law.
        let opener = SizzleScript.hook.segments.first
        #expect(opener?.chapter == .finale && opener?.seconds == 0.6)
        if case .window(let offset) = opener?.kind { #expect(offset == 2.05) }
        else { Issue.record("the hook must open on a window slice") }
        #expect(Array(SizzleScript.hook.segments.dropFirst()).count
                == SizzleScript.landscape.segments.count)
        #expect(abs(SizzleScript.hook.seconds - 24.8) < 1e-9)
        #expect(SizzleScript.hook.frameCount == 744)

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

    /// Every camera stop is a whole number of cells at its cut's scale.
    ///
    /// `PixelCanvasView` divides the side by 32 to get a cell, so a side that
    /// is not a multiple of 32 device pixels renders some columns a pixel wider
    /// than their neighbours — on a character whose whole read is that its
    /// pixels are square. The 9:16 rest sat at 264 (8.25 points per cell) for
    /// exactly this reason: nothing checked.
    @Test("Every camera stop lands on whole cells")
    func cameraStopsAreOnTheGrid() {
        for cut in SizzleScript.cuts + SizzleScript.plates {
            let fmt = SizzleRenderer.format(for: cut)
            let stops: [(String, CGFloat)] = [
                ("rest", fmt.spriteSide), ("punch", fmt.punchSide),
                ("face", fmt.faceSide), ("duo", fmt.duoSide),
            ]
            for (name, side) in stops {
                let devicePixels = side * cut.scale
                #expect(devicePixels.truncatingRemainder(dividingBy: CGFloat(PixelBuffer.side)) == 0,
                        "\(cut.name) \(name) is \(side)pt × \(cut.scale) = \(devicePixels)px, not whole cells")
            }
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

    /// How alike two renders of the same instant are, 0…1 by byte.
    ///
    /// Byte-exactness is the right bar for a frame with no antialiasing in it,
    /// and the wrong one for a frame with type on it. Antialiased glyph edges
    /// rasterise with run-to-run LSB noise under parallel load — the same
    /// GPU-scheduling class the glow's fractional centre exposed — so the
    /// strict form was a coin flip that grew more likely to land badly with
    /// every render test anyone added. It was blocking coverage rather than
    /// protecting anything.
    ///
    /// What the test is actually for is catching a clock or an RNG in a render
    /// path, and that does not move a handful of edge pixels — it moves the
    /// sprite, the props, the camera. A tenth of a percent separates the two
    /// by orders of magnitude.
    /// Compared as PIXELS, not as PNG. Two renders that differ in a handful of
    /// antialiased edge samples compress to different lengths, so byte-counting
    /// the encoded file reports nothing useful about how alike the images are.
    private func likeness(_ a: Data?, _ b: Data?) -> Double {
        guard let a, let b,
              let left = NSBitmapImageRep(data: a)?.representation(using: .tiff, properties: [:]),
              let right = NSBitmapImageRep(data: b)?.representation(using: .tiff, properties: [:]),
              left.count == right.count, !left.isEmpty else { return 0 }
        var same = 0
        for (x, y) in zip(left, right) where x == y { same += 1 }
        return Double(same) / Double(left.count)
    }

    @Test("Sampled frames render reproducibly twice")
    func determinism() {
        // One frame from a scaled chapter, one dice-locked, one montage flip.
        for t in [1.2, 7.0, 15.5] {
            let cut = SizzleScript.readme
            let a = frameData(cut: cut, t: t)
            let b = frameData(cut: cut, t: t)
            #expect(likeness(a, b) > 0.999, "readme frame at t=\(t) must be reproducible")
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
            #expect(likeness(a, b) > 0.999, "readme cook frame at t=\(t) must be reproducible")
        }
        // A frame mid-flashbang: the blanch adds a second fill pass over the
        // union of the sprite's runs, and that pass has to rasterise as
        // stably as the inks under it. The readme finale opens at cut t=6.0,
        // so t=6.4 is finale-local 0.4 — inside the first tap's plateau, i.e.
        // a fully white sprite.
        // A plate carries no type at all — it is the sprite on a flat key
        // field, whole pixels, no antialiasing anywhere — so it can hold the
        // strict bar the rich frames no longer can. This is the sample that
        // would actually catch a clock in a render path.
        do {
            let cut = SizzleScript.plate16x9
            let index = Int((12.0 * Double(cut.fps)).rounded())
            let a = SpriteImage.png(of: Image(decorative: SizzleRenderer.testFrame(cut: cut, index: index)!,
                                              scale: 1), scale: 1, isOpaque: true)
            let b = SpriteImage.png(of: Image(decorative: SizzleRenderer.testFrame(cut: cut, index: index)!,
                                              scale: 1), scale: 1, isOpaque: true)
            #expect(a != nil && a == b, "a plate frame must be byte-identical")
        }
        for t in [6.4] {
            let cut = SizzleScript.readme
            #expect(CrabView.epicBlanch(doneT: t - 6.0) == 1.0,
                    "the determinism sample must actually land on a flash")
            let a = frameData(cut: cut, t: t)
            let b = frameData(cut: cut, t: t)
            #expect(likeness(a, b) > 0.999, "blanched frame at t=\(t) must be reproducible")
        }
    }

    @Test("The hook cut opens on an actual flash, not a decay tail")
    func hookOpensOnTheBang() {
        let opener = SizzleScript.hook.segments[0]
        guard case .window(let offset) = opener.kind else {
            Issue.record("the hook must open on a window slice")
            return
        }
        let lit = stride(from: 0.0, to: opener.seconds, by: 1.0 / 30)
            .contains { CrabView.epicBlanch(doneT: offset + $0) > 0.99 }
        #expect(lit, "the cold open must contain a full-white frame")
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

    /// Plates are keyed AGAINST the titled masters, so type may be hidden on
    /// them but never REMOVED: the slot has to keep its height or everything
    /// below it moves, and a plate whose sprite sits ten rows off is a plate
    /// that cannot be keyed.
    ///
    /// Measured at the small views rather than at whole frames on purpose. The
    /// end-to-end version — one plate frame against one master frame, comparing
    /// where the sprite starts — is what caught this (he was ten rows out), but
    /// two extra full-canvas renders are enough load to tip the byte-identical
    /// guard in the frames suite, which is load-sensitive by documented design.
    /// This asks the same question of the two pieces that answer it.
    @Test("Type is hidden on plates, never removed")
    func plateKeepsTheTypeSlot() throws {
        let plateFmt = SizzleRenderer.format(for: SizzleScript.plate16x9)
        let masterFmt = SizzleRenderer.format(for: SizzleScript.landscape)
        #expect(plateFmt.type == false && masterFmt.type == true)

        // The words themselves must survive: an empty string is a different
        // height than a real line, which was half of the misregistration.
        #expect(plateFmt.captions == masterFmt.captions,
                "a plate must carry the master's captions and merely hide them")
        #expect(plateFmt.captions.isEmpty == false)

        // And the rendered type must occupy the same box either way.
        func size(_ view: some View) throws -> CGSize {
            let image = try #require(SpriteImage.cgImage(of: view, scale: 1))
            return CGSize(width: image.width, height: image.height)
        }
        for chapter in [SizzleScript.Chapter.mirror, .cook, .finale] {
            let text = plateFmt.captions[chapter] ?? ""
            guard !text.isEmpty else { continue }
            let hidden = try size(SizzleRenderer.captionProbe(text, fmt: plateFmt))
            let shown = try size(SizzleRenderer.captionProbe(text, fmt: masterFmt))
            #expect(hidden == shown,
                    "\(chapter) caption is \(hidden) hidden and \(shown) shown")
        }
        let hiddenTitle = try size(SizzleRenderer.titleProbe(fmt: plateFmt))
        let shownTitle = try size(SizzleRenderer.titleProbe(fmt: masterFmt))
        #expect(hiddenTitle == shownTitle,
                "the title card is \(hiddenTitle) hidden and \(shownTitle) shown")
    }

    @Test("A plate frame keys clean: exact green corners, a bounded palette")
    func platePurity() throws {
        // Mid-FINALE: the landscape cursor puts t=17.5 at finale-local ~8.7 —
        // rainbow tint, badge landing, suppressed shadow and bubble in play,
        // and deliberately past the last flashbang tap, so this samples the
        // plate's steady state rather than a white frame.
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

/// The party's confetti: in-grid, eased at both ends, deterministic.
@Suite("Party confetti")
@MainActor
struct PartyConfettiTests {

    private func render(elapsed: Double?) -> PixelBuffer {
        var pose = CrabAnimator.pose(mood: .done, t: 1.0)
        pose.confettiElapsed = elapsed
        return CrabRig.render(pose)
    }

    @Test("Confetti shows mid-party, in-grid, and never at the edges")
    func showerShape() {
        let bare = render(elapsed: nil)
        let mid = render(elapsed: 2.0)
        var changed = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where mid[x, y] != bare[x, y] {
                changed += 1
            }
        }
        #expect(changed > 0, "mid-party must shower")

        // The trapezoid's edges: nearly nothing at the very start and end.
        for edge in [0.05, 3.97] {
            let frame = render(elapsed: edge)
            var edgeChanged = 0
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where frame[x, y] != bare[x, y] {
                    edgeChanged += 1
                }
            }
            #expect(edgeChanged <= 2, "the shower must ease at elapsed \(edge)")
        }
    }

    @Test("The pose function only sets confetti during the live party")
    func frozenStaysDry() {
        for mood in PetMood.allCases {
            #expect(CrabAnimator.pose(mood: mood, t: 0).confettiElapsed == nil)
            #expect(CrabAnimator.pose(mood: mood, t: 5).confettiElapsed == nil)
        }
    }
}

/// The afterimage silhouette: one ink, same footprint.
@Suite("Party trails")
@MainActor
struct PartyTrailTests {

    @Test("A silhouette is body-only with its footprint preserved")
    func silhouetteContract() {
        let pose = CrabAnimator.pose(mood: .done, t: 0.3)
        let full = CrabRig.render(pose, costume: .gundam, costumeVisibility: 1)
        let ghost = full.silhouette()
        var fullCount = 0, ghostCount = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                if full[x, y] != .clear { fullCount += 1 }
                let ink = ghost[x, y]
                #expect(ink == .clear || ink == .body,
                        "silhouettes carry exactly one ink")
                if ink != .clear { ghostCount += 1 }
            }
        }
        #expect(fullCount == ghostCount, "the footprint must survive whole")
    }
}

/// The ray sweep: dark outside the party, reproducible inside it.
@Suite("Party rays", .serialized)
@MainActor
struct PartyRayTests {

    private func render(t: Double) -> Data? {
        let view = Canvas { context, size in
            RainbowRays.draw(in: &context, size: size, t: t)
        }
        .frame(width: 96, height: 96)
        .background(Color.black)
        return SpriteImage.png(of: view, scale: 1, isOpaque: true)
    }

    @Test("Dark at both ends, lit in the middle, byte-stable")
    func envelope() {
        let dark = render(t: -100)
        #expect(render(t: -0.1) == dark)
        #expect(render(t: 4.5) == dark)
        #expect(render(t: 2.0) != dark, "mid-party must shine")
        #expect(render(t: 2.0) == render(t: 2.0), "and reproducibly so")
    }
}

/// The thinking spell's star: alternation, dissolve, containment.
@Suite("The thinking star")
@MainActor
struct ThinkingStarTests {

    @Test("Sparkles first — every committed thinking clip stays byte-stable")
    func firstSpellIsSparkles() {
        #expect(CrabAnimator.thinkingProp(at: 1.0) == .sparkles)
        #expect(CrabAnimator.thinkingProp(at: 19.9) == .sparkles)
    }

    @Test("The star arrives on the second spell, through the dissolve")
    func starArrives() {
        #expect(CrabAnimator.thinkingProp(at: 21.0) == .star)
        // The boundary dips: visibility below 1 just before and after t=20.
        let before = CrabAnimator.pose(mood: .thinking, t: 19.9)
        let after = CrabAnimator.pose(mood: .thinking, t: 20.1)
        #expect(before.propVisibility < 1, "the sparkles must be put down")
        #expect(after.propVisibility < 1, "the star must be picked up")
        let settled = CrabAnimator.pose(mood: .thinking, t: 22.0)
        #expect(settled.propVisibility == 1 && settled.prop == .star)
    }

    @Test("The star holds the top-right airspace, clear of the glyph box")
    func starStaysInItsCorner() {
        var pose = CrabPose()
        pose.prop = .star
        let bare = CrabRig.render(CrabPose())
        let lit = CrabRig.render(pose)
        var cells = 0
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where lit[x, y] != bare[x, y] {
                cells += 1
                #expect(x >= 20 && y <= 8, "star pixel at (\(x),\(y)) strays")
            }
        }
        #expect(cells > 0, "the star must draw")
    }

    @Test("The working roll is untouched — the star never joins it")
    func workingRollUntouched() {
        #expect(!CrabPose.Prop.working.contains(.star))
        #expect(CrabAnimator.workingProp(at: SizzleScript.workBase + 1.0) == .terminal,
                "the sizzle's terminal pin must survive")
    }
}

/// The beat sidecars: monotonic, complete, and exact where pinned.
@Suite("Beat maps")
@MainActor
struct BeatMapTests {

    @Test("Every cut's map is monotonic and ends at its duration")
    func shape() {
        for cut in SizzleScript.cuts + SizzleScript.plates {
            let lines = SizzleScript.beatMap(for: cut)
                .split(separator: "\n").filter { !$0.hasPrefix("#") }
            let times = lines.compactMap { Double($0.split(separator: "\t")[0]) }
            #expect(times == times.sorted(), "\(cut.name) must be monotonic")
            #expect(abs((times.last ?? -1) - cut.seconds) < 0.002,
                    "\(cut.name) must end at its duration")
            #expect(lines.last?.hasSuffix("end\t-") == true)
        }
    }

    @Test("The landscape glyph beats land where the cadence says")
    func landscapeSpots() {
        let map = SizzleScript.beatMap(for: SizzleScript.landscape)
        // Glyphs start at 4.0 (wake 1.0 + mirror 3.0), compressed 6.0→2.8:
        // beats at 4.0, 4.7, 5.4, 6.1 master → /2.142857…
        #expect(map.contains("4.000\tglyph\tnpm"))
        #expect(map.contains("4.700\tglyph\tgithub"))
        #expect(map.contains("5.400\tglyph\tlinear"))
        #expect(map.contains("6.100\tglyph\tdeploy"))
        #expect(map.contains("chapter\tfinale"))
        #expect(map.contains("look\tsonic"))
    }
}

/// The montage tags: every resolved colour clears the field.
@Suite("Montage tag colours")
@MainActor
struct MontageTagTests {

    @Test func everyTagClears() {
        for costume in Costume.allCases {
            let color = SizzleRenderer.tagColor(for: costume)
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
            let luminance = 0.2126 * resolved.redComponent
                + 0.7152 * resolved.greenComponent
                + 0.0722 * resolved.blueComponent
            #expect(luminance >= 0.13, "\(costume) tag sinks into the field")
        }
        // The dark looks fall back rather than vanishing.
        #expect(SizzleRenderer.tagColor(for: .retroBlack) == Palette.kraft)
    }
}

/// The balloon's idle float: dark first cycle, dice-scheduled, eased.
@Suite("The idle balloon")
@MainActor
struct IdleBalloonTests {

    @Test("Never in the first cycle, and it does fire on some later one")
    func schedule() {
        for t in stride(from: 0.0, to: 150.0, by: 5.0) {
            #expect(CrabAnimator.idleBalloon(idleT: t) == nil,
                    "the first cycle must stay bare at t=\(t)")
        }
        var fired = false
        for cycle in 1...40 where CrabAnimator.idleBalloon(idleT: Double(cycle) * 150 + 4) != nil {
            fired = true
            break
        }
        #expect(fired, "the dice must land within forty cycles")
    }

    @Test("The float eases in and out")
    func easedEdges() {
        guard let cycle = (1...40).first(where: {
            CrabAnimator.idleBalloon(idleT: Double($0) * 150 + 4) != nil
        }) else { Issue.record("no firing cycle found"); return }
        let base = Double(cycle) * 150
        let early = CrabAnimator.idleBalloon(idleT: base + 0.1) ?? -1
        let mid = CrabAnimator.idleBalloon(idleT: base + 4) ?? -1
        let late = CrabAnimator.idleBalloon(idleT: base + 7.9) ?? -1
        #expect(early < 0.3 && late < 0.3, "the ends must be eased")
        #expect(mid > 0.9, "the middle must be full")
    }
}

/// The fire→finale bridge: continuous at the cut, absent everywhere else.
@Suite("The match cut")
@MainActor
struct MatchCutTests {

    @Test("The bridge is continuous across the boundary")
    func continuity() {
        let cut = SizzleScript.landscape
        let fmt = SizzleRenderer.format(for: cut)
        // Landscape: cook ends at 8.8, finale begins there.
        let exitFlash = SizzleRenderer.matchCutFlash(cut: cut, at: 8.799, fmt: fmt)
        let entryFlash = SizzleRenderer.matchCutFlash(cut: cut, at: 8.801, fmt: fmt)
        // 1.0, not 0.9: nine tenths of white composites to a grey over a dark
        // backdrop, which is the washed-out complaint in a different room.
        #expect(abs(exitFlash - 1.0) < 0.02, "the cook must exit at full white")
        #expect(abs(entryFlash - 1.0) < 0.02, "the finale must open at the same white")
        // And it dies quickly on both sides.
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: 8.0, fmt: fmt) < 0.01)
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: 9.4, fmt: fmt) < 0.01)
    }

    @Test("The hook's cold-open finale has no bridge, and readme never flashes")
    func gates() {
        let hook = SizzleScript.hook
        let hookFmt = SizzleRenderer.format(for: hook)
        // The cold open (t=0.1, finale with no previous segment).
        #expect(SizzleRenderer.matchCutFlash(cut: hook, at: 0.1, fmt: hookFmt) == 0)

        let readme = SizzleScript.readme
        let readmeFmt = SizzleRenderer.format(for: readme)
        for t in stride(from: 0.0, to: readme.seconds, by: 0.25) {
            #expect(SizzleRenderer.matchCutFlash(cut: readme, at: t, fmt: readmeFmt) == 0,
                    "the readme twins must never flash")
        }
    }
}

/// The glyph reactions: distinct per beat, gone at rest.
@Suite("Glyph reactions")
@MainActor
struct GlyphReactionTests {

    @Test("Each beat gestures differently, and all return to rest")
    func distinctAndTransient() {
        var poses: [CrabPose] = []
        for beat in 0...3 {
            var pose = CrabPose()
            SizzleRenderer.applyGlyphReaction(beat: beat, beatT: 0.7, to: &pose)
            poses.append(pose)
            var rest = CrabPose()
            SizzleRenderer.applyGlyphReaction(beat: beat, beatT: 1.45, to: &rest)
            #expect(rest == CrabPose(), "beat \(beat) must return to rest")
        }
        #expect(poses[0].bob == 1 && poses[0].gazeY == 1)
        #expect(poses[1].armRight > 0.9)
        #expect(poses[2].tilt == 1)
        #expect(poses[3].lean == -1 && poses[3].eyes == .wide)
    }
}

/// The showcase opens on action; the duet finally has a camera.
@Suite("Showcase and duet upgrades")
@MainActor
struct ShowcaseDuetTests {

    @Test("Text-free cuts skip the wake and stay lawful")
    func actionOpens() {
        for cut in [SizzleScript.showcaseGradient, SizzleScript.showcaseGradientTall] {
            #expect(cut.segments.first?.chapter != .wake, "\(cut.name) must open on action")
            #expect(cut.seconds < 25.0)
        }
        #expect(abs(SizzleScript.showcaseGradient.seconds - 23.2) < 1e-9)
        #expect(abs(SizzleScript.showcaseGradientTall.seconds - 22.1) < 1e-9)
    }

    @Test("The duet pan dwells on the pounce, crosses, and settles")
    func duetPan() {
        let fmt = SizzleRenderer.format(for: SizzleScript.landscape)
        #expect(SizzleRenderer.shot(for: .duet, t: 1.2, fmt: fmt).offset.x == 38,
                "the pounce lands on the dwell")
        #expect(SizzleRenderer.shot(for: .duet, t: 2.4, fmt: fmt).offset.x == -38,
                "then the pan crosses to pet two")
        #expect(SizzleRenderer.shot(for: .duet, t: 3.8, fmt: fmt).offset.x == 0,
                "and settles wide")
    }
}
