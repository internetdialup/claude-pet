import AppKit
import IOKit.pwr_mgt

// Ported from the octo-pet fork, where every number below was measured on real
// hardware; where a document disagrees with one of them the measurement wins.
// The worked example: two Studio Displays, both 2880×1620 in CGDisplayBounds, a
// film played in Arc first fullscreen and then in a window, the on-screen
// window list and IOPMCopyAssertionsByProcess dumped raw in both states.

/// One on-screen window, reduced to the four facts the rule below needs.
///
/// A plain value rather than the `[String: Any]` `CGWindowListCopyWindowInfo`
/// hands back, so every rule in this file can be asserted with arithmetic — no
/// display, no second monitor, and nothing playing.
struct WindowSnapshot: Equatable, Sendable {
    var pid: pid_t
    /// `kCGWindowLayer`. 0 is the ordinary application layer; the pet's own
    /// window is `.floating` and sits well above it.
    var layer: Int
    /// `kCGWindowBounds` — **a flipped space with its origin at the MAIN
    /// display's top-left**, which is why the rect it is compared against
    /// comes from `CGDisplayBounds` and never from `NSScreen.frame`.
    var bounds: CGRect
    var isOnscreen: Bool
}

/// One display, reduced to the two facts the cover test needs — read together,
/// off one screen, so they cannot disagree about which display they describe.
struct DisplayGeometry: Equatable, Sendable {
    /// `CGDisplayBounds`, in the window list's own flipped space.
    var bounds: CGRect
    /// The strip this display reserves along its top, in points. Measured in
    /// AppKit's space and used against a `CGDisplayBounds` rectangle — sound
    /// because it is a SCALAR: the two spaces disagree about origins and the
    /// direction of y, and agree exactly about how tall a display is.
    var menuBarHeight: CGFloat
}

/// One power assertion, held by one process. Three fields because the level
/// and the type answer different questions and the type is spelled two
/// different ways — see `holdsTheDisplayAwake`.
struct AssertionSnapshot: Equatable, Sendable {
    /// `AssertType`. The legacy spelling on Chromium, the modern one elsewhere.
    var type: String
    /// `AssertionTrueType`, when the process publishes one. **Undocumented**,
    /// so it is matched alongside `type` rather than instead of it.
    var trueType: String?
    /// `AssertLevel`. 255 is on; anything else is an assertion that exists and
    /// is doing nothing, which is most of them most of the time.
    var level: Int
}

/// Whether a film is playing fullscreen on one particular display.
///
/// The two readings the obvious implementation gets backwards, both measured:
///
/// **THE OFF-BY-THIRTY.** A fullscreen window is *not* the size of the
/// display. Arc fullscreen on a 2880×1620 display reports **2880 × 1590** —
/// thirty points short, a menu bar's worth, which macOS goes on reserving with
/// nothing drawn in it. Matched against the display rect within a couple of
/// points on all four edges, the predicate REJECTS the exact window it is
/// hunting for. So the width is matched to a few points and the HEIGHT is
/// allowed to fall short by up to a menu bar. And thirty is that desk's
/// number, not the number — a notched MacBook Pro reserves more — so the
/// shortfall is asked of the display rather than frozen from a measurement.
///
/// **The level is the signal; the type is only the address.** An assertion can
/// be listed while switched off: Arc creates its `Video Wake Lock` once and
/// toggles `AssertLevel`, so matching the type alone says a film is playing
/// for as long as the browser has been open. Nothing is believed below 255.
///
/// **And the conjunction is mandatory, with a counterexample for each half.**
/// A film in a WINDOW holds the wake lock and covers nothing — the assertion
/// alone would duck him for a video in a 900-point box. A fullscreen editor is
/// the mirror image — it covers the display holding no assertion at all. So it
/// is both, **on the same process id**, and that cannot be relaxed later
/// without quietly restoring both bugs at once.
enum FullScreenWatch {

    // MARK: - The shape of a cover

    /// How far the window's width may differ from the display's. Small on
    /// purpose: the width is the axis macOS reserves nothing on, so all the
    /// tolerance this predicate needs lives on the other axis.
    static let widthTolerance: CGFloat = 4

