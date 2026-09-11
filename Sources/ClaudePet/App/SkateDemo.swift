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

    /// 🔎 **ONE CUT, RENDERED TWICE.** The operator asked for the same clip
    /// with the rainbow trail and without it — a real A/B, where the only
    /// difference between the two files is the thing being judged.
    ///
    /// So both versions come from the SAME source: a window of a real scoring
    /// ride. The plain one is that ride with the score's decorations zeroed —
    /// no ribbon, no shell tint, no burning board — and nothing else touched.
    /// Frame for frame, beat for beat, magnification for magnification, the
    /// two are identical apart from the score. Building the plain one from
    /// `flourishPose` instead would have been easier and would have made it a
    /// different take rather than the same one.
    nonisolated static let rideOpensAt = 11.8
    nonisolated static let rideClosesAt = 19.3
    /// Half a second of frozen stance in front of it, so the poster frame is a
    /// crab standing rather than a crab mid-crouch.
    nonisolated static let head = 0.5
    nonisolated static func ride(reel: Double) -> Double { reel - head + rideOpensAt }

    /// The ride's own pose at a reel instant, or the stance before it starts.
    static func ridePose(reel: Double) -> CrabPose? {
        guard reel >= head else { return nil }
        return CrabAnimator.comboRide(local: ride(reel: reel),
                                      wardrobe: .init(current: .skater))
    }

    /// 🌈 With the trail: the ride exactly as the app runs it.
    static func trailPose(reel: Double) -> (CrabPose, SpriteTint.Tint?) {
        guard var pose = ridePose(reel: reel) else { return (skateStance, nil) }
        // The ribbon's wave on the REEL clock, so it is continuous across a
        // cut; the score itself is left alone, because it is what is under
        // review.
        pose.comboPhase = reel
        return (pose, CrabView.comboTint(t: reel, combo: pose.combo, costume: .skater))
    }

    /// 🛹 Without it: the same ride with the score's decorations off. `combo`
    /// drives the ribbon and the tint, `boardFire` the burning board — those
    /// three are what "rainbow mode" means, and they are the only things this
    /// version changes.
    static func plainPose(reel: Double) -> (CrabPose, SpriteTint.Tint?) {
        guard var pose = ridePose(reel: reel) else { return (skateStance, nil) }
        pose.combo = 0
        pose.comboPhase = 0
        pose.boardFire = 0
        return (pose, nil)
    }

    /// The shot list, shared. Eight seconds, sixteen beats.
    ///
    /// Every plate is cream and every cut is carried by the magnification and
    /// the horizontal nudge instead. That is not a shortage of ideas: the
    /// trail version is at four rungs of score from its first frame, and the
    /// gold plate is illegal against a shell that bright — so a ground that
    /// changed between shots would change between the two VERSIONS too, and
    /// the A/B would stop being one.
    /// 🔎 Cut to the trick's own beats, and the sidecar is what caught it: a
    /// first pass put a boundary at 5.5s and captioned the shot after it "the
    /// far end arriving at his truck" — but that arrival IS the pop, at reel
    /// 5.41, so the caption described something the previous shot had already
    /// shown. A beat map that disagrees with its own reel is worse than none.
    static let shots = [
        Shot(0.0, 1.0, MarketingPalette.cream, "cream", .large,
             "the stance, then the roll-in — the ledge still off to his right"),
        Shot(1.0, 2.0, MarketingPalette.cream, "cream", .small, cellsRight: 2,
             "the ledge arrives and he pops ONTO it, at the widest view the ground has"),
        Shot(3.0, 1.5, MarketingPalette.cream, "cream", .mid, cellsRight: -2,
             "the grind — the hedge and the floor carrying the speed the slab cannot show"),
        Shot(4.5, 2.0, MarketingPalette.cream, "cream", .large, cellsRight: 2,
             "the far end reaches his truck and he pops OFF the end of it, magnified"),
        Shot(6.5, 1.5, MarketingPalette.cream, "cream", .small,
             "the kickflip out, the stomp, and the settle"),
    ]

    static let plainReel = Reel(name: "backsmith-plain", shots: shots, pose: plainPose)
    static let trailReel = Reel(name: "backsmith-trail", shots: shots, pose: trailPose)
    /// 🎉 The same take again, with the room joining in. Same pose stream as the
    /// trail version — the party is entirely a layer behind and in front of it.
    static let partyReel = Reel(name: "backsmith-party", shots: shots, pose: trailPose)

    // MARK: - 🎉 The party

    /// 🔎 **THE LAYERS TAKE TURNS, and this envelope is how.**
    ///
    /// What changes across the reel is not how much is moving — it is WHICH SIDE
    /// OF THE SPRITE BOX it is on. Through the grind the sprite side is already
    /// carrying seven layers (the ledge, its crest, the hedge, the floor rush,
    /// the sparks, the ribbon and a colour-cycling shell), so the backdrop drops
    /// to its floor and stays out of the way. By the finale the ledge has gone
    /// (5.9), the hedge with it (6.7) and the sparks died at 5.4 — three things
    /// left — so the backdrop takes over.
    ///
    /// Nothing new arrives on a landing frame: the crest ignites WITH the sparks
    /// at the lock, which is the same physical event rather than a second one,
    /// and nothing at all enters at the stomp — the rings have been up since 5.4,
    /// so the cut at 6.5 reveals them rather than introducing them.
    nonisolated static let partyFloor = 0.25
    nonisolated static func partyLevel(reel: Double) -> Double {
        let up = Ease.smoothstep((reel - head) / 0.6)              // in with the ride
        let duck = Ease.smoothstep((reel - 2.6) / 0.4)             // out of the grind's way
        let back = Ease.smoothstep((reel - 5.4) / 0.6)             // and back for the finale
        return up * (1 - duck * (1 - partyFloor) + back * (1 - partyFloor))
    }

    /// 🔎 **THE LEDGE'S CREST — a view-side overlay, masked to the ledge's own
    /// cells, and NOT a recolour inside the buffer.**
    ///
    /// `.slate` and `.steel` deliberately do not consult `inkOverrides`;
    /// `.slate`'s own comment says a case with no override lookup CANNOT be
    /// recoloured by a wardrobe, and that is the point of it. Appending inks for
    /// a ramp would be new cases for one review clip — and any of them landing
    /// in rows 25–28 empties `BackSmithTests.ledgeCells`, which classifies by
    /// ink, taking every bookend pin with it.
    ///
    /// So it rides ABOVE the sprite on the ledge's steel top row only, on the
    /// hedge's own twelve-cell world pitch so the ground keeps one unit. The
    /// dark slab underneath is untouched: at a luminance near 25 it is the
    /// darkest large area in frame and the thing his silhouette reads against.
    /// The plate's hue, exposed for the pins — the complement claim is the one
    /// thing in the party that keeps him legible, so it is measured rather than
    /// asserted.
    nonisolated static func plateHueForTests(_ t: Double) -> Double { PartyGround.plateHue(t) }

    nonisolated static let crestRow = 24
    nonisolated static let crestPitch = 12
    /// Every visible column of the ledge's top row, with the hue and the
    /// STRENGTH of the crest passing over it.
    ///
    /// 🔎 A gradient, not a dotted line. The first cut lit one column in twelve
    /// and nothing else, which at a cell a column is three lit cells on a
    /// thirty-two cell row — invisible at any size the clip is watched at. Every
    /// column gets a strength now, on a raised cosine over the same twelve-cell
    /// world pitch, so what travels along the edge is a band with a bright
    /// middle and a fade either side. That is what "shimmer" means at this
    /// scale, and it is still whole cells: only the alpha varies.
    nonisolated static func crest(travel: Double, t: Double) -> [(x: Int, hue: Double, level: Double)] {
        let right = CrabRig.ledgeRightEnd(travel: travel)
        let left = right - (CrabRig.ledgeLength - 1)
        guard right >= 0, left <= PixelBuffer.side - 1 else { return [] }
        let scroll = t * 9
        var out: [(Int, Double, Double)] = []
        for x in max(0, left)...min(PixelBuffer.side - 1, right) {
            // The WORLD column, so the crest travels with the ground rather
            // than with the frame — it is a highlight on the ledge, not a
            // wiper across the screen.
            let world = Double(CrabRig.ledgeTravelled(travel: travel) + x)
            let phase = (world + scroll) / Double(crestPitch)
            let level = max(0, cos(2 * .pi * (phase - phase.rounded(.down)) - .pi))
            guard level > 0.02 else { continue }
            out.append((x, SpriteTint.neutralHue(phase.rounded(.down) * 0.17), level))
        }
        return out
    }

    static let reels = [plainReel, trailReel, partyReel]

    // MARK: - Composition

    /// The minimal scene: a flat opaque ground and the sprite. The drip
    /// renderer's shape, because `SizzleRenderer`'s own pet-and-layout
    /// helpers are private and a demo reel needs none of what they add.
    @ViewBuilder
    static func scene(_ pose: CrabPose, tint: SpriteTint.Tint?, shot: Shot,
                      format: Format, party: Double = 0, reel: Double = 0) -> some View {
        let side = format.side(shot.stop)
        let cell = format.cell(shot.stop)
        ZStack {
            shot.ground
            if party > 0.001 {
                Canvas { context, size in
                    PartyGround.draw(in: &context, size: size, t: reel,
                                     party: party, cell: cell)
                }
                .frame(width: format.canvas.width, height: format.canvas.height)
            }
            PixelCanvasView(buffer: CrabRig.render(pose, costume: .skater),
                            bodyTint: tint?.body,
                            bodyShadeTint: tint?.shade,
                            inkOverrides: CostumeStyle.blendedOverrides(
                                from: .skater, to: .skater, u: 1),
                            seamBleed: 0)
                .frame(width: side, height: side)
                .offset(x: CGFloat(shot.cellsRight) * format.cell(shot.stop),
                        y: format.offsetY(shot.stop))
            if party > 0.001 {
                Canvas { context, size in
                    let travel = ridePose(reel: reel)?.ledge ?? 0
                    for lit in crest(travel: travel, t: reel) {
                        let rgb = SpriteTint.rgb(hue: lit.hue, saturation: 0.75, brightness: 1.0)
                        let box = CGRect(x: CGFloat(lit.x) * cell,
                                         y: CGFloat(crestRow) * cell,
                                         width: cell, height: cell)
                        context.fill(Path(box),
                                     with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)
                                        // 🔎 NOT ducked with the backdrop. The
                                        // crest belongs to the LEDGE, which is
                                        // on the sprite side of the frame — the
                                        // turn-taking envelope exists to keep
                                        // the ROOM out of the grind's way, and
                                        // wiring the crest to it dimmed the
                                        // shimmer to a fifth exactly while the
                                        // ledge was on screen, which is the only
                                        // time it can be seen at all.
                                        .opacity(0.9 * lit.level)))
                    }
                }
                .frame(width: side, height: side)
                .offset(x: CGFloat(shot.cellsRight) * cell, y: format.offsetY(shot.stop))
            }
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
        let party = reel.name.hasSuffix("party") ? partyLevel(reel: t) : 0
        return SpriteImage.cgImage(of: scene(pose, tint: tint, shot: shot, format: format,
                                             party: party, reel: t),
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
    nonisolated static let fullExtentFrames = [4.05, 4.50, 4.90]

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
