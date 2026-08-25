import Foundation
import CoreGraphics

/// Every animatable part of Claw'd, in whole sprite pixels.
///
/// Claw'd's silhouette is a rectangle with four stubby legs and a nub on each
/// side. There is very little to move, which is the point: the character reads
/// from a handful of pixels, so the animation has to be legible at that scale —
/// a one-pixel bob, an eye that blinks to a single row, arms that go up.
public struct CrabPose: Sendable, Equatable {
    /// Whole-pixel vertical offset of the whole body. Negative is up.
    public var bob: Int = 0
    /// Whole-pixel horizontal lean.
    public var lean: Int = 0

    /// 0 = eyes open (3×3 squares), 1 = shut (a single row).
    public var blink: Double = 0
    /// Which single eye is closed. Separate from `blink`, which is one scalar
    /// consumed for both eyes at once and so cannot express a wink.
    public var winkEye: EyeSide = .none
    public enum EyeSide: Sendable { case none, left, right }
    /// Eye shape. `.determined` carves the inner-top corner into a focused slant.
    public var eyes: EyeStyle = .round
    public enum EyeStyle: Sendable { case round, determined, wide }
    /// Whole-pixel vertical offset applied to the eyes in opposite directions —
    /// a head tilt, on a grid that cannot rotate.
    public var tilt: Int = 0
    /// Eye offset in whole pixels.
    public var gazeX: Int = 0
    public var gazeY: Int = 0

    /// 0 = arm nub at rest on the body's side, 1 = arm raised straight up.
    public var armLeft: Double = 0
    public var armRight: Double = 0

    /// Walk cycle phase, and how much the legs actually move.
    public var legPhase: Double = 0
    public var legAmplitude: Double = 0

    public var mouth: Mouth = .smile
    public enum Mouth: Sendable { case smile, flat, open, none }

    /// Forces the eyes open even in the sleeping pose. Set when the pointer is
    /// on him: a pet you poke should stir, not keep snoring.
    public var asleepOverride: Bool = false

    /// Landing squash: the body draws one row shorter and one column wider per
    /// unit, so a jump lands with weight instead of stopping dead.
    public var squash: Int = 0
    /// Whole-body scale for the click reaction. 1 = full size. Never above 1:
    /// at the largest pixel size the sprite already fills its window.
    public var scale: Double = 1

    /// The prop drawn with Claw'd. Straight from the sticker set — he is almost
    /// always pictured *with* something.
    public var prop: Prop = .none
    public enum Prop: String, Sendable, CaseIterable {
        case none
        // World props: drawn at a fixed spot in the frame.
        case sparkles, terminal, check, bang, zzz, servers, balloon, plan
        // Worn props: drawn on the body, and must travel with `bob` and `lean`.
        case hardHat, phone, fire, glasses
        // Appended (stableSeed is the allCases index — order is load-bearing):
        // the 8-bit Claude star, the thinking spell's second wind.
        case star

        var isWorn: Bool {
            switch self {
            case .hardHat, .phone, .fire, .glasses: true
            default: false
            }
        }

        /// The props Claw'd picks between while a tool is running.
        static let working: [Prop] = [.terminal, .hardHat, .servers, .phone, .fire, .glasses]
    }

    /// Drives the prop's own animation (scrolling code, blinking cursor,
    /// drifting z's, flickering flame).
    public var propPhase: Double = 0

    /// How much of the prop is present, 0…1. Below 1 the prop renders as a
    /// deterministic pixel dissolve — an indexed grid has no alpha to fade.
    public var propVisibility: Double = 1
    /// The outgoing prop during a swap or a mood blend, dissolving away.
    public var ghostProp: Prop = .none
    public var ghostPropPhase: Double = 0
    public var ghostPropVisibility: Double = 0

    /// Fire-state body heat, 0…1, and the cascade's own clock. Inert until a
    /// pose sets them; the rig repaints body rows in banded heat inks.
    public var heat: Double = 0
    public var heatPhase: Double = 0

    /// A pixel bug scuttling across the floor rows, or nil. The column is the
    /// bug's centre; the animator owns its schedule.
    public var bugX: Int?
    /// Seconds into a petting session, for the floating hearts. nil = no hearts.
    public var heartsElapsed: Double?
    /// When the hold ended, on the hearts' own clock. New hearts stop being
    /// born there and the ones already climbing finish out. nil = still held.
    ///
    /// This exists because the purr envelope and a heart's life are different
    /// lengths: the envelope closes 0.45s after you let go, and a heart born
    /// just before that has 1.3s of climbing left. Tying them together is what
    /// made letting go delete every heart in the air in a single frame. Same
    /// contract as `heartsElapsed`: the blend never lerps it.
    public var heartsUntil: Double?
    /// Seconds into the shrimp snack, for the shrinking 🍤. nil = no snack.
    public var snackElapsed: Double?
    /// The midnight telescope: envelope 0…1 and its own clock for twinkles.
    public var stargaze: Double = 0
    public var stargazePhase: Double = 0

    /// The quiet completion badge at his bottom-right foot, 0…1. Written each
    /// frame by the live view from timestamps (like `heartsElapsed`), so the
    /// mood blend deliberately does not lerp it — the envelope owns it.
    public var doneBadge: Double = 0
    /// The badge's three-minute reminder breath, 0…1. Same contract.
    public var doneBadgePulse: Double = 0

