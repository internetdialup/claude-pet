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
        for cut in SizzleScript.cuts {
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

    @Test("The must-shows are protected in every cut that carries them")
    func mustShows() {
        // The finale plays complete in both social cuts, and at least 8s in
        // the README loop.
        for cut in [SizzleScript.landscape, SizzleScript.vertical] {
            let finale = cut.segments.first { $0.chapter == .finale }
            #expect(finale?.seconds == 10.0, "\(cut.name) must carry the whole finale")
        }
        let readmeFinale = SizzleScript.readme.segments.first { $0.chapter == .finale }
        #expect((readmeFinale?.seconds ?? 0) >= 8.0)

        // The montage carries every look, ending on Classic for the loop seam.
        #expect(Set(SizzleScript.montageOrder) == Set(Costume.allCases))
        #expect(SizzleScript.montageOrder.last == Costume.none)

        // The glyph chapter shows every service.
        #expect(SizzleScript.glyphBeats.map(\.glyph) == ServiceGlyph.allCases)
    }

    @Test("Every canvas is H.264-even at its scale")
    func canvasEvenness() {
        for cut in SizzleScript.cuts {
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
            #expect(a != nil && a == b, "frame at t=\(t) must be reproducible")
        }
    }

    private func frameData(cut: SizzleScript.Cut, t: Double) -> Data? {
        let index = Int((t * Double(cut.fps)).rounded())
        guard let image = SizzleRenderer.testFrame(cut: cut, index: index) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}
