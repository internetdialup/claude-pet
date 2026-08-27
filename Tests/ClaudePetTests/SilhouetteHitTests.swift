import Testing
import Foundation
import AppKit
@testable import ClaudePet

/// The mouse territory. He used to accept clicks anywhere in his 32×32 square
/// — the sky over his head, the floor under his feet, the corners — which both
/// swallowed clicks meant for the app behind him AND fired a poke on the way.
/// These pin the shape of the fix at every pixel size the operator can pick.
@Suite("Silhouette hit region")
@MainActor
struct SilhouetteHitTests {

    private func region(_ px: Double,
                        zones: @escaping () -> [CellRect] = { [] }) -> PetHitRegion {
        var r = PetHitRegion(pixelSize: px, mask: CrabHitMask.body)
        r.liveZones = zones
        return r
    }

    /// The view point at the centre of a grid cell.
    private func point(col: Int, row: Int, pixelSize: Double) -> CGPoint {
        let frame = PetRootView.spriteFrame(pixelSize: pixelSize)
        return CGPoint(x: frame.minX + (Double(col) + 0.5) * pixelSize,
                       y: frame.minY + (Double(PixelBuffer.side - 1 - row) + 0.5) * pixelSize)
    }

    @Test("Empty air passes through — the sky, the floor, the corners")
    func emptyAirPassesThrough() {
        for px in Preferences.pixelSizes {
            let r = region(px)
            for (col, row, what) in [(15, 5, "the crown airspace"),
                                     (15, 2, "high over his head"),
                                     (0, 0, "the top-left corner"),
                                     (31, 31, "the bottom-right corner"),
                                     (1, 15, "far left of him"),
                                     (30, 15, "far right of him"),
                                     (15, 29, "the bare floor")] {
                #expect(!r.accepts(point(col: col, row: row, pixelSize: px)),
                        "\(what) still eats the click at pixel size \(px)")
            }
        }
    }

    @Test("His body, legs and claws all accept")
    func hisBodyAccepts() {
        for px in Preferences.pixelSizes {
            let r = region(px)
            for (col, row, what) in [(15, 15, "the body centre"),
                                     (7, 22, "the first leg"),
                                     (11, 22, "the second leg"),
                                     (20, 22, "the third leg"),
                                     (24, 22, "the fourth leg"),
                                     (5, 15, "the left claw nub"),
                                     (26, 15, "the right claw nub")] {
                #expect(r.accepts(point(col: col, row: row, pixelSize: px)),
                        "\(what) is unclickable at pixel size \(px)")
            }
        }
    }

    /// The union of the sustained poses, not the rest pose alone: he bobs to
    /// −2 when he is excited, and a rest-only mask would make his head
    /// unclickable exactly when you most want to poke him.
    @Test("The bobbed-up headroom is still his")
    func bobbedHeadroomAccepts() {
        #expect(CrabHitMask.body[15, 8], "row 8 is where his head goes when excited")
        #expect(CrabHitMask.body[15, 9])
    }

    /// Deliberate: the gap between his legs is desktop showing through, and
    /// the operator picked the plain silhouette over a filled outline. This
    /// documents the choice so a later "tidy-up" has to argue with a test.
    @Test("The gaps between his legs stay pass-through")
    func legGapsPassThrough() {
        #expect(!CrabHitMask.body[16, 23], "the wide centre gap is not him")
    }

    @Test("The floor bug is clickable only while it is out, and is never a pet")
    func bugZoneIsLiveOnly() throws {
        // The bug rides a 90s cycle, is dice-gated, and only walks for the
        // first six seconds of a cycle it wins — so search by cycle rather
        // than sweeping the clock and hoping to land inside a window.
        var found: (t: Double, zone: CellRect)?
        for cycle in 1...200 {
            let t = Double(cycle) * 90 + 3
            if let zone = CrabAnimator.bugZone(idleT: t) { found = (t, zone); break }
        }
        let bug = try #require(found, "no bug in two hundred idle cycles")
        let column = bug.zone.x + 2
        let px = 3.0

        // With no bug published, that floor cell passes through…
        #expect(!region(px).accepts(point(col: column, row: 29, pixelSize: px)))
        // …and with the bug out, the same cell is claimed.
        let live = region(px, zones: { [bug.zone] })
        #expect(live.accepts(point(col: column, row: 29, pixelSize: px)),
                "the pounce lost its target")
        // But a pounce is never a pet: the bug is not his body.
        #expect(!live.onBody(point(col: column, row: 29, pixelSize: px)),
                "holding still on a bug must not start a purr")
        // And the far end of the floor is still not his.
        #expect(!live.accepts(point(col: (column + 14) % 32, row: 29, pixelSize: px)))
    }

    @Test("A hit on his body never consults the live zones")
    func liveZonesAreNotConsultedOnHits() {
        final class Counter { var n = 0 }
        let counter = Counter()
        let r = region(3, zones: { counter.n += 1; return [] })
        #expect(r.accepts(point(col: 15, row: 15, pixelSize: 3)))
        #expect(counter.n == 0, "the body path paid for the bug's schedule")
    }

    @Test("Points round-trip to the cells they are drawn in")
    func cellRoundTrip() throws {
        for px in Preferences.pixelSizes {
            for (col, row) in [(6, 10), (15, 15), (25, 20), (0, 0), (31, 31)] {
                let landed = try #require(
                    PetRootView.spriteCell(for: point(col: col, row: row, pixelSize: px),
                                           pixelSize: px))
                #expect(landed.x == col && landed.y == row,
                        "(\(col),\(row)) landed on (\(landed.x),\(landed.y)) at \(px)")
            }
        }
    }

    /// The regression net: if the art moves and the mask does not follow, this
    /// goes red instead of quietly putting a hole in him.
    @Test("Every inked cell of the rest pose is inside the mask")
    func maskCoversTheRestPose() {
        let rest = CrabRig.render(CrabPose())
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where rest[x, y] != .clear {
                #expect(CrabHitMask.body[x, y],
                        "cell (\(x),\(y)) is drawn but unclickable")
            }
        }
    }

    // MARK: - Sharing the desk

    /// The cells the union accepts and the resting crab does not draw. These
    /// ARE the invisible territory — the thing that reaches over a neighbour
    /// and eats presses meant for him.
    private var halo: [(x: Int, y: Int)] {
        var cells: [(x: Int, y: Int)] = []
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side
            where CrabHitMask.body[x, y] && !CrabHitMask.resting[x, y] {
                cells.append((x, y))
            }
        }
        return cells
    }

    /// The halo is real and worth removing — if it were a cell or two this
    /// whole change would be noise. Measured when the operator reported it:
    /// 264 drawn against 410 accepted.
    @Test("The generous mask really is much bigger than the crab")
    func haloIsSubstantial() {
        #expect(CrabHitMask.resting.cellCount < CrabHitMask.body.cellCount)
        #expect(halo.count > 100, "only \(halo.count) spare cells — is the union still a union?")
        // A subset, strictly: every cell he draws standing still must survive
        // the narrowing, or sharing a desk would make parts of him unclickable.
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side where CrabHitMask.resting[x, y] {
                #expect(CrabHitMask.body[x, y], "cell \(x),\(y) drawn but outside the union")
            }
        }
    }

    /// **The bug, stated as a test.** A press on the halo is claimed by this
    /// pet — and because only the torso drags, it finds no handle, moves
    /// nothing, and cannot fall through to the pet it was meant for either.
    /// With company, every one of those cells must let go.
    @Test("In company, the halo stops claiming the pointer")
    func haloReleasesThePointerWhenSharingADesk() {
        let spare = halo
        try! #require(!spare.isEmpty)
        for px in Preferences.pixelSizes {
            let alone = PetHitRegion(pixelSize: px, mask: CrabHitMask.mask(sharingDesk: false))
            let together = PetHitRegion(pixelSize: px, mask: CrabHitMask.mask(sharingDesk: true))
            for cell in spare {
                let p = point(col: cell.x, row: cell.y, pixelSize: px)
                #expect(alone.accepts(p), "alone he should still be generous at \(cell)")
                #expect(!together.accepts(p),
                        "cell \(cell) still eats the neighbour's press at pixel size \(px)")
            }
        }
    }

    /// Narrowing must not cost him himself: every cell he actually draws
    /// standing still still takes a click, in company as when alone.
    @Test("Narrowing never makes the crab himself unclickable")
    func heIsStillFullyClickableInCompany() {
        for px in Preferences.pixelSizes {
            let together = PetHitRegion(pixelSize: px, mask: CrabHitMask.mask(sharingDesk: true))
            for y in 0..<PixelBuffer.side {
                for x in 0..<PixelBuffer.side where CrabHitMask.resting[x, y] {
                    #expect(together.accepts(point(col: x, row: y, pixelSize: px)),
                            "cell \(x),\(y) is drawn but no longer clickable")
                }
            }
        }
    }

    /// The eyes follow the hit box, which was the operator's other ruling. The
    /// tracking area is derived from whichever mask is in force, so a narrower
    /// silhouette narrows the box his gaze and his greeting answer to.
    @Test("The hover box narrows with the silhouette")
    func hoverBoxFollowsTheMask() {
        for px in Preferences.pixelSizes {
            let sprite = PetRootView.spriteFrame(pixelSize: px)
            let window = PetRootView.windowSize(pixelSize: px)
            let alone = PetWindowController.hoverBounds(
                mask: CrabHitMask.mask(sharingDesk: false),
                sprite: sprite, pixelSize: px, window: window)
            let together = PetWindowController.hoverBounds(
                mask: CrabHitMask.mask(sharingDesk: true),
                sprite: sprite, pixelSize: px, window: window)
            #expect(together.width < alone.width, "at pixel size \(px)")
            #expect(together.height < alone.height, "at pixel size \(px)")
            #expect(alone.contains(together))
        }
    }
}
