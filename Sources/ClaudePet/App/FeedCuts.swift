import AppKit
import SwiftUI

/// 📣 **Three cuts for a feed — 4:5, no type, nothing committed.**
///
/// The operator asked for three clips to post: the laser flip with the rainbow
/// washing on and everything coming home; the backside jiggling; and the ribbon
/// streaming into the grind.
///
/// **Nothing here is new behaviour.** Every frame is the rig doing what it
/// already does — two real tricks back to back, the half cab's own held second,
/// and a window of a real scoring ride. A marketing clip that invented motion
/// would be selling something the app does not do.
///
/// **No type, deliberately** — the operator sets type in Figma, and a clip that
/// carried its own would be a second draft of theirs.
///
/// **Nothing is committed.** The flag points at `build/`, which is gitignored.
@MainActor
enum FeedCuts {

    // MARK: - The frame

    /// 4:5, the tallest a feed will render at full width, and a sprite that is a
    /// whole number of cells: 896 is 28 points a cell exactly, so nothing lands
    /// on a fractional pixel. The 92-point margin either side is what keeps him
    /// from filling the frame edge to edge like a sticker.
    nonisolated static let canvas = CGSize(width: 1080, height: 1350)
    nonisolated static let spriteSide: CGFloat = 896
    nonisolated static var cell: CGFloat { spriteSide / CGFloat(PixelBuffer.side) }
    /// Whole cells, and downward: he reads better a little below the middle of a
    /// tall frame than dead centre in it.
    nonisolated static let cellsDown = 1
    nonisolated static var offsetY: CGFloat { CGFloat(cellsDown) * cell }

    /// 20 fps — what a GIF can actually store, 0.05s a frame exactly. A twelfth
    /// rounds to 8 centiseconds and plays 4% fast.
    nonisolated static let fps = 20
    nonisolated static let frameDelay = 0.05
    /// 120 BPM, the house grid. Every cut below is a whole number of these.
    nonisolated static let beat = 0.5

    // MARK: - Cut one: the laser flip, and the colour coming home

    nonisolated static let flipLength = CrabAnimator.Flourish.laserFlip.duration   // 3.2
    nonisolated static let spinLength = CrabAnimator.Flourish.bigspin.duration     // 2.8
    /// 🔎 A BEAT OF HIM STANDING THERE, and it is not padding.
    ///
    /// The bigspin's turn only reaches a whole one in the LIMIT: at 20fps the
    /// last frame inside the trick sits at 0.93 of a turn, five and twenty
    /// degrees off square, and a clip that ends there ends unresolved. Live that
    /// never shows, because the flourish hands straight back to an idle pose
    /// which is square — so the cut includes the hand-off. `flourishPose` past a
    /// trick's duration returns the base on its own, so the tail costs no
    /// special case, and it gives the eye somewhere to land before the loop
    /// comes round again.
    /// 🔎 Eight tenths, not a round half, and the odd number is the point: the
    /// laser flip is 3.2s, so the two tricks together come to 8.2 — sixteen and
    /// two fifths of a beat. The tail is what carries the CLIP onto the grid,
    /// so it is sized to the remainder rather than to taste. Nine seconds, and
    /// eighteen whole beats.
    nonisolated static let oneTail = 0.8
    nonisolated static var oneTricks: Double { flipLength + spinLength }           // 6.0
    nonisolated static var oneLength: Double { oneTricks + oneTail }               // 6.5
    /// The cross-dissolve across the seam. Short — a quarter second — because
    /// what it is hiding is a board swap, not a change of subject.
    nonisolated static let seamBlend = 0.25
    /// When the party starts, chosen so its own trapezoid does the work: the
    /// rainbow is 4.0s with a 0.4s edge, so at this offset the colour washes on
    /// two-thirds through the flip and ramps out over the last 0.4s — which is
    /// exactly the bigspin's roll-out. The spin and the colour arrive home
    /// together, which is what was asked for.
    /// Off the TRICKS' end, not the clip's: the colour is home when he lands,
    /// and the tail after it is plain Claw'd standing in his own shell.
    nonisolated static var partyOnset: Double { oneTricks - CrabView.rainbowDuration }  // 2.0

    /// 🔎 The seam is BLENDED, not cut.
    ///
    /// `bob` and `squash` already match across it — the laser flip rolls out at
    /// `squash 1, bob 1` and the bigspin opens on the same — so the figure does
    /// not jump. The PROPS differ, though, and a one-frame board swap is a snap
    /// like any other. `CrabPose.blend` is the machinery the live view uses for
    /// exactly this: it holds the outgoing board in the ghost slot and dissolves
    /// it out while the incoming one dissolves in.
    static func onePose(_ t: Double) -> CrabPose {
        let flip = CrabAnimator.flourishPose(.laserFlip, at: min(t, flipLength - 1e-6))
        guard t >= flipLength else { return flip }
        let spin = CrabAnimator.flourishPose(.bigspin, at: t - flipLength)
        // Into the spin.
        if t < flipLength + seamBlend {
            return CrabPose.blend(from: flip, to: spin, u: (t - flipLength) / seamBlend)
        }
        guard t >= oneTricks else { return spin }
        // …and OUT of it. `flourishPose` past a trick's duration hands back the
        // base, and the base carries no board — so without this the deck
        // vanishes in a single frame the instant he lands, which is the same
        // one-frame prop change the seam above exists to avoid. Live it never
        // shows, because the view dissolves a flourish's prop away on the way
        // back to idle; the cut has to do the same thing itself.
        let ending = CrabAnimator.flourishPose(.bigspin, at: spinLength - 1e-6)
        guard t < oneTricks + seamBlend else { return spin }
        return CrabPose.blend(from: ending, to: spin, u: (t - oneTricks) / seamBlend)
    }

