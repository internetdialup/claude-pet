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
    public enum EyeStyle: Sendable { case round, determined, wide, squint }
    /// Whole-pixel vertical offset applied to the eyes in opposite directions —
    /// a head tilt, on a grid that cannot rotate.
    ///
    /// **Ignored while the lids are shut**, and that is not a special case, it
    /// is the channel's limit. A tilt is read from the two eyes' relative
    /// height, which needs eyes tall enough to overlap: at `eyeSize` 3 a
    /// one-pixel tilt puts blocks on rows 13 and 15 that still share a row, and
    /// the head reads as tipped. A shut lid is ONE pixel, so the same tilt
    /// leaves two thin bars two rows apart with nothing between them — which
    /// reads as a broken eye, not a tipped head. See `drawFace`.
    public var tilt: Int = 0

    /// The lids sit at the bottom of the socket rather than across its middle:
    /// asleep, as against mid-blink.
    ///
    /// The z's were removed at the operator's request and the head tilt was
    /// what replaced them — the one thing carrying "asleep" in a STILL, where
    /// the breath cannot help. The tilt turned out to be the wrong instrument
    /// for the job for the reason above, so this is the replacement's
    /// replacement, and it is symmetric: both lids drop together.
    public var lidsLowered = false
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
        case sparkles, terminal, check, bang, servers, mug, plan
        // Worn props: drawn on the body, and must travel with `bob` and `lean`.
        case hardHat, phone, fire, glasses
        // Appended (stableSeed is the allCases index — order is load-bearing):
        // the 8-bit Claude star, the thinking spell's second wind.
        case star
        // Appended for the same reason, never inserted: the arcade stick, the
        // shades off the stickers, and the board he kickflips.
        case joystick, shades, skateboard, skateboardVarial, skateboardRoll
        // Appended: the board mid-OLLIE, nose high. Its own case because pitch
        // is the one motion the flip boards refuse on purpose — see the
        // kickflip's comment calling tilt "an impossible". For an ollie the
        // tilt IS the trick.
        case skateboardOllie
        // Appended, the skateboarder round: the manual's held wheelie and
        // the shove-it's flat spin — each its own geometry, like every
        // board before them.
        case skateboardManual, skateboardShoveIt

        var isWorn: Bool {
            switch self {
            case .hardHat, .phone, .fire, .glasses, .shades, .skateboard, .skateboardVarial,
             .skateboardRoll, .skateboardOllie, .skateboardManual, .skateboardShoveIt: true
            default: false
            }
        }

        /// The props Claw'd picks between while a tool is running.
        static let working: [Prop] = [.terminal, .hardHat, .servers, .phone,
                                      .fire, .glasses, .joystick]
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

    /// Torso-turn shading, for the drip-feed sampler's ollie variants: which
    /// body edge the torso rotates away from (-1 = the left columns darken,
    /// +1 = the right, 0 = none), and how much of the turn is on him, 0…1.
    ///
    /// Envelope-owned like `doneBadge`: the sampler's variant map writes both
    /// fresh every frame from the trick's own air fraction, no live pose ever
    /// sets them, and `CrabPose.blend` deliberately does not lerp them — a
    /// blend could only ever see zeros, and averaging a shade that is pure in
    /// someone else's clock would invent a third turn nobody performed.
    public var torsoShade: Int = 0
    public var torsoShadeAmount: Double = 0

    /// The deal-with-it entrance: rows the shades still have to FALL
    /// (negative mid-drop, +1 during the overshoot beat, 0 at rest), and the
    /// four-point sparkle at the lens on a dinging landing. Envelope-owned
    /// like `torsoShade`: the view's knowledge latch writes them fresh every
    /// frame, no schedule in `pose()` ever sets them, and `blend`
    /// deliberately does not lerp them — a blend could only see zeros.
    public var shadesDrop: Int = 0
    public var shadesGlint: Bool = false

    /// The 1-in-50 jackpot deck. Set ONLY by the live schedule in `pose()` —
    /// never by `flourishPose` (the renderers' and sampler's door) and never
    /// by a preview — so a golden board cannot reach a committed byte by
    /// construction.
    public var goldenBoard: Bool = false

    /// 🧢 The skate headwear, on dice for about a skate beat in three — the
    /// operator's drip, in two cuts: a black beanie pulled low, or a green
    /// cap with a brim. The golden board's exact contract: live-schedule-only
    /// by placement, so committed media never wears either. Drawn only on the
    /// bare crab — headwear over a costume's crown would fight every helmet
    /// in the wardrobe.
    public enum Headwear: Sendable, Equatable {
        case none, blackBeanie
        /// The cap comes in colours, rolled per wearing — the operator's
        /// "randomize colors, and just go with a black beanie".
        case cap(PixelBuffer.Ink)
    }
    public var headwear: Headwear = .none

    /// 🌠 The stargaze session's rare streak: the head's cell, its sky row,
    /// and its travel direction (the trail extends opposite). nil = no
    /// sighting. Set only inside the live stargaze branch, whose hour gate
    /// already keeps every offline render dark.
    public var shootingStarX: Int?
    public var shootingStarY: Int = 0
    public var shootingStarDX: Int = 1

    /// 💍 Sonic's ring flight, 0…1, or nil for no rings. A travel parameter
    /// like `glint`, so the blend leaves it alone (`blend` starts from the
    /// incoming pose, so a non-lerped field takes its value by construction).
    /// Normally nil — the costume rolls its own dice on `propPhase` — and set
    /// only by the secret-menu preview, which must bypass those dice.
    public var ringFlight: Double?

    /// 💨 Landing dust: 0…1 through a stomp's puff, or nil. Written fresh
    /// each frame by the flourish that lands (pure in its own progress), so
    /// the blend leaves it alone like every travel parameter.
    public var dustBurst: Double?

    /// 💗 The idle heart's flight, 0…1, or nil — the sticker heart drifting
    /// up off his crown. A travel parameter; the blend leaves it alone.
    public var idleHeart: Double?

    /// 🗓 The season, resolved LIVE-ONLY by the view (`LocalDay` behind the
    /// frozen-sentinel lock) and defaulted nil everywhere else — offline
    /// renderers can never see one. Drives the weather; `blend` starts from
    /// the incoming pose, so none of these four lerp.
    public var holiday: Holiday?
    /// Halloween's floor pumpkins — idle-only, suppressed with the bug and
    /// the balloon whenever the telescope or the sun owns the spell.
    public var holidayGround: Bool = false
    /// A New Year's firework in flight, 0…1, or nil — and the cycle that
    /// launched it, for its colour and column.
    public var fireworkProgress: Double?
    public var fireworkCycle: Int = 0
    /// A single gait scuff cell behind a scuttling leg, or nil. Glint-class:
    /// one cell, locked to the leg cycle.
    public var scuffX: Int?

    /// A pixel bug scuttling across the floor rows, or nil. The column is the
    /// bug's centre; the animator owns its schedule.
    public var bugX: Int?
    /// How far a glint has travelled across the shell, 0…1, or nil for no
    /// glint. A travel parameter, so the blend leaves it alone — averaging
    /// two of them produces a third, unrelated one, which is the argument
    /// this file already makes for `legPhase`.
    public var glint: Double?
    /// A four-pointed sparkle at the winking eye, on the frame it opens.
    public var winkGlint: Bool = false
    /// How much of the afternoon's light is on him, 0…1. The floor patch, the
    /// warm on his shell and his shut eyes all ride this one envelope.
    public var sunPatch: Double = 0
    /// Seconds into the basking window, for the patch's drift across the
    /// floor. A travel parameter, so the blend leaves it alone.
    public var sunPatchPhase: Double = 0
    /// Seconds into a petting session, for the floating hearts. nil = no hearts.
    /// Mood-clock time while he is asleep, or nil. Drives the zZz's, which are
    /// pure in it — sleeping is continuous, so there is no event to latch and
    /// none is invented.
    public var sleepZElapsed: Double?
    /// Seconds between zZz's, already resolved from the wall clock by
    /// `CrabAnimator.sleepZInterval`. The rig is kept ignorant of what hour it
    /// is; it only ever asked "how far apart".
    public var sleepZInterval: Double = 0

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
    // Internal like the body block, and for the same reason: the costume
    // shoes stand on these legs, and the gait math must live once. A shoe
    // computing its own lift from a copied table is how feet detach.
    static let legX = [7, 11, 20, 24]

    /// Leg `index`'s gait swing in whole rows — positive lifts the foot,
    /// negative drops the knee. `drawLegs` shortens the legs by exactly this,
    /// and it is internal so a costume's shoe can ride the same number
    /// instead of waiting on the floor for the foot to come back.
    static func legSwing(_ index: Int, pose: CrabPose) -> Int {
        Int((sin(pose.legPhase + Double(index) * .pi / 2) * pose.legAmplitude).rounded())
    }

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

        // The ground shadow goes down before anything stands on it.
        drawShadow(&buffer, dx: dx, dy: dy, pose: pose)

        // Behind the body. The flame dissolves with its prop's visibility, so a
        // prop swap away from fire cannot vanish the burst in one frame.
        firePass(&buffer, pose: pose, dx: dx, dy: dy)
        costumeLayer(.behind)

        drawLegs(&buffer, dx: dx, dy: dy, pose: pose)
        drawDust(&buffer, dx: dx, dy: dy, pose: pose)
        drawArms(&buffer, dx: dx, dy: dy, pose: pose)

        // Squash widens and shortens the body, keeping its feet on the ground.
        buffer.rect(bodyX + dx - squash, bodyY + dy + squash,
                    bodyW + squash * 2, bodyH - squash, .body)

        // The hero pick, off the candidates sheet (B + E): the [ ] loses its
        // corners — a two-step carve at each shoulder, a nip at each jaw —
        // and the shell takes one flat step of shade along the belly and the
        // right flank, lit from the upper left the way the catchlights
        // already claim. This is a permanent look, not the sampler's
        // turn-shade event; the ink doc's event-only rule bends here at the
        // operator's explicit pick. Costumes draw over all of it and keep
        // their own opinions.
        let shellTop = bodyY + dy + squash
        let shellLeft = bodyX + dx - squash
        let shellRight = bodyX + bodyW - 1 + dx + squash
        for cell in [(shellLeft, shellTop), (shellLeft + 1, shellTop),
                     (shellLeft, shellTop + 1),
                     (shellRight, shellTop), (shellRight - 1, shellTop),
                     (shellRight, shellTop + 1),
                     (shellLeft, 20 + dy), (shellRight, 20 + dy)] {
            buffer.pixel(cell.0, cell.1, .clear)
        }
        for x in shellLeft...shellRight where buffer[x, 20 + dy] == .body {
            buffer.pixel(x, 20 + dy, .bodyShade)
        }
        for y in (shellTop + 1)...(19 + dy) where buffer[shellRight, y] == .body {
            buffer.pixel(shellRight, y, .bodyShade)
        }

        costumeLayer(.onBody)
        if pose.heat > 0.001 { heatPass(&buffer, pose: pose, dy: dy, squash: squash) }
        if let glint = pose.glint { glintPass(&buffer, u: glint, dy: dy, squash: squash) }
        if pose.torsoShade != 0, pose.torsoShadeAmount > 0.001 {
            shadePass(&buffer, pose: pose, dx: dx, dy: dy, squash: squash)
        }
        drawFace(&buffer, dx: dx, dy: dy, pose: pose)
        // After the face, so it reads as light coming off the eye rather than
        // as something behind it.
        if pose.winkGlint { drawWinkGlint(&buffer, dx: dx, dy: dy) }
        // Headwear rides the bare crab only — see its channel doc.
        if pose.headwear != .none, costume == .none, ghostCostume == .none {
            drawHeadwear(&buffer, kind: pose.headwear, dx: dx, dy: dy, squash: squash)
        }
        costumeLayer(.front)
        // 🗓 The season's weather, for EVERYONE in the window — the white
        // costume's snow rule generalised: clear cells only, continuous, no
        // dice. Winter skips anyone already wearing Arctic White, or the
        // snow would double.
        switch pose.holiday {
        case .halloween, .thanksgiving:
            HolidayAmbience.drawLeaves(&buffer, phase: pose.propPhase)
        case .winter where costume != .white && ghostCostume != .white:
            HolidayAmbience.drawSnow(&buffer, phase: pose.propPhase)
        default:
            break
        }
        if pose.holidayGround { HolidayAmbience.drawFloorPumpkins(&buffer) }
        if let firework = pose.fireworkProgress {
            HolidayAmbience.drawFireworks(&buffer, progress: firework,
                                          cycle: pose.fireworkCycle)
        }

        // Ghost first, so an incoming prop paints over an outgoing one where
        // they overlap.
        propPass(&buffer, pose: pose, prop: pose.ghostProp,
                 phase: pose.ghostPropPhase, visibility: pose.ghostPropVisibility,
                 dx: dx, dy: dy)
        propPass(&buffer, pose: pose, prop: pose.prop,
                 phase: pose.propPhase, visibility: pose.propVisibility,
                 dx: dx, dy: dy)
        // After the prop, so the sparkle sits on the landed shades rather
        // than under them; before the service glyph, which wins its own cells.
        if pose.shadesGlint {
            drawShadesGlint(&buffer, dx: dx, dy: dy + pose.shadesDrop)
        }

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
        if let idleHeart = pose.idleHeart { drawIdleHeart(&buffer, u: idleHeart, dx: dx) }
        if let sleepZ = pose.sleepZElapsed, pose.sleepZInterval > 0 {
            drawSleepZ(&buffer, elapsed: sleepZ, interval: pose.sleepZInterval)
        }
        if let snack = pose.snackElapsed { drawSnack(&buffer, elapsed: snack, dx: dx, dy: dy) }
        if pose.stargaze > 0.001 { drawStargaze(&buffer, pose: pose, dx: dx, dy: dy) }

        // The patch of sun goes in LAST and yet ends up behind everything,
        // because it preserves what is already painted. Ordering it here
        // rather than hoisting it above the body keeps it with its siblings
        // and states the intent in the call instead of in a comment about
        // where the line has to sit.
        if pose.sunPatch > 0.001 {
            drawSunPatch(&buffer, amount: pose.sunPatch, phase: pose.sunPatchPhase)
        }

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

    /// The afternoon's patch of light on the floor, drifting across it.
    ///
    /// This is the only thing in the app that uses
    /// `composite(preservingExisting:)`, which has existed and been documented
    /// as the "ground object" mode since the badge went in and has never once
    /// been called with `true`. It is what makes the effect work: the light
    /// goes in BEHIND him, so his legs cut it and he is standing *in* the
    /// patch rather than under a glow. A composition-layer halo cannot do
    /// that, which is why this lives on the sprite.
    ///
    /// Two properties come free from the house dissolve and are worth naming,
    /// because they are why this reads as light rather than as dirt. The
    /// stipple is keyed on the absolute cell, so when the patch drifts a
    /// column the dither pattern **stays put** — the shape moves and the
    /// texture does not shimmer. And because visibility rises with the
    /// envelope, the light *fills in* over two seconds instead of fading up
    /// as a block.
    ///
    /// A pool, rows 21-27, so his legs are standing IN it rather than beside
    /// it. Seed 764.
    ///
    /// The visibility is the raw envelope, deliberately reaching a **solid**
    /// pool at peak, and that is the whole difference between this reading as
    /// light and reading as dirt. The first draft held it at 0.45 across a
    /// ten-row wedge and looked like someone had spilled sand on the floor: a
    /// stipple is a *transition*, not a translucency, and a large area held
    /// at partial visibility forever is just grain. Letting the envelope carry
    /// visibility from 0 to 1 means the dither only ever appears during the
    /// two-second fades at each end — which is what it is for — and the ten
    /// seconds in between are a shape.
    private static func drawSunPatch(_ b: inout PixelBuffer, amount: Double, phase: Double) {
        // Three cells of travel over the fourteen seconds, one at a time, and
        // starting a cell left of centre so the pass is centred on him.
        let drift = Int((phase * 0.22).rounded()) - 1
        // Half-widths per row: a pool, not a rectangle and not a wedge.
        let halfWidths = [5, 7, 8, 8, 7, 5, 2]
        var light = PixelBuffer()
        for (row, half) in halfWidths.enumerated() {
            light.rect(16 + drift - half, 21 + row, half * 2, 1, .yellow)
        }
        b.composite(light, visibility: Ease.clamp01(amount),
                    seed: 764, preservingExisting: true)
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

    /// 💗 The idle heart, straight off the operator's sticker: a chunky red
    /// heart drifting up past his crown. It GROWS in — one cell, then the
    /// petting hearts' small glyph, then the sticker's full shape — and
    /// leaves by rising off-grid, so both ends are eased by geometry. One
    /// whole-pixel sway on the way up, the hearts' own quantum. Clear-cell
    /// masked: sky furniture never overdraws him or a prop.
    private static func drawIdleHeart(_ b: inout PixelBuffer, u: Double, dx: Int) {
        let top = 12 - Int((u * 20).rounded())
        let x = 7 + (u > 0.35 && u < 0.7 ? 1 : 0) + dx
        var heart = PixelBuffer()
        if u < 0.12 {
            heart.pixel(x + 3, top, .alert)
        } else if u < 0.28 {
            heart.stamp(["r.r", "rrr", ".r."], at: (x: x + 2, y: top), key: ["r": .alert])
        } else {
            heart.stamp([
                ".rr.rr.",
                "rprrrrr",
                "rrrrrrr",
                ".rrrrr.",
                "..rrr..",
                "...r...",
            ], at: (x: x, y: top), key: ["r": .alert, "p": .pink])
        }
        b.composite(heart, visibility: 1, seed: 703, preservingExisting: true)
    }

    /// Where a zZz may sit. Right of centre and clear of the crown, so the
    /// glyph leaves his head rather than out of the top of it — and clear of
    /// the service glyph's box at cols 1-8 for the same reason `heartColumns`
    /// is.
    private static let sleepZColumns = [18, 20, 22]

    /// zZz's drifting off a sleeping crab.
    ///
    /// Two shapes, alternating by ordinal: a three-wide capital and a
    /// two-wide lowercase. One glyph repeated is a stutter; the pair is what
    /// makes the read "zZz" rather than "zzz".
    ///
    /// `Ease.pulse` rather than a linear fade, for the reason the hearts
    /// learned it: a glyph must arrive and leave under its own envelope so
    /// nothing has to delete it mid-climb. The attack is longer than the
    /// hearts' — he is breathing out, not startled.
    ///
    /// Salt `59 &+ 11`: 59 already carries the petting hearts' column, and the
    /// registry says a shared multiplier takes a distinct addend. Same domain
    /// too — a rising glyph's ordinal, not a cycle — which is the case the
    /// registry's "over other domains" note covers.
    private static func drawSleepZ(_ b: inout PixelBuffer, elapsed: Double, interval: Double) {
        for (ordinal, born) in CrabAnimator.sleepZSpawns(t: elapsed, interval: interval) {
            let age = elapsed - born
            // Mostly hold. `composite(visibility:)` is a pixel DISSOLVE, and a
            // three-cell glyph part-dissolved is not a faded z — it is two
            // stray dots. A long hold keeps it legible and spends the fade at
            // the ends where a fragment reads as departure rather than as
            // noise.
            let visibility = Ease.pulse(age, attack: 0.30, hold: 1.15,
                                        decay: CrabAnimator.sleepZLife - 1.45)
            guard visibility > 0.001 else { continue }
            let row = CrabAnimator.sleepZRow(age: age)
            guard row >= 0 else { continue }
            let pick = Int(CrabAnimator.noise(ordinal &* 59 &+ 11) * Double(sleepZColumns.count))
            // The same one-cell lean the hearts use, so it does not rise in a
            // dead-straight line. One cell is the grid's own quantum.
            let drift = row <= 5 ? (ordinal % 2 == 0 ? 1 : -1) : 0
            let x = sleepZColumns[pick % sleepZColumns.count] + drift
            var glyph = PixelBuffer()
            if ordinal % 2 == 0 {
                // Four wide, because three is not enough for a Z. At 3x3 the
                // diagonal collapses onto the centre cell and the glyph reads
                // as 工 — rendered and looked at, which is the only way that
                // kind of thing gets caught.
                glyph.stamp([
                    "zzzz",
                    "..z.",
                    ".z..",
                    "zzzz",
                ], at: (x: x, y: row), key: ["z": .paper])
            } else {
                glyph.stamp([
                    "zzz",
                    ".z.",
                    "zzz",
                ], at: (x: x, y: row), key: ["z": .paper])
            }
            b.composite(glyph, visibility: visibility, seed: 760 + ordinal % 3)
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

        // 🌠 The rare streak — a DICED sighting he tracks with his eyes, not
        // the old hardcoded every-session one (a shooting star that always
        // comes is furniture). The schedule owns when and where; this only
        // paints the head bright and a two-cell tail trailing opposite the
        // travel, clamped to the sky rows.
        if let head = pose.shootingStarX {
            scene.pixel(head, max(0, pose.shootingStarY), .paper)
            for trail in 1...2 {
                let x = head - trail * pose.shootingStarDX
                scene.pixel(x, max(0, pose.shootingStarY - trail / 2), .mouth)
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
    /// A streak of light travelling diagonally across the shell, once in a
    /// while, for a second and a half. It makes him feel like an object with a
    /// hard surface rather than a flat sticker.
    ///
    /// Repaints only cells that are still `.body`, which is `heatPass`'s trick
    /// directly above — so the face, the props, the costume accessories and
    /// the matrix rain are all untouched **by construction** rather than by
    /// keeping clear of coordinates.
    ///
    /// The no-snap rule is satisfied by GEOMETRY, not by a fade. The streak
    /// enters from off-shell and leaves off-shell, so it paints nothing at
    /// u=0 and nothing at u=1 and there is no edge to ease. Thirty-four cells
    /// over 1.6s at idle's 20fps is almost exactly one cell per frame — the
    /// grid's own quantum, and the one exemption the doctrine grants. That is
    /// why the duration is 1.6 and not 0.6.
    ///
    /// This is the effect in the app closest to breaking the flat-palette
    /// rule, and it is worth being honest about: a travelling highlight is a
    /// specular, and specular is a cousin of shading. The defence is that it
    /// is an EVENT rather than a state — two flat inks, no ramp, diagonal so
    /// it cannot be read as a shading band, gone in 1.6s, and `BubbleShimmer`
    /// already ships this exact shape on the bubble. If it ever reads as a
    /// gradient sneaking in, delete it; do not soften it into one.
    private static func glintPass(_ b: inout PixelBuffer, u: Double, dy: Int, squash: Int) {
        let top = bodyY + dy + squash
        let height = bodyH - squash
        guard height > 0 else { return }
        let head = Int((-4 + u * 34).rounded())
        for y in max(0, top)..<min(PixelBuffer.side, top + height) {
            // Two rows per column: a lean, not a vertical wipe.
            let x = head + (y - top) / 2
            if b[x, y] == .body { b[x, y] = .flameCore }
            if b[x - 1, y] == .body { b[x - 1, y] = .yellow }
        }
    }

    /// The ting: a four-pointed twinkle in the air above his winking eye, on
    /// the frames the wink opens. A twinkle snaps in nature, which is the same
    /// exemption the stargaze stars and the thinking sparkles already take.
    ///
    /// In the AIRSPACE rather than on the shell, and that is the second try.
    /// On the shell it has to be masked to `.body` or it punches a hole in a
    /// costume — but the eye moves with `gazeY`, so at the moment of the wink
    /// one arm of the sparkle lands on `.eye`, gets masked out, and what
    /// renders is a lopsided blob rather than a twinkle. Off the shell it is
    /// symmetric, it reads as light rather than as a dent, and it needs no
    /// mask at all.
    ///
    /// It paints only cells that are still clear, so it can never damage a
    /// prop that happens to be passing — the same contract as the patch of
    /// sun, stated inline because it is only five cells.
    private static func drawWinkGlint(_ b: inout PixelBuffer, dx: Int, dy: Int) {
        let x = eyeRightX + eyeSize + 2 + dx     // clear of the eye, over the shoulder
        let y = bodyY - 2 + dy                   // in the air above the shell
        b.pixel(x, y, .flameCore)
        for arm in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        where b[arm.0, arm.1] == .clear {
            b[arm.0, arm.1] = .yellow
        }
    }

    /// The landing ding: the wink glint's four-point sparkle, parked at the
    /// shades' right temple for the beat after they touch down. Clear cells
    /// only, like its sibling — light off the lens, never paint over it.
    private static func drawShadesGlint(_ b: inout PixelBuffer, dx: Int, dy: Int) {
        let x = 26 + dx                          // one cell out from the line's right end
        let y = 11 + dy                          // one row above the lens line
        if b[x, y] == .clear { b[x, y] = .flameCore }
        for arm in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
        where b[arm.0, arm.1] == .clear {
            b[arm.0, arm.1] = .yellow
        }
    }

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

    /// The torso-turn shade: up to two columns hugging one body edge, one flat
    /// step below the shell, quantised off the amount the way `heatPass`
    /// quantises its half-width. The `== .body` mask is the whole safety
    /// story — costume cells, eyes and props are other inks, so the shade can
    /// only ever land on bare shell, and the edge columns are geometrically
    /// clear of the eye windows anyway. Legs live below the body rect, so the
    /// band is torso-only by construction: the whole shell yawing is the
    /// sticker's picture.
    private static func shadePass(_ b: inout PixelBuffer, pose: CrabPose,
                                  dx: Int, dy: Int, squash: Int) {
        let top = bodyY + dy + squash
        let height = bodyH - squash
        let cols = Int((Ease.clamp01(pose.torsoShadeAmount) * 2).rounded())
        guard height > 0, cols > 0, pose.torsoShade != 0 else { return }
        let left = bodyX + dx - squash
        let right = bodyX + bodyW - 1 + dx + squash
        let xs = pose.torsoShade > 0 ? (right - cols + 1)...right : left...(left + cols - 1)
        for y in max(0, top)..<min(PixelBuffer.side, top + height) {
            for x in xs where b[x, y] == .body { b[x, y] = .bodyShade }
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

    /// 🧢 The skater's headwear, both cuts pulled LOW over the crown — two
    /// rows sit ON the shell, so even the ollie apex (crown at the grid's
    /// top row) keeps a real hat instead of a cropped line, which was the
    /// operator's note on the first beanie.
    private static func drawHeadwear(_ b: inout PixelBuffer, kind: CrabPose.Headwear,
                                     dx: Int, dy: Int, squash: Int) {
        let crown = bodyY + dy + squash
        switch kind {
        case .none:
            break
        case .blackBeanie:
            // TALLER, and ON the head — the operator's second note: a
            // proper standing beanie, band on the brow, folded cuff, dome
            // rising four rows clear of the shell. The ollie apex still
            // crops it against the grid top (the lofty pin's ceiling), and
            // every other airborne frame shows the whole hat.
            b.rect(11 + dx, crown, 10, 1, .slate)
            b.rect(11 + dx, crown - 1, 10, 1, .slate)
            b.rect(12 + dx, crown - 2, 8, 1, .slate)
            b.rect(12 + dx, crown - 3, 8, 1, .slate)
            b.rect(13 + dx, crown - 4, 6, 1, .slate)
        case .cap(let ink):
            // The cap, ANGLED — the operator's note: tipped back off the
            // brow, the dome climbing toward the front, and the brim
            // jutting out a row clear of the head so there is AIR under it.
            // The empty cells at (19…22, crown−1) are the whole look.
            b.rect(11 + dx, crown, 7, 1, ink)
            b.rect(12 + dx, crown - 1, 8, 1, ink)
            b.rect(13 + dx, crown - 2, 6, 1, ink)
            b.rect(19 + dx, crown - 2, 4, 1, ink)
        }
    }

    /// ✨ A one-cell flash on a wheel, riding the prop's own clock — weight,
    /// per the operator. ~7% of the phase, glint-class by size and nature.
    private static func wheelShimmer(_ phase: Double) -> Bool {
        (phase * 2.6).truncatingRemainder(dividingBy: 1) < 0.11
    }

    // MARK: - Ground

    /// The soft pool under him: full width with his feet on the floor,
    /// shrinking two cells per row of air and gone past three — high enough
    /// that he reads as flying, not hovering. Skipped while a board is worn:
    /// the deck grounds him already, and a shadow under wheels reads as
    /// grease. Whole-pixel steps riding the already-eased `bob`, so the
    /// shadow inherits the jump's own easing.
    private static func drawShadow(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        switch pose.prop {
        case .skateboard, .skateboardVarial, .skateboardRoll, .skateboardOllie: return
        default: break
        }
        let rise = max(0, -dy)
        let width = 20 - rise * 2
        guard width >= 8 else { return }
        // A SOLID line, at the operator's call: the checkerboard dots read
        // as grit to a viewer, not softness. The ink's own translucency
        // keeps it gentle live; in a GIF it collapses to a clean dark line,
        // which is the look.
        b.rect(16 + dx - width / 2, 25, width, 1, .shadow)
    }

    /// 💨 Landing dust: two puffs racing outward from the feet, chunky at
    /// impact, thinning as they go, gone under their own travel. The burst's
    /// first frame IS the impact — a stomp is snap-by-nature, the landing
    /// squash's own exemption — and the exit is two lone cells, glint-class.
    private static func drawDust(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        if let u = pose.dustBurst, u < 1 {
            // A row above the floor line, or the puffs vanish into the
            // shadow's own dither.
            let spread = 2 + Int((u * 4).rounded())
            b.pixel(16 + dx - 8 - spread, 23 + dy, .steel)
            b.pixel(16 + dx + 8 + spread, 23 + dy, .steel)
            if u < 0.5 {
                b.pixel(16 + dx - 7 - spread, 22 + dy, .steel)
                b.pixel(16 + dx + 7 + spread, 22 + dy, .steel)
            }
        }
        if let scuff = pose.scuffX {
            b.pixel(scuff + dx, 23 + dy, .shadow)
        }
    }

    // MARK: - Legs

    private static func drawLegs(_ b: inout PixelBuffer, dx: Int, dy: Int, pose: CrabPose) {
        for (index, x) in legX.enumerated() {
            // Alternating pairs, so the scuttle reads as a gait rather than a jitter.
            let lift = legSwing(index, pose: pose)
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

            // A wink is checked independently of `blink`, and deliberately not
            // gated on `asleepOverride` — the hover greeting sets that flag on
            // every frame, so routing a wink through `blink` renders two open
            // eyes and nothing else.
            let shut = (pose.blink > 0.5 && !pose.asleepOverride) || pose.winkEye == side

            // The tilt is dropped for a shut lid. A one-pixel bar cannot
            // express a tipped head — offset, it just reads as one eye sitting
            // wrong. See the note on `CrabPose.tilt`. This is the general rule
            // rather than a fix to the sleeping pose alone, so a tilt arriving
            // over a blink from anywhere else cannot reintroduce it.
            let top = eyeTop + (shut ? 0 : (side == .left ? -pose.tilt : pose.tilt))

            guard !shut else {
                // Lowered lids sit at the socket's floor: asleep reads
                // differently from a blink, and reads it symmetrically.
                b.rect(x, top + (pose.lidsLowered ? 2 : 1), eyeSize, 1, .eye)
                continue
            }

            switch pose.eyes {
            case .round:
                b.rect(x, top, eyeSize, eyeSize, .eye)
                // The catchlight: one cell of light in the upper-left of
                // each open eye — the sprite trick that reads as life at
                // any size. Round and wide only: the squint has no room and
                // the determined carve owns its corners.
                b.pixel(x, top, .paper)
            case .wide:
                // One row taller, for the expectant "well?" of the nudge.
                b.rect(x, top - 1, eyeSize, eyeSize + 1, .eye)
                b.pixel(x, top - 1, .paper)
            case .squint:
                // >_< . Two chevrons pointing at each other — the scrunched
                // face off the stickers, which read at two centimetres with no
                // motion and no context to help them. Mirrored per side, so
                // the left eye opens outward and the right one does too.
                let tip = side == .left ? x : x + eyeSize - 1
                let mid = side == .left ? x + 1 : x + eyeSize - 2
                b.pixel(tip, top, .eye)
                b.pixel(mid, top + 1, .eye)
                b.pixel(tip, top + 2, .eye)

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

        case .mug:
            // A mug, because a five-year-old can name one.
            //
            // This slot used to hold a balloon: a seven-by-five green blob on a
            // string that read as a lollipop, a sweet or a bush depending on who
            // was looking. It was also the only prop in the app that signalled
            // NOTHING — every other one tells you something about the session,
            // and that one just floated. A mug says the thing the slot is
            // actually for: he has been idle a while, he is on a break.
            //
            // The motion is unchanged and it still fits — `idleBalloon` HOLDS
            // the prop for eight seconds rather than drifting it past, which is
            // what you do with a mug and not what you do with a balloon.
            //
            // Drawn in `.slate` and `.paper`, both of which a costume cannot
            // repaint, so it stays a white mug on the ninja and on the matrix.
            let key: [Character: PixelBuffer.Ink] = [
                "o": .slate, "w": .paper, "s": .screenLight,
            ]
            // Steam rises and resets — two wisps a half-cycle apart, so
            // something is always moving without either one racing.
            let lift = Int(phase * 3) % 3
            b.stamp([
                "..s..s..",
                ".s..s...",
            ], at: (x: 1, y: 6 - lift), key: key)
            b.stamp([
                "oooooo..",
                "owwwwoo.",
                "owwwwo.o",
                "owwwwoo.",
                "oooooo..",
            ], at: (x: 1, y: 9), key: key)

        case .hardHat:
            drawHardHat(&b, dx: dx, dy: dy, phase: phase)

        case .joystick:
            // An arcade stick, HELD — up at his claw, not sitting on the floor.
            //
            // It used to stand on the ground beside him, which was a fix for a
            // worse first draft that floated it at his own height where it
            // looked stuck to his flank. The floor solved the sticking and
            // created a different problem: a stick on the ground is scenery. He
            // is meant to be USING it, so it comes up to where his claw is and
            // overlaps him deliberately — the overlap is what says "held".
            //
            // The lean is the point. A stick standing straight is a lamp; one
            // that tips reads as being pushed, which is what makes it say he is
            // driving something rather than that an object exists. Whole-pixel
            // steps, which the grid's own quantum exempts from the no-snap rule.
            let lean = Int((sin(phase * 2.2) * 1.4).rounded())
            let key: [Character: PixelBuffer.Ink] = ["r": .alert, "o": .slate]
            // Outboard of his right CLAW, which is the nub at columns 26-27 on
            // rows 14-16. His body is a solid block from column 6 to 25, so
            // anything placed over that is on his face, not in his grip — a
            // first attempt at "held" put the base across his cheek. The base
            // overlaps the claw and nothing else, and that single column of
            // contact is what reads as holding.
            b.stamp([
                ".rrr.",
                ".rrr.",
            ], at: (x: 27 + lean, y: 10), key: key)
            b.pixel(29 + lean, 12, .slate)
            b.pixel(29, 13, .slate)
            b.pixel(29, 14, .slate)
            b.stamp([
                ".ooo.",
                "ooooo",
                "ororo",
                "ooooo",
            ], at: (x: 27, y: 15), key: key)

        case .star:
            // The Claude star, holding the top-right airspace (cols 20-28) —
            // clear of the service glyph box on the left and the body below.
            b.stamp(StarMark.art.rows, at: (x: 20, y: 0), key: StarMark.art.key)

        case .shades:
            // The DEAL-WITH-IT shades, matched cell-for-cell to the sticker
            // on the operator's desk — third cut, against the photograph.
            //
            // What the photo actually shows, and the first two cuts missed:
            // the pair is TWO hanging lenses on one thin line, not a visor.
            // A single 1-cell top line runs temple to temple (it is the
            // arms AND the bridge at once), each lens hangs off it as a
            // wedge tapering inward-and-down, and the shell shows through
            // UNDER the line between the lenses — that gap is what makes it
            // read as glasses rather than a mask. The print is PURE black
            // (`.memeBlack`, costume-immune), and each lens carries the
            // sticker's four-cell checker glint at its left side — both
            // lenses, same side, straight off the print.
            //
            // Deliberately NOT the `glasses` prop with a new coat. Those are a
            // wire outline and they say READING — you can see his eyes through
            // them, which is the whole point of drawing them hollow. These are
            // solid, and solid says something else entirely. Two props, two
            // meanings, and the resolution is the same either way.
            //
            // Wedges taper toward the BRIDGE and stay over the eye windows
            // (left 10-12, right 19-21) all three rows — the second cut
            // anchored its rake at the temples and his eye corners peeked
            // out underneath, reading as the shades sliding off.
            // `sy` carries the MLG entrance: `shadesDrop` is rows still to
            // fall, so mid-drop the whole pair rides above the face and
            // `PixelBuffer`'s subscript clips the off-sprite rows for free.
            let sy = dy + pose.shadesDrop
            b.rect(6 + dx, 12 + sy, 20, 1, .memeBlack)      // the line: arms + tops + bridge
            b.rect(8 + dx, 13 + sy, 6, 1, .memeBlack)       // left lens
            b.rect(9 + dx, 14 + sy, 5, 1, .memeBlack)
            b.rect(10 + dx, 15 + sy, 4, 1, .memeBlack)
            b.rect(18 + dx, 13 + sy, 6, 1, .memeBlack)      // right lens
            b.rect(18 + dx, 14 + sy, 5, 1, .memeBlack)
            b.rect(18 + dx, 15 + sy, 4, 1, .memeBlack)
            b.pixel(9 + dx, 13 + sy, .paper)                // checker glint, left lens
            b.pixel(11 + dx, 13 + sy, .paper)
            b.pixel(10 + dx, 14 + sy, .paper)
            b.pixel(12 + dx, 14 + sy, .paper)
            b.pixel(19 + dx, 13 + sy, .paper)               // checker glint, right lens
            b.pixel(21 + dx, 13 + sy, .paper)
            b.pixel(20 + dx, 14 + sy, .paper)
            b.pixel(22 + dx, 14 + sy, .paper)

        case .skateboard:
            // A board doing a KICKFLIP, and the shape of it is the opposite of
            // what it looks like it should be.
            //
            // The deck's long axis runs left-right across this face-on view,
            // and a kickflip rotates about exactly that axis. So the axis of
            // rotation is the one direction that CANNOT change on screen: the
            // deck is seventeen points wide in every single frame, it is never
            // diagonal, and it never shortens. Two earlier attempts got this
            // backwards — one narrowed the width (that is yaw, a shove-it) and
            // one tilted it (that is pitch, an impossible).
            //
            // What actually changes is THICKNESS. Flat on you see a one-point
            // line; a quarter turn later you are looking at the whole underside
            // and it is a seven-point slab. It pumps 1-7-1-7-1 across the turn.
            //
            // The wheels orbit rather than swap: three points below at rest,
            // level with the deck at the quarter turns, three above when the
            // board is inverted. They vanish behind the slab on the far half of
            // the turn, and that occlusion is not a nicety — it is the only
            // thing distinguishing a kickflip from a heelflip at this size.
            let turn = pose.propPhase.truncatingRemainder(dividingBy: 1)
            let theta = turn * 2 * .pi
            let cx = 16 + dx, deckY = 25 + dy
            let thick = max(1, Int((7 * abs(sin(theta))).rounded()))
            // The golden board inverts the two board inks: deck gold, wheels
            // slate. `.yellow` because it is the palette's only gold — the
            // wheels' own ink and the star's — and the inversion (rather than
            // gold-on-gold) keeps the deck/wheel boundary the board tests
            // measure. Same swap in all four board cases.
            let deckInk: PixelBuffer.Ink = pose.goldenBoard ? .yellow : .deck
            let wheelInk: PixelBuffer.Ink = pose.goldenBoard ? .slate : .yellow
            b.rect(cx - 8, deckY - thick / 2, 17, thick, deckInk)
            // Grip tape, the operator's ask: when the flip brings the TOP
            // face round (the far half of the turn — the wheels hide behind
            // the slab there) and the slab is fat enough to read as a face,
            // it carries a sparse grit of texture cells. Steel on the slate
            // deck — grit catches light against near-black — and slate grit
            // on the golden deck, where dark specks read as the tape itself.
            // Deterministic in the turn, whole-pixel, gone with the face.
            if sin(theta) < 0, thick >= 5 {
                // SLANTED and barely-there, per the operator: two-cell `/`
                // slashes in `.screenDark` — one step off the deck's black,
                // texture you feel more than see. Slate slashes on gold.
                let grit: PixelBuffer.Ink = pose.goldenBoard ? .slate : .screenDark
                for gx in stride(from: cx - 6, through: cx + 6, by: 4) {
                    b.pixel(gx, deckY + 1, grit)
                    b.pixel(gx + 1, deckY, grit)
                }
            }

            let orbit = Int((3 * cos(theta)).rounded())     // + is below: y grows down
            if sin(theta) >= 0 || abs(orbit) > thick / 2 {
                for hub in [cx - 5, cx + 4] {
                    b.rect(hub, deckY + orbit - 1, 3, 1, wheelInk)
                    b.pixel(hub, deckY + orbit, wheelInk)
                    // The bearing is `.screenDark`, not slate. Slate is the
                    // DECK's ink and nothing else's, which is what lets the
                    // suite measure the deck by looking for it — a bearing in
                    // the same ink put the wheel inside the deck's bounding box
                    // and made every frame look diagonal to the test.
                    b.pixel(hub + 1, deckY + orbit, .screenDark)   // the bearing
                    b.pixel(hub + 2, deckY + orbit, wheelInk)
                    b.rect(hub, deckY + orbit + 1, 3, 1, wheelInk)
                }
                // ✨ Weight: a one-cell flash off a wheel now and then.
                if wheelShimmer(pose.propPhase) {
                    b.pixel(cx - 5, deckY + orbit - 1, .flameCore)
                }
            }

        case .skateboardVarial:
            // A VARIAL KICKFLIP: the board turns over AND swings round, both at
            // once. This is the one the operator liked from the very first
            // draft, restored — with the two things the review found wrong with
            // it fixed, because both were bugs rather than style.
            //
            // FIRST: it used to narrow to NOTHING. A board seen straight down
            // its own length is not invisible, it is as wide as the deck — five
            // points here. Narrowing to zero is a door closing, not a board.
            //
            // SECOND: the wheels used to swap sides and stay there, which meant
            // he landed on the underside. That is not a trick, it is a bail
            // (landing "primo"). They now orbit through a whole turn and come
            // back underneath, which is what landing it means.
            //
            // The yaw does a half turn while the roll does a whole one, which
            // is exactly a varial kickflip's budget — and it reads distinctly
            // from the plain kickflip next door, whose deck never narrows at
            // all.
            let spin = pose.propPhase.truncatingRemainder(dividingBy: 1)
            let yaw = spin * .pi                              // 180 across the trick
            let roll = spin * 2 * .pi                         // a whole turn
            let cx = 16 + dx, deckY = 25 + dy
            // Eight points of half-length flat on, two and a half when you are
            // looking straight down the nose-tail axis.
            let half = max(2, Int((8 * abs(cos(yaw)) + 2.5 * abs(sin(yaw))).rounded()))
            let thick = max(1, Int((5 * abs(sin(roll))).rounded()))
            let deckInk: PixelBuffer.Ink = pose.goldenBoard ? .yellow : .deck
            let wheelInk: PixelBuffer.Ink = pose.goldenBoard ? .slate : .yellow
            b.rect(cx - half, deckY - thick / 2, half * 2 + 1, thick, deckInk)
            // Grip tape on the varial's top face too — same rule as the
            // kickflip's, spanning whatever width the yaw has left the deck.
            if sin(roll) < 0, thick >= 4 {
                let grit: PixelBuffer.Ink = pose.goldenBoard ? .slate : .screenDark
                for gx in stride(from: cx - half + 1, through: cx + half - 2, by: 4) {
                    b.pixel(gx, deckY + 1, grit)
                    b.pixel(gx + 1, deckY, grit)
                }
            }

            let orbit = Int((3 * cos(roll)).rounded())
            if sin(roll) >= 0 || abs(orbit) > thick / 2 {
                let reach = max(1, half - 3)
                for hub in [cx - reach - 1, cx + reach - 1] {
                    b.rect(hub, deckY + orbit - 1, 3, 1, wheelInk)
                    b.pixel(hub, deckY + orbit, wheelInk)
                    b.pixel(hub + 1, deckY + orbit, .screenDark)
                    b.pixel(hub + 2, deckY + orbit, wheelInk)
                    b.rect(hub, deckY + orbit + 1, 3, 1, wheelInk)
                }
                if wheelShimmer(pose.propPhase) {
                    b.pixel(cx + reach - 1, deckY + orbit - 1, .flameCore)
                }
            }

        case .skateboardOllie:
            // An OLLIE, off the sticker: nose high, board glued to his feet,
            // nothing spinning. The one board where PITCH is the picture —
            // the kickflip rolls, the varial yaws, this one tilts and floats.
            //
            // `propPhase` is the air 0…1, and the tilt is its story: the pop
            // kicks the nose up hard, the float carries it proudly high (the
            // sticker's whole attitude), and only the last beat levels the
            // deck for the wheels to land flat. Nothing snaps — every segment
            // of the profile eases.
            //
            // Drawn as three deck slabs stepping up toward the nose — a pixel
            // diagonal, since a 17-point line can hold at most a few honest
            // steps. The wheels hang under their own third of the deck and
            // ride its height, because a board that tilts while its wheels
            // stay level is two props, not one.
            let air = pose.propPhase.truncatingRemainder(dividingBy: 1)
            let tilt: Double =
                air < 0.35 ? Ease.smoothstep(air / 0.35)                 // pop: 0 → 1
                : air < 0.75 ? 1 - 0.55 * Ease.smoothstep((air - 0.35) / 0.4)  // float: 1 → 0.45
                : 0.45 * (1 - Ease.smoothstep((air - 0.75) / 0.25))      // level out: → 0
            let cx = 16 + dx, deckY = 25 + dy
            let rise = Int((5 * tilt).rounded())          // nose lift, in cells
            // The tail SLAPS down on the pop, then TUCKS up through the float
            // to meet the back foot — the operator's note, and the physics:
            // after the pop the back foot carries the tail, so a tail still
            // drooping two rows under his feet mid-float read as the board
            // hanging off him rather than glued to him. Eased at every
            // segment; ends level, same as before.
            let tuck: Double =
                air < 0.35 ? 2 * Ease.smoothstep(air / 0.35)             // slap: 0 → +2
                : air < 0.6 ? 2 - 3 * Ease.smoothstep((air - 0.35) / 0.25) // tuck: +2 → −1
                : air < 0.75 ? -1
                : -1 * (1 - Ease.smoothstep((air - 0.75) / 0.25))        // level out: → 0
            let dip = Int(tuck.rounded())                 // tail offset, signed
            // Tail, middle, nose — each a third of the deck, stepping.
            let yTail = deckY + dip
            let yMid = deckY + dip - (rise + dip) / 2
            let yNose = deckY - rise
            let deckInk: PixelBuffer.Ink = pose.goldenBoard ? .yellow : .deck
            let wheelInk: PixelBuffer.Ink = pose.goldenBoard ? .slate : .yellow
            b.rect(cx - 8, yTail, 6, 1, deckInk)
            b.rect(cx - 2, yMid, 6, 1, deckInk)
            b.rect(cx + 4, yNose, 5, 1, deckInk)
            // A joining pixel where the steps gap, so the deck reads as one
            // plank rather than three floating dashes.
            if yTail - yMid > 1 { b.pixel(cx - 2, yMid + 1, deckInk) }
            if yMid - yNose > 1 { b.pixel(cx + 4, yNose + 1, deckInk) }

            for (hub, y) in [(cx - 5, yTail), (cx + 4, yNose)] {
                b.rect(hub, y + 1, 3, 1, wheelInk)
                b.pixel(hub, y + 2, wheelInk)
                b.pixel(hub + 1, y + 2, .screenDark)      // the bearing
                b.pixel(hub + 2, y + 2, wheelInk)
                b.rect(hub, y + 3, 3, 1, wheelInk)
            }
            if wheelShimmer(pose.propPhase) {
                b.pixel(cx + 4, yNose + 1, .flameCore)
            }

        case .skateboardManual:
            // The wheelie, held: tail on the ground, nose stepping up through
            // an eased pitch, the back wheel planted and the front one riding
            // the nose. The ground streaks underneath — the cruise's trick,
            // borrowed: on a fixed camera the world moves, not the rider.
            let p = min(1, max(0, pose.propPhase))
            let pitch = Ease.smoothstep(min(p, 1 - p) * 5)
            let rise = Int((3 * pitch).rounded())
            let cx = 16 + dx, deckY = 25 + dy
            let deckInk: PixelBuffer.Ink = pose.goldenBoard ? .yellow : .deck
            let wheelInk: PixelBuffer.Ink = pose.goldenBoard ? .slate : .yellow
            let yTail = deckY
            let yMid = deckY - rise / 2
            let yNose = deckY - rise
            b.rect(cx - 8, yTail, 6, 1, deckInk)
            b.rect(cx - 2, yMid, 6, 1, deckInk)
            b.rect(cx + 4, yNose, 5, 1, deckInk)
            if yTail - yMid > 1 { b.pixel(cx - 2, yMid + 1, deckInk) }
            if yMid - yNose > 1 { b.pixel(cx + 4, yNose + 1, deckInk) }
            for (hub, y) in [(cx - 5, yTail), (cx + 4, yNose)] {
                b.rect(hub, y + 1, 3, 1, wheelInk)
                b.pixel(hub, y + 2, wheelInk)
                b.pixel(hub + 1, y + 2, .screenDark)
                b.pixel(hub + 2, y + 2, wheelInk)
                b.rect(hub, y + 3, 3, 1, wheelInk)
            }
            if wheelShimmer(pose.propPhase * 2.6) {
                b.pixel(cx - 5, yTail + 1, .flameCore)
            }
            // Ground rush: three dashes streaming left under the wheels,
            // stepped whole-pixel off the ride's own clock.
            let rush = Int((p * 34).rounded())
            for lane in 0..<3 {
                let x = ((28 - rush + lane * 11) % 32 + 32) % 32
                b.rect(x, 29, 3, 1, .shadow)
            }

        case .skateboardShoveIt:
            // The flat spin: yaw only. The deck narrows toward edge-on and
            // widens back out — the varial's width math with the roll struck
            // out — while the wheels ride the shrinking ends and duck behind
            // the deck at the pass-through.
            let u = pose.propPhase.truncatingRemainder(dividingBy: 1)
            let yaw = u * .pi
            let cx = 16 + dx, deckY = 25 + dy
            let half = max(2, Int((8 * abs(cos(yaw)) + 2.5 * abs(sin(yaw))).rounded()))
            let deckInk: PixelBuffer.Ink = pose.goldenBoard ? .yellow : .deck
            let wheelInk: PixelBuffer.Ink = pose.goldenBoard ? .slate : .yellow
            b.rect(cx - half, deckY, half * 2 + 1, 1, deckInk)
            if half >= 5 {
                for hub in [cx - half + 1, cx + half - 3] {
                    b.rect(hub, deckY + 1, 3, 1, wheelInk)
                    b.pixel(hub + 1, deckY + 2, .screenDark)
                }
            }

        case .skateboardRoll:
            // NO TRICK. He rides, fast, and stays exactly where he is while the
            // ground rushes past underneath him.
            //
            // The board used to accelerate out of frame and leave him behind.
            // That was me reading "the board goes away" too literally: it made
            // the BOARD the thing that moved, and a crab standing still while
            // his board escapes reads as him losing it, not as speed. The
            // camera is on him. He holds, the world streaks.
            //
            // The speed is carried by the ground lines, not by the wheels, and
            // that was measured rather than assumed: a wheel is three points
            // across, so the bearing mark walking round its hub covers about
            // nine points in total. Against anything else moving it is
            // invisible. It stays as a grace note for anyone who looks closely.
            let u = pose.propPhase.truncatingRemainder(dividingBy: 1)
            let deckY = 25 + dy
            let cx = 16 + dx
            let deckInk: PixelBuffer.Ink = pose.goldenBoard ? .yellow : .deck
            let wheelInk: PixelBuffer.Ink = pose.goldenBoard ? .slate : .yellow
            b.rect(cx - 8, deckY, 17, 1, deckInk)

            let tick = Int(u * 34) % 4
            let mark = [(0, -1), (1, 0), (0, 1), (-1, 0)][tick]
            for hub in [cx - 5, cx + 4] {
                b.rect(hub, deckY + 1, 3, 1, wheelInk)
                b.pixel(hub, deckY + 2, wheelInk)
                b.pixel(hub + 2, deckY + 2, wheelInk)
                b.rect(hub, deckY + 3, 3, 1, wheelInk)
                b.pixel(hub + 1 + mark.0, deckY + 2 + mark.1, .screenDark)
            }

            // Ground streaking past, in the floor band below him — the only
            // part of the frame nothing else occupies. Four lanes at different
            // phases so they never line up into a grid, easing in over the
            // first beat so the speed arrives rather than switching on.
            let arrive = Ease.smoothstep(u / 0.18)
            if arrive > 0.05 {
                for lane in 0..<4 {
                    let y = 28 + lane % 3
                    let travel = (u * 62 + Double(lane) * 7.5)
                        .truncatingRemainder(dividingBy: 26)
                    let x = 26 - Int(travel)
                    let long = 3 + Int(arrive * 2)
                    b.rect(x, y, long, 1, .steel)
                }
            }

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

        // ONE tool, and it is a hammer.
        //
        // There used to be two: a wrench on his left and a screwdriver on his
        // right, each two points wide. At that width neither had a jaw or a
        // blade to read, so they were a pair of grey rods standing either side
        // of him — the operator's word was "lightsaber", which is exactly what
        // a glowing-length-of-nothing looks like.
        //
        // A hammer survives the resolution where those did not, because its
        // whole silhouette is two solid masses: a heavy head and a thin handle.
        // The claw — the notch in the head's top-left — is the one detail that
        // separates "hammer" from "mallet", and it costs a single pixel.
        //
        // Held on one side only. Two objects read as scenery; one reads as
        // being carried, and the bob sells it.
        let jiggle = sin(phase * 2) > 0 ? 0 : 1
        let key: [Character: PixelBuffer.Ink] = ["h": .slate, "s": .ember]
        b.stamp([
            "hh.hh",
            "hhhhh",
            "..s..",
            "..s..",
            "..s..",
            "..s..",
        ], at: (x: 27, y: 11 + jiggle), key: key)
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

    /// Where the blaze may anchor: off his back into the sky band (the
    /// classic), or LOW — rising off the floor past his left flank, the
    /// operator's "put it by his feet sometimes". One placement per 45-second
    /// stretch, rolled on `47 &+ 11` (the 47 family over yet another domain);
    /// cycle zero keeps the classic, the frozen renders' sentinel.
    private static func fireBurnsLow(cycle: Int) -> Bool {
        cycle > 0 && CrabAnimator.noise(cycle &* 47 &+ 11) < 0.35
    }

    private static func drawFire(_ b: inout PixelBuffer, dx: Int, dy: Int, phase: Double) {
        let key: [Character: PixelBuffer.Ink] = [
            "c": .flameCore, "f": .flame, "e": .ember,
        ]
        // Slow enough to read as flame rather than strobe.
        let frame = flameFrames[Int(phase * 6) % flameFrames.count]
        // Two anchors: behind his back rising into the free band (the
        // classic), or by his feet climbing his flank. A placement change
        // CROSS-DISSOLVES over the first second of its cycle — a blaze that
        // teleports is exactly the cut the no-snap rule bans — via the same
        // scratch-and-composite the prop dissolve uses (seeds 770/771).
        func anchor(low: Bool) -> (x: Int, y: Int) {
            low ? (x: 2 + dx, y: 17 + dy) : (x: 17 + dx, y: 1 + dy)
        }
        let cycle = Int(floor(phase / 45))
        let into = phase - Double(cycle) * 45
        let current = fireBurnsLow(cycle: cycle)
        let previous = fireBurnsLow(cycle: cycle - 1)
        if into < 1, current != previous {
            var out = PixelBuffer()
            out.stamp(frame, at: anchor(low: previous), key: key)
            b.composite(out, visibility: 1 - into, seed: 770)
            var inc = PixelBuffer()
            inc.stamp(frame, at: anchor(low: current), key: key)
            b.composite(inc, visibility: into, seed: 771)
        } else {
            b.stamp(frame, at: anchor(low: current), key: key)
        }
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
