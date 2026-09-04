import SwiftUI

/// Contact sheets for the costume-refinement rounds: big labeled grids of
/// frozen frames the operator points at. `ClaudePet --render-costume-sheet
/// <dir>` writes one PNG per subject. Review material, never committed.
///
/// Everything here is staged by pose construction — a hand-built pose, a
/// `propPhase` set inside a dice window solved offline — so the sheets are
/// deterministic and need no clock. The *option* tiles (scan inks, quill
/// heights, the ring stamps) are painted straight onto the rendered buffer by
/// this file: mocks for choosing a look, not the implementation. Whatever the
/// operator picks gets built properly in `CrabCostume` afterwards.
@MainActor
enum CostumeSheet {

    // MARK: - Tiles

    private struct Tile {
        let buffer: PixelBuffer
        let costume: Costume
        let caption: String
    }

    private static func tile(_ buffer: PixelBuffer, _ costume: Costume,
                             _ caption: String) -> Tile {
        Tile(buffer: buffer, costume: costume, caption: caption)
    }

    /// A neutral the whole cast reads on. Slate deck, RX-78 white, sonic
    /// blue, paper effects and yellow all need to be visible at once, which
    /// rules out both the dark grounds (they eat `.slate`) and the light ones
    /// (they eat `.paper`).
    private static let ground = Color(white: 0.62)

    private static func sheet(_ title: String, rows: [[Tile]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.slate)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        VStack(spacing: 3) {
                            PixelCanvasView(buffer: cell.buffer,
                                            inkOverrides: CostumeStyle.blendedOverrides(
                                                from: cell.costume, to: cell.costume, u: 1),
                                            seamBleed: 0)
                                .frame(width: 128, height: 128)
                            Text(cell.caption)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Palette.slate.opacity(0.85))
                                .frame(width: 132)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(ground)
    }

    private static func write(_ title: String, rows: [[Tile]], to url: URL) -> Bool {
        SpriteImage.write(SpriteImage.png(of: sheet(title, rows: rows), scale: 2,
                                          isOpaque: true), to: url)
    }

    // MARK: - Staged poses

