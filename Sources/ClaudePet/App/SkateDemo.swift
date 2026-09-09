import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 🛹 **The demo reels — review artifacts, not marketing.**
///
/// Two short cuts the operator watches to fine-tune geometry they have just
/// asked for, before any marketing material is generated from it: `skate-ledge`
/// (the ledge, the bushes, the grind, the kickflip out) and `rainbow-combo`
/// (the score building, the Nyan ribbons, the board catching fire).
///
/// **No type, anywhere.** The operator sets type in Figma; a reel that carried
/// its own would be a second draft of theirs. That also exempts this file from
/// most of the house reel doctrine, which is largely about type and about a
/// multi-chapter product story. What still binds: the 120 BPM grid, real speed,
/// every cut changes the frame, and whole-pixel scaling.
///
/// **Deliberately NOT part of `SizzleScript`.** No `Chapter` case (`masterSums`
/// pins the 32.0 total) and no entry in `SizzleScript.cuts` (a dozen tests
/// iterate that array wholesale and apply caption laws a no-type reel cannot
/// satisfy in spirit). Its own file, its own flag, its own output directory —
/// and it writes nowhere near `docs/media`.
///
/// The shot lists are not improvised. They were designed by a fourteen-agent
/// pass — four grounded surveys, three independent shot lists per reel, a
/// director per reel, and a hostile reviewer who re-derived every number
/// against this source — then re-cut against the operator's own notes.
@MainActor
enum SkateDemo {

    // MARK: - Formats

    /// Which of the three magnifications a shot is framed at. Named rather
    /// than numeric because the same shot list serves two canvas shapes, and
    /// only the SHAPE knows what "large" is worth in points.
    enum Stop: CaseIterable { case small, mid, large }

    /// A canvas shape and its three whole-cell magnifications.
    ///
    /// Every side is a multiple of 32, so a cell is a whole number of points
    /// and nothing lands on a fractional pixel. The vertical nudges are whole
    /// CELLS, chosen so the ledge's steel top row sits within a few points of
    /// the same canvas line at all three stops — the ledge must not jump
    /// vertically across a magnification cut, or positions stop being
    /// comparable between shots.
    struct Format {
        let name: String
        let canvas: CGSize
        let sides: [Stop: CGFloat]
        let dy: [Stop: CGFloat]

        func side(_ stop: Stop) -> CGFloat { sides[stop] ?? 320 }
        func cell(_ stop: Stop) -> CGFloat { side(stop) / CGFloat(PixelBuffer.side) }
        func offsetY(_ stop: Stop) -> CGFloat { dy[stop] ?? 0 }
    }

    /// 512², sprite 320 / 384 / 448 → 10 / 12 / 14 points a cell.
    static let square = Format(
        name: "square", canvas: CGSize(width: 512, height: 512),
        sides: [.small: 320, .mid: 384, .large: 448],
        dy: [.small: 20, .mid: 0, .large: -14])

    /// 640×360, sprite 224 / 256 / 320 → 7 / 8 / 10 points a cell. The large
    /// stop is capped by the 360pt height, not by taste.
    static let wide = Format(
        name: "wide", canvas: CGSize(width: 640, height: 360),
        sides: [.small: 224, .mid: 256, .large: 320],
        dy: [.small: 14, .mid: 8, .large: -10])

    static let formats = [square, wide]

    // MARK: - The grid

    /// 120 BPM, the house grid. Every shot boundary in both reels is a whole
    /// beat, which is why 20 and 30 both land on whole frames everywhere.
    nonisolated static let beat = 0.5
    /// The GIF's rate. 0.05s is what GIF actually stores — 1/12 rounds to 8
    /// centiseconds and plays 4.2% fast, 1/15 rounds to 7 and plays 4.8% slow.
    nonisolated static let gifFps = 20
    nonisolated static let gifDelay = 0.05
    /// The MP4's rate. 🔎 The review rate: the ledge's entry runs at about 23
    /// cells a second, which is a shade over one cell a frame at 30 and nearly
    /// two at 20 — and a scrolling pixel element only reads as travel below
    /// about one cell a frame. The arrival is honest in the video and
    /// impressionistic in the GIF, and the hand-off says so.
    nonisolated static let videoFps: Int32 = 30

