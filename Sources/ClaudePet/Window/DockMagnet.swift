import Foundation
import CoreGraphics

/// Edge snapping for the pet window.
///
/// The dock's edge and thickness are inferred from the difference between a
/// screen's `frame` and its `visibleFrame` — AppKit gives no public dock API, but
/// the inset it carves out is exactly what we want to sit on top of.
public enum DockMagnet {
    /// How close (in points) a dragged window must come to an edge before it snaps.
    public static let snapDistance: CGFloat = 60

    public enum Edge: Sendable, Equatable { case left, right, bottom, top, none }

    /// Which edge the dock occupies, and how thick it is.
    ///
    /// - Parameters:
    ///   - frame: the screen's full frame.
    ///   - visibleFrame: the screen's frame minus menu bar and dock.
    /// - Returns: the dock edge and its thickness in points. `.none` when no
    ///   meaningful inset exists (dock hidden or auto-hiding).
    public static func dockEdge(frame: CGRect, visibleFrame: CGRect) -> (edge: Edge, thickness: CGFloat) {
        // AppKit's origin is bottom-left, so the menu bar shows up as a top inset
        // and must not be mistaken for the dock.
        let left = visibleFrame.minX - frame.minX
        let right = frame.maxX - visibleFrame.maxX
        let bottom = visibleFrame.minY - frame.minY

        let candidates: [(Edge, CGFloat)] = [(.left, left), (.right, right), (.bottom, bottom)]
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 4 else {
            return (.none, 0)
        }
        return (best.0, best.1)
    }

    /// Snap `origin` to the nearest edge of `visibleFrame` if it is within
    /// `snapDistance`, keeping the window fully on screen either way.
    ///
    /// - Parameters:
    ///   - origin: proposed bottom-left origin of the window.
    ///   - size: the window's size.
    ///   - visibleFrame: the area the window must stay inside.
    ///   - avoiding: another pet's frame. Both pets snap to exact corners, so
    ///     two dropped near the same one would land at the identical origin
    ///     with the back one fully hidden — when the snapped frame would
    ///     overlap `avoiding` by more than half, it slides along the edge by
    ///     its own width instead. Deliberate mid-screen overlap from a drag is
    ///     left alone; only the snap resolution de-stacks.
    public static func snap(origin: CGPoint, size: CGSize, visibleFrame: CGRect,
                            avoiding: CGRect? = nil) -> CGPoint {
        var result = clamp(origin: origin, size: size, visibleFrame: visibleFrame)

        let distLeft = result.minXDistance(to: visibleFrame)
        let distRight = visibleFrame.maxX - (result.x + size.width)
        let distBottom = result.y - visibleFrame.minY
        let distTop = visibleFrame.maxY - (result.y + size.height)

        // Horizontal snap wins ties — the dock is bottom-mounted by default and a
        // pet that slides sideways along it feels better than one that jumps down.
        if distLeft <= snapDistance && distLeft <= distRight {
            result.x = visibleFrame.minX
        } else if distRight <= snapDistance {
            result.x = visibleFrame.maxX - size.width
        }

        if distBottom <= snapDistance && distBottom <= distTop {
            result.y = visibleFrame.minY
        } else if distTop <= snapDistance {
            result.y = visibleFrame.maxY - size.height
        }

        // De-stack only when a snap actually moved the window: a deliberate
        // mid-screen drop onto the sibling is the operator's business.
        let preSnap = clamp(origin: origin, size: size, visibleFrame: visibleFrame)
        if let avoiding, result != preSnap {
            let snapped = CGRect(origin: result, size: size)
            let overlap = snapped.intersection(avoiding)
            if !overlap.isNull, overlap.width * overlap.height > size.width * size.height * 0.5 {
                // Slide away from the occupied spot, along x (the shared edge
                // is almost always the bottom), and stay on screen.
                let step = size.width + 12
                result.x = snapped.midX <= avoiding.midX ? avoiding.minX - step : avoiding.maxX + 12
                result = clamp(origin: result, size: size, visibleFrame: visibleFrame)
            }
        }

        return result
    }

    /// Keep the window inside `visibleFrame`. Used on drag, on restore, and when
    /// the display arrangement changes.
    public static func clamp(origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        guard visibleFrame.width >= size.width, visibleFrame.height >= size.height else {
            return CGPoint(x: visibleFrame.minX, y: visibleFrame.minY)
        }
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }
}

private extension CGPoint {
    func minXDistance(to rect: CGRect) -> CGFloat { x - rect.minX }
}
