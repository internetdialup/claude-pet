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

    @Test("The master chapters sum to thirty-two seconds")
    func masterSums() {
        // The authored performance lengths for the chapters every cut windows
        // into (mirror 5.5, cook 6.0, finale 10.0) plus the reel lengths the
        // rest are authored AT, so a `.window(offset: 0)` plays them at 1×:
        // wake 1.0, glyphs 2.5, breath 0.5, montage 2.5, duet 1.0, outro 3.0.
        // This was 50.0 when the montage was one second per look and every
        // other chapter was time-stretched to fit around the finale.
        let total = SizzleScript.Chapter.allCases
            .reduce(0.0) { $0 + (SizzleScript.masterSeconds[$1] ?? 0) }
        #expect(total == 32.0)
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

        // The hook: the finale's apex as a cold open of one beat less a
        // frame, then the landscape master verbatim, still inside the law.
        let opener = SizzleScript.hook.segments.first
        #expect(opener?.chapter == .finale && opener?.seconds == 0.4)
        if case .window(let offset) = opener?.kind { #expect(offset == 2.05) }
        else { Issue.record("the hook must open on a window slice") }
        #expect(Array(SizzleScript.hook.segments.dropFirst()).count
                == SizzleScript.landscape.segments.count)
        #expect(abs(SizzleScript.hook.seconds - (0.4 + SizzleScript.landscape.seconds)) < 1e-9)
        #expect(SizzleScript.hook.frameCount == 747)

        // The montage carries every look, ending on Classic for the loop seam.
        #expect(Set(SizzleScript.montageOrder) == Set(Costume.allCases))
        #expect(SizzleScript.montageOrder.last == Costume.none)

        // The glyph chapter shows every service, each with its own beat.
        #expect(SizzleScript.glyphBeats.map(\.glyph) == ServiceGlyph.allCases)
        #expect(SizzleScript.glyphBeatSeconds.count == SizzleScript.glyphBeats.count)
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
                ("hero", fmt.heroSide), ("duo", fmt.duoSide),
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
        // The cooking shot: a clean lead-in, then heat inside it. The disco
        // fires here on the desktop too — the reel no longer passes it (no
        // body colour before the finale's own), but the live schedule this
        // base was chosen against must not drift under the window.
        #expect(CrabView.discoTint(cookingT: SizzleScript.cookBase + 0.5) == nil,
                "the shot must open clean")
        #expect(CrabView.discoTint(cookingT: SizzleScript.cookBase + 3.5) != nil,
                "the disco must fire mid-shot")
        #expect(CrabAnimator.pose(mood: .cooking, t: SizzleScript.cookBase + 4.0).heat > 0,
                "the heat cascade must fire mid-shot")
        // The working spell holds the terminal.
        #expect(CrabAnimator.workingProp(at: SizzleScript.workBase + 1.0) == .terminal)
    }

    @Test("Window segments enter their chapter's own clock, and nothing is stretched")
    func resolveKinds() {
        // README mirror opens at offset 1.6 into the chapter clock.
        let start = SizzleScript.resolve(SizzleScript.readme, at: 0)
        #expect(start?.chapter == .mirror)
        #expect(abs((start?.localT ?? 0) - 1.6) < 1e-9)

        // Time is trimmed, never stretched: every segment of every cut is a
        // window, so `scaleFactor` is 1 on every frame. The README montage
        // used to compress fifteen looks into 5.5s — a 0.35s dissolve in one
        // frame at 10fps, in the committed asset.
        for cut in SizzleScript.cuts + SizzleScript.plates {
            for index in 0..<cut.frameCount {
                let t = Double(index) / Double(cut.fps)
                #expect(SizzleScript.resolve(cut, at: t)?.scaleFactor == 1,
                        "\(cut.name) is time-stretched at frame \(index)")
            }
        }
    }

    /// The trap the battery caught one edit before it fired: the montage clock
    /// said eight seconds, the running order held ten looks, and the pose
    /// table held eight entries — two costumes silently never rendered. The
    /// pose table is keyed by costume now and held to `Costume.allCases`; the
    /// clock is each cut's own running order, and the segment must be exactly
    /// as long as the looks it plays.
    @Test("The montage is a running order, not a rate")
    func montageIsARunningOrder() {
        #expect(Set(SizzleRenderer.montageMoods.keys) == Set(Costume.allCases),
                "every costume needs a montage pose")
        for cut in SizzleScript.cuts + SizzleScript.plates {
            for segment in cut.segments where segment.chapter == .montage {
                if case .window(let offset) = segment.kind {
                    #expect(offset == 0, "\(cut.name) montage must open on its first look")
                } else {
                    Issue.record("\(cut.name) montage must be a window, not a rate")
                }
                #expect(abs(segment.seconds - cut.looksSeconds) < 1e-9,
                        "\(cut.name) montage plays \(segment.seconds)s of \(cut.looksSeconds)s of looks")
            }
            #expect(cut.looks.last?.costume == Costume.none,
                    "\(cut.name) must close on Classic for the loop seam")
        }
        // The masters: every look long enough to register, the last held.
        let looks = SizzleScript.masterLooks
        for look in looks {
            #expect(look.seconds >= 0.5, "\(look.costume) shows for \(look.seconds)s")
        }
        #expect((looks.last?.seconds ?? 0) >= 1.3 * (looks.first?.seconds ?? 1),
                "the last look is the hold")
        #expect(SizzleScript.masterSeconds[.montage] == looks.reduce(0) { $0 + $1.seconds })
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
        let stops: Set<CGFloat> = [fmt.spriteSide, fmt.punchSide, fmt.heroSide]
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
        for (chapter, caption) in masterFmt.captions {
            let hidden = try size(SizzleRenderer.captionProbe(caption.wide, fmt: plateFmt))
            let shown = try size(SizzleRenderer.captionProbe(caption.wide, fmt: masterFmt))
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

    @Test("The landscape glyph beats land where the table says, and every kind is present")
    func landscapeSpots() {
        let cut = SizzleScript.landscape
        let map = SizzleScript.beatMap(for: cut)
        // Derived, not restated: the glyph chapter starts where the segments
        // before it end, and each beat starts where the table says.
        let glyphsIndex = cut.segments.firstIndex { $0.chapter == .glyphs } ?? 0
        let glyphsAt = SizzleScript.segmentStarts(in: cut)[glyphsIndex]
        for (start, entry) in zip(SizzleScript.glyphBeatStarts, SizzleScript.glyphBeats) {
            let row = String(format: "%.3f\tglyph\t%@", glyphsAt + start, entry.glyph.rawValue)
            #expect(map.contains(row), "missing \(row)")
        }
        #expect(map.contains("# grid 120bpm"))
        // The face punch lands before the master's window opens (frame 0 IS
        // the face), so it is not a row here; everything else is.
        for kind in ["chapter\tfinale", "look\tninja", "stopdown\tfinale", "hop\thop",
                     "badge\tdone", "pounce\tone", "card\turl", "punch\tmerged", "roster\tsessions",
                     "flash-irregular\ttap"] {
            #expect(map.contains(kind), "the sidecar must name \(kind)")
        }
    }

    /// The sound editor cuts to this file with the audio off: no stretch of
    /// a master may go two bars without a row to land on.
    @Test("No two bars of silence in a master's sidecar")
    func noSilence() {
        for cut in [SizzleScript.landscape, SizzleScript.vertical] {
            let times = SizzleScript.beatMap(for: cut)
                .split(separator: "\n").filter { !$0.hasPrefix("#") }
                .compactMap { Double($0.split(separator: "\t")[0]) }
            for (a, b) in zip(times, times.dropFirst()) {
                #expect(b - a <= 2 * SizzleScript.bar + 1e-9,
                        "\(cut.name) is silent from \(a) to \(b)")
            }
        }
    }

    /// A render whose sidecar disagrees with the script is a render of a reel
    /// that no longer exists — and a critique of it is void. When a rendered
    /// set is on disk, its sidecars must be the script's.
    @Test("An on-disk sidecar matches the script")
    func noDrift() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let renders = root.appendingPathComponent("build/sizzle")
        for cut in SizzleScript.cuts {
            let base = (cut.name as NSString).deletingPathExtension
            let sidecar = renders.appendingPathComponent("\(base).beats.txt")
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            // Below the name line: the README GIF and its MP4 twin share one
            // sidecar file, and whichever wrote last named itself in it.
            func body(_ map: String) -> String { map.split(separator: "\n").dropFirst().joined(separator: "\n") }
            let onDisk = try String(contentsOf: sidecar, encoding: .utf8)
            #expect(body(onDisk) == body(SizzleScript.beatMap(for: cut)),
                    "\(cut.name)'s rendered sidecar has drifted from the script — re-render")
        }
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

    @Test("The bridge is one flash: the breath whites out, the first tap carries it down")
    func continuity() {
        let cut = SizzleScript.landscape
        let fmt = SizzleRenderer.format(for: cut)
        // Derived, not restated: the boundary is wherever the finale starts.
        let finaleIndex = cut.segments.firstIndex { $0.chapter == .finale } ?? 0
        let boundary = SizzleScript.segmentStarts(in: cut)[finaleIndex]
        let frame = 1.0 / Double(cut.fps)
        #expect(SizzleScript.isOnBeat(boundary), "the bang lands on the grid")
        // Full white one frame before the cut, and across it.
        // 1.0, not 0.9: nine tenths of white composites to a grey over a dark
        // backdrop, which is the washed-out complaint in a different room.
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: boundary - frame, fmt: fmt) > 0.99,
                "the breath must exit at full white")
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: boundary + 0.001, fmt: fmt) == 1,
                "the finale must open at the same white")
        // The white HOLDS through the first tap's plateau — one flash, not
        // two edges 0.2s apart — then rides that tap's decay down, and is
        // gone before the second tap so the second tap is its own hit.
        let tap = CrabView.celebrationFlashes[0]
        let plateauEnd = tap.at + CrabView.flashAttack + tap.hold
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: boundary + plateauEnd - 0.01, fmt: fmt) == 1)
        #expect(CrabView.epicBlanch(doneT: plateauEnd - 0.01) == 1,
                "the sprite's own tap must be inside the white")
        let secondTap = CrabView.celebrationFlashes[1].at
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: boundary + secondTap - frame, fmt: fmt) < 0.01,
                "the bridge must be gone before the second tap")
        // Light arrives fast: nothing before the attack, and the attack is
        // no longer than 0.12s.
        #expect(SizzleRenderer.matchCutFlash(cut: cut, at: boundary - SizzleRenderer.bridgeAttack - 2 * frame,
                                             fmt: fmt) < 0.01)
        // Exactly one rising edge in the whole cut.
        var risingEdges = 0
        var wasLit = false
        for index in 0..<cut.frameCount {
            let lit = SizzleRenderer.matchCutFlash(cut: cut, at: Double(index) * frame, fmt: fmt) > 0.05
            if lit && !wasLit { risingEdges += 1 }
            wasLit = lit
        }
        #expect(risingEdges == 1, "\(risingEdges) flashes in a reel allowed one")
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
        // Beat-relative time: mid-beat gestures, the last few frames rest.
        for beat in 0...3 {
            var pose = CrabPose()
            SizzleRenderer.applyGlyphReaction(beat: beat, u: 0.5, to: &pose)
            poses.append(pose)
            var rest = CrabPose()
            SizzleRenderer.applyGlyphReaction(beat: beat, u: 0.97, to: &rest)
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

    @Test("Every cut opens on the thesis, and the showcase is the master unclothed")
    func actionOpens() {
        for cut in [SizzleScript.landscape, SizzleScript.vertical,
                    SizzleScript.showcaseGradient, SizzleScript.showcaseGradientTall] {
            #expect(cut.segments.first?.chapter == .mirror, "\(cut.name) must open on the thesis")
            #expect(cut.seconds < 25.0)
        }
        #expect(SizzleScript.showcaseGradient.seconds == SizzleScript.landscape.seconds)
        #expect(SizzleScript.showcaseGradientTall.seconds == SizzleScript.vertical.seconds)
    }

    @Test("The duet holds its frame: one second, one pounce, no pan")
    func duetHolds() {
        let fmt = SizzleRenderer.format(for: SizzleScript.landscape)
        for t in [0.0, 0.3, 0.6, 0.99] {
            let shot = SizzleRenderer.shot(for: .duet, t: t, fmt: fmt)
            #expect(shot.offset == .zero && shot.side == fmt.spriteSide, "the duet camera moved at \(t)")
        }
        #expect(SizzleScript.duetPounceAt < 0.5, "the pounce must land inside the second")
    }
}