    /// The service glyph floating in his top-left airspace, or nil, and its
    /// presence 0…1. Written each frame by the live view from latch
    /// timestamps (like `doneBadge`), so the mood blend deliberately does
    /// not lerp them — the envelope owns the entrance and the exit.
    public var serviceGlyph: ServiceGlyph? = nil
    public var serviceGlyphVisibility: Double = 0

    /// Seconds into the rainbow party, for the confetti. nil = no party.
    /// Same contract as `heartsElapsed`: the blend never lerps it.
    public var confettiElapsed: Double? = nil
}

extension CrabPose.Prop {
    /// A dissolve seed that is stable across runs — `String.hashValue` is
    /// per-process randomised, which would re-deal the dissolve every launch.
    var stableSeed: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

extension ServiceGlyph {
    /// Dissolve seeds well clear of every other seed space (props are their
    /// allCases indices, the easter eggs sit at 700-731, costumes at 900+).
    var stableSeed: Int { 760 + (Self.allCases.firstIndex(of: self) ?? 0) }

    /// The mark's bitmap and ink key — the single source both the sprite
    /// stamp and the bubble badge draw from. Original 8-bit takes, all of
    /// them: evocative, never copied.
    var art: (rows: [String], key: [Character: PixelBuffer.Ink]) {
        switch self {
        case .npm:
            // The red cube with the lowercase n carved in paper.
            return ([
                "rrrrrrr",
                "rrrrrrr",
                "rpppppr",
                "rpprppr",
                "rpprppr",
                "rpprppr",
                "rrrrrrr",
            ], ["r": .alert, "p": .paper])
        case .github:
            // A cephalo-cat cut out of a charcoal tile. The dark is the
            // FIELD and the creature is the paper, so the light spreads and
            // the silhouette survives the badge's two points a cell.
            //
            // Three proportions carry the read, and all three were checked at
            // 2pt rather than at sprite size: a small face set HIGH on a big
            // body; ears one row deep, so they read as ears rather than as
            // the antennae a two-row notch makes; and a body that flares
            // wider than the head into four tentacle tips. A shape that
            // narrows to a chin is a devil, which is what the mark this
            // replaces was — its ears were two isolated 1x1 spikes with
            // nothing joining them and its eye row was a gap-toothed grin.
            // Evocative, never copied.
            return ([
                "dppddppd",
                "dppppppd",
                "dpdppdpd",
                "dppppppd",
                "dppppppd",
                "pppppppp",
                "pdppppdp",
                "pddpdpdp",
            ], ["d": .slate, "p": .paper])
        case .linear:
            // The ascending diamond, one notch of steel through it.
            return ([
                "...ll...",
                "..llll..",
                ".llssll.",
                "llssssll",
                ".llssll.",
                "..llll..",
                "...ll...",
            ], ["l": .screenLight, "s": .steel])
        case .deploy:
            // The rocket, exhaust in flame and ember.
            return ([
                "...ss...",
                "..ssss..",
                "..slls..",
                "..ssss..",
                ".ssssss.",
                "..f..f..",
                "..ee.ee.",
            ], ["s": .steel, "l": .screenLight, "f": .flame, "e": .ember])
        }
    }
}

/// Rasterises a `CrabPose` into a `PixelBuffer`.
public enum CrabRig {
    // Claw'd's proportions on the 32×32 grid, measured off the sticker art:
    // a wide body, eyes high and far apart, four legs with a wide centre gap.
    // Wider than tall, with a wide gap between the inner pair of legs and thin
    // nubs for arms. Getting this ratio wrong is what made the first attempt
    // read as a cat rather than as Claw'd.
    // The body block is internal, not private: the costume tailoring and the
    // window's torso drag handle measure the same torso the shell is drawn
    // with, so the measurement lives once, here, at its origin.
    static let bodyX = 6
    static let bodyW = 20
    static let bodyY = 10
    static let bodyH = 11

    private static let legTop = 21
    private static let legH = 4
    private static let legW = 2
    private static let legX = [7, 11, 20, 24]

    private static let armW = 2
    private static let armH = 3
    private static let armY = 14

    private static let eyeSize = 3
    private static let eyeY = 13
    private static let eyeLeftX = 10
    private static let eyeRightX = 19

