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
/// against this source. Three of its findings are load-bearing here and are
/// marked 🔎 where they land.
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
    /// Ledge line 356 / 352 / 354.
    static let square = Format(
        name: "square", canvas: CGSize(width: 512, height: 512),
        sides: [.small: 320, .mid: 384, .large: 448],
        dy: [.small: 20, .mid: 0, .large: -14])

    /// 640×360, sprite 224 / 256 / 320 → 7 / 8 / 10 points a cell. The large
    /// stop is capped by the 360pt height, not by taste.
    /// Ledge line 250 / 252 / 250.
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
    /// The MP4's rate. 🔎 The review rate: the ledge's entry peaks near 35
    /// cells a second, which is 1.16 cells a frame at 30 and 1.74 at 20 — and
    /// a scrolling pixel element only reads as travel below about one cell a
    /// frame. The arrival is honest in the video and impressionistic in the
    /// GIF, and the hand-off says so.
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

    /// A whole reel: its shots, its pose source, and the events worth indexing.
    struct Reel {
        let name: String
        let shots: [Shot]
        /// Reel time → the pose to draw and the body tint to draw it with.
        let pose: @MainActor (Double) -> (CrabPose, Color?)
        /// Reel-time events for the sidecar, beyond the shot boundaries.
        let events: [(Double, String)]

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
    /// a held one-pixel downward dart. Frozen into a base and held for two
    /// seconds, that is a poster frame of a crab staring at his feet. The drip
    /// renderer inherits the same instant but hides it behind a 0.6s lead.
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

    /// Pass A starts at reel 2.0, pass B at reel 8.0 — the same 5.4s trick
    /// twice, from the same base at the same local instants, so the two passes
    /// are **bit-identical in the 32×32 buffer**. The operator's A/B is exact,
    /// not approximate. Past the trick's duration `flourishPose` returns the
    /// base on its own, so the trailing rest costs no special case.
    static func skatePose(reel: Double) -> (CrabPose, Color?) {
        let stance = skateStance
        guard reel >= 2.0 else { return (stance, nil) }
        let local = reel - (reel < 8.0 ? 2.0 : 8.0)
        return (CrabAnimator.flourishPose(.backSmith, at: local, base: stance), nil)
    }

    static let skateReel = Reel(
        name: "skate-ledge",
        shots: [
            Shot(0.0, 2.0, MarketingPalette.gold, "gold", .large,
                 "the empty stage — the poster, and the control frame for shot 3"),
            Shot(2.0, 6.0, MarketingPalette.cream, "cream", .small,
                 "the reference take, uncut: both rates over their whole extent"),
            Shot(8.0, 1.5, MarketingPalette.gold, "gold", .large,
                 "the arrival magnified, into the frame shot 1 memorised"),
            Shot(9.5, 3.0, MarketingPalette.cream, "cream", .mid,
                 "the lock and the parallax — 14 ledge cells against 7 bush cells, 2:1"),
            Shot(12.5, 1.5, MarketingPalette.gold, "gold", .large,
                 "the kickflip out and the exit; sparks are dead, so gold is legal"),
        ],
        pose: skatePose,
        events: [
            (2.015, "pass A · bushes appear"), (2.114, "pass A · first ledge pixel"),
            (2.648, "pass A · pop"), (3.728, "pass A · LOCK, bushes at home columns"),
            (3.806, "pass A · sparks alight"), (3.910, "pass A · nose fully dipped"),
            (4.160, "pass A · steeze full"), (6.104, "pass A · steeze tucked"),
            (6.134, "pass A · sparks die"), (6.212, "pass A · grind ends"),
            (6.483, "pass A · kickflip apex"), (6.786, "pass A · ledge gone"),
            (6.860, "pass A · stomp"), (7.076, "pass A · bushes gone"),
            (9.728, "pass B · LOCK"), (9.806, "pass B · sparks alight"),
            (11.000, "pass B · ledge right end passes column 13"),
            (12.134, "pass B · sparks die"), (12.212, "pass B · grind ends"),
            (12.786, "pass B · ledge gone"), (12.860, "pass B · stomp"),
            (13.076, "pass B · bushes gone"),
        ])

    // MARK: - Reel two: the combo

    /// The ride is 19.3s and the ceiling is 15, so 4.8s comes out in three
    /// cuts: a 0.2s head trim inside the ollie's load plateau (pose-identical),
    /// **the nollie beat entire**, and a 1.0s tail trim.
    ///
    /// The nollie is the cheapest possible whole-beat excision: across the five
    /// landings the ribbon grows 0→2, 2→5, 5→7, **7→8**, 8→8, and the nollie's
    /// is the only contribution that is a single capped cell.
    nonisolated static let seam = 8.0
    nonisolated static func ride(reel: Double) -> Double {
        reel < seam ? reel + 0.2 : reel + 3.8
    }

    /// 🔎 The decorative phases run on the REEL clock, not the ride's. The
    /// score is left alone — it is the thing being reviewed — but the ribbon's
    /// wave and the fire's flicker are put on reel time so both stay
    /// continuous across the seam (a 3.6s skip is a whole number of neither
    /// period). What the cut then costs, visibly, is one ribbon cell and 0.18
    /// of tint amount: "a landing happened off-screen", which is true.
    static func rainbowPose(reel: Double) -> (CrabPose, Color?) {
        guard var pose = CrabAnimator.comboRide(local: ride(reel: reel),
                                                wardrobe: .init(current: .skater))
        else { return (skateStance, nil) }
        pose.comboPhase = reel
        return (pose, CrabView.comboTint(t: reel, combo: pose.combo))
    }

    static let rainbowReel = Reel(
        name: "rainbow-combo",
        shots: [
            Shot(0.0, 2.0, MarketingPalette.gold, "gold", .small,
                 "the zero — score exactly 0, both draw gates shut, no colour anywhere"),
            Shot(2.0, 1.5, MarketingPalette.cream, "cream", .large,
                 "the birth of the colour, largest stop, quietest plate"),
            Shot(3.5, 2.5, MarketingPalette.gold, "gold", .small,
                 "the ribbon's LENGTH growing 2 → 5 through a whole bob arc"),
            Shot(6.0, 2.0, MarketingPalette.cream, "cream", .mid,
                 "the staircase's last rungs at counting magnification"),
            Shot(8.0, 1.5, MarketingPalette.cream, "cream", .small, cellsRight: 2,
                 "the seam — lands on a bare plate, then the ledge arrives"),
            Shot(9.5, 3.5, MarketingPalette.cream, "cream", .mid, cellsRight: -2,
                 "the climax uncut: lock, grind, kickflip out, the board catching fire"),
            Shot(13.0, 1.5, MarketingPalette.cream, "cream", .large,
                 "the payoff — the burning board lands and settles, nothing competing"),
        ],
        pose: rainbowPose,
        events: [
            (2.520, "first colour · the shell steps grape → terracotta in one frame"),
            (2.661, "ribbon cell 1"), (2.800, "ribbon cell 2"),
            (5.432, "ribbon cell 3"), (5.578, "ribbon cell 4"), (5.707, "ribbon cell 5"),
            (7.788, "ribbon cell 6"), (7.882, "ribbon cell 7 · length caps here"),
            (8.000, "THE SEAM · the nollie beat is skipped"),
            (8.015, "bushes appear"), (8.114, "first ledge pixel"),
            (9.728, "the lock"), (9.806, "sparks alight"),
            (10.110, "nose two rows down"), (10.160, "steeze full"),
            (11.780, "steeze tucks"), (12.134, "sparks die"), (12.212, "grind ends"),
            (12.605, "THE BOARD CATCHES FIRE"), (12.786, "ledge gone"),
            (12.860, "stomp"), (13.064, "bushes gone"),
            (13.400, "full score"), (13.500, "the resting deck draws"),
        ])

    static let reels = [skateReel, rainbowReel]

    // MARK: - Composition

    /// The minimal scene: a flat opaque ground and the sprite. The drip
    /// renderer's shape, because `SizzleRenderer`'s own pet-and-layout
    /// helpers are private and a demo reel needs none of what they add.
    @ViewBuilder
    static func scene(_ pose: CrabPose, tint: Color?, shot: Shot,
                      format: Format) -> some View {
        let side = format.side(shot.stop)
        ZStack {
            shot.ground
            PixelCanvasView(buffer: CrabRig.render(pose, costume: .skater),
                            bodyTint: tint,
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
        for (t, what) in reel.events { rows.append((t, "event", what)) }
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

    /// 🔎 **"Twice the length" is not reviewable from motion, so here it is as
    /// stills.** The ledge is 28 cells in a 32-cell buffer: it is entirely on
    /// the grid for 0.167s of its 5.4s life, and through the grind — the part
    /// anyone actually stares at — its left end is permanently outside the
    /// buffer, showing 20 cells falling to 14. These are the only three frames
    /// at 30fps with all 28 cells present.
    nonisolated static let fullExtentFrames = [1.100, 1.170, 1.240]

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
