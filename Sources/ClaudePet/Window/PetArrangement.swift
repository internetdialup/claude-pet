import Foundation

/// Where the second pet stands, and how he gets there.
///
/// ── Why this exists ─────────────────────────────────────────────────────────
///
/// A bubble is capped at `ThoughtBubble.maxWidth`, and that cap comes from text
/// metrics, so it does **not** scale with the pet. At the default `pixelSize` of
/// 3 the crab is 72pt wide and his bubble is up to 210 — nearly three times the
/// character, overhanging about 69pt past each shoulder. Two pets standing level
/// therefore cannot both be close together and have bubbles that clear: that is
/// arithmetic, not tuning.
///
/// So the pets clear each other in Y and stand close in X. The diagonals put
/// them at `DockMagnet.gutter` apart — the same 12pt the dock park and the
/// de-stack already use — and lift the mover just enough that no bubble touches
/// anything.
///
/// ── Nothing here is a typed-in offset ───────────────────────────────────────
///
/// Every distance is SOLVED: the smallest separation in a direction at which all
/// four rect pairs (bubble/bubble, bubble/body both ways, body/body) are
/// disjoint. The inputs are constants that already exist elsewhere —
/// `ThoughtBubble.maxWidth`, `PetRootView.bubbleBand`, `spriteFrame`, and
/// `CrabHitMask.resting`'s ink box — so a change to the bubble or to the sprite
/// moves these slots with it instead of leaving a stale number behind.
///
/// The solver is a 1pt scan rather than closed-form algebra, deliberately. The
/// closed form is eight cases of "which edge clears which", and every one of
/// them is a chance to be subtly wrong in a way no test would name; the scan is
/// obviously correct, deterministic, and runs in microseconds.
///
/// Everything is `nonisolated` and takes plain geometry, for the reason
/// `DockMagnetTests` exists at all: `PetWindowController` is `@MainActor` and
/// cannot be built in a test, so the maths has to live where it can be called
/// directly.
public enum PetArrangement {

    /// The eight places pet two can stand, as compass points from pet one.
    public enum Slot: String, CaseIterable, Sendable {
        case north, northEast, east, southEast, south, southWest, west, northWest

        /// The direction, as whole steps. `y` runs UP, matching AppKit screen
        /// coordinates rather than the sprite grid.
        var unit: (x: CGFloat, y: CGFloat) {
            switch self {
            case .north:     (0, 1)
            case .northEast: (1, 1)
            case .east:      (1, 0)
            case .southEast: (1, -1)
            case .south:     (0, -1)
            case .southWest: (-1, -1)
            case .west:      (-1, 0)
            case .northWest: (-1, 1)
            }
        }
    }

    // MARK: - The two rectangles that must not touch

    /// The crab's ink, in window coordinates.
    ///
    /// The rest pose rather than the union of every holdable pose: this is about
    /// where he VISIBLY is, and the union's extra cells are for clicking, not
    /// for looking at. `CrabHitMask.resting` is already exactly that box.
    public nonisolated static func bodyRect(pixelSize: Double) -> CGRect {
        let sprite = PetRootView.spriteFrame(pixelSize: pixelSize)
        guard let box = CrabHitMask.resting.bounds else { return .zero }
        // The sprite grid's y runs down from its top row; the window's runs up
        // from its bottom edge. Hence the flip.
        return CGRect(x: sprite.minX + CGFloat(box.x) * pixelSize,
                      y: sprite.minY + CGFloat(PixelBuffer.side - box.y - box.h) * pixelSize,
                      width: CGFloat(box.w) * pixelSize,
                      height: CGFloat(box.h) * pixelSize)
    }

    /// The ground a bubble can cover, at its very widest.
    ///
    /// The band, not the bubble: the real one is only as wide as its sentence
    /// and only as tall as one line, but it changes with every utterance and the
    /// slots must not move when he starts talking. So the reserved area is the
    /// widest and tallest a bubble is allowed to be, and a slot that clears
    /// this clears every line he could say.
    public nonisolated static func bubbleRect(pixelSize: Double) -> CGRect {
        let window = PetRootView.windowSize(pixelSize: pixelSize)
        return CGRect(x: (window.width - ThoughtBubble.maxWidth) / 2,
                      y: window.height - PetRootView.bubbleBand,
                      width: ThoughtBubble.maxWidth,
                      height: PetRootView.bubbleBand)
    }

