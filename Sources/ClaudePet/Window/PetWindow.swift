import AppKit
import SwiftUI

/// The floating, borderless, transparent window the crab lives in.
///
/// `.canJoinAllSpaces` + `.fullScreenAuxiliary` is what makes the pet persistent:
/// it follows the operator across Spaces and survives another app going fullscreen,
/// which is the whole point of an ambient status object.
final class PetWindow: NSWindow {
    /// Whether a click may take keyboard focus.
    ///
    /// Off by default. A desktop pet that steals focus when you poke it pulls
    /// the caret out of whatever you were typing in, which is precisely the
    /// wrong behaviour for something that sits on top all day. It is flipped on
    /// only while the roster popover is open, because a popover needs a key
    /// window before its rows can be clicked.
    var acceptsKey = false

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    init(contentSize: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false   // we drive dragging ourselves, to snap on release
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

@MainActor
final class PetWindowController: NSObject, NSWindowDelegate {
    let window: PetWindow
    private var dragOffset: CGSize?
    private let contentSize: CGSize

    /// Called when the crab is clicked without being dragged or petted. The
    /// arguments are the click count (a triple-click means something extra)
    /// and the click's location in view coordinates, so a click can hit a
    /// specific sprite cell — the floor bug earns a pounce.
    var onClick: ((Int, CGPoint) -> Void)?
    /// Called when the pointer enters or leaves the crab itself.
    var onHover: ((Bool) -> Void)?
    /// A press held still for 0.35s is petting, ended by release or movement.
    var onPetStart: (() -> Void)?
    var onPetEnd: (() -> Void)?
    /// Fired after a drag settles — the film watch re-reads a window that may
    /// have landed on another display, and a deferred step-aside gets its turn.
    var onDragEnded: (() -> Void)?

    /// The sprite square — hover tracking and pet eligibility never widen
    /// beyond it, because greeting and petting mean "the pointer is on HIM".
    private let spriteRect: CGRect
    /// Whether the bubble band is currently a grab handle (only while a bubble
    /// is actually on screen — an always-on invisible strip would swallow
    /// clicks meant for the desktop).
    private var bubbleGrabbable = false

    /// The rects that accept the mouse: the sprite square grown by a 14pt halo
    /// (clamped to the window), plus the bubble band while a bubble shows.
    /// Everything outside stays click-through.
    static func grabRects(sprite: CGRect, window: CGSize, bubbleVisible: Bool) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: window)
        var rects = [sprite.insetBy(dx: -14, dy: -14).intersection(bounds)]
        if bubbleVisible {
            let band = CGRect(x: 0, y: sprite.maxY,
                              width: window.width,
                              height: max(0, window.height - sprite.maxY))
            if !band.isEmpty { rects.append(band) }
        }
        return rects
    }

    /// Called when the bubble appears or disappears, so the band above his
    /// head is draggable exactly while there is something visible to grab.
    func setBubbleGrabbable(_ visible: Bool) {
        guard visible != bubbleGrabbable else { return }
        bubbleGrabbable = visible
        (window.contentView as? DragHostView)?.grabRects =
            Self.grabRects(sprite: spriteRect, window: contentSize, bubbleVisible: visible)
    }

    /// Where this pet's position persists. Injected because pet 2 keeps his
    /// own home — the controller must not hardcode pet 1's keys.
    private let loadPosition: () -> CGPoint?
    private let storePosition: (CGPoint) -> Void
    /// Shifts the first-launch dock park along the edge, so a summoned second
    /// pet does not land exactly under the first and look like a no-op.
    private let parkOffset: CGFloat
    /// The other pet's frame, for snap de-stacking. Nil when there is no
    /// other pet.
    var avoidingFrame: () -> CGRect? = { nil }