    /// The rounding allowance on the height match, at both ends. Equal to
    /// `widthTolerance` by coincidence, its own constant on purpose.
    static let shortfallSlack: CGFloat = 4

    /// How much shorter than its display a fullscreen window may be: whatever
    /// strip that display reserves, plus rounding. The `max(0, …)` is not
    /// dressing — a `ClosedRange` built lower > upper traps, and a predicate
    /// that crashes the app is a far worse answer than "no film".
    static func toleratedShortfall(menuBarHeight: CGFloat) -> ClosedRange<CGFloat> {
        -shortfallSlack...(max(0, menuBarHeight) + shortfallSlack)
    }

    /// Whether one window is covering `display`. The CENTRE is what has to
    /// land in the display rect: containment is a point-rounding argument away
    /// from disagreeing with itself at a display seam.
    static func covers(_ window: WindowSnapshot, display: CGRect,
                       menuBarHeight: CGFloat) -> Bool {
        guard window.layer == 0, window.isOnscreen else { return false }
        let centre = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        guard display.contains(centre) else { return false }
        guard abs(window.bounds.width - display.width) <= widthTolerance else { return false }
        return toleratedShortfall(menuBarHeight: menuBarHeight)
            .contains(display.height - window.bounds.height)
    }

    /// Every process with a window covering `display` — **a SET, never the
    /// first match.** Stage Manager's `WindowManager` mirrors real windows at
    /// layer 0 with identical bounds; read the owner off the first covering
    /// window and the question becomes "is WindowManager playing a film",
    /// which it never is.
    static func coveringPIDs(windows: [WindowSnapshot], display: CGRect,
                             menuBarHeight: CGFloat,
                             ourPID: pid_t) -> Set<pid_t> {
        var owners: Set<pid_t> = []
        for window in windows where window.pid != ourPID
            && covers(window, display: display, menuBarHeight: menuBarHeight) {
            owners.insert(window.pid)
        }
        return owners
    }

    // MARK: - The shape of a wake lock

    /// `kIOPMAssertionLevelOn`, spelled out because the comparison is the
    /// whole point of reading the field at all.
    static let activeLevel = Int(kIOPMAssertionLevelOn)

