import Testing
import Foundation
@testable import ClaudePet

/// Two pets that know where to stand.
///
/// The bubble is capped by text metrics, not by the sprite, so it does not
/// shrink with the pet: at the default `pixelSize` of 3 the crab is 72pt wide
/// and his bubble up to 210. Two pets standing level therefore cannot both be
/// close and have clear bubbles, and every slot below is the arithmetic that
/// falls out of that.
@Suite("Pet arrangement")
struct PetArrangementTests {

    /// Every size the operator can actually pick, so a slot cannot be right at
    /// one scale and wrong at another — which is exactly the trap here, since
    /// the crab scales and the bubble does not.
    private var sizes: [Double] { Preferences.pixelSizes }

    // MARK: - The guarantee

    /// **The whole point of the feature.** No arrangement may put any bubble on
    /// top of anything — not the other bubble, and not the other crab.
    @Test("No slot lets a bubble touch anything, at any size")
    func everySlotClears() {
        for px in sizes {
            for slot in PetArrangement.Slot.allCases {
                let offset = PetArrangement.offset(slot, pixelSize: px)
                #expect(PetArrangement.clears(dx: offset.width, dy: offset.height,
                                              pixelSize: px),
                        "\(slot.rawValue) at pixel size \(px) overlaps: \(offset)")
            }
        }
    }

    /// A slot that clears is easy; a slot that clears by a mile is a slot that
    /// pushed the pets further apart than it needed to. This is what makes the
    /// solved distance a MINIMUM rather than a safe guess — take one point off
    /// the axis the solver worked on and the arrangement must break.
    @Test("Every slot is the closest that clears, not merely one that does")
    func everySlotIsMinimal() {
        let gutter = DockMagnet.gutter
        for px in sizes {
            for slot in PetArrangement.Slot.allCases {
                let offset = PetArrangement.offset(slot, pixelSize: px)
                let unit = slot.unit
                // The diagonals fix dx at the house gutter and solve dy; the
                // straight slots solve the single axis they move along.
                let tighter: CGSize = unit.x != 0 && unit.y != 0
                    ? CGSize(width: offset.width,
                             height: offset.height - (gutter + 1) * unit.y)
                    : CGSize(width: offset.width - (gutter + 1) * unit.x,
                             height: offset.height - (gutter + 1) * unit.y)
                #expect(!PetArrangement.clears(dx: tighter.width, dy: tighter.height,
                                               pixelSize: px),
                        "\(slot.rawValue) at pixel size \(px) had room to spare")
            }
        }
    }

    /// The diagonals are the arrangement worth having, and this is why: whatever
    /// size he is, the two crabs stand one house gutter apart. Read from
    /// `DockMagnet.gutter` rather than typed, because the dock park and the
    /// de-stack use the same number and all three must move together.
    @Test("The diagonals hold the crabs a house gutter apart")
    func diagonalsUseTheHouseGutter() {
        let diagonals: [PetArrangement.Slot] = [.northEast, .southEast, .southWest, .northWest]
        for px in sizes {
            let body = PetArrangement.bodyRect(pixelSize: px)
            for slot in diagonals {
                let offset = PetArrangement.offset(slot, pixelSize: px)
                #expect(abs(offset.width) - body.width == DockMagnet.gutter,
                        "\(slot.rawValue) at pixel size \(px) leaves \(abs(offset.width) - body.width)pt")
            }
        }
    }

    /// Opposite slots are mirror images. Not decoration: a pet dragged left of
    /// his sibling must sit as far away as one dragged right, or the pair would
    /// creep across the desk each time the operator swapped them over.
    @Test("Opposite slots are mirrors of each other")
    func oppositeSlotsMirror() {
        let opposites: [(PetArrangement.Slot, PetArrangement.Slot)] = [
            (.north, .south), (.east, .west),
            (.northEast, .southWest), (.northWest, .southEast),
        ]
        for px in sizes {
            for (a, b) in opposites {
                let one = PetArrangement.offset(a, pixelSize: px)
                let other = PetArrangement.offset(b, pixelSize: px)
                #expect(one.width == -other.width && one.height == -other.height,
                        "\(a.rawValue)/\(b.rawValue) at pixel size \(px): \(one) against \(other)")
            }
        }
    }

    // MARK: - The crosshair

    /// Total and deterministic: every direction lands in exactly one octant,
    /// and turning right through a full circle visits all eight in order. A gap
    /// or a repeat here would be a direction the pet could not be dragged to.
    @Test("The crosshair covers every direction, once")
    func crosshairIsTotal() {
        var seen: [PetArrangement.Slot] = []
        for degrees in stride(from: 0, to: 360, by: 1) {
            let radians = Double(degrees) * .pi / 180
            let slot = PetArrangement.slot(forDelta: CGSize(width: cos(radians),
                                                            height: sin(radians)))
            if seen.last != slot { seen.append(slot) }
        }
        // The sweep starts mid-east and ends mid-east, so east bookends it.
        #expect(seen.first == .east && seen.last == .east)
        #expect(Set(seen).count == PetArrangement.Slot.allCases.count,
                "only reached \(Set(seen).count) of the eight: \(Set(seen).map(\.rawValue).sorted())")
    }

    /// A delta and its negation must give opposite slots, or the crosshair is
    /// not centred on the anchor.
    @Test("Reversing a direction reverses the slot")
    func crosshairIsSymmetric() {
        let opposites: [PetArrangement.Slot: PetArrangement.Slot] = [
            .north: .south, .south: .north, .east: .west, .west: .east,
            .northEast: .southWest, .southWest: .northEast,
            .northWest: .southEast, .southEast: .northWest,
        ]
        for degrees in stride(from: 0, to: 360, by: 7) {
            let radians = Double(degrees) * .pi / 180
            let delta = CGSize(width: cos(radians) * 137, height: sin(radians) * 137)
            let forward = PetArrangement.slot(forDelta: delta)
            let back = PetArrangement.slot(forDelta: CGSize(width: -delta.width,
                                                            height: -delta.height))
            #expect(opposites[forward] == back, "\(degrees)°: \(forward.rawValue) reversed to \(back.rawValue)")
        }
    }

    /// Concentric windows are not a direction. The tie-break only has to be
    /// stable, and it only lasts until the pointer moves a single point.
    @Test("A zero delta resolves without argument")
    func crosshairHandlesZero() {
        #expect(PetArrangement.slot(forDelta: .zero) == .east)
    }

    // MARK: - The pull

    /// **The no-snap rule, applied to a window.** The pull must be exactly
    /// nothing at the edge of its reach and exactly complete at the centre, so
    /// there is no seam at either end — no jump as the pet enters the zone, and
    /// nothing left to happen when the hand lets go.
    @Test("The pull has no seam at either end")
    func pullIsContinuousAtBothEnds() {
        let radius = DockMagnet.snapDistance
        let target = CGPoint(x: 500, y: 400)

        let atRadius = CGPoint(x: target.x - radius, y: target.y)
        #expect(PetArrangement.pull(from: atRadius, to: target, radius: radius) == atRadius,
                "the pull must not begin before the pet is inside its reach")

        let beyond = CGPoint(x: target.x - radius * 3, y: target.y)
        #expect(PetArrangement.pull(from: beyond, to: target, radius: radius) == beyond)

        #expect(PetArrangement.pull(from: target, to: target, radius: radius) == target,
                "at the slot there is nothing left to pull")
    }

    /// Monotone and gentle: closing on the slot never pushes the pet back out,
    /// and no single point of pointer movement moves the window more than a few.
    /// A pull that lurched would be the release-time jump this exists to avoid,
    /// just relocated to the middle of the drag.
    @Test("The pull closes smoothly, never lurching")
    func pullIsMonotoneAndGentle() {
        let radius = DockMagnet.snapDistance
        let target = CGPoint(x: 0, y: 0)
        var previousGap = radius
        var worstStep: CGFloat = 0

        for step in stride(from: radius, through: 0, by: -0.5) {
            let raw = CGPoint(x: -step, y: 0)
            let pulled = PetArrangement.pull(from: raw, to: target, radius: radius)
            let gap = abs(pulled.x)
            #expect(gap <= previousGap + 0.0001,
                    "the pull pushed him away at \(step)pt out: \(gap) against \(previousGap)")
            worstStep = max(worstStep, abs(previousGap - gap))
            previousGap = gap
        }
        #expect(previousGap == 0, "the pull never quite arrived: \(previousGap)pt short")
        // Half a point of pointer travel must not move the window more than a
        // couple of points, or the easing is not easing.
        #expect(worstStep < 2, "the pull lurched by \(worstStep)pt in half a point of travel")
    }
}