    /// - Parameter interactiveRect: the sprite square, in view coordinates —
    ///   the seed for the grab area. Hover and petting stay scoped to it; the
    ///   mouse target itself is widened by `grabRects`.
    init(contentSize: CGSize, interactiveRect: CGRect, rootView: some View,
         loadPosition: @escaping () -> CGPoint? = { Preferences.shared.position },
         storePosition: @escaping (CGPoint) -> Void = { Preferences.shared.position = $0 },
         parkOffset: CGFloat = 0) {
        self.contentSize = contentSize
        self.spriteRect = interactiveRect
        self.loadPosition = loadPosition
        self.storePosition = storePosition
        self.parkOffset = parkOffset
        window = PetWindow(contentSize: contentSize)
        super.init()

        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = CGRect(origin: .zero, size: contentSize)
        let host = DragHostView(hosting: hosting, controller: self)
        host.spriteRect = interactiveRect
        host.grabRects = Self.grabRects(sprite: interactiveRect,
                                        window: contentSize, bubbleVisible: false)
        host.updateTrackingAreas()
        window.contentView = host
        window.delegate = self

        restorePosition()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        // A deliberate show cancels any fade in flight and clears its alpha —
        // without this, "show" after an interrupted step-aside orders front an
        // invisible window with no path back (the alpha-0 trap).
        fadeSeq += 1
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    func hide() {
        fadeSeq += 1
        window.orderOut(nil)
    }

    // MARK: - Step-aside fades

    /// Bumped by every deliberate show/hide and every new fade, so a deadline
    /// belonging to an abandoned fade lands on nothing — an interrupted
    /// step-aside must not order the window out half a second after he came
    /// back.
    private var fadeSeq = 0

    /// Whether a drag is in flight — the step-aside defers to a held crab.
    var isDragging: Bool { dragOffset != nil }

    /// Floating (above every window) or normal (apps cover him) — the
    /// Persistency toggle. A level change is live; no rebuild involved. At
    /// `.normal` the pet still never raises himself on app switches: the app
    /// is an accessory and nothing here calls order-front except deliberate
    /// shows, so "not shuffled" holds by omission.
    func setPersistent(_ on: Bool) {
        window.level = on ? .floating : .normal
    }

    /// Eases the window out over `duration`, ordering it out only when the
    /// fade actually finishes. Retargeting an NSWindow animator's `alphaValue`
    /// continues from its current value, so an interrupted fade never snaps.
    func fadeOut(over duration: TimeInterval = 0.45) {
        fadeSeq += 1
        let seq = fadeSeq
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit delivers animation completions on the main thread; the
            // closure is typed Sendable, so re-assert the isolation the same
            // way the mouse handlers below do.
            MainActor.assumeIsolated {
                guard let self, self.fadeSeq == seq else { return }
                self.window.orderOut(nil)
            }
        })
    }

    /// Orders the window front at its CURRENT alpha first, then eases it up —
    /// in at zero, then rise. Committing the frame before the animation is
    /// what keeps a return from a film from flashing.
    func fadeIn(over duration: TimeInterval = 0.5) {
        fadeSeq += 1
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// Builds the window already faded out, for a rebuild that happens while
    /// he is stepped aside — the new window must not flash over the film.
    func prepareSteppedAside() {
        fadeSeq += 1
        window.alphaValue = 0
        window.orderOut(nil)
    }

    /// Tears the window down for good. Drops the SwiftUI host so its animation
    /// timeline stops; ordering out alone leaves it rendering.
    func close() {
        NotificationCenter.default.removeObserver(self)
        window.delegate = nil
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    var isVisible: Bool { window.isVisible }

    // MARK: - Dragging

    fileprivate func beginDrag(at screenPoint: CGPoint) {
        let origin = window.frame.origin
        dragOffset = CGSize(width: screenPoint.x - origin.x, height: screenPoint.y - origin.y)
    }

    /// Follows the cursor with **no clamping**.
    ///
    /// Clamping here to the current screen's frame is what previously made the
    /// pet impossible to drag onto a second display — the window hit the shared
    /// edge and stopped. Validity is resolved once, on release.
    fileprivate func continueDrag(to screenPoint: CGPoint) {
        guard let offset = dragOffset else { return }
        window.setFrameOrigin(CGPoint(x: screenPoint.x - offset.width,
                                      y: screenPoint.y - offset.height))
    }

    fileprivate func endDrag() {
        dragOffset = nil
        // Resolve against whichever display he actually landed on. With no
        // display at all, defer: leave the window where the hand let go, and
        // do not persist an origin resolved against nothing.
        guard let target = Self.screen(for: window.frame)?.visibleFrame else {
            onDragEnded?()
            return
        }
        let snapped = DockMagnet.snap(origin: window.frame.origin, size: contentSize,
                                      visibleFrame: target, avoiding: avoidingFrame())
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(snapped)
        }
        savePosition(origin: snapped)
        onDragEnded?()
    }

    // MARK: - Screens

    /// The rule, pure over plain geometry: the frame containing `rect`'s
    /// centre, else the nearest by centre distance — as an INDEX into the
    /// array it was asked about, so "no displays" is `[]` in a unit test
    /// instead of hardware nobody owns. Ties go to the earliest index, which
    /// is `NSScreen.screens` order; without that rule a window on a seam
    /// resolves to a different monitor per call.
    static func nearestScreenIndex(to rect: CGRect, among frames: [CGRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = frames.firstIndex(where: { $0.contains(centre) }) { return hit }
        return frames.enumerated().min { lhs, rhs in
            Self.distanceSquared(centre, CGPoint(x: lhs.element.midX, y: lhs.element.midY))
                < Self.distanceSquared(centre, CGPoint(x: rhs.element.midX, y: rhs.element.midY))
        }?.offset
    }

    /// The screen for `rect`, or nil when no display is attached.
    ///
    /// nil is an honest answer, not a defect to paper over: `NSScreen.main` is
    /// documented to return nil and `NSScreen.screens` documented to be empty
    /// exactly then (clamshell with the external unplugged, mid-
    /// reconfiguration, wake). The old chain ended in `NSScreen.screens[0]`,
    /// which subscripts the exact array whose emptiness got it there — a
    /// launch or an unplug became an abort. Callers defer rather than guess:
    /// there is no right position when there is nowhere to put it, and the
    /// display-change notification is the same one that will ask again.
    static func screen(for rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens   // one read; the index resolves against this local
        guard let index = nearestScreenIndex(to: rect, among: screens.map(\.frame)) else {
            return nil
        }
        return screens[index]
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    // MARK: - Position persistence

    /// Persists to the `com.internetdialup.claude-pet` UserDefaults suite,
    /// backed by `~/Library/Preferences/com.internetdialup.claude-pet.plist`.
    private func savePosition(origin: CGPoint) {
        storePosition(origin)
    }

    /// Whether the launch placement is still owed. An `LSUIElement` app that
    /// launched with no display attached has an unplaced, invisible window, no
    /// Dock icon to click, and no way to be asked back short of relaunching —
    /// so that path must remember the debt and settle it when a display
    /// arrives. Cleared only when a placement actually lands, never by being
    /// read: the display change that still has no display must not discharge
    /// it.
    struct PlacementDebt: Equatable, Sendable {
        private(set) var isOwed = false
        mutating func attempted(placed: Bool) { isOwed = !placed }
    }

    private var placementDebt = PlacementDebt()

    private func restorePosition() {
        placementDebt.attempted(placed: attemptRestorePosition())
    }

    /// One placement attempt. Returns whether it landed — false means no
    /// display was attached and the window is exactly where it was.
    private func attemptRestorePosition() -> Bool {
        let origin: CGPoint
        if let saved = loadPosition(),
           Self.isUsable(origin: saved, size: contentSize) {
            origin = saved
        } else {
            // First launch: park next to the dock, which is where the operator
            // asked for it to live. The screen comes from the optional lookup —
            // the old `window.screen ?? NSScreen.main!` spent its optional
            // chain on the wrong operand: both nils fire for the same reason
            // (nothing attached), so the force unwrap aborted first launches
            // in clamshell.
            guard let screen = window.screen ?? Self.screen(for: window.frame) else {
                return false
            }
            let frame = screen.visibleFrame
            let (edge, thickness) = DockMagnet.dockEdge(frame: screen.frame,
                                                        visibleFrame: frame)
            switch edge {
            case .left:  origin = CGPoint(x: frame.minX + parkOffset, y: frame.minY + thickness + 8)
            case .right: origin = CGPoint(x: frame.maxX - contentSize.width - parkOffset,
                                          y: frame.minY + thickness + 8)
            default:     origin = CGPoint(x: frame.maxX - contentSize.width - 24 - parkOffset,
                                          y: frame.minY)
            }
        }
        guard let target = Self.screen(for: CGRect(origin: origin, size: contentSize))?.visibleFrame
        else { return false }
        window.setFrameOrigin(DockMagnet.clamp(origin: origin, size: contentSize, visibleFrame: target))
        return true
    }

    /// A saved position is usable if a decent chunk of the window would still be
    /// on some display. Guards against restoring onto a monitor that has since
    /// been unplugged.
    ///
    /// `contains` on the empty array is false, so "no displays" reads as "not
    /// usable" — safe, and correctly so. That is the load-bearing difference
    /// from the subscript this file used to end its screen lookup with: this
    /// read degrades to the parking path, that one took the process.
    static func isUsable(origin: CGPoint, size: CGSize) -> Bool {
        let rect = CGRect(origin: origin, size: size)
        let needed = size.width * size.height * 0.5
        return NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(rect)
            return !overlap.isNull && overlap.width * overlap.height >= needed
        }
    }

    /// Displays were added, removed, or rearranged. The launch debt settles
    /// first — "was he ever placed" and "did he drift off screen" are
    /// different questions and the first one comes first. Otherwise intervene
    /// only if he is stranded, and defer when there is currently no display
    /// to resolve against: the frame is still the best record of where he was.
    @objc private func screenParametersChanged() {
        if placementDebt.isOwed {
            placementDebt.attempted(placed: attemptRestorePosition())
            return
        }
        guard !Self.isUsable(origin: window.frame.origin, size: contentSize) else { return }
        guard let target = Self.screen(for: window.frame)?.visibleFrame else { return }
        window.setFrameOrigin(DockMagnet.clamp(origin: window.frame.origin, size: contentSize, visibleFrame: target))
        savePosition(origin: window.frame.origin)
    }
}

/// What a press turned out to be. Pure so the thresholds are testable without
/// synthesising AppKit events: movement always wins (drag), a still press
/// matures into petting at 0.35s, anything shorter is a click.
enum PressGesture {
    case click
    case drag
    case pet

    static let movementThreshold: CGFloat = 3
    static let petDelay: TimeInterval = 0.35

    static func classify(elapsed: TimeInterval, movement: CGFloat) -> PressGesture {
        if movement > movementThreshold { return .drag }
        return elapsed >= petDelay ? .pet : .click
    }
}

/// Hosts the SwiftUI view and turns raw mouse events into drags.
///
/// SwiftUI's own `DragGesture` cannot move an `NSWindow` without fighting the
/// hosting view's hit testing, so the drag is handled at the AppKit layer and the
/// SwiftUI content stays purely declarative.
private final class DragHostView: NSView {
    private weak var controller: PetWindowController?
    private var didDrag = false
    private var pressStartedAt: Date?
    private var pressOrigin: NSPoint = .zero
    private var maxMovement: CGFloat = 0
    private var isPetting = false
    private var petTimer: Timer?
    private var petEligible = false

    /// The sprite square: hover tracking and pet eligibility. Touching the
    /// halo or the bubble grabs him; only touching HIM greets or pets him.
    var spriteRect: CGRect = .infinite

    /// The rects that accept the mouse. Outside all of them `hitTest` returns
    /// nil and the click passes through to whatever is behind the window.
    var grabRects: [CGRect] = []

    init(hosting: NSView, controller: PetWindowController) {
        self.controller = controller
        super.init(frame: hosting.frame)
        addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate space.
        let local = convert(point, from: superview)
        return grabRects.contains(where: { $0.contains(local) }) ? self : nil
    }

    /// The app is an accessory and the window never takes key focus, so without
    /// this the first press while another app is frontmost is treated as an
    /// activation click and swallowed — you had to click him twice to drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Tracking is scoped to the sprite square, so hovering the halo, the
    /// transparent margin, or the bubble does not make him react — the wider
    /// area is for grabbing, not for greeting.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: spriteRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.onHover?(true) }
    }

    override func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.onHover?(false) }
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        isPetting = false
        maxMovement = 0
        pressOrigin = NSEvent.mouseLocation
        pressStartedAt = Date()
        // Petting means touching HIM — a hold on the halo or the bubble is
        // just a grip, so only a press inside the sprite square can mature.
        petEligible = spriteRect.contains(convert(event.locationInWindow, from: nil))
        MainActor.assumeIsolated {
            controller?.beginDrag(at: NSEvent.mouseLocation)
        }
        // A press that stays put matures into petting. The timer dies on the
        // first real movement, so drag always wins.
        petTimer?.invalidate()
        guard petEligible else { return }
        petTimer = Timer.scheduledTimer(withTimeInterval: PressGesture.petDelay,
                                        repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.maxMovement <= PressGesture.movementThreshold else { return }
                self.isPetting = true
                self.controller?.onPetStart?()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        maxMovement = max(maxMovement, hypot(location.x - pressOrigin.x, location.y - pressOrigin.y))
        guard maxMovement > PressGesture.movementThreshold else { return }
        petTimer?.invalidate()
        didDrag = true
        MainActor.assumeIsolated {
            // Movement cancels an engaged petting into a normal drag.
            if isPetting {
                isPetting = false
                controller?.onPetEnd?()
            }
            controller?.continueDrag(to: location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        petTimer?.invalidate()
        let clicks = event.clickCount
        let location = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated {
            controller?.endDrag()
            if isPetting {
                isPetting = false
                controller?.onPetEnd?()
            } else if !didDrag {
                // Still suppressed by a drag: a click that moved him is a move.
                controller?.onClick?(clicks, location)
            }
        }
    }
}