    /// Does a second pet, offset by this much, touch the first anywhere?
    ///
    /// `CGRect.intersects` is false for rectangles that merely share an edge,
    /// which is the behaviour wanted: touching is clear, overlapping is not.
    public nonisolated static func clears(dx: CGFloat, dy: CGFloat, pixelSize: Double) -> Bool {
        let mine = [bodyRect(pixelSize: pixelSize), bubbleRect(pixelSize: pixelSize)]
        let theirs = mine.map { $0.offsetBy(dx: dx, dy: dy) }
        return !mine.contains { a in theirs.contains { a.intersects($0) } }
    }

    // MARK: - The slots

    /// How far pet two's origin sits from pet one's, for a given slot.
    public nonisolated static func offset(_ slot: Slot, pixelSize: Double) -> CGSize {
        let unit = slot.unit
        let gutter = DockMagnet.gutter

        // A bound, so a geometry change that made a slot unsolvable fails loudly
        // in a test rather than spinning. Nothing can need more than the widest
        // bubble plus a whole window.
        let window = PetRootView.windowSize(pixelSize: pixelSize)
        let limit = Int(ThoughtBubble.maxWidth + window.width + window.height)

        if unit.x != 0 && unit.y != 0 {
            // Diagonal: stand them side by side at the house gutter and lift
            // only as far as that requires. This is the arrangement worth
            // having — the crabs stay a gutter apart at every pixel size, and
            // the bubbles clear above rather than beside.
            let dx = (bodyRect(pixelSize: pixelSize).width + gutter) * unit.x
            let lift = solve(pixelSize: pixelSize, limit: limit) { d in
                clears(dx: dx, dy: d * unit.y, pixelSize: pixelSize)
            }
            return CGSize(width: dx, height: (lift + gutter) * unit.y)
        }

        // Straight along one axis: push until it clears.
        let distance = solve(pixelSize: pixelSize, limit: limit) { d in
            clears(dx: d * unit.x, dy: d * unit.y, pixelSize: pixelSize)
        } + gutter
        return CGSize(width: distance * unit.x, height: distance * unit.y)
    }

    /// The smallest whole point at which `test` passes. Returns `limit` when it
    /// never does, so an unsolvable geometry surfaces as an absurd slot the
    /// suite will catch rather than as a hang.
    private nonisolated static func solve(pixelSize: Double, limit: Int,
                                          _ test: (CGFloat) -> Bool) -> CGFloat {
        for step in 0...limit where test(CGFloat(step)) { return CGFloat(step) }
        return CGFloat(limit)
    }

    // MARK: - The crosshair

    /// Which slot a direction falls in.
    ///
    /// This is the "invisible crosshair": the eight octants around pet one, with
    /// boundaries every 45°, and nothing else — no hysteresis, no memory of the
    /// last slot. Where the pointer is decides where he lands, and the same
    /// delta always gives the same answer.
    ///
    /// A zero delta means the two windows are concentric, which is not a
    /// direction; `.east` is the arbitrary tie-break, and it only lasts until
    /// the pointer moves a single point.
    public nonisolated static func slot(forDelta delta: CGSize) -> Slot {
        guard delta.width != 0 || delta.height != 0 else { return .east }
        let turns = atan2(delta.height, delta.width) / (2 * .pi)
        let octant = Int(((turns + 1) * 8).rounded()) % 8
        let ring: [Slot] = [.east, .northEast, .north, .northWest,
                            .west, .southWest, .south, .southEast]
        return ring[octant]
    }

    // MARK: - The pull

    /// The dragged origin, drawn toward its slot the closer it gets.
    ///
    /// At `radius` it returns `raw` untouched and at zero distance it returns
    /// `target` exactly, so there is no seam at either end — the pointer is
    /// never fighting a discontinuity, and letting go changes nothing about
    /// where the window already is. That is the no-snap rule applied to a
    /// window instead of a sprite: the release-time jump is what a live eased
    /// pull exists to avoid.
    public nonisolated static func pull(from raw: CGPoint, to target: CGPoint,
                                        radius: CGFloat) -> CGPoint {
        guard radius > 0 else { return raw }
        let distance = hypot(target.x - raw.x, target.y - raw.y)
        let amount = Ease.smoothstep(1 - distance / radius)
        return CGPoint(x: raw.x + (target.x - raw.x) * amount,
                       y: raw.y + (target.y - raw.y) * amount)
    }
}
