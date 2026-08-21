import Foundation

/// A 32×32 boolean mask over the sprite grid — one `UInt32` per row, bit `x`
/// of `rows[y]` set when that cell is solid.
///
/// A bitmask rather than a `Set` of cells because this is queried from
/// `hitTest`, which AppKit runs on **every mouse move over the window**. A set
/// costs a hash and an allocation per query; this costs a shift and a mask,
/// and the whole structure is 128 bytes.
public struct SpriteMask: Sendable, Equatable {
    private var rows: [UInt32]

    public init() { rows = Array(repeating: 0, count: PixelBuffer.side) }

    /// Every non-clear cell of a rendered buffer.
    public init(_ buffer: PixelBuffer) {
        self.init()
        for y in 0..<PixelBuffer.side {
            var bits: UInt32 = 0
            for x in 0..<PixelBuffer.side where buffer[x, y] != .clear {
                bits |= (1 << UInt32(x))
            }
            rows[y] = bits
        }
    }

    @inline(__always)
    public subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < PixelBuffer.side, y < PixelBuffer.side else { return false }
        return rows[y] & (1 << UInt32(x)) != 0
    }

    public mutating func formUnion(_ other: SpriteMask) {
        for y in 0..<PixelBuffer.side { rows[y] |= other.rows[y] }
    }

    public var isEmpty: Bool { rows.allSatisfy { $0 == 0 } }

    /// The lit cells, for tests and for sizing a tracking area.
    public var cellCount: Int { rows.reduce(0) { $0 + $1.nonzeroBitCount } }

    /// The bounding box in cell space, or nil when nothing is lit. An
    /// `NSTrackingArea` can only be a rectangle, so this is the coarse filter
    /// that the mask itself then refines.
    public var bounds: (x: Int, y: Int, w: Int, h: Int)? {
        var minX = PixelBuffer.side, maxX = -1, minY = PixelBuffer.side, maxY = -1
        for y in 0..<PixelBuffer.side where rows[y] != 0 {
            minY = min(minY, y)
            maxY = max(maxY, y)
            minX = min(minX, rows[y].trailingZeroBitCount)
            maxX = max(maxX, 31 - rows[y].leadingZeroBitCount)
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}

/// A rectangle in cell space — how a transient overlay describes the cells it
/// is standing on.
public struct CellRect: Sendable, Equatable {
    public var x: Int, y: Int, w: Int, h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public func contains(_ cell: (x: Int, y: Int)) -> Bool {
        cell.x >= x && cell.x < x + w && cell.y >= y && cell.y < y + h
    }
}

/// Where the mouse may land on the pet: his silhouette, plus whatever
/// transient thing is standing on the floor asking to be clicked.
///
/// This replaces the axis-aligned sprite square that used to be the whole
/// answer. The square was 32×32, but at rest he only occupies cols 4–27 and
/// rows 10–24 — so the airspace over his head, the floor under his feet and
/// the window's corners all swallowed clicks that belonged to whatever was
/// behind him, and fired a poke on the way.
public struct PetHitRegion {
    public let pixelSize: Double
    public let mask: SpriteMask

    /// Cells that are clickable only right now — the floor bug. Consulted
    /// ONLY when the mask misses, so a hit on his body never pays for it and
    /// the bug's schedule is evaluated at most once per pointer sample that
    /// was already going to pass through.
    public var liveZones: () -> [CellRect] = { [] }

    public init(pixelSize: Double, mask: SpriteMask) {
        self.pixelSize = pixelSize
        self.mask = mask
    }

    public func cell(at point: CGPoint) -> (x: Int, y: Int)? {
        PetRootView.spriteCell(for: point, pixelSize: pixelSize)
    }

    /// The point is on HIM — the test for petting and for hovering, both of
    /// which mean "the pointer is touching the character".
    public func onBody(_ point: CGPoint) -> Bool {
        guard let c = cell(at: point) else { return false }
        return mask[c.x, c.y]
    }

    /// The window should claim this point at all: his body, or a live zone.
    public func accepts(_ point: CGPoint) -> Bool {
        guard let c = cell(at: point) else { return false }
        if mask[c.x, c.y] { return true }
        return liveZones().contains { $0.contains(c) }
    }
}

/// The cells a click can land on.
public enum CrabHitMask {

    /// His silhouette, as a union of every pose he can HOLD.
    ///
    /// Rendered, not measured: the rig's own `render` is the only honest
    /// answer to "which cells are ink", and asking it keeps `legX`, `armW`
    /// and friends private rather than raising them the way the torso drag
    /// handle needed `bodyX…bodyH` raised.
    ///
    /// The union IS the dilation, and it is anisotropic in exactly the right
    /// way because it comes from the real motion rather than a guessed
    /// margin: `bob` reaches −2 when he is excited, so a rest-only mask would
    /// make his head unclickable precisely when you most want to poke him.
    ///
    /// Deliberately NOT unioned: arms raised (a bar six cells above `armY`,
    /// on both outer flanks), the jump (`bob = −5`), and the finale's 1.2×
    /// scale. All are sub-second flourishes, and claiming their airspace
    /// permanently would rebuild the 14pt halo that was deleted for sitting
    /// over the pet parked next door and stealing his pointer. The failure
    /// mode this chooses is the right one: mid-flourish, a click at his
    /// extreme edge falls through to the app behind instead of poking him. A
    /// missed poke costs nothing; a swallowed click is the bug being fixed.
    ///
    /// Built once per process, off the hit-test path entirely.
    public static let body: SpriteMask = {
        var mask = SpriteMask()
        for lean in -1...1 {
            for bob in -2...1 {
                for squash in 0...1 {
                    var pose = CrabPose()
                    pose.lean = lean
                    pose.bob = bob
                    pose.squash = squash
                    mask.formUnion(SpriteMask(CrabRig.render(pose)))
                }
            }
        }
        return mask
    }()
}
