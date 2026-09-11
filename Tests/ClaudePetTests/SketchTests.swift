import Testing
import Foundation
import SwiftUI
@testable import ClaudePet

/// ✏️ **A short suite, on purpose.**
///
/// The sketchpad carries no ceremony — no Knob, no anonymity sweep, because
/// nothing it draws ships. What is pinned here is only what would fail
/// *silently*: an exporter that writes at the wrong rate, a scene that drifts
/// from the window it was previewed in, and an effect that quietly never
/// reaches the tool at all. Each of those you would discover after sending
/// somebody the file, which is too late to be worth the saving.
///
/// The last two are the coms-bridge: tricks and costumes reach the sketchpad
/// by themselves through `allCases`, so the only thing that can go missing is
/// a new *effect*, and `noEffectIsStrandedFromTheSketchpad` is what makes that
/// impossible to do by accident.
@Suite(.serialized)
@MainActor
struct SketchTests {

    /// 🔎 THE CONVENTION THE WHOLE TOOL RESTS ON. The live window and the
    /// exporter are the same function called on different clocks, so if the
    /// scene is not pure in `t` the GIF you get is not the loop you watched —
    /// and you would only find out by comparing them frame by frame.
    @Test("The scene is pure in t")
    func theSceneIsPureInT() {
        var stack = SketchScene.Stack.starter
        stack.layers.append(.init(kind: .canvas,
                                  preset: SketchScene.CanvasPreset.party.rawValue))
        stack.layers.append(.init(kind: .sprite,
                                  preset: SketchScene.SpritePreset.snow.rawValue))

        func bytes(_ t: Double) -> Data? {
            (SpriteImage.cgImage(of: SketchScene.scene(stack, t: t),
                                 scale: 1, isOpaque: true)?.dataProvider?.data) as Data?
        }
        let first = bytes(1.25)
        #expect(first != nil, "the scene did not render at all")
        // Six, not two: the glyph cache is process-global and its first few
        // draws disagree with every draw after.
        for repetition in 1..<6 {
            #expect(bytes(1.25) == first, "render \(repetition + 1) differs from the first")
        }
        // …and it is not pure by being static. A different t must differ.
        #expect(bytes(1.30) != first, "nothing moves between frames")
    }

    /// The bubble is the one layer whose whole point is that it changes with
    /// the loop clock — every other product surface freezes it deliberately.
    /// So it gets both halves: it must type, and it must still be pure.
    @Test("A bubble layer types on the loop clock, and is still pure in t")
    func theBubbleTypesOnTheLoopClock() {
        var stack = SketchScene.Stack(layers: [
            .init(kind: .bubble, text: "Let's build something awesome!"),
        ])
        stack.beats = 8

        func bytes(_ t: Double) -> Data? {
            (SpriteImage.cgImage(of: SketchScene.scene(stack, t: t),
                                 scale: 1, isOpaque: true)?.dataProvider?.data) as Data?
        }
        let start = bytes(0)
        #expect(start != nil, "the bubble layer did not render")
        #expect(bytes(0.5) != start, "the bubble did not type — it is frozen")
        // …and asking twice at one instant still gives one answer.
        #expect(bytes(0.5) == bytes(0.5), "the bubble layer is not pure in t")
    }