    /// - Parameters:
    ///   - costume: the wardrobe drawn into the sprite. Defaults to `.none`, so
    ///     every pre-costume call site renders byte-identically.
    ///   - ghostCostume: the outgoing wardrobe during a change, dissolving away.
    ///   - costumeVisibility: eased progress of a costume change, 1 when settled.
    public static func render(_ pose: CrabPose,
                              costume: Costume = .none,
                              ghostCostume: Costume = .none,
                              costumeVisibility: Double = 1) -> PixelBuffer {
        var buffer = PixelBuffer()

        let dx = pose.lean
        let dy = pose.bob
        let squash = max(0, pose.squash)

        // A crown accessory steps aside while a crown prop is worn — the prop
        // is a status signal, and status outranks wardrobe.
        let crownProp = pose.prop == .hardHat && pose.propVisibility > 0.5
        func costumeLayer(_ layer: CrabCostume.Layer) {
            costumePass(&buffer, pose: pose, costume: ghostCostume, layer: layer,
                        visibility: 1 - costumeVisibility, crownProp: crownProp,
                        dx: dx, dy: dy, squash: squash)
            costumePass(&buffer, pose: pose, costume: costume, layer: layer,
                        visibility: costumeVisibility, crownProp: crownProp,
                        dx: dx, dy: dy, squash: squash)
        }

        // Behind the body. The flame dissolves with its prop's visibility, so a
        // prop swap away from fire cannot vanish the burst in one frame.
        firePass(&buffer, pose: pose, dx: dx, dy: dy)
        costumeLayer(.behind)

        drawLegs(&buffer, dx: dx, dy: dy, pose: pose)
        drawArms(&buffer, dx: dx, dy: dy, pose: pose)

        // Squash widens and shortens the body, keeping its feet on the ground.
        buffer.rect(bodyX + dx - squash, bodyY + dy + squash,
                    bodyW + squash * 2, bodyH - squash, .body)

        costumeLayer(.onBody)
        if pose.heat > 0.001 { heatPass(&buffer, pose: pose, dy: dy, squash: squash) }
        drawFace(&buffer, dx: dx, dy: dy, pose: pose)
        costumeLayer(.front)

        // Ghost first, so an incoming prop paints over an outgoing one where
        // they overlap.
        propPass(&buffer, pose: pose, prop: pose.ghostProp,
                 phase: pose.ghostPropPhase, visibility: pose.ghostPropVisibility,
                 dx: dx, dy: dy)
        propPass(&buffer, pose: pose, prop: pose.prop,
                 phase: pose.propPhase, visibility: pose.propVisibility,
                 dx: dx, dy: dy)

        // The service glyph, after the props so it wins its own cells where a
        // sparkle wanders in — its own channel, like the fire layer, so it
        // never fights the rolled prop, the ghost slot, or the crown yield.
        servicePass(&buffer, pose: pose)

        // The quiet-hour extras: a scuttling bug on the floor, hearts while he
        // is petted, the snack, the telescope. Each is a world overlay that
        // dissolves in and out like everything else. The completion badge
        // rides in the FOREGROUND, tucked against his side — it wins the leg
        // cells it overlaps, and only ever shell cells.
        if let confetti = pose.confettiElapsed {
            drawConfetti(&buffer, elapsed: confetti)
        }
        if pose.doneBadge > 0.001 {
            drawDoneBadge(&buffer, visibility: pose.doneBadge, pulse: pose.doneBadgePulse)
        }
        if let bugX = pose.bugX { drawBug(&buffer, x: bugX, phase: pose.propPhase) }
        if let hearts = pose.heartsElapsed {
            drawHearts(&buffer, elapsed: hearts, until: pose.heartsUntil)
        }
        if let snack = pose.snackElapsed { drawSnack(&buffer, elapsed: snack, dx: dx, dy: dy) }
        if pose.stargaze > 0.001 { drawStargaze(&buffer, pose: pose, dx: dx, dy: dy) }

        // Applied last so props scale with him rather than floating free.
        return abs(pose.scale - 1) > 0.001 ? buffer.scaled(pose.scale) : buffer
    }

    // MARK: - Quiet-hour extras

    /// The quiet completion marker: the same 8-bit checkbox the done pose
    /// holds overhead, tucked against his right side with its bottom edge
    /// exactly on the footline (legs end at row 24) and one column into his
    /// outer leg — z-ABOVE him, like a sticker in the foreground. The signal
    /// a finished task leaves behind once the pose has relaxed — present,
    /// not insistent.
    ///
    /// The foreground read is the operator's call (it replaced a
    /// ground-object version he stood in front of): where the badge and the
    /// leg overlap, the badge wins the cell. It still only ever covers shell
    /// ink — never a face, prop, or costume cell, which the corner test pins.
    private static func drawDoneBadge(_ b: inout PixelBuffer, visibility: Double, pulse: Double) {
        let shape = [
            ".gggg.",
            "gggggg",
            "ggg.wg",
            "gw.wgg",
            "g.wggg",
            ".gggg.",
        ]
        var badge = PixelBuffer()
        badge.stamp(shape, at: (x: 25, y: 19), key: ["g": .green, "w": .mouth])

        // The reminder breath: a golden shimmer through the badge's own
        // footprint, applied to the badge's scratch buffer so the pair lands
        // in one pass. Never a ring — a ring one cell out clips off the grid.
        // The house dissolve gives the swell its speckle; the envelope its
        // ease.
        if pulse > 0.001 {
            var glow = PixelBuffer()
            glow.stamp(shape, at: (x: 25, y: 19), key: ["g": .yellow, "w": .yellow])
            badge.composite(glow, visibility: Ease.clamp01(pulse), seed: 731)
        }

        b.composite(badge, visibility: Ease.clamp01(visibility), seed: 730)
    }

    /// A two-pixel bug on floor row 29, legs flickering, with a tiny bob.
    private static func drawBug(_ b: inout PixelBuffer, x: Int, phase: Double) {
        let bob = sin(phase * 9) > 0.6 ? -1 : 0
        b.rect(x, 29 + bob, 2, 1, .eye)
        // Leg flicker: alternate single pixels under the body.
        if sin(phase * 12) > 0 {
            b.pixel(x - 1, 30 + bob, .eye)
            b.pixel(x + 2, 30 + bob, .eye)
        } else {
            b.pixel(x, 30 + bob, .eye)
            b.pixel(x + 1, 30 + bob, .eye)
        }
    }

