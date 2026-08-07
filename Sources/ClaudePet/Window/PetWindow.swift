import AppKit
import SwiftUI

/// The floating, borderless, transparent window the crab lives in.
///
/// `.canJoinAllSpaces` + `.fullScreenAuxiliary` is what makes the pet persistent:
/// it follows the operator across Spaces and survives another app going fullscreen,
/// which is the whole point of an ambient status object.
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
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

    /// Called when the crab is clicked without being dragged. The argument is
    /// the click count, so a triple-click can mean something extra.
    var onClick: ((Int) -> Void)?
    /// Called when the pointer enters or leaves the crab itself.
    var onHover: ((Bool) -> Void)?

    /// - Parameter interactiveRect: the part of the window that actually
    ///   responds to the mouse, in view coordinates. Everything outside it is
    ///   click-through, so the transparent margin around a large sprite does not
    ///   swallow clicks meant for the desktop.
    init(contentSize: CGSize, interactiveRect: CGRect, rootView: some View) {
        self.contentSize = contentSize
        window = PetWindow(contentSize: contentSize)
        super.init()

        let hosting = NSHostingView(rootView: AnyView(rootView))
        hosting.frame = CGRect(origin: .zero, size: contentSize)
        let host = DragHostView(hosting: hosting, controller: self)
        host.interactiveRect = interactiveRect
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

/// Hosts the SwiftUI view and turns raw mouse events into drags.
///
/// SwiftUI's own `DragGesture` cannot move an `NSWindow` without fighting the
/// hosting view's hit testing, so the drag is handled at the AppKit layer and the
/// SwiftUI content stays purely declarative.
private final class DragHostView: NSView {
    private weak var controller: PetWindowController?
    private var didDrag = false

    /// Only this rect accepts the mouse. Outside it, `hitTest` returns nil and
    /// the click passes through to whatever is behind the window.
    var interactiveRect: CGRect = .infinite

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
        return interactiveRect.contains(local) ? self : nil
    }

    /// Tracking is scoped to `interactiveRect`, so hovering the transparent
    /// margin — or the bubble — does not make him react.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: interactiveRect,
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
        MainActor.assumeIsolated {
            controller?.beginDrag(at: NSEvent.mouseLocation)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        MainActor.assumeIsolated {
            controller?.continueDrag(to: NSEvent.mouseLocation)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let clicks = event.clickCount
        MainActor.assumeIsolated {
            controller?.endDrag()
            // Still suppressed by a drag: a click that moved him is a move.
            if !didDrag { controller?.onClick?(clicks) }
        }
    }
}
