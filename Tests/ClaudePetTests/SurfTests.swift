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

    /// He rides the FACE of the swell — part-way up it, not perched on the
    /// crest — and his height is still derived from the water's own surface
    /// so the two cannot drift apart.
    @Test("He rides the face, and never above the wave")
    func heRidesTheWater() {
        var highest = 0, lowest = 0
        for step in 0...60 {
            let p = Double(step) / 60
            var pose = CrabAnimator.pose(mood: .idle, t: 3, flourishes: false)
            CrabAnimator.applySurf(p, t: 3, to: &pose)
            #expect(pose.prop == .surfboard, "he lost the board at p=\(p)")
            let surface = SurfSet.surface(16, crest: SurfSet.crest(at: p),
                                          lift: SurfSet.lift(at: p),
                                          sea: SurfSet.sea(at: p))
            // Never below his own standing height…
            #expect(pose.bob <= 0, "he sank below standing height at p=\(p)")
            // …and once a swell has actually lifted him, he is ON its face
            // rather than floating over the top of it. Before that the sea
            // is still below the grid, so "above the water" is where he is
            // supposed to be — it is flat water, not a wave.
            if pose.bob < 0 {
                #expect(25 + pose.bob >= surface,
                        "he rode above the wave at p=\(p)")
            }
            highest = min(highest, pose.bob)
            lowest = max(lowest, pose.bob)
        }
        #expect(highest == -6, "the crest should lift him six rows, not \(-highest)")
        #expect(lowest == 0, "he never settled back to standing height")
    }

    /// **A wave, not a hill.** The swell was a symmetric Gaussian, which at
    /// 32×32 read as a lump of blue with a crab on top — the operator's note.
    /// A real swell is steep on the face it breaks down and long on the back
    /// it drags, and the crest travels leftward here, so the left side is the
    /// face.
    @Test("The swell is steeper on its face than on its back")
    func theWaveHasAFace() {
        let crest = 16.0, lift = 1.0, sea = 1.0
        let peak = SurfSet.surface(16, crest: crest, lift: lift, sea: sea)
        let onFace = SurfSet.surface(11, crest: crest, lift: lift, sea: sea)
        let onBack = SurfSet.surface(21, crest: crest, lift: lift, sea: sea)
        // Both sides fall away from the crest (surface y grows downward).
        #expect(onFace > peak && onBack > peak, "the crest is not the highest point")
        // …and the face falls away FASTER at the same distance out.
        #expect(onFace - peak > onBack - peak,
                "five cells out, the face dropped \(onFace - peak) and the back \(onBack - peak)")
    }

    /// **The wave carries him.** A crest crossing at a constant rate lifts
    /// him and sets him down; one that slows while it has him is a ride. The
    /// eased sweep is what makes the difference, so it is pinned as a rate:
    /// the middle of the ride must be visibly slower than the ends.
    @Test("The crest slows down while it has him")
    func theCrestLingers() {
        func speed(around p: Double) -> Double {
            abs(SurfSet.crest(at: p + 0.02) - SurfSet.crest(at: p - 0.02))
        }
        let middle = speed(around: 0.5)
        let entry = speed(around: 0.1)
        let exit = speed(around: 0.9)
        #expect(middle < entry * 0.7,
                "the crest runs at \(middle) through the middle and \(entry) on the way in")
        #expect(middle < exit * 0.7,
                "the crest runs at \(middle) through the middle and \(exit) on the way out")
        // And it still crosses the whole grid, start to finish.
        #expect(SurfSet.crest(at: 0) > 30 && SurfSet.crest(at: 1) < -10)
    }

    /// The spray and the wake have to be drawn where they can be SEEN. Both
    /// were first laid within a couple of cells of his centre, which is
    /// inside a silhouette running about x=10 to x=22 — and the crab is drawn
    /// after the water, so every one of those cells was painted over. The
    /// effect existed only in the buffer.
    @Test("The whitewater lands clear of the crab")
    func sprayIsWhereItCanBeSeen() {
        var buffer = PixelBuffer()
        var top = [Int](repeating: 26, count: PixelBuffer.side)
        for x in 0..<PixelBuffer.side { top[x] = 26 }
        SurfSet.drawSpray(&buffer, top: top, crest: 20, lift: 1.0)
        var marks: [Int] = []
        for x in 0..<PixelBuffer.side {
            for y in 0..<PixelBuffer.side where buffer[x, y] == .paper { marks.append(x) }
        }
        #expect(!marks.isEmpty, "no whitewater at full lift")
        #expect(marks.allSatisfy { $0 < 11 },
                "whitewater at columns \(marks.filter { $0 >= 11 }) would be hidden behind him")
    }

}
