import Foundation
import AppKit
import SwiftUI

/// Claw'd, flattened into something Figma can hold.
///
/// The operator edits vectors in Figma and the sprite lives in this repo, so
/// the two need a seam that survives a rig change. This is that seam, and it
/// runs the same direction as every other renderer here: the CODE is the
/// source of the shape, and the export is a fresh statement of it. Nothing
/// reads back — a hand-edited artboard is the operator's, and re-running
/// this replaces it rather than merging with it.
///
/// The output is deliberately not a picture. It is the ink grid itself,
/// run-length encoded per row, so the far side can build whatever it wants
/// out of it — one square per cell, merged rectangles, or a flattened
/// outline — without this file having an opinion about which.
/// `@MainActor` because it reads the canvas's own ink table, which is. The
/// entry point already enters the actor via `MainActor.assumeIsolated`, so
/// this costs nothing and says out loud what was previously true only by
/// accident — a newer toolchain inferred the isolation and an older one
/// refused to, which is a build that passes here and fails on CI.
@MainActor
enum FigmaExport {

    /// A board is one artboard's worth of crab: a name, the group it belongs
    /// under, and thirty-two rows.
    private struct Board {
        let group: String
        let name: String
        let pose: CrabPose
        let costume: Costume
    }

    static func render(to path: String) -> Bool {
        var boards: [Board] = []

        // The base body: the frozen sentinel, which is the one pose in the
        // whole rig guaranteed to be at rest.
        boards.append(Board(group: "Base", name: "base-body",
                            pose: CrabAnimator.pose(mood: .idle, t: 0, flourishes: false),
                            costume: .none))

        // The eight moods, each at the same instant of its own clock so the
        // set reads as one sheet rather than eight unrelated frames.
        for mood in PetMood.allCases {
            boards.append(Board(group: "Moods", name: mood.rawValue,
                                pose: CrabAnimator.pose(mood: mood, t: 0.9, flourishes: false),
                                costume: .none))
        }

        // The skate beats, each staged at the moment that IS the trick —
        // the apex, the edge-on frame, the held wheelie.
        let beats: [(String, CrabAnimator.Flourish, Double)] = [
            ("ollie-apex", .ollie, 0.5), ("kickflip-air", .kickflip, 0.5),
            ("varial-edge-on", .varialFlip, 0.475), ("manual-hold", .manual, 0.5),
            ("nollie-float", .nollie, 0.55), ("cruise", .cruise, 0.5),
        ]
        for (name, kind, at) in beats {
            boards.append(Board(group: "Skate", name: name,
                                pose: CrabAnimator.flourishPose(kind, at: at * kind.duration),
                                costume: .none))
        }

        // The face, on the whole body: an expression is not a crop, and a
        // designer restyling an eye needs to see the head it sits in.
        var faces: [(String, (inout CrabPose) -> Void)] = [
            ("eyes-round", { $0.eyes = .round }),
            ("eyes-determined", { $0.eyes = .determined }),
            ("eyes-wide", { $0.eyes = .wide }),
            ("eyes-squint", { $0.eyes = .squint }),
            ("eyes-blink", { $0.blink = 1 }),
            ("eyes-wink", { $0.winkEye = .right }),
            ("eyes-asleep", { $0.blink = 1; $0.lidsLowered = true }),
        ]
        for (name, mouth) in [("mouth-smile", CrabPose.Mouth.smile),
                              ("mouth-flat", .flat), ("mouth-open", .open)] {
            faces.append((name, { $0.mouth = mouth }))
        }
        for (name, apply) in faces {
            var pose = CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
            apply(&pose)
            boards.append(Board(group: "Face", name: name, pose: pose, costume: .none))
        }

        // The turn, at eight stops of one revolution — the rotation
        // reference for a body that has no rotation in the grid.
        for eighth in 0..<8 {
            var pose = CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false)
            pose.bob = -9
            pose.legAmplitude = 1.6
            pose.legPhase = .pi / 2
            pose.torsoTurn = Double(eighth) / 8
            boards.append(Board(group: "Turn", name: "turn-\(eighth * 45)", pose: pose, costume: .none))
        }

        // Every ink any board actually uses, and nothing else: a palette
        // full of slots this sprite never paints is a menu, not a palette.
        var used = Set<UInt8>()
        var encoded: [[String: Any]] = []
        for board in boards {
            let buffer = CrabRig.render(board.pose, costume: board.costume)
            var rows: [String] = []
            for y in 0..<PixelBuffer.side {
                var row = "", run = 0
                var current = buffer[0, y].rawValue
                for x in 0..<PixelBuffer.side {
                    let ink = buffer[x, y].rawValue
                    if ink == current { run += 1; continue }
                    row += "\(inkChar(current))\(run)"
                    if current != 0 { used.insert(current) }
                    current = ink; run = 1
                }
                row += "\(inkChar(current))\(run)"
                if current != 0 { used.insert(current) }
                rows.append(row)
            }
            encoded.append(["group": board.group, "name": board.name, "rows": rows])
        }

        var palette: [[String: Any]] = []
        for raw in used.sorted() {
            guard let ink = PixelBuffer.Ink(rawValue: raw) else { continue }
            palette.append(["char": String(inkChar(raw)), "name": inkName(ink),
                            "hex": resolved(ink).hex,
                            "opacity": resolved(ink).opacity])
        }

        let payload: [String: Any] = ["side": PixelBuffer.side,
                                      "palette": palette, "boards": encoded]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return false }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard (try? data.write(to: url)) != nil else { return false }
        print("wrote \(encoded.count) boards and \(palette.count) inks to \(url.path)")
        return true
    }

    /// One printable character per ink, so a row of thirty-two cells is a
    /// short string rather than an array of numbers.
    private static func inkChar(_ raw: UInt8) -> Character {
        Character(UnicodeScalar(65 + raw))
    }

    private static func inkName(_ ink: PixelBuffer.Ink) -> String {
        String(describing: ink)
    }

    /// Straight off the canvas's own table, resolved through AppKit so what
    /// lands in Figma is the colour that ships, not a hex someone retyped.
    /// The alpha travels separately because `.shadow` is translucent and a
    /// flattened shadow is a black bar under his feet.
    private static func resolved(_ ink: PixelBuffer.Ink) -> (hex: String, opacity: Double) {
        let color = PixelCanvasView.color(for: ink, bodyTint: nil, inkOverrides: [:])
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return ("000000", 1) }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return (String(format: "%02X%02X%02X", r, g, b),
                (srgb.alphaComponent * 100).rounded() / 100)
    }
}