    /// The two spellings of "keep this display awake". Both, because neither
    /// field alone covers both kinds of process: Chromium publishes only the
    /// legacy `NoDisplaySleepAssertion` in `AssertType` — which is most of the
    /// films anyone watches on a Mac — and `AssertionTrueType` normalises it
    /// but is undocumented and not always published.
    static let displayAssertionTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep,
        kIOPMAssertionTypeNoDisplaySleep,
    ]

    /// `AssertionTrueType` has no constant because it is not documented. One
    /// place to delete it from if it ever stops being published.
    static let trueTypeKey = "AssertionTrueType"

    /// One assertion, judged. The level is checked FIRST and is not
    /// negotiable — a browser open all afternoon lists its wake lock with the
    /// level dropped, and without the check he would spend the afternoon away.
    static func holdsTheDisplayAwake(_ assertion: AssertionSnapshot) -> Bool {
        guard assertion.level == activeLevel else { return false }
        if displayAssertionTypes.contains(assertion.type) { return true }
        guard let trueType = assertion.trueType else { return false }
        return displayAssertionTypes.contains(trueType)
    }

    // MARK: - The predicate, pure

    /// **The whole rule**, as a function of five values — pure so every
    /// measured number above can be a literal in a test that needs no display,
    /// no second monitor, no film and no IOKit.
    ///
    /// **Fails visible.** An empty window list, a display of no size, a nil
    /// IOKit read upstream — every one answers false, and false means he stays
    /// where he is. The failure this direction guards against is a bug that
    /// leaves him away forever with no film anywhere and no way to tell why.
    static func filmIsPlaying(windows: [WindowSnapshot], display: CGRect,
                              menuBarHeight: CGFloat,
                              ourPID: pid_t,
                              assertions: [pid_t: [AssertionSnapshot]]) -> Bool {
        guard !windows.isEmpty, display.width > 0, display.height > 0 else { return false }
        let owners = coveringPIDs(windows: windows, display: display,
                                  menuBarHeight: menuBarHeight, ourPID: ourPID)
        return owners.contains { pid in
            (assertions[pid] ?? []).contains(where: holdsTheDisplayAwake)
        }
    }

    // MARK: - The impure reads

    /// Every window macOS currently considers on-screen, everywhere. Display
    /// scoping is the predicate's job, by the window's own centre.
    ///
    /// No Screen Recording permission is involved: that gate is on
    /// `kCGWindowName`, which this never reads — the owner's pid, its layer
    /// and its rectangle are the whole question.
    static func onScreenWindows() -> [WindowSnapshot] {
        guard let raw = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            // Absent reads as off-screen — the direction that keeps him on the
            // screen.
            let onscreen = (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            return WindowSnapshot(pid: pid, layer: layer, bounds: bounds, isOnscreen: onscreen)
        }
    }

    /// Every power assertion, by the process holding it. **Never the
    /// system-wide `IOPMCopyAssertionsStatus`** — the aggregate carries no
    /// owner, and `coreaudiod` proxies display assertions for other processes,
    /// which is exactly the shape that cannot be joined to the window covering
    /// the screen. The join IS this feature.
    static func displayAssertions() -> [pid_t: [AssertionSnapshot]] {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [:] }

        var result: [pid_t: [AssertionSnapshot]] = [:]
        for (owner, entries) in byProcess {
            result[owner.int32Value] = entries.map { entry in
                AssertionSnapshot(
                    type: entry[kIOPMAssertionTypeKey] as? String ?? "",
                    trueType: entry[trueTypeKey] as? String,
                    // Absent reads as dormant: an assertion nobody can vouch
                    // for is not one.
                    level: (entry[kIOPMAssertionLevelKey] as? NSNumber)?.intValue ?? 0)
            }
        }
        return result
    }

    /// One display's rectangle, **in the window list's own space** —
    /// `CGDisplayBounds` and NOT `NSScreen.frame`. `kCGWindowBounds` is a
    /// flipped space with its origin at the main display's top-left; compare a
    /// flipped window rect against an AppKit frame and the centre test lands
    /// on the wrong monitor, silently, on exactly one of two.
    @MainActor
    static func displayBounds(of screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else { return nil }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }

    /// The strip a display reserves along its top: the largest of the
    /// visible-frame inset (zero when the bar auto-hides — the floor exists
    /// for exactly that), the auxiliary areas a notch leaves beside itself,
    /// and the status bar's own thickness. Given an unverified guess, err
    /// toward a taller strip: too tall tolerates a slightly-short window; too
    /// short is the off-by-thirty — a film that is simply never noticed.
    @MainActor
    static func menuBarHeight(of screen: NSScreen) -> CGFloat {
        let inset = screen.frame.maxY - screen.visibleFrame.maxY
        let auxiliary = max(screen.auxiliaryTopLeftArea?.height ?? 0,
                            screen.auxiliaryTopRightArea?.height ?? 0)
        return max(inset, auxiliary, NSStatusBar.system.thickness)
    }

    /// One display's rectangle and the strip it reserves, read together so
    /// they cannot describe different displays.
    @MainActor
    static func geometry(of screen: NSScreen) -> DisplayGeometry? {
        guard let bounds = displayBounds(of: screen) else { return nil }
        return DisplayGeometry(bounds: bounds, menuBarHeight: menuBarHeight(of: screen))
    }
}

/// Two agreeing samples, in both directions, about one display.
///
/// **Why debounce:** the reading is usually correct and merely *brief* — an ad
/// break, a skip, a half-second where the player drops its wake lock between
/// segments. Two agreeing samples on a five-second backstop is about ten
/// seconds of hysteresis, deliberately longer than any of those: a pet that
/// surfaced and sank across every ad break would be worse company than one
/// that never left.
struct FilmDetector: Equatable, Sendable {
    /// Samples that must agree before the answer is believed.
    static let agreementRequired = 2

    /// What the detector currently believes, after debouncing.
    private(set) var believesPlaying = false

    private var lastSample: Bool?
    private var agreeing = 0