    /// The party's confetti: six flecks falling from the crown on a
    /// deterministic spawn table, each fading as it falls, the whole shower
    /// eased by the party's own trapezoid so the ends never snap. Seeds
    /// 740-745 — the registry gap between the easter eggs and the glyphs.
    private static func drawConfetti(_ b: inout PixelBuffer, elapsed: Double) {
        let window = Ease.window(elapsed, duration: 4.0, edge: 0.4)
        guard window > 0.001 else { return }
        let spawns: [(x: Int, born: Double, ink: PixelBuffer.Ink)] = [
            (6, 0.2, .yellow), (12, 0.5, .pink), (18, 0.8, .green),
            (24, 0.35, .screenLight), (9, 1.4, .pink), (21, 1.7, .yellow),
        ]
        for (index, fleck) in spawns.enumerated() {
            let age = (elapsed - fleck.born).truncatingRemainder(dividingBy: 2.4)
            guard elapsed > fleck.born, age >= 0 else { continue }
            let y = Int(age / 0.12)
            guard y < PixelBuffer.side else { continue }
            var piece = PixelBuffer()
            piece.pixel(fleck.x, y, fleck.ink)
            piece.pixel(fleck.x + (index % 2 == 0 ? 1 : -1), y + 1, fleck.ink)
            let fade = max(0, 1 - age / 1.6) * window
            b.composite(piece, visibility: fade, seed: 740 + index)
        }
    }

    /// The columns a heart may rise in. Nine is the leftmost the drift can
    /// reach, which keeps them clear of the service glyph's box at cols 1-8 —
    /// `drawHearts` runs after `servicePass`, so an overlap would eat the mark.
    private static let heartColumns = [10, 13, 16, 19, 22]

    /// Pink hearts rising from the crown while he is held. `CrabAnimator`
    /// owns when they are born; this owns what one looks like on its way up.
    ///
    /// Three things here are load-bearing, and each replaces something that
    /// was quietly wrong:
    ///
    /// - **`Ease.pulse`, not a linear fade.** The old heart had an ease at
    ///   neither end: `1 - age/1.6` is 1 at birth, so all seven cells
    ///   appeared in a single frame, and a `guard y > 0` deleted it at age
    ///   1.2s while the dissolve was still showing a quarter of it. `pulse`
    ///   is zero outside its own window, so a heart now arrives and leaves
    ///   under its own envelope and nothing has to kill it.
    /// - **A rise slow enough to outlast the grid** — see
    ///   `CrabAnimator.heartRow`. The old rate asked for 8.7 rows of travel
    ///   out of seven rows of airspace, and that mismatch *was* the bug.
    /// - **No `dx`/`dy`.** They were applied live rather than at birth, so
    ///   `applyPetting`'s own purr wiggle shifted every heart already in the
    ///   air one pixel sideways in lockstep. A heart he has let go of is not
    ///   attached to him any more. `drawConfetti` takes neither, for the
    ///   same reason.
    ///
    /// Seeds 700-702, cycling by ordinal.
    private static func drawHearts(_ b: inout PixelBuffer, elapsed: Double, until: Double?) {
        for (ordinal, born) in CrabAnimator.heartSpawns(elapsed: elapsed, until: until) {
            let age = elapsed - born
            let visibility = CrabAnimator.heartVisibility(age: age)
            guard visibility > 0.001 else { continue }
            let row = CrabAnimator.heartRow(age: age)
            let pick = Int(CrabAnimator.noise(ordinal &* 59 &+ 7) * Double(heartColumns.count))
            // A single-pixel lean part-way up, so it does not rise in a
            // dead-straight line. One cell is the grid's own quantum.
            let drift = row <= 5 ? (ordinal % 2 == 0 ? 1 : -1) : 0
            var heart = PixelBuffer()
            heart.stamp([
                "p.p",
                "ppp",
                ".p.",
            ], at: (x: heartColumns[pick % heartColumns.count] + drift, y: row),
               key: ["p": .pink])
            b.composite(heart, visibility: visibility, seed: 700 + ordinal % 3)
        }
    }

    /// The 🍤: a small pink shrimp beside his mouth that loses a column per
    /// munch beat, easing in at the start. The last bite leaves a single pink
    /// pixel rather than nothing — one cell is the grid's own quantum, so it
    /// reads as a crumb and disappears with the envelope at 2.8s.
    private static func drawSnack(_ b: inout PixelBuffer, elapsed: Double, dx: Int, dy: Int) {
        // Three munch beats at 0.9, 1.5, 2.1s; a column disappears at each.
        let bites = [0.9, 1.5, 2.1].filter { elapsed >= $0 }.count
        let width = 4 - bites
        guard width > 0 else { return }
        var shrimp = PixelBuffer()
        shrimp.stamp([
            ".ppp",
            "pppk",
            ".pp.",
        ], at: (x: 3 + dx, y: 15 + dy), key: ["p": .pink, "k": .paper])
        // Eat right-to-left: clear the consumed columns.
        for eaten in 0..<bites {
            for row in 15...17 { shrimp.pixel(3 + dx + 3 - eaten, row + dy, .clear) }
        }
        let entry = Ease.smoothstep(elapsed / 0.4)
        b.composite(shrimp, visibility: entry, seed: 710)
    }

