import Testing
import Foundation
import SwiftUI
@testable import ClaudePet

/// ✏️ **Three pins, and only three.**
///
/// The sketchpad's whole point is that it carries no ceremony — no kill-tests,
/// no Knob, no anonymity sweep, because nothing it draws ships. But a silently
/// wrong *exporter* costs a real evening, so these three stay: they are the
/// only claims whose failure would be invisible until you had already sent
/// somebody the file.
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
}
