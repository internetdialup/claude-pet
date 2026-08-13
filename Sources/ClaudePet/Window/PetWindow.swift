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

    /// - Parameter interactiveRect: the sprite square, in view coordinates —
    ///   the seed for the grab area. Hover and petting stay scoped to it; the
    ///   mouse target itself is widened by `grabRects`.
    init(contentSize: CGSize, interactiveRect: CGRect, rootView: some View) {
        self.contentSize = contentSize
        self.spriteRect = interactiveRect
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
        window.orderFrontRegardless()
    }

    func hide() {
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
        // Resolve against whichever display he actually landed on.
        let target = Self.screen(for: window.frame).visibleFrame
        let snapped = DockMagnet.snap(origin: window.frame.origin, size: contentSize, visibleFrame: target)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(snapped)
        }
        savePosition(origin: snapped)
    }

    // MARK: - Screens

    /// The screen containing `rect`'s centre, else the one whose centre is
    /// nearest. Never returns nil: a window dropped in the gap between two
    /// non-aligned displays still has to land somewhere.
    static func screen(for rect: CGRect) -> NSScreen {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(centre) }) { return hit }
        let nearest = NSScreen.screens.min { lhs, rhs in
            Self.distanceSquared(centre, CGPoint(x: lhs.frame.midX, y: lhs.frame.midY))
                < Self.distanceSquared(centre, CGPoint(x: rhs.frame.midX, y: rhs.frame.midY))
        }
        return nearest ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private var currentVisibleFrame: CGRect {
        Self.screen(for: window.frame).visibleFrame
    }

    // MARK: - Position persistence

    /// Persists to the `com.internetdialup.claude-pet` UserDefaults suite,
    /// backed by `~/Library/Preferences/com.internetdialup.claude-pet.plist`.
    private func savePosition(origin: CGPoint) {
        Preferences.shared.position = origin
    }

    private func restorePosition() {
        let origin: CGPoint
        if let saved = Preferences.shared.position,
           Self.isUsable(origin: saved, size: contentSize) {
            origin = saved
        } else {
            let frame = currentVisibleFrame
            // First launch: park next to the dock, which is where the operator
            // asked for it to live.
            let (edge, thickness) = DockMagnet.dockEdge(frame: (window.screen ?? NSScreen.main!).frame,
                                                        visibleFrame: frame)
            switch edge {
            case .left:  origin = CGPoint(x: frame.minX, y: frame.minY + thickness + 8)
            case .right: origin = CGPoint(x: frame.maxX - contentSize.width, y: frame.minY + thickness + 8)
            default:     origin = CGPoint(x: frame.maxX - contentSize.width - 24, y: frame.minY)
            }
        }
        let target = Self.screen(for: CGRect(origin: origin, size: contentSize)).visibleFrame
        window.setFrameOrigin(DockMagnet.clamp(origin: origin, size: contentSize, visibleFrame: target))
    }

    /// A saved position is usable if a decent chunk of the window would still be
    /// on some display. Guards against restoring onto a monitor that has since
    /// been unplugged.
    static func isUsable(origin: CGPoint, size: CGSize) -> Bool {
        let rect = CGRect(origin: origin, size: size)
        let needed = size.width * size.height * 0.5
        return NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(rect)
            return !overlap.isNull && overlap.width * overlap.height >= needed
        }
    }

    /// Displays were added, removed, or rearranged. Only intervene if he is now
    /// stranded — otherwise leave him exactly where the operator put him.
    @objc private func screenParametersChanged() {
        guard !Self.isUsable(origin: window.frame.origin, size: contentSize) else { return }
        let target = currentVisibleFrame
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