    /// An idle frame with `propPhase` pushed to an instant inside a solved
    /// effect window, so the costume's own scheduled effect draws itself.
    private static func staged(_ t: Double, phase: Double) -> CrabPose {
        var pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false)
        pose.propPhase = phase
        return pose
    }

    // MARK: - The sheets

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch { return false }
        return gundamSheet(to: root.appendingPathComponent("sheet-gundam.png"))
            && sonicSheet(to: root.appendingPathComponent("sheet-sonic.png"))
            && ollieSheet(to: root.appendingPathComponent("sheet-ollie.png"))
            && clawdSheet(to: root.appendingPathComponent("sheet-clawd.png"))
            && holidaySheet(to: root.appendingPathComponent("sheet-holiday.png"))
            && skaterSheet(to: root.appendingPathComponent("sheet-skater.png"))
            && headwearSheet(to: root.appendingPathComponent("sheet-headwear.png"))
            && effectsSheet(to: root.appendingPathComponent("sheet-effects.png"))
            && clawdVariantSheet(to: root.appendingPathComponent("sheet-clawd-candidates.png"))
            && tigerSheet(to: root.appendingPathComponent("sheet-tiger.png"))
            && coderSheet(to: root.appendingPathComponent("sheet-coder.png"))
            && turnSheet(to: root.appendingPathComponent("sheet-turn.png"))
    }

    // MARK: The body turn

    /// One revolution, sampled — bare, and then dressed, since the whole
    /// case for the mapping pass is that the wardrobe turns with him.
    private static func turnSheet(to url: URL) -> Bool {
        func turned(_ turn: Double, _ costume: Costume, _ label: String) -> Tile {
            var pose = CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false)
            pose.bob = -9
            pose.legAmplitude = 1.6
            pose.legPhase = .pi / 2
            pose.torsoTurn = turn
            return tile(CrabRig.render(pose, costume: costume), costume, label)
        }
        let steps = [0.0, 0.08, 0.17, 0.25, 0.33, 0.42, 0.5]
        let bare = steps.map { turned($0, .none, "θ \(Int($0 * 360))°") }
        let back = [0.58, 0.67, 0.75, 0.83, 0.92, 0.97, 1.0]
            .map { turned($0, .none, "θ \(Int($0 * 360))°") }
        let ninja = [0.0, 0.17, 0.25, 0.42, 0.5, 0.67, 0.83].map { turned($0, .ninja, "ninja \(Int($0 * 360))°") }
        let sonic = [0.0, 0.17, 0.25, 0.42, 0.5, 0.67, 0.83].map { turned($0, .sonic, "sonic \(Int($0 * 360))°") }
        return write("THE TURN — one revolution, bare and dressed",
                     rows: [bare, back, ninja, sonic], to: url)
    }

    // MARK: The tiger, for pointing

    /// The current tiger fitting across his moods — the pointing surface
    /// for its refinement round, the way the gundam and sonic sheets were.
    private static func tigerSheet(to url: URL) -> Bool {
        func dressed(_ mood: PetMood, t: Double = 0.9, phase: Double = 0,
                     _ label: String) -> Tile {
            var pose = CrabAnimator.pose(mood: mood, t: t, flourishes: false)
            pose.propPhase = phase
            return tile(CrabRig.render(pose, costume: .tiger), .tiger, label)
        }
        let stills = [
            dressed(.idle, "idle"),
            dressed(.idle, phase: 0.9, "tail mid-swish"),
            dressed(.idle, phase: 1.8, "tail far"),
            dressed(.working, "working"),
            dressed(.thinking, "thinking"),
        ]
        let moods = [
            dressed(.done, "done"),
            dressed(.nudging, "nudging"),
            dressed(.cooking, "cooking"),
            dressed(.needsAttention, "needs you"),
            dressed(.sleeping, t: 2.0, "sleeping"),
        ]
        return write("TIGER — current fitting, for pointing", rows: [stills, moods], to: url)
    }

    // MARK: The coder

    /// Matrix-turned-Coder: the glasses, with and without the rain.
    private static func coderSheet(to url: URL) -> Bool {
        func dressed(_ mood: PetMood, t: Double = 0.9, phase: Double,
                     _ label: String) -> Tile {
            var pose = CrabAnimator.pose(mood: mood, t: t, flourishes: false)
            pose.propPhase = phase
            return tile(CrabRig.render(pose, costume: .matrix), .matrix, label)
        }
        let row = [
            dressed(.idle, phase: 0.0, "idle, rain t=0"),
            dressed(.idle, phase: 2.0, "rain t=2"),
            dressed(.idle, phase: 4.5, "rain t=4.5"),
            dressed(.working, phase: 2.0, "working"),
            dressed(.thinking, phase: 2.0, "thinking"),
        ]
        return write("CODER — glasses on, rain running", rows: [row], to: url)
    }

    // MARK: The seasons

    private static func holidaySheet(to url: URL) -> Bool {
        func dressed(_ costume: Costume, t: Double = 0.9,
                     phase: Double? = nil, label: String) -> Tile {
            var pose = CrabAnimator.pose(mood: .idle, t: t, flourishes: false)
            if let phase { pose.propPhase = phase }
            return tile(CrabRig.render(pose, costume: costume), costume, label)
        }
        // Effects staged at solved windows: pumpkin flicker salt 5 cycle 1
        // (8.0-8.6), turkey strut salt 7 cycle 1 (9.0-9.9), santa breath
        // salt 17 cycle 3 (30.0-30.8).
        let costumes = [
            dressed(.pumpkin, label: "pumpkin"),
            dressed(.pumpkin, phase: 8.2, label: "pumpkin flicker"),
            dressed(.turkey, label: "turkey"),
            dressed(.turkey, phase: 9.4, label: "turkey strut"),
            dressed(.santa, phase: 30.3, label: "santa + breath"),
        ]
        func ambient(_ label: String, mutate: (inout CrabPose) -> Void) -> Tile {
            var pose = CrabAnimator.pose(mood: .idle, t: 2.3, flourishes: false)
            mutate(&pose)
            return tile(CrabRig.render(pose), .none, label)
        }
        let ambience = [
            ambient("autumn leaves") { $0.holiday = .halloween },
            ambient("snow for everyone") { $0.holiday = .winter },
            ambient("floor pumpkins") { $0.holidayGround = true },
            ambient("firework rise") { $0.fireworkProgress = 0.2; $0.fireworkCycle = 3 },
            ambient("firework burst") { $0.fireworkProgress = 0.6; $0.fireworkCycle = 3 },
        ]
        return write("THE SEASONS — costumes · ambience",
                     rows: [costumes, ambience], to: url)
    }

    // MARK: Every effect

    /// One tile per costume effect, each staged mid-window at its solved
    /// dice instant — the whole wardrobe's motion on one page, for the
    /// operator's per-costume VFX review.
    private static func effectsSheet(to url: URL) -> Bool {
        func staged(_ costume: Costume, _ phase: Double, _ label: String,
                    mutate: (inout CrabPose) -> Void = { _ in }) -> Tile {
            // t = 0.9: eyes open, no blink — a blinking tile reads as a
            // broken face, which this sheet learned the hard way.
            var pose = CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false)
            pose.propPhase = phase
            mutate(&pose)
            return tile(CrabRig.render(pose, costume: costume), costume, label)
        }
        let rowOne = [
            staged(.ninja, 90.9, "shuriken t=90.9"),
            staged(.frankenstein, 35.3, "sparks t=35.3"),
            staged(.retroBlack, 33.8, "sheen t=33.8"),
            staged(.matrix, 2.0, "rain (continuous)"),
            staged(.tiger, 2.0, "tail (continuous)"),
        ]
        let rowTwo = [
            staged(.white, 2.0, "snow (continuous)"),
            // The arcade marquee tile stood here until the operator killed
            // the marquee; the second bolt's spark takes the slot.
            staged(.frankenstein, 35.55, "sparks, right bolt t=35.55"),
            staged(.gundam, 36.55, "scan t=36.55"),
            staged(.gundam, 14.3, "eye flare t=14.3"),
            staged(.sonic, 9.8, "dash t=9.8"),
        ]
        let rowThree = [
            staged(.sonic, 1.0, "rings (staged)") { $0.ringFlight = 0.4 },
            staged(.pumpkin, 8.2, "flicker t=8.2"),
            staged(.turkey, 9.4, "strut t=9.4"),
            staged(.santa, 30.3, "breath t=30.3"),
            staged(.skater, 27.3, "kick-push t=27.3"),
        ]
        return write("EVERY EFFECT — one per costume, mid-window",
                     rows: [rowOne, rowTwo, rowThree], to: url)
    }

    // MARK: Headwear

    private static func headwearSheet(to url: URL) -> Bool {
        func hatted(_ wear: CrabPose.Headwear, t: Double, flourish: CrabAnimator.Flourish?,
                    _ label: String) -> Tile {
            var pose = flourish.map { CrabAnimator.flourishPose($0, at: t) }
                ?? CrabAnimator.pose(mood: .idle, t: t, flourishes: false)
            pose.headwear = wear
            return tile(CrabRig.render(pose), .none, label)
        }
        let beanie = [
            hatted(.blackBeanie, t: 0.9, flourish: nil, "beanie, idle"),
            hatted(.blackBeanie, t: 0.9, flourish: .ollie, "beanie, ollie rise"),
            hatted(.blackBeanie, t: 1.6, flourish: .ollie, "beanie, apex (crops)"),
            hatted(.blackBeanie, t: 1.3, flourish: .manual, "beanie, manual"),
        ]
        let caps = CrabAnimator.capColours.map { ink in
            hatted(.cap(ink), t: 0.9, flourish: nil, "cap: \(ink)")
        } + [hatted(.cap(.alert), t: 0.9, flourish: .ollie, "cap, ollie rise")]
        return write("HEADWEAR — the taller beanie · the baseball hat",
                     rows: [beanie, caps], to: url)
    }

    // MARK: The skater

    private static func skaterSheet(to url: URL) -> Bool {
        func dressed(_ pose: CrabPose, _ label: String) -> Tile {
            tile(CrabRig.render(pose, costume: .skater), .skater, label)
        }
        let idle = [0.0, 0.9, 1.6].map {
            dressed(CrabAnimator.pose(mood: .idle, t: $0, flourishes: false), "idle t=\($0)")
        }
        // Kick-push: salt 43 cycle 3 fires — 27.0…27.8.
        var pushed = CrabAnimator.pose(mood: .idle, t: 1.0, flourishes: false)
        pushed.propPhase = 27.3
        let row = idle + [dressed(pushed, "kick-push")]
        let tricks = [
            dressed(CrabAnimator.flourishPose(.manual, at: 1.3), "manual"),
            dressed(CrabAnimator.flourishPose(.ollie, at: 0.9), "ollie rise"),
            dressed(CrabAnimator.flourishPose(.kickflip, at: 1.4), "kickflip air"),
            dressed(CrabAnimator.flourishPose(.shoveIt, at: 1.0), "shove-it"),
            dressed(CrabAnimator.flourishPose(.nollie, at: 0.9), "nollie rise"),
            dressed(CrabAnimator.flourishPose(.bigspin, at: 1.3), "bigspin"),
            dressed(CrabAnimator.pose(mood: .sleeping, t: 2, flourishes: false), "asleep in it"),
        ]
        return write("THE SKATER — the fit · on the board",
                     rows: [row, tricks], to: url)
    }

    // MARK: Normal Claw'd

    /// The base crab and his whole current VFX inventory, staged — the
    /// operator's pointing surface for the clawd-polish round.
    private static func clawdSheet(to url: URL) -> Bool {
        func posed(_ mutate: (inout CrabPose) -> Void = { _ in }) -> PixelBuffer {
            var pose = CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false)
            mutate(&pose)
            return CrabRig.render(pose)
        }

        let poses = [
            tile(posed(), .none, "idle"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.jump, at: 0.45)), .none, "jump apex"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.kickflip, at: 1.4)), .none, "kickflip air"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.6)), .none, "scuttle"),
            tile(CrabRig.render(CrabAnimator.pose(mood: .sleeping, t: 2, flourishes: false)),
                 .none, "asleep"),
        ]

        let reactions = [
            tile(CrabRig.render(CrabAnimator.flourishPose(.wave, at: 0.9)), .none, "wave"),
            tile(posed { p in p.confettiElapsed = 1.2; p.mouth = .open }, .none, "party confetti"),
            tile(posed { p in p.heartsElapsed = 3.0 }, .none, "petting hearts"),
            tile(posed { p in p.snackElapsed = 1.0 }, .none, "the shrimp"),
            tile(posed { p in
                p.prop = .shades
                p.shadesDrop = -6
            }, .none, "shades mid-drop"),
            tile(posed { p in p.idleHeart = 0.5 }, .none, "idle heart"),
            {
                var pose = CrabAnimator.flourishPose(.ollie, at: 1.6)
                pose.headwear = .blackBeanie
                return tile(CrabRig.render(pose), .none, "black beanie ollie")
            }(),
            {
                var pose = CrabAnimator.flourishPose(.ollie, at: 0.9)
                pose.headwear = .cap(.alert)
                return tile(CrabRig.render(pose), .none, "red cap rise")
            }(),
        ]

        let light = [
            tile(posed { p in p.glint = 0.5 }, .none, "shell glint"),
            tile(posed { p in
                p.sunPatch = 1
                p.sunPatchPhase = 7
                p.blink = 1
                p.mouth = .smile
            }, .none, "patch of sun"),
            tile(posed { p in
                p.stargaze = 1
                p.stargazePhase = 3
                p.shootingStarX = 20
                p.shootingStarY = 3
                p.shootingStarDX = -1
            }, .none, "stargaze + star"),
            tile(posed { p in p.doneBadge = 1 }, .none, "done badge"),
            tile(posed { p in
                p.winkEye = .right
                p.winkGlint = true
                p.mouth = .smile
            }, .none, "wink ting"),
        ]

        return write("NORMAL CLAW'D — poses · reactions · light",
                     rows: [poses, reactions, light], to: url)
    }

    /// Candidate looks for the clawd-polish round, painted as MOCKS on the
    /// rendered idle frame — the quill-options pattern. Whatever the
    /// operator picks gets built properly in the rig.
    private static func clawdVariantSheet(to url: URL) -> Bool {
        func mock(_ label: String, paint: (inout PixelBuffer) -> Void) -> Tile {
            var b = CrabRig.render(CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false))
            paint(&b)
            return Tile(buffer: b, costume: .none, caption: label)
        }
        // The idle body at t=0.9: bob 0, squash 0 — rows 10…20, x6…25.
        func nip(_ b: inout PixelBuffer) {
            for (x, y) in [(6, 10), (25, 10), (6, 20), (25, 20)] { b.pixel(x, y, .clear) }
        }
        func carve(_ b: inout PixelBuffer) {
            for (x, y) in [(6, 10), (7, 10), (6, 11), (25, 10), (24, 10), (25, 11),
                           (6, 20), (25, 20)] { b.pixel(x, y, .clear) }
        }
        func catchlight(_ b: inout PixelBuffer) {
            b.pixel(10, 13, .paper)
            b.pixel(19, 13, .paper)
        }
        func bellyShade(_ b: inout PixelBuffer) {
            for x in 6...25 where b[x, 20] == .body { b.pixel(x, 20, .bodyShade) }
        }
        func sideShade(_ b: inout PixelBuffer) {
            for x in 6...25 where b[x, 20] == .body { b.pixel(x, 20, .bodyShade) }
            for y in 11...19 where b[25, y] == .body { b.pixel(25, y, .bodyShade) }
        }

        let silhouette = [
            mock("today: the [ ]") { _ in },
            mock("A: corner nips") { b in nip(&b) },
            mock("B: carved corners") { b in carve(&b) },
        ]
        let face = [
            mock("eyes today") { _ in },
            mock("C: catchlights") { b in catchlight(&b) },
        ]
        let shade = [
            mock("flat today") { _ in },
            mock("D: belly shade") { b in bellyShade(&b) },
            mock("E: belly + side") { b in sideShade(&b) },
        ]
        let hero = [
            mock("HERO: A + C + D") { b in
                nip(&b); catchlight(&b); bellyShade(&b)
            },
            mock("HERO: B + C + E") { b in
                carve(&b); catchlight(&b); sideShade(&b)
            },
        ]
        return write("CLAW'D CANDIDATES — silhouette · face · shading · heroes",
                     rows: [silhouette, face, shade, hero], to: url)
    }

    // MARK: Gundam

    private static func gundamSheet(to url: URL) -> Bool {
        let g = Costume.gundam

        let idle = [0.0, 0.4, 0.9, 1.6, 2.3].map {
            tile(CrabRig.render(CrabAnimator.pose(mood: .idle, t: $0, flourishes: false),
                                costume: g), g, "idle t=\($0)")
        }

        let motion = [
            tile(CrabRig.render(CrabAnimator.flourishPose(.wiggle, at: 0.5), costume: g),
                 g, "wiggle mid"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.kickflip, at: 0.2), costume: g),
                 g, "kickflip crouch (squash)"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.kickflip, at: 2.7), costume: g),
                 g, "kickflip stomp"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.3), costume: g),
                 g, "scuttle a (feet?)"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.6), costume: g),
                 g, "scuttle b (feet?)"),
        ]

        // Scan A as shipped: salt 19, period 12 — cycle 3 fires (dice 0.145
        // < 0.35), so propPhase 36.0…37.8 is a live window.
        let scan = [36.1, 36.55, 37.0, 37.45].map {
            tile(CrabRig.render(staged(1.0, phase: $0), costume: g),
                 g, "scan p=\($0)")
        }

        return write("GUNDAM — idle · motion · the scan (option A, thickened)",
                     rows: [idle, motion, scan], to: url)
    }

    // MARK: Sonic

    private static func sonicSheet(to url: URL) -> Bool {
        let s = Costume.sonic

        let idle = [0.0, 0.4, 0.9, 1.6, 2.3].map {
            tile(CrabRig.render(CrabAnimator.pose(mood: .idle, t: $0, flourishes: false),
                                costume: s), s, "idle t=\($0)")
        }

        // Dash A: salt 23, period 9 — cycle 1 fires (dice 0.012 < 0.4):
        // 9.0…10.6. The middle instants carry the afterimage ticks.
        let motion = [
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.3), costume: s),
                 s, "scuttle a"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.6), costume: s),
                 s, "scuttle b"),
            tile(CrabRig.render(staged(1.0, phase: 9.2), costume: s), s, "dash p=9.2"),
            tile(CrabRig.render(staged(1.0, phase: 9.8), costume: s), s, "dash peak p=9.8"),
            tile(CrabRig.render(staged(1.0, phase: 10.4), costume: s), s, "dash exit p=10.4"),
        ]

        // The golden rings in flight, through the real draw.
        let rings = [0.15, 0.4, 0.65, 0.9].map { p in
            var pose = CrabAnimator.pose(mood: .idle, t: 0.5, flourishes: false)
            pose.propPhase = 0.5   // cycle 0: scheduled effects silent
            pose.ringFlight = p
            return tile(CrabRig.render(pose, costume: s), s, "rings p=\(p)")
        }

        return write("SONIC — idle · motion+dash · rings (spike quills, eye field)",
                     rows: [idle, motion, rings], to: url)
    }

    // MARK: The ollie

    private static func ollieSheet(to url: URL) -> Bool {
        let arc = [(0.25, "pop"), (0.9, "rise"), (1.6, "apex"), (2.3, "coming down"),
                   (3.0, "stomp")].map { t, label in
            tile(CrabRig.render(CrabAnimator.flourishPose(.ollie, at: t)), .none,
                 "\(label) t=\(t)")
        }
        // The drip-feed variants at the instant they differ most — a third
        // into the air, where lofty's flatter arc and the turns' shade bands
        // are all visible at once.
        let variants: [(SoloVariant, String)] = [(.ollie, "straight"),
                                                 (.ollieFrontside, "frontside"),
                                                 (.ollieBackside, "backside"),
                                                 (.ollieLofty, "lofty")]
        let dressed = variants.map { variant, label in
            tile(CrabRig.render(CostumeSampler.soloPose(variant: variant, at: 1.23)), .none,
                 "\(label) t=1.23")
        }
        return write("THE OLLIE — the arc · the drip variants",
                     rows: [arc, dressed], to: url)
    }
}