    /// The display the belief is ABOUT. A belief formed about one display is
    /// not weak evidence about another — it is an answer to a different
    /// question, and the display under him really does change: unplug the
    /// monitor he stepped aside on and the next resolve lands elsewhere.
    /// Without this, the step-aside would survive the display that caused it.
    private var about: CGRect?

    /// Feeds one observation.
    ///
    /// - Returns: the new belief on the sample that CHANGES it, nil otherwise —
    ///   the caller never diffs, and a fade already under way never restarts.
    mutating func sample(playing: Bool, on display: CGRect?) -> Bool? {
        // A different display (or none) resets the count and drops the belief
        // BEFORE the new reading is considered: he surfaces first and re-earns
        // the step-aside second. The first sample of every session lands here
        // too (`about` starts nil), and is counted rather than spent on the
        // reset.
        if display != about {
            about = display
            lastSample = nil
            agreeing = 0
            if believesPlaying {
                believesPlaying = false
                return false
            }
        }

        if playing == lastSample {
            agreeing += 1
        } else {
            lastSample = playing
            agreeing = 1
        }
        guard agreeing >= Self.agreementRequired, believesPlaying != playing else { return nil }
        believesPlaying = playing
        return playing
    }
}

/// The impure half: when to look. Wraps the predicate and the detector and
/// does nothing else of consequence, so everything with a rule in it stays
/// testable and this class stays a schedule.
@MainActor
final class FilmWatch {
    /// Which display to ask about, and what it reserves. A closure because he
    /// can be dragged to another monitor and the window is rebuilt on every
    /// size change — a captured rectangle (or a captured controller) is the
    /// one that is wrong at the moment it matters. One closure returning both
    /// halves, never two returning one each: the rectangle and the strip must
    /// describe the same display.
    private let geometry: () -> DisplayGeometry?
    /// Called only when the believed answer changes.
    private let onChange: (Bool) -> Void

    private var detector = FilmDetector()
    private var timer: Timer?

    /// The slow lane, and the one that catches everything nobody announces:
    /// pausing a film, resuming it, and letting it end all happen inside an
    /// already-fullscreen Space, and macOS posts no notification for any of
    /// them.
    private static let interval: TimeInterval = 5

    /// How long after a notification to actually look — mid-transition the
    /// window list is nonsense while a whole Space animates.
    private static let settle: TimeInterval = 0.75

    init(geometry: @escaping () -> DisplayGeometry?, onChange: @escaping (Bool) -> Void) {
        self.geometry = geometry
        self.onChange = onChange
    }

    /// Starts watching, from no belief at all. Begins by stopping, which makes
    /// it idempotent. Called once at launch; the step-aside preference gates
    /// what is DONE with the answer, never whether the question is asked.
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.sample() }
        }

        // Going fullscreen makes a Space and switches to it — the notification
        // that fires when a film starts, and again when it ends.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(nudged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // And the one that catches ⌘-tabbing away from a film and back, which
        // moves no Space on a machine where the displays share theirs.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(nudged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    /// Stops watching, **and forgets what it believed** — a detector restarted
    /// still believing "playing" would report no change when the film ended.
    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        detector = FilmDetector()
    }

    /// Ask again now — the app's way of saying the world moved under the
    /// answer (a drag ended, a preference flipped, a display changed).
    func reconsider() {
        sample()
    }

    @objc private func nudged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in
            self?.sample()
        }
    }

    private func sample() {
        // A stopped watch answers nothing — including the deferred `nudged`
        // block already in flight when it stopped.
        guard timer != nil else { return }
        let display = geometry()
        let playing = display.map { screen in
            FullScreenWatch.filmIsPlaying(windows: FullScreenWatch.onScreenWindows(),
                                          display: screen.bounds,
                                          menuBarHeight: screen.menuBarHeight,
                                          ourPID: ProcessInfo.processInfo.processIdentifier,
                                          assertions: FullScreenWatch.displayAssertions())
        } ?? false
        // The belief is about the RECTANGLE, and only the rectangle: a menu
        // bar that changed height while the display stayed put is not a move
        // to another monitor.
        guard let believed = detector.sample(playing: playing, on: display?.bounds) else { return }
        onChange(believed)
    }
}
