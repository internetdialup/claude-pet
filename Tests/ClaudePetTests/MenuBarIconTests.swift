import Testing
import Foundation
import AppKit
@testable import ClaudePet

/// The menu-bar icon. It used to be freehand bezier — an oval body, two stick
/// eye-stalks and two oval claws — which shared nothing with the character on
/// the desktop. These pin it to the rig, so the bar and the desktop can never
/// again disagree about what Claw'd looks like.
@Suite("Menu bar icon")
@MainActor
struct MenuBarIconTests {

    @Test("The icon is the rig's own crab, cropped to what he inks")
    func iconComesFromTheRig() throws {
        let buffer = CrabRig.render(CrabPose())
        let box = try #require(SpriteMask(buffer).bounds)
        let icon = MenuBarController.templateIcon()

        #expect(icon.isTemplate, "a menu-bar icon must tint itself for the bar")
        // The cell is DERIVED from a target height now, after the raw
        // half-point cell shipped a 12 x 7.5pt speck the operator could not
        // find on their own menu bar. The contract flips from "cells are this
        // big" to "the icon is this tall": exactly `iconHeight`, whatever the
        // crab's proportions do.
        #expect(icon.size.height == MenuBarController.iconHeight)
        #expect(abs(icon.size.width
                    - CGFloat(box.w) * MenuBarController.iconHeight / CGFloat(box.h)) < 0.001)

        // Cropped: he fills the icon rather than floating in the sprite's
        // transparent margins.
        #expect(box.w < PixelBuffer.side && box.h < PixelBuffer.side)
        // And it stays inside what a menu bar will show — but is no longer
        // allowed to be a speck either. The bar's glyph body is ~16-18pt, and
        // anything under 14 disappears next to every neighbour it has.
        #expect(icon.size.height <= 18)
        #expect(icon.size.height >= 14,
                "\(icon.size.height)pt is a speck — this is the exact bug that shipped")
    }

    /// The face is punched, not drawn — a template image carries only alpha.
    /// His silhouette alone is a rectangle with legs; the holes are what make
    /// the shape read as him.
    @Test("The eyes are holes and the shell is solid")
    func theFaceIsPunchedThrough() throws {
        let buffer = CrabRig.render(CrabPose())
        let box = try #require(SpriteMask(buffer).bounds)
        let icon = MenuBarController.templateIcon()

        // Drawn into a bitmap of exactly one pixel per sprite cell, rather
        // than sampled from whatever backing scale `tiffRepresentation`
        // happens to hand back. At a half-point cell a 1x bitmap would put two
        // cells in one pixel and the punch would become unreadable — the test
        // would then be measuring the sampling, not the icon.
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: box.w, pixelsHigh: box.h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: box.w, height: box.h))
        NSGraphicsContext.restoreGraphicsState()

        // A cell's row in the bitmap is its row in the crop: the draw flips
        // once going into the unflipped image and the bitmap flips back.
        func alpha(bufferX: Int, bufferY: Int) -> CGFloat? {
            let column = bufferX - box.x, row = bufferY - box.y
            guard column >= 0, row >= 0, column < box.w, row < box.h else { return nil }
            return rep.colorAt(x: column, y: row)?.alphaComponent
        }

        var checkedEye = false, checkedShell = false
        for y in 0..<PixelBuffer.side {
            for x in 0..<PixelBuffer.side {
                switch buffer[x, y] {
                case .eye:
                    if let a = alpha(bufferX: x, bufferY: y) {
                        #expect(a < 0.5, "the eye at (\(x),\(y)) was filled in")
                        checkedEye = true
                    }
                case .body:
                    if let a = alpha(bufferX: x, bufferY: y) {
                        #expect(a > 0.5, "the shell at (\(x),\(y)) is see-through")
                        checkedShell = true
                    }
                default: break
                }
            }
        }
        #expect(checkedEye, "the fixture has no eyes to punch")
        #expect(checkedShell, "the fixture has no shell to fill")
    }
}
