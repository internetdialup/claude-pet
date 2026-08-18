import Testing
import AppKit
@testable import ClaudePet

/// The film predicate, asserted with the numbers that were measured rather
/// than the ones a document would predict. The worked example throughout: a
/// 2880×1620 Studio Display whose fullscreen Arc window reports 2880×1590 —
/// thirty points short, the strip macOS goes on reserving with nothing drawn
/// in it — while holding `Video Wake Lock` at level 255.
@Suite("Full-screen watch")
struct FullScreenWatchTests {

    private let display = CGRect(x: 0, y: 0, width: 2880, height: 1620)
    private let menuBar: CGFloat = 30
    private let ourPID: pid_t = 999

    private func fullscreenFilm(pid: pid_t = 3825) -> WindowSnapshot {
        // The measured Arc window: thirty points short of the display.
        WindowSnapshot(pid: pid, layer: 0,
                       bounds: CGRect(x: 0, y: 30, width: 2880, height: 1590),
                       isOnscreen: true)
    }

    private func activeWakeLock() -> AssertionSnapshot {
        // The raw dump, verbatim: legacy type, modern true-type, level on.
        AssertionSnapshot(type: "NoDisplaySleepAssertion",
                          trueType: "PreventUserIdleDisplaySleep",
                          level: 255)
    }

    // MARK: - The cover

    @Test func theOffByThirtyIsTolerated() {
        #expect(FullScreenWatch.covers(fullscreenFilm(), display: display, menuBarHeight: menuBar),
                "the exact window this predicate hunts for must match")
    }

    @Test func aWindowedFilmDoesNotCover() {
        let windowed = WindowSnapshot(pid: 3825, layer: 0,
                                      bounds: CGRect(x: 400, y: 300, width: 900, height: 500),
                                      isOnscreen: true)
        #expect(!FullScreenWatch.covers(windowed, display: display, menuBarHeight: menuBar))
    }

    @Test func widthIsTheStrictAxis() {
        var short = fullscreenFilm()
        short.bounds.size.width = 2860       // 20pt narrow — no strip explains that
        #expect(!FullScreenWatch.covers(short, display: display, menuBarHeight: menuBar))
    }

    @Test func theShortfallIsAskedOfTheDisplay() {
        // A notched machine reserves a taller strip; the same window shape
        // must match there and not on a strip-less display.
        var tall = fullscreenFilm()
        tall.bounds.size.height = 1620 - 74
        #expect(FullScreenWatch.covers(tall, display: display, menuBarHeight: 74))
        #expect(!FullScreenWatch.covers(tall, display: display, menuBarHeight: 30))
    }

    @Test func floatingLayersNeverCover() {
        var floating = fullscreenFilm()
        floating.layer = 3
        #expect(!FullScreenWatch.covers(floating, display: display, menuBarHeight: menuBar))
    }

    @Test func stageManagerMirrorsAreASet() {
        // WindowManager mirrors the film's window at layer 0 with identical
        // bounds. The answer must contain BOTH pids — reading the first match
        // asks "is WindowManager playing a film", which it never is.
        let film = fullscreenFilm(pid: 3825)
        let mirror = fullscreenFilm(pid: 501)
        let owners = FullScreenWatch.coveringPIDs(windows: [mirror, film],
                                                  display: display,
                                                  menuBarHeight: menuBar,
                                                  ourPID: ourPID)
        #expect(owners == [3825, 501])
    }

    // MARK: - The wake lock

    @Test func theLevelIsTheSignal() {
        var dormant = activeWakeLock()
        dormant.level = 0
        #expect(!FullScreenWatch.holdsTheDisplayAwake(dormant),
                "a browser open all afternoon lists exactly this, switched off")
        #expect(FullScreenWatch.holdsTheDisplayAwake(activeWakeLock()))
    }

    @Test func bothSpellingsAreHeard() {
        let modern = AssertionSnapshot(type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                       trueType: nil, level: 255)
        let legacyOnly = AssertionSnapshot(type: "NoDisplaySleepAssertion",
                                           trueType: nil, level: 255)
        let unrelated = AssertionSnapshot(type: "PreventUserIdleSystemSleep",
                                          trueType: nil, level: 255)
        #expect(FullScreenWatch.holdsTheDisplayAwake(modern))
        #expect(FullScreenWatch.holdsTheDisplayAwake(legacyOnly))
        #expect(!FullScreenWatch.holdsTheDisplayAwake(unrelated))
    }

    // MARK: - The conjunction

    @Test func aFullscreenEditorIsNotAFilm() {
        // Covers the display, holds nothing.
        #expect(!FullScreenWatch.filmIsPlaying(windows: [fullscreenFilm(pid: 777)],
                                               display: display, menuBarHeight: menuBar,
                                               ourPID: ourPID,
                                               assertions: [3825: [activeWakeLock()]]),
                "the wake lock belongs to a different process — no film")
    }

    @Test func theConjunctionOnOnePIDIsAFilm() {
        #expect(FullScreenWatch.filmIsPlaying(windows: [fullscreenFilm(pid: 3825)],
                                              display: display, menuBarHeight: menuBar,
                                              ourPID: ourPID,
                                              assertions: [3825: [activeWakeLock()]]))
    }

    @Test func emptyWorldsAnswerFalse() {
        // Fails visible: every degenerate input keeps him on screen.
        #expect(!FullScreenWatch.filmIsPlaying(windows: [], display: display,
                                               menuBarHeight: menuBar, ourPID: ourPID,
                                               assertions: [:]))
        #expect(!FullScreenWatch.filmIsPlaying(windows: [fullscreenFilm()],
                                               display: .zero, menuBarHeight: menuBar,
                                               ourPID: ourPID,
                                               assertions: [3825: [activeWakeLock()]]))
    }

    @Test func degenerateMenuBarNeverTraps() {
        // A ClosedRange built lower > upper traps; the max(0,…) is the guard.
        let range = FullScreenWatch.toleratedShortfall(menuBarHeight: -50)
        #expect(range.contains(0))
    }

    // MARK: - The detector

    @Test func twoSamplesToBelieveEitherDirection() {
        var detector = FilmDetector()
        let screen = CGRect(x: 0, y: 0, width: 2880, height: 1620)
        #expect(detector.sample(playing: true, on: screen) == nil, "one sample is a rumour")
        #expect(detector.sample(playing: true, on: screen) == true, "two agreeing samples believe")
        #expect(detector.sample(playing: true, on: screen) == nil, "a held belief does not repeat")
        #expect(detector.sample(playing: false, on: screen) == nil, "an ad break is one sample")
        #expect(detector.sample(playing: true, on: screen) == nil, "…and it passed")
        #expect(detector.sample(playing: false, on: screen) == nil)
        #expect(detector.sample(playing: false, on: screen) == false, "the film really ended")
    }

    @Test func aDisplayChangeSurfacesFirst() {
        var detector = FilmDetector()
        let a = CGRect(x: 0, y: 0, width: 2880, height: 1620)
        let b = CGRect(x: -2880, y: 0, width: 2880, height: 1620)
        _ = detector.sample(playing: true, on: a)
        #expect(detector.sample(playing: true, on: a) == true)
        // Unplug / move: the belief drops BEFORE the new display's reading
        // counts — he surfaces first and re-earns the step-aside second. The
        // sample that forced the surface is SPENT on it; agreement starts
        // fresh from the next one.
        #expect(detector.sample(playing: true, on: b) == false)
        #expect(detector.sample(playing: true, on: b) == nil)
        #expect(detector.sample(playing: true, on: b) == true,
                "two fresh agreeing samples re-earn the step-aside")
    }
}