    /// The midnight telescope: a steel tube angled at the sky, twinkling stars
    /// in the top rows, and one shooting-star streak per session.
    private static func drawStargaze(_ b: inout PixelBuffer, pose: CrabPose, dx: Int, dy: Int) {
        var scene = PixelBuffer()
        let phase = pose.stargazePhase

        // Tube: a 5-pixel diagonal from his right claw toward the sky.
        for step in 0..<5 {
            scene.pixel(24 + step + dx, 14 - step + dy, .steel)
        }
        scene.pixel(24 + dx, 15 + dy, .steel)   // tripod hint

        // Four stars on offset twinkle phases — a twinkle snaps like a blink.
        let stars = [(4, 2), (9, 5), (17, 1), (27, 3)]
        for (index, star) in stars.enumerated() {
            if sin(phase * (1.1 + Double(index) * 0.4) + Double(index) * 2.3) > 0.1 {
                scene.pixel(star.0, star.1, index % 2 == 0 ? .yellow : .mouth)
            }
        }

        // One shooting star early in the session: a three-pixel diagonal streak.
        if phase > 2, phase < 2.5 {
            let head = Int((phase - 2) * 20)
            for trail in 0..<3 {
                scene.pixel(6 + head - trail, 3 + (head - trail) / 3, .mouth)
            }
        }

        b.composite(scene, visibility: Ease.clamp01(pose.stargaze), seed: 720)
    }

    /// One costume layer at a given visibility, dissolving like a prop does.
    private static func costumePass(_ b: inout PixelBuffer, pose: CrabPose, costume: Costume,
                                    layer: CrabCostume.Layer, visibility: Double,
                                    crownProp: Bool, dx: Int, dy: Int, squash: Int) {
        guard costume != .none, visibility > 0.001 else { return }
        if layer == .front, crownProp, CostumeStyle.of(costume).yieldsCrownToProps { return }
        if visibility > 0.999 {
            CrabCostume.draw(&b, costume: costume, layer: layer,
                             dx: dx, dy: dy, squash: squash, pose: pose)
        } else {
            var scratch = PixelBuffer()
            CrabCostume.draw(&scratch, costume: costume, layer: layer,
                             dx: dx, dy: dy, squash: squash, pose: pose)
            b.composite(scratch, visibility: visibility,
                        seed: 900 + (Costume.allCases.firstIndex(of: costume) ?? 0))
        }
    }

    /// The service glyph at its own visibility — the fire layer's shape, one
    /// glyph at a time. World-anchored in the top-left airspace (cols 1-8,
    /// rows 0-7), which every scheduled occupant verifiably avoids.
    private static func servicePass(_ b: inout PixelBuffer, pose: CrabPose) {
        guard let glyph = pose.serviceGlyph, pose.serviceGlyphVisibility > 0.001 else { return }
        if pose.serviceGlyphVisibility > 0.999 {
            drawServiceGlyph(&b, glyph)
        } else {
            var scratch = PixelBuffer()
            drawServiceGlyph(&scratch, glyph)
            b.composite(scratch, visibility: pose.serviceGlyphVisibility, seed: glyph.stableSeed)
        }
    }

    /// One original 8-bit mark, centred in the (1,0) 8×8 box. The bitmap and
    /// key come from `ServiceGlyph.art` — the same rows the bubble badge
    /// draws, so the two renditions cannot drift.
    private static func drawServiceGlyph(_ b: inout PixelBuffer, _ glyph: ServiceGlyph) {
        let art = glyph.art
        b.stamp(art.rows, at: (x: 1, y: 0), key: art.key)
    }

    /// The behind-the-body flame layer for whichever of the live and ghost
    /// props is `.fire`, at its own visibility.
    private static func firePass(_ b: inout PixelBuffer, pose: CrabPose, dx: Int, dy: Int) {
        func layer(phase: Double, visibility: Double) {
            guard visibility > 0.001 else { return }
            if visibility > 0.999 {
                drawFire(&b, dx: dx, dy: dy, phase: phase)
            } else {
                var scratch = PixelBuffer()
                drawFire(&scratch, dx: dx, dy: dy, phase: phase)
                b.composite(scratch, visibility: visibility, seed: CrabPose.Prop.fire.stableSeed)
            }
        }
        if pose.ghostProp == .fire { layer(phase: pose.ghostPropPhase, visibility: pose.ghostPropVisibility) }
        if pose.prop == .fire { layer(phase: pose.propPhase, visibility: pose.propVisibility) }
    }

    /// The cooking heat: a three-row band of quantised heat inks sweeping up
    /// through the shell. Only cells that are currently `.body` repaint — the
    /// face, the costume pixels and the props sit above the heat, and the
    /// arms and legs staying terracotta is what makes it read as heat rising
    /// through the shell rather than a whole-sprite recolour. Banded, never a
    /// gradient: the band's width is itself quantised by the heat envelope, so
    /// the cascade eases in as a growing band and out as a shrinking one.
    private static func heatPass(_ b: inout PixelBuffer, pose: CrabPose, dy: Int, squash: Int) {
        let top = bodyY + dy + squash
        let height = bodyH - squash
        let bottom = top + height - 1
        guard height > 0 else { return }

        let sweep = pose.heatPhase - floor(pose.heatPhase)
        let center = Double(bottom) - sweep * Double(height + 3)
        let halfWidth = Int((Ease.clamp01(pose.heat) * 2).rounded())

        for y in max(0, top)...min(PixelBuffer.side - 1, bottom) {
            let distance = abs(Double(y) - center)
            guard distance <= Double(halfWidth) + 0.001 else { continue }
            let ink: PixelBuffer.Ink = distance <= Double(max(0, halfWidth - 1)) ? .bodyEmber : .bodyHot
            for x in 0..<PixelBuffer.side where b[x, y] == .body {
                b[x, y] = ink
            }
        }
    }

