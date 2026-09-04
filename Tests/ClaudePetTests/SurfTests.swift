import Testing
import Foundation
@testable import ClaudePet

/// 🌊 The surf set: a swell rolls through and he rides it.
@Suite("Surf")
@MainActor
struct SurfTests {

    /// The ocean is not there until the spell says so, and never at rest.
    @Test("No swell at the frozen instant, and none in cycle zero")
    func nothingIsWetAtTimeZero() {
        for mood in PetMood.allCases {
            #expect(CrabAnimator.pose(mood: mood, t: 0, flourishes: true).surf == nil)
        }
        // Cycle zero never fires, the way every spell in this rig behaves.
        for t in stride(from: 0.0, through: SpawnRates.surfSet.period - 1, by: 3) {
            #expect(CrabAnimator.surfSet(idleT: t) == nil, "a swell ran in cycle zero at t=\(t)")
        }
        #expect(CrabRig.render(CrabPose()).cells == CrabRig.render(CrabPose()).cells)
    }

    /// It arrives and leaves off-grid: the crest starts right of the frame
    /// and finishes left of it, so no cell of water ever appears from
    /// nothing or vanishes into it.
    @Test("The swell enters and leaves off the grid")
    func theSwellNeverPopsIn() {
        #expect(SurfSet.crest(at: 0) > Double(PixelBuffer.side))
        #expect(SurfSet.crest(at: 1) < 0)
        // …and it stands up and settles rather than switching on.
        #expect(SurfSet.lift(at: 0) == 0)
        #expect(SurfSet.lift(at: 1) == 0)
        #expect(SurfSet.lift(at: 0.5) > 0.9)

        var previous = 0
        for step in 0...200 {
            let p = Double(step) / 200
            var pose = CrabPose()
            pose.surf = p
            let b = CrabRig.render(pose)
            var wet = 0
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side
                where b[x, y] == .water || b[x, y] == .waterDeep { wet += 1 }
            }
            // No frame may add or drop a whole sea at once.
            #expect(abs(wet - previous) < 90,
                    "the sea jumped by \(abs(wet - previous)) cells at p=\(p)")
            previous = wet
        }
    }

    /// **The water frames him and never paints over him.**
    ///
    /// This began as a barrel — a lip curling in FRONT of him — which would
    /// have been the first ambience-class draw in the app to overpaint the
    /// crab. It did not fit at this size and was dropped, so the promise
    /// `HolidayAmbience` makes still holds everywhere. This is the pin that
    /// keeps it true if anyone tries again.
    @Test("The sea never covers the crab")
    func theSeaFramesHim() {
        for step in 0...60 {
            let p = Double(step) / 60
            var dry = CrabAnimator.pose(mood: .idle, t: 3 + p * 14, flourishes: false)
            CrabAnimator.applySurf(p, t: 3 + p * 14, to: &dry)
            var without = dry
            without.surf = nil
            let wet = CrabRig.render(dry), bare = CrabRig.render(without)
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side {
                    let before = bare[x, y]
                    guard before != .clear else { continue }
                    let after = wet[x, y]
                    #expect(after == before,
                            "the sea painted \(after) over \(before) at (\(x),\(y)), p=\(p)")
                }
            }
        }
    }

    /// He rides the water rather than hovering over it: his board sits on
    /// the surface at his own column, so he rises and falls WITH the swell.
    @Test("He rides the surface, not a curve of his own")
    func heRidesTheWater() {
        var highest = 0, lowest = 0
        for step in 0...60 {
            let p = Double(step) / 60
            var pose = CrabAnimator.pose(mood: .idle, t: 3, flourishes: false)
            CrabAnimator.applySurf(p, t: 3, to: &pose)
            #expect(pose.prop == .surfboard, "he lost the board at p=\(p)")
            let surface = SurfSet.surface(16, crest: SurfSet.crest(at: p),
                                          lift: SurfSet.lift(at: p))
            // On the swell he sits ON the surface; on flat water — where
            // the sea is still easing up from below the grid — he stands at
            // his own height rather than sinking to meet it.
            #expect(25 + pose.bob == min(25, max(13, surface)),
                    "the board is off the water at p=\(p)")
            highest = min(highest, pose.bob)
            lowest = max(lowest, pose.bob)
        }
        #expect(highest < -4, "the swell never lifted him (best \(highest))")
        #expect(lowest == 0, "he never settled back to standing height")
    }
}