/// The reel-choreography doctrine, measured: the grid, the frame floor under
/// every ease, the grounds' contrast, the type roles, the captions'
/// readability, the boundaries, the poster frame, the button. Every rule
/// here has a number because a rule that cannot fail is not a rule.
@Suite("Reel choreography")
@MainActor
struct ReelChoreographyTests {

    private var masters: [SizzleScript.Cut] { [SizzleScript.landscape, SizzleScript.vertical] }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: Time

    @Test("Every master boundary is a beat; the finale and the montage open on bars")
    func everyBoundaryIsOnABeat() {
        for cut in masters {
            let starts = SizzleScript.segmentStarts(in: cut)
            for (start, segment) in zip(starts, cut.segments) {
                #expect(SizzleScript.isOnBeat(start),
                        "\(cut.name) \(segment.chapter) opens at \(start), off the beat")
                // The climax and the list chapter open on bar lines; the
                // outro opens on a beat (the skill asks no more of it).
                if [.finale, .montage].contains(segment.chapter) {
                    let bars = start / SizzleScript.bar
                    #expect(abs(bars - bars.rounded()) < 1e-6,
                            "\(cut.name) \(segment.chapter) opens at \(start), off the bar line")
                }
            }
            #expect(SizzleScript.isOnBeat(cut.seconds), "\(cut.name) ends off the beat")
        }
    }

    /// An ease under three output frames is a snap wearing an ease's clothes.
    /// Measured in CUT frames at the cut's fps: every run of frames in which
    /// the camera's side is changing is at least three long, every costume
    /// dissolve spans at least three frames, and the type envelope's edges do.
    @Test("No eased edge is shorter than three frames of the cut")
    func noEaseUnderThreeFrames() {
        for cut in [SizzleScript.landscape, SizzleScript.vertical, SizzleScript.meme, SizzleScript.hook] {
            let fmt = SizzleRenderer.format(for: cut)
            var run = 0
            var previous: SizzleRenderer.Shot?
            var lastChapter: SizzleScript.Chapter?
            for index in 0..<cut.frameCount {
                let t = Double(index) / Double(cut.fps)
                guard let cue = SizzleScript.resolve(cut, at: t) else { continue }
                let shot = SizzleRenderer.shot(for: cue.chapter, t: cue.localT, fmt: fmt)
                if let previous, lastChapter == cue.chapter, shot.side != previous.side {
                    run += 1
                } else {
                    if run > 0 {
                        #expect(run >= 3, "\(cut.name): a \(run)-frame side move before frame \(index)")
                    }
                    run = 0
                }
                previous = shot
                lastChapter = cue.chapter
            }
        }
        for cut in SizzleScript.cuts {
            let fmt = SizzleRenderer.format(for: cut)
            for look in cut.looks {
                let dissolve = min(0.35, look.seconds * 0.5)
                #expect(dissolve / fmt.frame >= 3 - 1e-9,
                        "\(cut.name): \(look.costume) dissolves in \(dissolve / fmt.frame) frames")
            }
            #expect(SizzleRenderer.typeAttack / fmt.frame >= 3 - 1e-9)
            // The envelope floors its own decay at three frames — sample it.
            let decayStart = 2.0
            let gone = (0...40).first { step in
                SizzleRenderer.typeEnvelope(decayStart + Double(step) * fmt.frame, from: 1.0,
                                            until: decayStart, frame: fmt.frame) < 0.01
            } ?? 0
            #expect(gone >= 3, "\(cut.name): type leaves in \(gone) frames")
        }
    }

    // MARK: Colour

    private func rgb(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private func hueSat(_ c: (r: Double, g: Double, b: Double)) -> (hue: Double, sat: Double) {
        let n = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        return (n.hueComponent * 360, n.saturationComponent)
    }

    private func bodyRGB(_ costume: Costume) -> (r: Double, g: Double, b: Double) {
        if costume == .none { return SpriteTint.bodyRGB }
        guard let ink = CostumeStyle.of(costume).inks[.body] else { return SpriteTint.bodyRGB }
        return (ink.r, ink.g, ink.b)
    }

    /// The costumes a chapter puts on screen, for a cut.
    private func cast(_ chapter: SizzleScript.Chapter, in cut: SizzleScript.Cut) -> [Costume] {
        switch chapter {
        case .montage: return cut.looks.map(\.costume)
        case .duet, .outro: return [.none, .ninja]
        default: return [.none]
        }
    }

    /// A body clears its ground by luminance (≥ 0.15) or, failing that, by
    /// hue (≥ 60° apart with both saturated) — terracotta on cobalt is the
    /// social preview's pairing and reads on hue alone. The caption ink clears
    /// its ground at the large-text ratio (≥ 3:1).
    @Test("Every ground clears every costume it carries, and its ink reads")
    func groundsClearTheirCostumes() {
        for cut in masters + [SizzleScript.meme] {
            for (chapter, ground) in cut.grounds {
                let groundRGB = rgb(ground.color)
                let groundL = luminance(groundRGB)
                let groundHS = hueSat(groundRGB)
                for costume in cast(chapter, in: cut) {
                    let body = bodyRGB(costume)
                    let deltaL = abs(luminance(body) - groundL)
                    let bodyHS = hueSat(body)
                    var deltaH = abs(bodyHS.hue - groundHS.hue)
                    deltaH = min(deltaH, 360 - deltaH)
                    let byHue = deltaH >= 60 && bodyHS.sat >= 0.25 && groundHS.sat >= 0.25
                    #expect(deltaL >= 0.15 || byHue,
                            "\(cut.name) \(chapter): \(costume) sinks into \(ground.name) (ΔL \(deltaL), Δhue \(deltaH))")
                }
                let inkL = luminance(rgb(ground.ink))
                let ratio = (max(inkL, groundL) + 0.05) / (min(inkL, groundL) + 0.05)
                #expect(ratio >= 3.0, "\(cut.name) \(chapter): ink on \(ground.name) is \(ratio):1")
            }
        }
    }

    @Test("No body tint before the finale's own")
    func noTintBeforeTheFinale() {
        for chapter in SizzleScript.Chapter.allCases where chapter != .finale {
            for t in stride(from: 0.0, through: 10.0, by: 0.5) {
                #expect(SizzleRenderer.bodyTint(for: chapter, t: t) == nil,
                        "\(chapter) tints the body at \(t)")
            }
        }
        #expect(SizzleRenderer.bodyTint(for: .finale, t: 5.0) != nil, "the finale is the colour")
    }

    // MARK: Type

    @Test("Type roles sit on the sprite's cell grid, a step apart, over whole-cell margins")
    func typeRolesAreOnTheCellGrid() {
        for cut in SizzleScript.cuts {
            let fmt = SizzleRenderer.format(for: cut)
            let cell = fmt.cell
            for (name, size) in [("tag", fmt.tag), ("caption", fmt.caption), ("wordmark", fmt.wordmark),
                                 ("shout", fmt.caption * fmt.captionScale)] {
                #expect(abs(size.truncatingRemainder(dividingBy: cell)) < 1e-6,
                        "\(cut.name) \(name) \(size)pt is off the \(cell)pt cell")
            }
            #expect(fmt.caption >= 1.25 * fmt.tag && fmt.wordmark >= 1.25 * fmt.caption,
                    "\(cut.name): roles are not a step apart")
            #expect(abs(fmt.bottomMargin.truncatingRemainder(dividingBy: cell)) < 1e-6
                    && fmt.bottomMargin >= 3 * cell,
                    "\(cut.name): bottom margin \(fmt.bottomMargin) is not whole cells")
            if fmt.vertical {
                #expect(fmt.bottomMargin >= cut.canvas.height * 0.25,
                        "\(cut.name): type sits inside the platform band")
            }
        }
    }

    /// ≤ 5 words, ≤ 45 characters, held long enough to read and never past
    /// three seconds; proven by the frame it declares; gone half a second
    /// before its segment ends; and type owns under half of any cut.
    @Test("Every caption is readable, proven, and gone before the cut")
    func captionsAreReadable() {
        for cut in SizzleScript.cuts {
            let fmt = SizzleRenderer.format(for: cut)
            let starts = SizzleScript.segmentStarts(in: cut)
            var distinct = Set<String>()
            for (chapter, caption) in fmt.captions where chapter != .outro && chapter != .wake {
                distinct.insert(caption.wide)
                let words = caption.wide.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
                let chars = caption.wide.filter { $0 != "\n" }.count
                #expect(words <= 5 && chars <= 45, "\(cut.name) \(chapter): \"\(caption.wide)\"")
                #expect(caption.tall.split(whereSeparator: { $0 == " " || $0 == "\n" }).count == words,
                        "\(cut.name) \(chapter): the tall line says something else")
                let hold = caption.until - caption.from
                #expect(hold >= max(0.83, Double(chars) / 15) - 1e-9 && hold <= 3.0,
                        "\(cut.name) \(chapter) holds \(hold)s for \(chars) chars")
                for (start, segment) in zip(starts, cut.segments) where segment.chapter == chapter {
                    guard case .window(let offset) = segment.kind else { continue }
                    _ = start
                    let end = offset + segment.seconds
                    func at(_ local: Double) -> Double {
                        SizzleRenderer.typeEnvelope(local, from: caption.from, until: caption.until,
                                                    frame: fmt.frame)
                    }
                    let peak = stride(from: offset, to: end, by: fmt.frame).map(at).max() ?? 0
                    #expect(peak >= 0.9, "\(cut.name) \(chapter): the caption never shows")
                    if let proves = caption.proves, proves >= offset, proves < end {
                        #expect(at(proves - 0.3) >= 0.9,
                                "\(cut.name) \(chapter): the line arrives after its proof")
                    }
                    #expect(at(end - 0.5) <= 0.1,
                            "\(cut.name) \(chapter): the caption is still up half a second before the cut")
                }
            }
            #expect(distinct.count <= 3, "\(cut.name) makes \(distinct.count) claims")

            // Type-on time, whole cut: captions past a tenth, or a card.
            guard fmt.type else { continue }
            var on = 0
            var uncaptioned = Set<SizzleScript.Chapter>()
            for index in 0..<cut.frameCount {
                let t = Double(index) / Double(cut.fps)
                guard let cue = SizzleScript.resolve(cut, at: t) else { continue }
                if cue.chapter == .outro || cue.chapter == .wake {
                    on += 1
                } else if let caption = fmt.captions[cue.chapter] {
                    if SizzleRenderer.typeEnvelope(cue.localT, from: caption.from, until: caption.until,
                                                   frame: fmt.frame) > 0.1 { on += 1 }
                } else {
                    uncaptioned.insert(cue.chapter)
                }
            }
            #expect(Double(on) / Double(cut.frameCount) <= 0.5,
                    "\(cut.name): type is up \(100 * on / cut.frameCount)% of the runtime")
            #expect(uncaptioned.count >= 2, "\(cut.name): only \(uncaptioned) go without a caption")
        }
    }

    /// SwiftUI never wraps reel type: every authored line fits its canvas
    /// inside the margins (and, on 9:16, clear of the right-hand band).
    @Test("Every authored caption line fits its canvas")
    func authoredLineBreaks() {
        for cut in SizzleScript.cuts {
            let fmt = SizzleRenderer.format(for: cut)
            guard fmt.type else { continue }
            let size = fmt.caption * fmt.captionScale
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)
            let rightBand = fmt.vertical ? cut.canvas.width * 0.15 : 0
            let available = cut.canvas.width - 3 * fmt.cell - max(3 * fmt.cell, rightBand)
            for (chapter, caption) in fmt.captions {
                for line in caption.text(vertical: fmt.vertical).split(separator: "\n") {
                    let width = (String(line) as NSString).size(withAttributes: [.font: font]).width
                    #expect(width <= available,
                            "\(cut.name) \(chapter): \"\(line)\" is \(width)pt of \(available)pt")
                }
            }
        }
    }

    @Test("Reel type is seven-bit; the bubbles keep the product's own strings")
    func sevenBitReelType() {
        for table in [SizzleScript.captions, SizzleScript.memeCaptions] {
            for (chapter, caption) in table {
                for text in [caption.wide, caption.tall] {
                    #expect(text.unicodeScalars.allSatisfy { $0.isASCII },
                            "\(chapter): \"\(text)\" carries non-ASCII reel type")
                }
            }
        }
        #expect(SizzleScript.url.unicodeScalars.allSatisfy { $0.isASCII })
    }

    @Test("One wordmark, in one file")
    func oneWordmark() throws {
        let sources = packageRoot.appendingPathComponent("Sources/ClaudePet")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
        // Wordmark.swift is the one file allowed the literal — and its doc
        // comment names the caps version it replaced, so it is skipped whole.
        for file in files where !file.hasSuffix("Wordmark.swift") {
            let text = try source("Sources/ClaudePet/\(file)")
            #expect(!text.contains("\"CLAUDE PET\""), "\(file) sets the wordmark in caps")
            #expect(!text.contains("\"Claude Pet\""), "\(file) restates the wordmark")
        }
    }

    /// The type paths ride the asymmetric envelope, never the symmetric
    /// window — and reel furniture is square, unscaled, ungraded.
    @Test("Type never rides a symmetric window; reel furniture is square")
    func typeAndFurnitureHygiene() throws {
        // Code only: the header comment names `.scaleEffect` as the thing the
        // camera must never be, which is not a use of it.
        let renderer = try source("Sources/ClaudePet/App/SizzleRenderer.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let typeStart = try #require(renderer.range(of: "static let typeAttack")).lowerBound
        let typeEnd = try #require(renderer.range(of: "private static func chapterLayout(")).lowerBound
        let typeSection = String(renderer[typeStart..<typeEnd])
        #expect(!typeSection.contains("Ease.window("), "type rides a symmetric window")
        for forbidden in ["cornerRadius", ".scaleEffect", ".blur(", ".shadow(", "RadialGradient"] {
            #expect(!renderer.contains(forbidden), "reel furniture uses \(forbidden)")
        }
        #expect(renderer.components(separatedBy: "LinearGradient").count == 2,
                "the showcase dusk is the one sanctioned gradient")
    }

    // MARK: The cut

    /// A hard cut changes the frame in at least two of: sprite side (a grid
    /// step), sprite centre (a tenth of the width), the ground, whether the
    /// chapter carries type, the mood. A change of caption text alone is not
    /// a cut. The bridged boundary is exempt: the white IS the change.
    @Test("Every master boundary changes the frame twice over")
    func everyCutChangesTheFrame() {
        for cut in masters {
            let fmt = SizzleRenderer.format(for: cut)
            let frame = fmt.frame
            let starts = SizzleScript.segmentStarts(in: cut)
            for index in 1..<cut.segments.count {
                let before = cut.segments[index - 1]
                let after = cut.segments[index]
                if before.chapter == .breath && after.chapter == .finale { continue }
                guard let a = SizzleScript.resolve(cut, at: starts[index] - frame),
                      let b = SizzleScript.resolve(cut, at: starts[index]) else {
                    Issue.record(Comment(rawValue: "\(cut.name): boundary \(index) does not resolve")); continue
                }
                let shotA = SizzleRenderer.shot(for: a.chapter, t: a.localT, fmt: fmt)
                let shotB = SizzleRenderer.shot(for: b.chapter, t: b.localT, fmt: fmt)
                var differences: [String] = []
                if abs(shotA.side - shotB.side) >= 32 { differences.append("side") }
                let shift = hypot(shotA.offset.x - shotB.offset.x, shotA.offset.y - shotB.offset.y)
                if shift >= cut.canvas.width * 0.1 { differences.append("centre") }
                if fmt.grounds[a.chapter] != fmt.grounds[b.chapter] { differences.append("ground") }
                func typed(_ chapter: SizzleScript.Chapter) -> Bool {
                    fmt.captions[chapter] != nil || chapter == .outro || chapter == .wake
                }
                if typed(a.chapter) != typed(b.chapter) { differences.append("type") }
                if SizzleRenderer.mood(for: a.chapter, t: a.localT, fmt: fmt)
                    != SizzleRenderer.mood(for: b.chapter, t: b.localT, fmt: fmt) {
                    differences.append("mood")
                }
                #expect(differences.count >= 2,
                        "\(cut.name) \(before.chapter)→\(after.chapter) changes only \(differences)")
            }
        }
    }

    // MARK: Shape

    @Test("Frame 0 is the poster: the thesis, big, with nothing mid-fade")
    func frameZeroIsThePoster() {
        for cut in masters {
            let fmt = SizzleRenderer.format(for: cut)
            guard let cue = SizzleScript.resolve(cut, at: 0) else { Issue.record(Comment(rawValue: cut.name)); continue }
            #expect(cue.chapter == .mirror, "\(cut.name) opens on \(cue.chapter), not the thesis")
            let shot = SizzleRenderer.shot(for: cue.chapter, t: cue.localT, fmt: fmt)
            #expect(shot.side >= cut.canvas.height * 0.4,
                    "\(cut.name): he is \(shot.side)pt tall on a \(cut.canvas.height)pt frame")
            #expect(shot.side == fmt.punchSide, "\(cut.name): frame 0 should be the face")
            for (chapter, caption) in fmt.captions where chapter == cue.chapter {
                let presence = SizzleRenderer.typeEnvelope(cue.localT, from: caption.from,
                                                           until: caption.until, frame: fmt.frame)
                #expect(presence == 0 || presence >= 0.95, "\(cut.name): frame 0 type is mid-fade")
            }
            // The thesis line is up and the session signal follows within 3s.
            #expect(fmt.captions[.mirror] != nil)
            #expect(cue.localT <= 2.0, "\(cut.name): the working bubble arrives after 3.0s")
        }
    }

    @Test("The finale is the star: longest by a bar's margin, the largest stop, first hit in the window")
    func finaleIsTheStar() {
        for cut in masters {
            let fmt = SizzleRenderer.format(for: cut)
            let finale = cut.segments.first { $0.chapter == .finale }?.seconds ?? 0
            let rest = cut.segments.filter { $0.chapter != .finale }.map(\.seconds).max() ?? 0
            #expect(finale - rest >= 1.5, "\(cut.name): the finale is not the longest by 1.5s")
            #expect(fmt.heroSide > fmt.punchSide && fmt.heroSide > fmt.spriteSide,
                    "\(cut.name): the finale's stop is not the largest")
            #expect(fmt.heroSide - fmt.punchSide >= 32, "by at least one grid step")
            let starts = SizzleScript.segmentStarts(in: cut)
            let finaleIndex = cut.segments.firstIndex { $0.chapter == .finale } ?? 0
            let firstHit = starts[finaleIndex] + CrabView.celebrationFlashes[0].at
            let fraction = firstHit / cut.seconds
            #expect(fraction >= 0.25 && fraction <= 0.40,
                    "\(cut.name): the first hit lands at \(Int(fraction * 100))% of the runtime")
            #expect(starts[finaleIndex] <= finale, "the build is longer than the payoff")
            // The stopdown sits immediately before it.
            #expect(cut.segments[finaleIndex - 1].chapter == .breath, "\(cut.name): no breath before the bang")
            let breath = cut.segments[finaleIndex - 1].seconds
            #expect(breath >= 0.4 && breath <= 0.8)
        }
    }

    @Test("The button holds: the URL is up for two and a half seconds and nothing else moves")
    func theButtonHolds() {
        for cut in masters {
            let fmt = SizzleRenderer.format(for: cut)
            let outro = cut.segments.last
            #expect(outro?.chapter == .outro)
            let seconds = outro?.seconds ?? 0
            // The URL arrives by 0.1 + the type attack; from there it holds.
            let urlFullBy = 0.1 + SizzleRenderer.typeAttack
            #expect(seconds - urlFullBy >= 2.5, "\(cut.name): the URL reads for \(seconds - urlFullBy)s")
            for t in stride(from: seconds - 0.5, to: seconds, by: fmt.frame) {
                let shot = SizzleRenderer.shot(for: .outro, t: t, fmt: fmt)
                #expect(shot.offset == .zero && shot.side == fmt.spriteSide,
                        "\(cut.name): the camera moves under the end card")
            }
            // The URL appears in exactly one place.
            let urlChapters = fmt.captions.values.filter { $0.wide.contains("github.com") }
            #expect(urlChapters.isEmpty, "the URL is a card line, never a caption")
        }
    }
}