    static func oneTint(_ t: Double) -> SpriteTint.Tint? {
        CrabView.rainbowTint(elapsed: t - partyOnset)
    }

    // MARK: - Cut two: the jiggle

    /// The half cab's held second, twice.
    ///
    /// The window is `ButtLoop`'s, asked for rather than restated — a second copy
    /// of those two constants is a second thing to drift. Two passes rather than
    /// one because a one-second clip between two six-second ones reads as a
    /// stutter, and because a feed that does not loop politely still gets a
    /// jiggle out of it.
    nonisolated static let jigglePasses = 2
    nonisolated static var twoLength: Double {
        (ButtLoop.closeAt - ButtLoop.openAt) * CrabAnimator.Flourish.halfCab.duration
            * Double(jigglePasses)
    }

    static func twoPose(_ index: Int) -> CrabPose {
        ButtLoop.pose(index % ButtLoop.frameCount)
    }

    // MARK: - Cut three: the trail into the grind

    /// The back smith's own extent inside a scoring ride: the ribbon is already
    /// streaming at four rungs when the window opens and never goes out.
    ///
    /// 🔎 Taken from the RIDE, not composed. `flourishPose` never scores — it is
    /// pinned not to — so a hand-built "back smith with a trail" would mean
    /// writing `combo` in from outside and showing something the app does not do.
    /// `comboRide` is the app doing it.
    nonisolated static let rideOpensAt = 11.8
    nonisolated static let rideClosesAt = 18.3
    nonisolated static var threeLength: Double { rideClosesAt - rideOpensAt }     // 6.5

    /// 🛹 IN THE SKATER'S FIT, because the combo ride IS the Skater's ride:
    /// live it is the wardrobe that unlocks the session, and `deckStance`
    /// returns nought for anything else. The first cut of this file rendered it
    /// on a bare crab, which read fine and was quietly the wrong character.
    nonisolated static let threeCostume = Costume.skater
    static func threePose(_ t: Double) -> CrabPose {
        CrabAnimator.comboRide(local: rideOpensAt + t,
                               wardrobe: .init(current: threeCostume)) ?? CrabPose()
    }

    /// 🔎 THE SHELL IS TINTED, and it is not decoration.
    ///
    /// `composedTint` says it in as many words at the point it reaches for this:
    /// *"a review that showed the trail without the rainbow would be lying about
    /// the ride."* The score drives both — the ribbon off the board and the
    /// colour on the shell are one signal — so a cut that carried the ribbon on
    /// a plain terracotta crab would be a state the app never produces. The
    /// first pass of this file did exactly that, and the contact sheet caught it.
    ///
    /// The clock is the ride's own, so the hue is continuous across the cut and
    /// is the hue the app would be showing at that instant of that ride.
    static func threeTint(_ t: Double) -> SpriteTint.Tint? {
        CrabView.comboTint(t: rideOpensAt + t, combo: threePose(t).combo,
                           costume: threeCostume)
    }

    // MARK: - Composition

    @ViewBuilder
    static func scene(_ pose: CrabPose, tint: SpriteTint.Tint?,
                      costume: Costume = .none) -> some View {
        ZStack {
            MarketingPalette.cream
            PixelCanvasView(buffer: CrabRig.render(pose, costume: costume),
                            bodyTint: tint?.body,
                            bodyShadeTint: tint?.shade,
                            inkOverrides: CostumeStyle.blendedOverrides(from: costume,
                                                                        to: costume, u: 1),
                            seamBleed: 0)
                .frame(width: spriteSide, height: spriteSide)
                .offset(y: offsetY)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    static func frame(_ pose: CrabPose, tint: SpriteTint.Tint?,
                      costume: Costume) -> CGImage? {
        // Opaque: it lets ImageIO delta-code only the cells that moved, where
        // transparency forces a re-encode of the whole sprite box every frame.
        SpriteImage.cgImage(of: scene(pose, tint: tint, costume: costume),
                            scale: 1, isOpaque: true)
    }

    // MARK: - Render

    struct Cut {
        let name: String
        let seconds: Double
        let costume: Costume
        let pose: @MainActor (Int) -> CrabPose
        let tint: @MainActor (Int) -> SpriteTint.Tint?

        var frames: Int { Int((seconds * Double(fps)).rounded()) }
    }

    static var cuts: [Cut] {
        [
            Cut(name: "1-laserflip", seconds: oneLength, costume: .none,
                pose: { onePose(Double($0) / Double(fps)) },
                tint: { oneTint(Double($0) / Double(fps)) }),
            Cut(name: "2-jiggle", seconds: twoLength, costume: .none,
                pose: { twoPose($0) }, tint: { _ in nil }),
            Cut(name: "3-backsmith", seconds: threeLength, costume: threeCostume,
                pose: { threePose(Double($0) / Double(fps)) },
                tint: { threeTint(Double($0) / Double(fps)) }),
        ]
    }

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(directory)\n".utf8))
            return false
        }

        for cut in cuts {
            var images: [CGImage] = []
            images.reserveCapacity(cut.frames)
            for index in 0..<cut.frames {
                guard let image = frame(cut.pose(index), tint: cut.tint(index),
                                        costume: cut.costume) else {
                    FileHandle.standardError.write(Data("frame \(index) of \(cut.name) failed\n".utf8))
                    return false
                }
                images.append(image)
            }
            guard GifRenderer.encode(images, to: root.appendingPathComponent("\(cut.name).gif"),
                                     frameDelay: frameDelay)
            else { return false }
        }

        print("wrote \(cuts.count) cuts at \(Int(canvas.width))×\(Int(canvas.height)) to \(directory)")
        return true
    }
}
