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
        #expect(icon.size.width == CGFloat(box.w) * MenuBarController.iconCell)
        #expect(icon.size.height == CGFloat(box.h) * MenuBarController.iconCell)

        // Cropped: he fills the icon rather than floating in the sprite's
        // transparent margins.
        #expect(box.w < PixelBuffer.side && box.h < PixelBuffer.side)
        // And it stays inside what a menu bar will show.
        #expect(icon.size.height <= 18)
    }

    /// The face is punched, not drawn — a template image carries only alpha.
    /// His silhouette alone is a rectangle with legs; the holes are what make
    /// the shape read as him.
    @Test("The eyes are holes and the shell is solid")
    func theFaceIsPunchedThrough() throws {
        let buffer = CrabRig.render(CrabPose())
        let box = try #require(SpriteMask(buffer).bounds)
        let icon = MenuBarController.templateIcon()
        let tiff = try #require(icon.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))

        // A cell's row in the bitmap is its row in the crop: the draw flips
        // once going into the unflipped image and the bitmap flips back.
        func alpha(bufferX: Int, bufferY: Int) -> CGFloat? {
            let column = bufferX - box.x, row = bufferY - box.y
            guard column >= 0, row >= 0, column < box.w, row < box.h else { return nil }
            let scale = Int(CGFloat(rep.pixelsWide) / icon.size.width)
            return rep.colorAt(x: column * scale, y: row * scale)?.alphaComponent
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
