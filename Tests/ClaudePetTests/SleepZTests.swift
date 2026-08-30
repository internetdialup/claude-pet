import Testing
import Foundation
@testable import ClaudePet

/// The zZz's, and the two constraints they live between.
///
/// Above: `sleeping.gif` is exactly one breath long and has to LOOP, so a glyph
/// still in the air when the clip ends is a visible seam. Below: the operator
/// wants to SEE them, and after dark wants to see more. Every number in
/// `CrabAnimator`'s sleep block is the result of those two pulling against each
/// other — the first attempt satisfied the second and broke the first.
@Suite("Sleep zZz")
struct SleepZTests {

    private var day: Double { CrabAnimator.sleepZInterval(hourOfDay: 14) }
    private var night: Double { CrabAnimator.sleepZInterval(hourOfDay: 2) }

    // MARK: - The loop

    /// **The constraint that shaped everything else.** Nothing may be in the
    /// air at t=0 or at the end of a breath, or the clip does not close.
    ///
    /// Checked at BOTH densities even though only the daytime one is ever
    /// rendered: night is one edit away from being rendered, and a seam that
    /// only appears after 22:00 is the kind of bug nobody reproduces.
    @Test("No zZz is in the air at either end of a breath")
    func theLoopCloses() {
        let breath = CrabAnimator.breathPeriod
        for (label, interval) in [("day", day), ("night", night)] {
            for t in [0.0, breath, breath * 2, breath * 3] {
                let aloft = CrabAnimator.sleepZSpawns(t: t, interval: interval)
                #expect(aloft.isEmpty,
                        "\(label): \(aloft.count) zZz still up at t=\(t) — the clip would seam")
            }
        }
    }

    /// The frozen sentinel, stated on the rendered frame rather than the table:
    /// `still-sleeping.png` is sampled at t=0.4 and the sizzle's wake chapter
    /// opens on the same instant, so a glyph climbing at zero would print into
    /// both.
    @Test("t=0 renders no zZz at all")
    func nothingAtTimeZero() {
        let pose = CrabAnimator.pose(mood: .sleeping, t: 0, flourishes: false)
        let bare = CrabAnimator.pose(mood: .working, t: 0, flourishes: false)
        #expect(pose.sleepZElapsed == 0)
        // Whatever else differs between the two, no paper cell may be set by a
        // zZz at the origin.
        let frame = CrabRig.render(pose)
        var paper = 0
        for y in 0..<PixelBuffer.side where y < 12 {
            for x in 0..<PixelBuffer.side where frame[x, y] == .paper { paper += 1 }
        }
        #expect(paper == 0, "\(paper) paper cells above the crown at t=0")
        _ = bare
    }

    // MARK: - Density

    /// The operator's actual ask: more of them between 22:00 and 06:00.
    @Test("Night is denser than day, and the window is 22:00–06:00")
    func nightIsDenser() {
        #expect(night < day, "night spacing \(night) is not tighter than day's \(day)")
        for hour in [22, 23, 0, 3, 5] {
            #expect(CrabAnimator.sleepZInterval(hourOfDay: hour) == night,
                    "hour \(hour) should be night")
        }
        for hour in [6, 9, 14, 18, 21] {
            #expect(CrabAnimator.sleepZInterval(hourOfDay: hour) == day,
                    "hour \(hour) should be day")
        }
    }

    /// Counted over a real stretch rather than inferred from the spacing, so a
    /// change to the life or the onset that quietly cancelled the night window
    /// would be caught.
    @Test("Twice as many glyphs cross a minute after dark")
    func nightShowsMore() {
        func births(interval: Double, over span: Double) -> Int {
            var seen = Set<Int>()
            for step in stride(from: 0.0, through: span, by: 0.05) {
                for z in CrabAnimator.sleepZSpawns(t: step, interval: interval) {
                    seen.insert(z.ordinal)
                }
            }
            return seen.count
        }
        let byDay = births(interval: day, over: 60)
        let byNight = births(interval: night, over: 60)
        #expect(byNight >= byDay * 2 - 1,
                "night showed \(byNight) against day's \(byDay) — the window is not biting")
    }

    /// **`nil` must be daytime.** Every offline renderer passes it, and if
    /// absence meant night then `sleeping.gif` would come out denser or
    /// sparser depending on the hour someone regenerated it — which is the one
    /// thing a byte-compared asset cannot survive.
    @Test("No clock means daytime, exactly")
    func nilIsDaytime() {
        #expect(CrabAnimator.sleepZInterval(hourOfDay: nil) == day)
    }

    // MARK: - How one behaves

    /// No-snap: a glyph may not appear or vanish in a single frame. Sampled at
    /// the GIF's own rate, the visibility either side of every step has to move
    /// gently rather than jump from nothing to everything.
    @Test("A zZz eases in and out rather than blinking")
    func itEases() {
        var previous = 0.0
        var worst = 0.0
        for step in stride(from: 0.0, through: CrabAnimator.sleepZLife, by: 1.0 / 12) {
            let v = Ease.pulse(step, attack: 0.30, hold: 1.15,
                               decay: CrabAnimator.sleepZLife - 1.45)
            worst = max(worst, abs(v - previous))
            previous = v
        }
        #expect(worst < 0.45, "visibility jumped by \(worst) in one frame")
    }

    /// It has to run out of LIFE before it runs out of SKY. An earlier version
    /// climbed to row 0 and was still solid when it met the top edge, so every
    /// glyph ended as a fragment sliced by the sprite boundary.
    @Test("A zZz never reaches the top edge")
    func itNeverClips() {
        var highest = Int.max
        for step in stride(from: 0.0, to: CrabAnimator.sleepZLife, by: 0.01) {
            highest = min(highest, CrabAnimator.sleepZRow(age: step))
        }
        #expect(highest >= 1, "a zZz reached row \(highest); the glyph is up to 4 tall")
    }

    /// The ordinal picks the column and the shape, so recycling it would make
    /// two consecutive glyphs identical twins — the thing that makes a rise
    /// read as a stutter rather than as breathing.
    @Test("Ordinals keep counting up")
    func ordinalsDoNotRecycle() {
        var last = -1
        for step in stride(from: 0.1, through: 40.0, by: 0.1) {
            for z in CrabAnimator.sleepZSpawns(t: step, interval: day) {
                #expect(z.ordinal >= last, "ordinal went backwards at t=\(step)")
                last = max(last, z.ordinal)
            }
        }
        #expect(last >= 6, "only \(last + 1) glyphs in forty seconds")
    }
}
