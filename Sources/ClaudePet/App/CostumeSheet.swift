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
            && clawdVariantSheet(to: root.appendingPathComponent("sheet-clawd-candidates.png"))
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