    // MARK: - A shot

    struct Shot {
        let start: Double
        let seconds: Double
        let ground: Color
        let groundName: String
        let stop: Stop
        /// Horizontal nudge in whole CELLS — the third dimension a no-type cut
        /// has, after side and ground.
        let cellsRight: Int
        let note: String

        var end: Double { start + seconds }

        init(_ start: Double, _ seconds: Double, _ ground: Color, _ groundName: String,
             _ stop: Stop, cellsRight: Int = 0, _ note: String) {
            self.start = start; self.seconds = seconds
            self.ground = ground; self.groundName = groundName
            self.stop = stop; self.cellsRight = cellsRight; self.note = note
        }
    }

    /// A whole reel: its shots and its pose source.
    struct Reel {
        let name: String
        let shots: [Shot]
        /// Reel time → the pose to draw and the tint to draw it with.
        let pose: @MainActor (Double) -> (CrabPose, SpriteTint.Tint?)

        var seconds: Double { shots.last.map(\.end) ?? 0 }
        func shot(at t: Double) -> Shot {
            shots.last { t >= $0.start - 1e-9 } ?? shots[0]
        }
    }

    // MARK: - Reel one: the ledge, twice

    /// The frozen base every skate frame is built on.
    ///
    /// 🔎 **`gazeX`/`gazeY` are zeroed, and that is not cosmetic.**
    /// `pose(mood:.idle, t: 0.4)` runs `gaze(at: 0.4)`, whose die
    /// `noise(0) = 0.8833` lands in the `>= 0.68` arm and returns `(0, +1)` —
    /// a held one-pixel downward dart. Frozen into a base and held for a
    /// second, that is a poster frame of a crab staring at his feet.
    ///
    /// The wardrobe is passed EXPLICITLY. `deckStance` returns 0 for any
    /// costume but the Skater, so the bare-wardrobe convenience overload would
    /// give a crab standing on nothing — and it also rebuilds its base on the
    /// trick's own clock, which would break the two passes' bit-identity.
    static var skateStance: CrabPose {
        var stance = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false,
                                       wardrobe: .init(current: .skater))
        stance.prop = .skateboardSmith
        stance.propVisibility = 1
        stance.propPhase = 0
        stance.gazeX = 0
        stance.gazeY = 0
        return stance
    }

    nonisolated static let skateOnsetA = 1.0
    nonisolated static let skateOnsetB = 8.0

    /// Pass A starts at reel 1.0, pass B at reel 8.0 — the same 6.5s trick
    /// twice, from the same base at the same local instants, so the two passes
    /// are **bit-identical in the 32×32 buffer**. The operator's A/B is exact,
    /// not approximate. Past the trick's duration `flourishPose` returns the
    /// base on its own, so the trailing rest costs no special case.
    static func skatePose(reel: Double) -> (CrabPose, SpriteTint.Tint?) {
        let stance = skateStance
        guard reel >= skateOnsetA else { return (stance, nil) }
        let local = reel - (reel < skateOnsetB ? skateOnsetA : skateOnsetB)
        return (CrabAnimator.flourishPose(.backSmith, at: local, base: stance), nil)
    }

    static let skateReel = Reel(
        name: "skate-ledge",
        shots: [
            Shot(0.0, 1.0, MarketingPalette.gold, "gold", .large,
                 "the empty stage — the poster, and the control frame for shot 3"),
            Shot(1.0, 7.0, MarketingPalette.cream, "cream", .small,
                 "the reference take, uncut: both rates over their whole extent"),
            Shot(8.0, 1.5, MarketingPalette.gold, "gold", .large,
                 "the arrival magnified, into the frame shot 1 memorised"),
            Shot(9.5, 3.5, MarketingPalette.cream, "cream", .mid,
                 "the lock and the parallax — 24 ledge cells against 12 bush cells, 2:1"),
            Shot(13.0, 1.5, MarketingPalette.gold, "gold", .large,
                 "the kickflip out — a whole turn, unhurried now — and the exit"),
        ],
        pose: skatePose)

    // MARK: - Reel two: the combo

    /// The ride is 20.4s and the ceiling is 15, so 6.9s comes out in three
    /// cuts: half a second of frozen stance in front of it (so the poster is a
    /// crab standing, not a crab loading a pop), **the shove-it and the nollie
    /// together** — one contiguous ellipsis, ride 6.0 → 11.8 — and a 1.1s tail.
    ///
    /// The seam used to take the nollie alone, because across the five landings
    /// the ribbon grows 2, 3, 2, 1, 0 cells and the nollie's single capped cell
    /// was the cheapest thing to lose. The back smith growing to 6.5s took
    /// another 1.1s out of the budget, and the next cheapest whole beat is its
    /// neighbour. One seam either way; it now costs two rungs instead of one.
    ///
    /// 🔎 **The tail is 1.1s, not 0.6s, and the extra 0.5s is not slack.** The
    /// ride's own ease-out begins at ride 19.6: by 19.8 the score has fallen to
    /// 0.84 and the fire to 0.22. A reel ending there would close on the fire
    /// going out, which is the opposite of the shot's job. `rideEnd` is 19.3 —
    /// inside the plateau, with the board still fully alight.
    nonisolated static let head = 0.5
    nonisolated static let seam = 6.5
    nonisolated static let skip = 5.8
    nonisolated static func ride(reel: Double) -> Double {
        reel < seam ? reel - head : reel - head + skip
    }

    /// 🔎 The decorative phases run on the REEL clock, not the ride's. The
    /// score is left alone — it is the thing being reviewed — but the ribbon's
    /// wave and the fire's flicker are put on reel time so both stay
    /// continuous across the seam (the skip is a whole number of neither
    /// period).
    static func rainbowPose(reel: Double) -> (CrabPose, SpriteTint.Tint?) {
        guard reel >= head,
              var pose = CrabAnimator.comboRide(local: ride(reel: reel),
                                                wardrobe: .init(current: .skater))
        else { return (skateStance, nil) }
        pose.comboPhase = reel
        // The costume goes IN: the tint now mixes out of the Skater's own
        // grape rather than stepping to Claw'd's terracotta on the first rung.
        return (pose, CrabView.comboTint(t: reel, combo: pose.combo, costume: .skater))
    }

    static let rainbowReel = Reel(
        name: "rainbow-combo",
        shots: [
            Shot(0.0, 2.0, MarketingPalette.gold, "gold", .small,
                 "the zero — half a second standing, then the ollie; score 0, no colour"),
            Shot(2.0, 1.5, MarketingPalette.cream, "cream", .large,
                 "the birth of the colour, largest stop, quietest plate"),
            Shot(3.5, 3.0, MarketingPalette.gold, "gold", .small,
                 "the kickflip, and the ribbon growing through a whole bob arc"),
            Shot(6.5, 1.5, MarketingPalette.cream, "cream", .small, cellsRight: 2,
                 "the seam — lands on a bare plate, then the ledge arrives from his right"),
            Shot(8.0, 2.5, MarketingPalette.cream, "cream", .mid, cellsRight: -2,
                 "the lock and the grind, with the ledge sliding on beneath him"),
            Shot(10.5, 2.0, MarketingPalette.cream, "cream", .small, cellsRight: 2,
                 "the kickflip out — a whole turn, unhurried — and the board alight"),
            Shot(12.5, 1.5, MarketingPalette.cream, "cream", .large,
                 "the payoff — the stomp, full score, nothing else on screen"),
        ],
        pose: rainbowPose)

    static let reels = [skateReel, rainbowReel]

    // MARK: - Composition

    /// The minimal scene: a flat opaque ground and the sprite. The drip
    /// renderer's shape, because `SizzleRenderer`'s own pet-and-layout
    /// helpers are private and a demo reel needs none of what they add.
    @ViewBuilder
    static func scene(_ pose: CrabPose, tint: SpriteTint.Tint?, shot: Shot,
                      format: Format) -> some View {
        let side = format.side(shot.stop)
        ZStack {
            shot.ground
            PixelCanvasView(buffer: CrabRig.render(pose, costume: .skater),
                            bodyTint: tint?.body,
                            bodyShadeTint: tint?.shade,
                            inkOverrides: CostumeStyle.blendedOverrides(
                                from: .skater, to: .skater, u: 1),
                            seamBleed: 0)
                .frame(width: side, height: side)
                .offset(x: CGFloat(shot.cellsRight) * format.cell(shot.stop),
                        y: format.offsetY(shot.stop))
        }
        .frame(width: format.canvas.width, height: format.canvas.height)
    }

    /// One frame of a reel at a given instant, rasterised.
    ///
    /// **`isOpaque: true` always.** Measured at 3.7–4.1× in bytes: an opaque
    /// ground lets ImageIO choose disposal 1 and delta-code only the pixels
    /// that changed, where transparency forces disposal 2 and re-encodes the
    /// whole sprite box every frame.
    static func frame(_ reel: Reel, at t: Double, format: Format,
                      scale: CGFloat = 1) -> CGImage? {
        let shot = reel.shot(at: t)
        let (pose, tint) = reel.pose(t)
        return SpriteImage.cgImage(of: scene(pose, tint: tint, shot: shot, format: format),
                                   scale: scale, isOpaque: true)
    }

    // MARK: - Render

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(directory)\n".utf8))
            return false
        }

        for reel in reels {
            for format in formats {
                let stem = "\(reel.name)-\(format.name)"

                // The GIF: the operator asked for GIF clips, and this is the
                // one they scrub in a chat window.
                let count = Int((reel.seconds * Double(gifFps)).rounded())
                var frames: [CGImage] = []
                frames.reserveCapacity(count)
                for index in 0..<count {
                    guard let image = frame(reel, at: Double(index) / Double(gifFps),
                                            format: format) else {
                        FileHandle.standardError.write(Data("frame \(index) of \(stem) failed\n".utf8))
                        return false
                    }
                    frames.append(image)
                }
                guard GifRenderer.encode(frames, to: root.appendingPathComponent("\(stem).gif"),
                                         frameDelay: gifDelay) else { return false }
                frames.removeAll(keepingCapacity: false)

                // The MP4: the review artifact for anything that moves fast —
                // the ledge's arrival and the spark flicker are honest here and
                // undersampled in the GIF. Streamed, one frame in flight.
                let videoCount = Int((reel.seconds * Double(videoFps)).rounded())
                guard VideoWriter.write(to: root.appendingPathComponent("\(stem).mp4"),
                                        fps: videoFps, frameCount: videoCount,
                                        frame: { index in
                                            frame(reel, at: Double(index) / Double(videoFps),
                                                  format: format)
                                        })
                else { return false }
            }
            guard writeSidecar(reel, to: root.appendingPathComponent("\(reel.name)-beats.tsv"))
            else { return false }
        }

        guard renderLedgeSheet(to: root.appendingPathComponent("ledge-full-extent.png"))
        else { return false }

        print("wrote \(reels.count * formats.count * 2) clips, "
              + "\(reels.count) beat sidecars and the ledge sheet to \(directory)")
        return true
    }

    // MARK: - The sidecar

    /// Whether the ledge has any cell on the grid at this instant.
    static func ledgeOnGrid(_ pose: CrabPose) -> Bool {
        guard pose.ledge > 0.001, pose.ledge < 0.999 else { return false }
        let right = CrabRig.ledgeRightEnd(travel: pose.ledge)
        return right >= 0 && right - (CrabRig.ledgeLength - 1) <= PixelBuffer.side - 1
    }

    /// Every rig event in reel time, **derived by watching the pose stream**.
    ///
    /// Never hand-listed. A typed table of instants is a second copy of the
    /// choreography, and the moment a phase boundary moves it becomes a
    /// confident lie — which is exactly what the first cut's sidecar became the
    /// day the trick grew from 5.4s to 6.5s. This walks the reel at the video
    /// rate and reports the frame each thing actually changes on, so it cannot
    /// drift from what was rendered.
    static func events(_ reel: Reel) -> [(Double, String)] {
        var out: [(Double, String)] = []
        let step = 1.0 / Double(videoFps)
        func rung(_ pose: CrabPose) -> Int { Int((pose.combo * 5).rounded(.down)) }
        var index = 1
        while Double(index) * step <= reel.seconds + 1e-9 {
            let t = Double(index) * step
            let (pose, tint) = reel.pose(t)
            let (before, beforeTint) = reel.pose(t - step)
            if ledgeOnGrid(pose) != ledgeOnGrid(before) {
                out.append((t, ledgeOnGrid(pose) ? "the ledge reaches the grid"
                                                 : "the ledge leaves the grid"))
            }
            if (before.bushes > 0.001) != (pose.bushes > 0.001) {
                out.append((t, pose.bushes > 0.001 ? "bushes appear" : "bushes gone"))
            }
            if (before.grindSparks > 0.001) != (pose.grindSparks > 0.001) {
                out.append((t, pose.grindSparks > 0.001 ? "sparks alight" : "sparks die"))
            }
            if (before.boardFire > 0.001) != (pose.boardFire > 0.001) {
                out.append((t, pose.boardFire > 0.001 ? "THE BOARD CATCHES FIRE"
                                                      : "the fire is out"))
            }
            if rung(pose) != rung(before) {
                out.append((t, "score rung \(rung(pose)) of 5"))
            }
            if before.prop != pose.prop {
                out.append((t, "board → \(pose.prop.rawValue)"))
            }
            if (beforeTint == nil) != (tint == nil) {
                out.append((t, tint == nil ? "the colour leaves" : "the first colour"))
            }
            if (before.deckUnderfoot > 0.5) != (pose.deckUnderfoot > 0.5) {
                out.append((t, pose.deckUnderfoot > 0.5 ? "the resting deck draws"
                                                        : "the resting deck is covered"))
            }
            index += 1
        }
        return out
    }

    /// The review index: every boundary and every rig event in reel time. The
    /// reel carries no type, so this is where the operator reads what they are
    /// looking at — and it is the hand-off to Figma.
    static func writeSidecar(_ reel: Reel, to url: URL) -> Bool {
        var lines = ["# \(reel.name) — \(String(format: "%.1f", reel.seconds))s, "
                     + "\(reel.shots.count) shots, no type",
                     "# seconds\tkind\twhat"]
        var rows: [(Double, String, String)] = []
        for (index, shot) in reel.shots.enumerated() {
            rows.append((shot.start, "shot \(index + 1)",
                         "\(shot.groundName) · \(shot.stop) · \(String(format: "%.1f", shot.seconds))s · \(shot.note)"))
        }
        for (t, what) in events(reel) { rows.append((t, "event", what)) }
        for (t, kind, what) in rows.sorted(by: { $0.0 < $1.0 }) {
            lines.append("\(String(format: "%.3f", t))\t\(kind)\t\(what)")
        }
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            FileHandle.standardError.write(Data("could not write \(url.path)\n".utf8))
            return false
        }
    }

    /// 🔎 **The ledge's extent, as stills.** At 44 cells it is half again as
    /// long as the 32-cell buffer, so unlike the 28-cell first cut it is NEVER
    /// wholly on screen — which is the point of "longer", and also the reason
    /// motion cannot show it. The best a still can do is the moment its right
    /// end first comes inside the grid, when it runs from the last column clear
    /// off the left edge; the other two are the lock and the end of the drift,
    /// so the sheet reads as one block travelling rather than three fragments.
    nonisolated static let fullExtentFrames = [1.70, 2.50, 5.00]

    static func renderLedgeSheet(to url: URL) -> Bool {
        let stance = skateStance
        let side: CGFloat = 448
        let sheet = HStack(spacing: 16) {
            ForEach(fullExtentFrames, id: \.self) { local in
                ZStack {
                    MarketingPalette.cream
                    PixelCanvasView(
                        buffer: CrabRig.render(
                            CrabAnimator.flourishPose(.backSmith, at: local, base: stance),
                            costume: .skater),
                        inkOverrides: CostumeStyle.blendedOverrides(
                            from: .skater, to: .skater, u: 1),
                        seamBleed: 0)
                        .frame(width: side, height: side)
                        .offset(y: -14)
                }
                .frame(width: side, height: side)
            }
        }
        .padding(16)
        .background(MarketingPalette.cream)

        guard let image = SpriteImage.cgImage(of: sheet, scale: 1, isOpaque: true),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
