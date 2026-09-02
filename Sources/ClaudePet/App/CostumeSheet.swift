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

        // The scan as shipped: salt 19, period 6 — cycle 2 fires (dice 0.587
        // < 0.7), so propPhase 12.0…13.1 is a live window.
        let scanToday = [12.05, 12.3, 12.6, 12.9].map {
            tile(CrabRig.render(staged(1.0, phase: $0), costume: g),
                 g, "scan today p=\($0)")
        }

        // Ink/width options, painted as mocks at the same mid-sweep column.
        func scanMock(_ label: String, paint: (inout PixelBuffer, Int) -> Void) -> Tile {
            var b = CrabRig.render(CrabAnimator.pose(mood: .idle, t: 1.0, flourishes: false),
                                   costume: g)
            let column = CrabRig.bodyX + Int(0.45 * Double(CrabRig.bodyW))
            paint(&b, column)
            return tile(b, g, label)
        }
        let options = [
            scanMock("A: 2-col gold+steel") { b, c in
                for row in 0..<PixelBuffer.side {
                    if b[c, row] == .body { b.pixel(c, row, .yellow) }
                    if b[c - 1, row] == .body { b.pixel(c - 1, row, .steel) }
                }
            },
            scanMock("B: visor glow (no sweep)") { b, _ in
                for row in [13, 16] {
                    for x in (CrabRig.bodyX + 2)..<(CrabRig.bodyX + CrabRig.bodyW - 2)
                    where b[x, row] == .costumeC {
                        b.pixel(x, row, .yellow)
                    }
                }
            },
            scanMock("C: 1-col gold") { b, c in
                for row in 0..<PixelBuffer.side where b[c, row] == .body {
                    b.pixel(c, row, .yellow)
                }
            },
        ]

        return write("GUNDAM — idle · motion · the scan · scan options",
                     rows: [idle, motion, scanToday, options], to: url)
    }

    // MARK: Sonic

    private static func sonicSheet(to url: URL) -> Bool {
        let s = Costume.sonic

        let idle = [0.0, 0.4, 0.9, 1.6, 2.3].map {
            tile(CrabRig.render(CrabAnimator.pose(mood: .idle, t: $0, flourishes: false),
                                costume: s), s, "idle t=\($0)")
        }

        // Salt 23, period 5 — cycle 1 fires (dice 0.012 < 0.5): 5.0…5.75.
        let motion = [
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.3), costume: s),
                 s, "scuttle a (sneakers?)"),
            tile(CrabRig.render(CrabAnimator.flourishPose(.scuttle, at: 0.6), costume: s),
                 s, "scuttle b (sneakers?)"),
            tile(CrabRig.render(staged(1.0, phase: 5.1), costume: s), s, "lines today p=5.1"),
            tile(CrabRig.render(staged(1.0, phase: 5.4), costume: s), s, "lines today p=5.4"),
            tile(CrabRig.render(staged(1.0, phase: 5.7), costume: s), s, "lines today p=5.7"),
        ]

        // Quill and eye variants, painted as mocks on the idle frame.
        func mock(_ label: String, paint: (inout PixelBuffer) -> Void) -> Tile {
            var b = CrabRig.render(CrabAnimator.pose(mood: .idle, t: 0, flourishes: false),
                                   costume: s)
            paint(&b)
            return tile(b, s, label)
        }
        let crown = CrabRig.bodyY  // idle t=0: dy = 0, squash = 0
        let variants = [
            mock("quills today") { _ in },
            mock("quills +1 taller") { b in
                b.rect(14, crown - 3, 4, 1, .costumeA)
                b.pixel(15, crown - 4, .costumeA)
                b.pixel(16, crown - 4, .costumeA)
                b.pixel(11, crown - 3, .costumeA)
                b.pixel(20, crown - 3, .costumeA)
            },
            mock("quills sharp spike") { b in
                b.rect(14, crown - 3, 4, 1, .costumeA)
                b.pixel(15, crown - 4, .costumeA)
                b.pixel(16, crown - 4, .costumeA)
                b.pixel(16, crown - 5, .costumeA)
            },
            mock("eye field (mock)") { b in
                for x in 9...22 where b[x, 12] == .body { b.pixel(x, 12, .paper) }
                for x in [9, 13, 18, 22] {
                    for y in 13...15 where b[x, y] == .body { b.pixel(x, y, .paper) }
                }
            },
            mock("eyes today") { _ in },
        ]

        // The golden rings: the three spin stamps alone, then in flight.
        func stamp(_ b: inout PixelBuffer, x: Int, y: Int, frame: Int) {
            switch frame % 4 {
            case 0:  // full, 5 wide
                b.rect(x + 1, y, 3, 1, .yellow)
                b.rect(x + 1, y + 4, 3, 1, .yellow)
                for r in 1...3 { b.pixel(x, y + r, .yellow); b.pixel(x + 4, y + r, .yellow) }
                b.pixel(x + 4, y + 2, .flameCore)
            case 2:  // edge-on, 1 wide
                for r in 0...4 { b.pixel(x + 2, y + r, .yellow) }
                b.pixel(x + 2, y + 2, .flameCore)
            default: // three-quarter, 3 wide
                for r in 0...4 { b.pixel(x + 1, y + r, .yellow) }
                b.pixel(x + 3, y + 2, .yellow)
                b.pixel(x + 2, y + 2, .flameCore)
            }
        }
        var stampsAlone = PixelBuffer()
        stamp(&stampsAlone, x: 4, y: 13, frame: 0)
        stamp(&stampsAlone, x: 13, y: 13, frame: 1)
        stamp(&stampsAlone, x: 22, y: 13, frame: 2)
        let rings = [tile(stampsAlone, s, "ring stamps 5w/3w/1w")]
            + [0.15, 0.4, 0.65, 0.9].map { p in
                mock("rings in flight p=\(p)") { b in
                    for k in 0..<3 {
                        let q = min(1, max(0, p * 1.3 - Double(k) * 0.15))
                        guard q > 0, q < 1 else { continue }
                        let x = 30 - Int(q * 38)
                        let y = 2 + ((0.35...0.65).contains(q) ? -1 : 0)
                        stamp(&b, x: x, y: y, frame: Int(q * 16))
                    }
                }
            }

        return write("SONIC — idle · motion+lines · quill/eye options · rings",
                     rows: [idle, motion, variants, rings], to: url)
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