    /// Catches an H.264 hard-fail and a smeared column before either costs a
    /// render: the encoder refuses odd dimensions outright, and a sprite side
    /// that is not a whole number of cells puts a seam down every few columns.
    @Test("Every shape is whole-cell, even, and does not crop")
    func everyShapeIsWholeCellAndEven() {
        #expect(!SketchScene.shapes.isEmpty)
        for shape in SketchScene.shapes {
            #expect(shape.sprite.truncatingRemainder(dividingBy: 32) == 0,
                    "\(shape.name)'s sprite is \(shape.sprite)pt — not a whole cell")
            #expect(shape.cell == shape.cell.rounded(),
                    "\(shape.name)'s cell is \(shape.cell)pt")
            #expect(shape.canvas.width.truncatingRemainder(dividingBy: 2) == 0
                    && shape.canvas.height.truncatingRemainder(dividingBy: 2) == 0,
                    "\(shape.name) is \(shape.canvas) — H.264 refuses odd dimensions")
            #expect(shape.sprite <= min(shape.canvas.width, shape.canvas.height),
                    "\(shape.name)'s sprite does not fit its canvas")
        }
    }

    /// The whole export pipeline, end to end, into a temp directory. Not a
    /// ceremony pin — a smoke test, because every other check here is about
    /// numbers and this is the one that would catch the encoder having stopped
    /// producing a file at all.
    @Test("Both exports actually write a file")
    func bothExportsWriteAFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawd-sketch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Two beats, the shortest loop, so the test stays quick.
        var stack = SketchScene.Stack.starter
        stack.beats = 2

        let gif = Sketchpad.writeGIF(stack, to: dir)
        #expect(gif != nil, "the GIF export produced nothing")
        if let gif {
            let size = try gif.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            #expect(size > 1024, "the GIF is \(size) bytes — that is not a clip")
        }

        let mp4 = Sketchpad.writeVideo(stack, to: dir)
        #expect(mp4 != nil, "the MP4 export produced nothing")
        if let mp4 {
            let size = try mp4.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            #expect(size > 1024, "the MP4 is \(size) bytes — that is not a clip")
        }
    }

    /// 🔎 The bug `GifRenderer`'s own doc warns about in capitals: a GIF stores
    /// its delay in whole centiseconds, so sampling at one rate and declaring
    /// another ships a clip that plays at a speed nobody chose. The exporter
    /// strides by `frameDelay` and passes `frameDelay`, and this pins that they
    /// are the same number AND that the number survives the round trip.
    @Test("The GIF stride matches its declared delay, in whole centiseconds")
    func theGifStrideMatchesItsDelay() {
        let delay = SketchScene.frameDelay
        #expect(delay == 1.0 / Double(SketchScene.fps),
                "the stride \(delay) is not 1/\(SketchScene.fps)")
        let centiseconds = delay * 100
        #expect(abs(centiseconds - centiseconds.rounded()) < 1e-9,
                "\(delay)s is \(centiseconds) centiseconds — GIF will round it and play off-rate")

        // The loop is a whole number of frames at both rates, so neither export
        // ends on a fraction of one.
        var stack = SketchScene.Stack.starter
        for beats in [2, 4, 8, 16] {
            stack.beats = beats
            let gif = stack.seconds * Double(SketchScene.fps)
            let mp4 = stack.seconds * Double(SketchScene.videoFps)
            #expect(abs(gif - gif.rounded()) < 1e-9, "\(beats) beats is \(gif) GIF frames")
            #expect(abs(mp4 - mp4.rounded()) < 1e-9, "\(beats) beats is \(mp4) MP4 frames")
        }
    }

    // MARK: - The coms-bridge

    /// Every preset actually draws something. Catches one wired to nothing, or
    /// one whose underlying function changed out from under it.
    @Test("Every preset draws something")
    func everyPresetRenders() {
        func bytes(_ layers: [SketchScene.Layer]) -> Data? {
            var stack = SketchScene.Stack(layers: layers)
            stack.beats = 8
            // Sampled across the loop, because several presets are born and die
            // on their own schedule — a firework is nothing for most of a second.
            var all = Data()
            for t in [0.35, 1.1, 2.6, 3.9] {
                guard let frame = (SpriteImage.cgImage(of: SketchScene.scene(stack, t: t),
                                                       scale: 1, isOpaque: true)?
                    .dataProvider?.data) as Data? else { return nil }
                all.append(frame)
            }
            return all
        }
        let empty = bytes([])
        #expect(empty != nil, "an empty sketch did not render")

        for preset in SketchScene.CanvasPreset.allCases {
            #expect(bytes([.init(kind: .canvas, preset: preset.rawValue)]) != empty,
                    "the \(preset.rawValue) preset drew nothing at all")
        }
        for preset in SketchScene.SpritePreset.allCases {
            #expect(bytes([.init(kind: .sprite, preset: preset.rawValue)]) != empty,
                    "the \(preset.rawValue) preset drew nothing at all")
        }
    }

    /// 🔎 THE DRIFT PIN — the reason a new effect cannot go missing.
    ///
    /// Tricks, costumes, moods and preview effects reach the sketchpad on their
    /// own: every picker reads `allCases`, so a new `Flourish` appears the
    /// moment it exists. **Effects do not.** The preset enums are hand-written,
    /// so an effect added without a preset case is invisible to the tool
    /// forever, and nothing says so.
    ///
    /// So this counts them. Every non-private draw function under `Sources` is
    /// either claimed by a preset or named below with a reason. Adding one and
    /// doing neither fails here with the whole inventory printed — which is the
    /// point. It forces the decision at the moment the effect is written rather
    /// than relying on anybody remembering months later.
    ///
    /// Blunt on purpose: it will fire for draw functions that should never be
    /// presets, and the answer to those is a line in `exempt`, not a weaker
    /// test. A list of "we looked and decided no" is worth more than a list
    /// nobody maintains.
    @Test("No effect is stranded from the sketchpad")
    func noEffectIsStrandedFromTheSketchpad() {
        // Components of drawing the crab, his board or his wardrobe — not
        // layers anyone could stack on their own.
        let exempt: Set<String> = [
            "Sketch.swift:drawSprite",        // IS the custom layer
            "Sketch.swift:drawCanvas",        // …and its other half
            "CrabCostume.swift:draw",         // the wardrobe, drawn with him
            "CrabRig.swift:drawWheel",        // one wheel of a board
            "CrabRig.swift:drawRestingDeck",  // the board he stands on
            "SurfSet.swift:drawSpray",        // needs the swell's own surface array
        ]

        // 🔎 A LIST, not a set, and that distinction is load-bearing.
        // `PetRootView.swift` holds three different functions all called
        // `draw` — CelebrationGlow's, WaitingLight's and RainbowRays' — so a
        // set keyed on file-and-name silently collapses them to one and
        // under-counts by two. The first version of this test did exactly
        // that, and reported 21 where the truth is 23.
        let found = Self.declaredDraws()
        let unique = Set(found)
        let claimed = SketchScene.CanvasPreset.allCases.count
            + SketchScene.SpritePreset.allCases.count
        let accounted = claimed + exempt.count

        // Against the COUNT, deliberately. Matching names would mean teaching
        // the test which function each preset wraps — a second mapping, which
        // is a second thing to drift, solving drift.
        let note = "\(found.count) non-private draw functions under Sources, but "
            + "\(claimed) presets + \(exempt.count) exempt = \(accounted). "
            + "Something was added: wire it as a preset, or add it to `exempt` "
            + "and say why.\nfound:\n  " + found.sorted().joined(separator: "\n  ")
        #expect(found.count == accounted, "\(note)")

        // …and the exempt list has not rotted either.
        for name in exempt {
            #expect(unique.contains(name),
                    "`\(name)` is exempted but no longer exists — drop the line")
        }
    }

    /// Every non-private `draw…` taking a `GraphicsContext` or a `PixelBuffer`,
    /// as `File.swift:functionName`.
    private static func declaredDraws() -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // ClaudePetTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // the repo
            .appendingPathComponent("Sources/ClaudePet")

        var found: [String] = []
        let files = (FileManager.default.enumerator(at: root,
                                                    includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                guard !line.contains("private"),
                      line.contains("static func draw"),
                      line.contains("inout GraphicsContext") || line.contains("inout PixelBuffer"),
                      let keyword = line.range(of: "static func "),
                      let open = line[keyword.upperBound...].firstIndex(of: "(")
                else { continue }
                found.append("\(file.lastPathComponent):\(line[keyword.upperBound..<open])")
            }
        }
        return found
    }
}