    /// One prop at a given visibility. Full visibility draws straight into the
    /// buffer — byte-identical to the pre-dissolve renderer; anything less
    /// renders to a scratch buffer and composites as a stable pixel dissolve.
    private static func propPass(_ b: inout PixelBuffer, pose: CrabPose, prop: CrabPose.Prop,
                                 phase: Double, visibility: Double, dx: Int, dy: Int) {
        guard prop != .none, visibility > 0.001 else { return }
        var proxy = pose
        proxy.prop = prop
        proxy.propPhase = phase
        if visibility > 0.999 {
            drawProp(&b, dx: dx, dy: dy, pose: proxy)
        } else {
            var scratch = PixelBuffer()
            drawProp(&scratch, dx: dx, dy: dy, pose: proxy)
            b.composite(scratch, visibility: visibility, seed: prop.stableSeed)
        }
    }

    // MARK: - Legs

    private static func drawLegs(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        for (index, x) in legX.enumerated() {
            // Alternating pairs, so the scuttle reads as a gait rather than a jitter.
            let swing = sin(pose.legPhase + Double(index) * .pi / 2) * pose.legAmplitude
            let lift = Int(swing.rounded())
            b.rect(x + dx, legTop + dy - min(0, lift), legW, legH - abs(lift), .body)
        }
    }

    // MARK: - Arms

    /// At rest the arm is a short nub on the body's side. Raised, it becomes a
    /// narrower vertical bar rising above the shoulder — the "arms up" pose from
    /// the sticker set.
    private static func drawArms(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        drawArm(&b, lift: pose.armLeft, isLeft: true, dx: dx, dy: dy)
        drawArm(&b, lift: pose.armRight, isLeft: false, dx: dx, dy: dy)
    }

    private static func drawArm(_ b: inout PixelBuffer, lift: Double, isLeft: Bool, dx: Int, dy: Int) {
        let clamped = max(0, min(1, lift))
        let x = (isLeft ? bodyX - armW : bodyX + bodyW) + dx

        // The nub always stays put at the body's side; raising grows a bar
        // upward from it. Moving the whole nub instead made the arms detach and
        // read as ears poking off the top corners.
        b.rect(x, armY + dy, armW, armH, .body)

        let reach = Int((clamped * 6).rounded())
        if reach > 0 {
            // Stepped one pixel further out. Flush against the body, a raised
            // arm merges into the top corner and the whole silhouette reads as
            // a cat with ears; the step keeps it reading as a raised arm.
            let outward = isLeft ? x - 1 : x + 1
            b.rect(outward, armY + dy - reach, armW, reach, .body)
        }
    }

    // MARK: - Face

    private static func drawFace(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        let eyeTop = eyeY + dy + pose.gazeY
        // Tilt raises one eye and drops the other. The grid cannot rotate, so a
        // head tilt is expressed entirely in the face.
        for (side, baseX) in [(CrabPose.EyeSide.left, eyeLeftX), (.right, eyeRightX)] {
            let x = baseX + dx + pose.gazeX
            let top = eyeTop + (side == .left ? -pose.tilt : pose.tilt)

            // A wink is checked independently of `blink`, and deliberately not
            // gated on `asleepOverride` — the hover greeting sets that flag on
            // every frame, so routing a wink through `blink` renders two open
            // eyes and nothing else.
            let shut = (pose.blink > 0.5 && !pose.asleepOverride) || pose.winkEye == side
            guard !shut else {
                b.rect(x, top + 1, eyeSize, 1, .eye)
                continue
            }

            switch pose.eyes {
            case .round:
                b.rect(x, top, eyeSize, eyeSize, .eye)
            case .wide:
                // One row taller, for the expectant "well?" of the nudge.
                b.rect(x, top - 1, eyeSize, eyeSize + 1, .eye)
            case .determined:
                // Carve the inner-top corner so the brows slant toward the nose.
                // drawFace runs after the body, so painting `.body` over a corner
                // is a clean erase — cutting the OUTER corners instead would read
                // as worried rather than focused.
                b.rect(x, top, eyeSize, eyeSize, .eye)
                b.pixel(side == .left ? x + eyeSize - 1 : x, top, .body)
            }
        }

        let mouthY = 17 + dy
        let centre = bodyX + bodyW / 2 + dx
        switch pose.mouth {
        case .none:
            break
        case .flat:
            b.rect(centre - 2, mouthY, 4, 1, .mouth)
        case .smile:
            // A shallow bowl: wide bottom row with the ends stepping up.
            b.rect(centre - 2, mouthY + 1, 5, 1, .mouth)
            b.pixel(centre - 3, mouthY, .mouth)
            b.pixel(centre + 3, mouthY, .mouth)
        case .open:
            // Small — a wide white block reads as bared teeth, not delight.
            b.rect(centre - 1, mouthY, 3, 2, .mouth)
        }
    }

    // MARK: - Props
    //
    // Claw'd in the official art is nearly always holding or standing next to
    // something. Reusing that vocabulary is what makes each state instantly
    // readable at dock size.


    private static func drawProp(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        let phase = pose.propPhase
        switch pose.prop {
        case .none:
            break
        case .fire:
            // The blaze itself is drawn behind him; only its sparks come forward.
            drawSparks(&b, dx: dx, dy: dy, phase: phase)

        case .sparkles:
            // Three sparkles pulsing out of phase above his head.
            let positions = [(3, 5), (27, 3), (25, 9)]
            for (index, position) in positions.enumerated() {
                let p = phase + Double(index) * 2.1
                guard sin(p) > -0.2 else { continue }
                b.pixel(position.0, position.1, .yellow)
                if sin(p) > 0.6 {
                    b.pixel(position.0 - 1, position.1, .yellow)
                    b.pixel(position.0 + 1, position.1, .yellow)
                    b.pixel(position.0, position.1 - 1, .yellow)
                    b.pixel(position.0, position.1 + 1, .yellow)
                }
            }

        case .terminal:
            drawTerminal(&b, dx: dx, dy: dy, phase: phase)

        case .check:
            let key: [Character: PixelBuffer.Ink] = ["g": .green, "w": .mouth]
            b.stamp([
                ".gggg.",
                "gggggg",
                "ggg.wg",
                "gw.wgg",
                "g.wggg",
                ".gggg.",
            ], at: (x: 0, y: 1), key: key)

        case .bang:
            // A proper 8-bit exclamation: three wide with an ember outline
            // and a paper highlight, bouncing a single pixel on the phase —
            // the sanctioned snap, and the urgency the two plain rects of
            // the first draft never had.
            let hop = sin(phase * 4) > 0.3 ? -1 : 0
            b.rect(14, 1 + hop, 4, 6, .ember)
            b.rect(15, 1 + hop, 2, 5, .pink)
            b.pixel(15, 1 + hop, .paper)
            b.rect(14, 8 + hop, 4, 2, .ember)
            b.rect(15, 8 + hop, 2, 1, .pink)

        case .zzz:
            let key: [Character: PixelBuffer.Ink] = ["z": .screenLight]
            let drift = Int((sin(phase) * 1.5).rounded())
            b.stamp(["zzz", "..z", ".z.", "zzz"], at: (x: 25, y: 3 + drift), key: key)
            if sin(phase * 0.7) > 0 {
                b.stamp(["zz", ".z", "zz"], at: (x: 22, y: 9 - drift), key: key)
            }

        case .servers:
            // The blue rack he leans on in the sticker set. Status lights blink
            // independently so the stack looks powered rather than painted.
            let key: [Character: PixelBuffer.Ink] = ["d": .screenDark, "l": .screenLight]
            for (index, top) in [9, 14, 19].enumerated() {
                b.stamp([
                    "llllll",
                    "d....d",
                    "dddddd",
                ], at: (x: 26, y: top), key: key)
                let lit = sin(phase * 2 + Double(index) * 1.7) > -0.3
                b.pixel(28, top + 1, lit ? .green : .screenDark)
            }

        case .balloon:
            // String first, so the knot sits under the balloon.
            let sway = Int((sin(phase * 0.9) * 1.5).rounded())
            for y in 9...14 {
                b.pixel(4 + sway + (y > 11 ? 1 : 0), y, .steel)
            }
            let key: [Character: PixelBuffer.Ink] = ["g": .green, "b": .screenLight]
            b.stamp([
                ".ggggg.",
                "ggbbbgg",
                "gbbbbbg",
                "ggbbbgg",
                ".ggggg.",
            ], at: (x: 1 + sway, y: 3), key: key)

        case .hardHat:
            drawHardHat(&b, dx: dx, dy: dy, phase: phase)

        case .star:
            // The Claude star, holding the top-right airspace (cols 20-28) —
            // clear of the service glyph box on the left and the body below.
            b.stamp(StarMark.art.rows, at: (x: 20, y: 0), key: StarMark.art.key)

        case .glasses:
            drawGlasses(&b, dx: dx, dy: dy, pose: pose)

        case .plan:
            // A little clipboard: clip, page, ruled lines. He holds it out.
            let key: [Character: PixelBuffer.Ink] = ["p": .paper, "s": .steel, "l": .screenLight]
            b.stamp([
                "..ss..",
                "pppppp",
                "pllllp",
                "pllllp",
                "pppppp",
                "pllllp",
                "pppppp",
            ], at: (x: 25, y: 4), key: key)

        case .phone:
            // Held at his side, screen facing out. The first draft read as
            // a smudge at desk size: now a wider slab with a lit screen, a
            // glow row, a notification dot pulsing in alert red, and a home
            // button — a phone, not a domino.
            let x = 26 + dx
            let y = 10 + dy
            b.rect(x, y, 5, 8, .screenDark)
            b.rect(x + 1, y + 1, 3, 5, sin(phase * 3) > 0 ? .screenLight : .screenDark)
            b.rect(x + 1, y + 1, 3, 1, .paper)
            if sin(phase * 2.2) > -0.2 { b.pixel(x + 3, y + 2, .alert) }
            b.pixel(x + 2, y + 7, .steel)
        }
    }

    /// The little code window, with output scrolling up through it.
    ///
    /// Held in front of him like a laptop: the frame overlaps the lower body
    /// and the inner legs, his claws grip the top corners, and his eyes peer
    /// over the lid — so it reads as something he is using, not backdrop
    /// furniture. It tracks `dx`/`dy` for the same reason: a console that
    /// ignores his bob reads as painted onto the wall behind him.
    private static func drawTerminal(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let originX = 10 + dx
        let originY = 17 + dy
        let width = 12
        let height = 7

        b.rect(originX, originY, width, height, .screenDark)
        b.rect(originX, originY, width, 2, .screenLight)

        // Title-bar dots cycling, like a window that is doing something.
        let dots: [PixelBuffer.Ink] = [.pink, .yellow, .green]
        for index in 0..<3 {
            let active = Int(phase * 1.5) % 3 == index
            b.pixel(originX + 1 + index * 2, originY + 1, active ? dots[index] : .screenDark)
        }

        // Interior: rows 3..<height-1. Code lines scroll upward and wrap.
        let interiorTop = originY + 3
        let interiorHeight = height - 4
        let lineWidths = [5, 3, 6, 2, 4, 7]
        let scroll = Int(phase * 3) % lineWidths.count

        for row in 0..<interiorHeight {
            let width = lineWidths[(row + scroll) % lineWidths.count]
            let indent = (row + scroll) % 2
            b.rect(originX + 1 + indent, interiorTop + row, width, 1, .green)
        }

        // Cursor on the bottom line.
        if sin(phase * 4) > 0 {
            b.rect(originX + 1, interiorTop + interiorHeight, 2, 1, .green)
        }

        // Claw tips over the top corners: the grip is what sells "held".
        b.rect(originX, originY, 2, 1, .body)
        b.rect(originX + width - 2, originY, 2, 1, .body)
    }

    /// Yellow hat on his crown, wrench and screwdriver at his sides.
    private static func drawHardHat(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let hatY = bodyY + dy - 4
        let centre = bodyX + bodyW / 2 + dx

        b.rect(centre - 5, hatY + 1, 10, 3, .yellow)   // dome
        b.rect(centre - 4, hatY, 8, 1, .yellow)        // crown
        b.rect(centre - 7, hatY + 4, 14, 1, .yellow)   // brim

        // Tools, bobbing gently so they read as held rather than glued on.
        let jiggle = sin(phase * 2) > 0 ? 0 : 1
        b.rect(2, 13 + jiggle, 2, 6, .steel)           // wrench shaft
        b.rect(1, 12 + jiggle, 4, 2, .steel)           // wrench head
        b.rect(29, 14 - jiggle, 2, 5, .steel)          // screwdriver shaft
        b.rect(28, 12 - jiggle, 4, 2, .screenDark)     // screwdriver handle
    }

    /// Wire frames around both eyes.
    ///
    /// Drawn as an outline only — filling the lenses would cover the eyes, and
    /// his eyes are most of his expression. Steel rather than black so the frame
    /// separates from the pupils behind it.
    private static func drawGlasses(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        let top = eyeY + dy + pose.gazeY - 1
        let bridgeY = top + 2

        for lensX in [eyeLeftX + dx - 1, eyeRightX + dx - 1] {
            b.rect(lensX, top, 5, 1, .steel)          // upper rim
            b.rect(lensX, top + 4, 5, 1, .steel)      // lower rim
            b.rect(lensX, top + 1, 1, 3, .steel)      // outer edge
            b.rect(lensX + 4, top + 1, 1, 3, .steel)  // inner edge
        }

        // Bridge between the lenses, and a temple arm on each side.
        b.rect(eyeLeftX + dx + 4, bridgeY, 6, 1, .steel)
        b.rect(eyeLeftX + dx - 3, bridgeY, 2, 1, .steel)
        b.rect(eyeRightX + dx + 4, bridgeY, 2, 1, .steel)
    }

    /// The blaze. An upward burst rising off his back, with sparks.
    ///
    /// Authored as silhouettes rather than computed: at this size a flame drawn
    /// by arithmetic reads as bars, and the eye recognises fire by its ragged
    /// outline. Three frames cycle, so it flickers by changing shape.
    ///
    /// Drawn BEFORE the body (`render`), so it may bleed down behind him and be
    /// harmlessly overpainted. Rows 0-9 are free in every fire-bearing pose.
    private static let flameFrames: [[String]] = [
        [
            "....cc....",
            "...cffc...",
            "..cffffc..",
            ".cffffffc.",
            ".cfffeefc.",
            "cffeeeeffc",
            "cfeeeeeefc",
            ".eeeeeeee.",
        ],
        [
            "...cc.c...",
            "..cffcfc..",
            ".cffffffc.",
            ".cfffffec.",
            "cffffeeefc",
            "cffeeeeefc",
            ".feeeeeef.",
            "..eeeeee..",
        ],
        [
            ".....cc...",
            "....cffc..",
            "...cffffc.",
            "..cffffefc",
            ".cfffeeefc",
            "cffeeeeeef",
            "cfeeeeeef.",
            ".eeeeee...",
        ],
    ]

    private static func drawFire(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let key: [Character: PixelBuffer.Ink] = [
            "c": .flameCore, "f": .flame, "e": .ember,
        ]
        // Slow enough to read as flame rather than strobe.
        let frame = flameFrames[Int(phase * 6) % flameFrames.count]
        // Sits behind his back, rising into the free band above him. The old
        // version anchored at the frame edge and clamped, so most of its flicker
        // produced an identical bar.
        b.stamp(frame, at: (x: 17 + dx, y: 1 + dy), key: key)
    }

    /// Sparks thrown off the blaze, drawn in FRONT of him.
    ///
    /// Four-pointed stars, from the reference art. They scatter and fade on
    /// their own cycles so the fire never looks like a static decal.
    private static func drawSparks(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let spots = [(14, 3), (28, 6), (24, 0), (12, 8)]
        for (index, spot) in spots.enumerated() {
            let life = sin(phase * 3 + Double(index) * 1.9)
            guard life > 0 else { continue }
            let x = spot.0 + dx, y = spot.1 + dy
            let ink: PixelBuffer.Ink = life > 0.7 ? .flameCore : .flame
            b.pixel(x, y, ink)
            // At full brightness it opens into a four-pointed star.
            if life > 0.45 {
                b.pixel(x - 1, y, ink)
                b.pixel(x + 1, y, ink)
                b.pixel(x, y - 1, ink)
                b.pixel(x, y + 1, ink)
            }
        }
    }

}
