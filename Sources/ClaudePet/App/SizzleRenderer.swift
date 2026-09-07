import SwiftUI

/// Renders the sizzle reel — `SizzleScript`'s chapters, in every cut.
///
/// The scenes bypass `CrabView` and drive `CrabRig` with the pure functions,
/// exactly as `ReelRenderer` does: every effect the live pet earns from
/// latches and clocks is reconstructed here from a deterministic chapter
/// clock. No `Date()`, no randomness, `Backdrop(phase: 0)` — the same
/// invocation produces the same bytes.
///
/// The camera is a per-frame sprite side plus a whole-point offset — never
/// `.scaleEffect` on the sprite (a scaled CTM lands the canvas cells on
/// fractional pixels and antialiases the one thing that must stay hard).
/// `PixelCanvasView` is vector, so rebuilding at the shot's side renders
/// crisp at any size; dwells hold constant sides, moves are fast enough
/// (< 0.5s) that the cell-width reshuffle is invisible.
@MainActor
enum SizzleRenderer {

    /// Per-cut layout: sprite, camera stops, type roles, grounds — plus the
    /// per-frame dressing `frameImage` sets before handing it to a scene.
    struct Format {
        let spriteSide: CGFloat
        /// Camera stops. Rest is `spriteSide`; every stop is even-celled
        /// (side × scale % 32 == 0) so dwells never shimmer. The punch is two
        /// grid steps up from rest (224 → 288 — a one-step punch to 256 read
        /// as breathing, not a decision); the hero stop is the finale's own
        /// and the largest in the cut, because the star is the biggest thing.
        let punchSide: CGFloat
        let heroSide: CGFloat
        let duoSide: CGFloat
        /// The three type roles, in whole sprite cells: tag 2, caption 3,
        /// wordmark 5 — 14 / 21 / 35 on a 7pt cell. Sizes off the cell grid
        /// float over the pixel art.
        let wordmark: CGFloat
        let caption: CGFloat
        let tag: CGFloat
        let vertical: Bool
        /// GIF cuts skip the finale's radial bloom — a smooth ramp would
        /// smuggle hundreds of colours into the global palette.
        let gifSafe: Bool
        /// Camera moves and frame-space furniture (cards, roster) ride only
        /// the rich cuts: the README pair stays static so the GIF keeps its
        /// palette, its size and its loop seam.
        let rich: Bool
        /// Chroma plates: cameras run, everything translucent or typographic
        /// is suppressed, the field is the dark-red key field.
        let plate: Bool
        /// The cut's language and its volume — the meme family shouts.
        let captions: [SizzleScript.Chapter: SizzleScript.Caption]
        let captionScale: CGFloat
        /// Title cards, captions, tags. Off for plates (they fringe keys)
        /// and showcase cuts (the operator's ruling: just show the pet).
        let type: Bool
        /// Cards and the roster. Off wherever type is off — they are text.
        let furniture: Bool
        /// The cut's flat grounds per chapter and its montage running order.
        let grounds: [SizzleScript.Chapter: SizzleScript.Ground]
        let looks: [SizzleScript.Look]
        /// The bottom margin under the caption slot: three cells, or the
        /// platform's UI band on 9:16 (the bottom quarter carries the
        /// player's own chrome, and type under it is type nobody sees).
        let bottomMargin: CGFloat
        /// One output frame in seconds — the unit every eased edge is
        /// measured in. Nothing eases in fewer than three of these.
        let frame: Double

        /// Per-frame dressing, set by `frameImage`: the ink that reads on
        /// this chapter's ground, the luminance bridge, the segment's
        /// compression factor.
        var ink: Color = Palette.kraft
        var flash: Double = 0
        var scaleFactor: Double = 1

        /// One sprite cell in points at the rest stop — the grid every reel
        /// element sits on.
        var cell: CGFloat { spriteSide / CGFloat(PixelBuffer.side) }
        /// The caption slot's fixed height: two lines, so a one-line caption
        /// and a two-line one leave the sprite exactly where it was, and a
        /// chapter with no caption at all leaves it there too.
        var captionSlot: CGFloat { (caption * captionScale * 1.25 * 2).rounded() }
    }

    static func format(for cut: SizzleScript.Cut) -> Format {
        let vertical = cut.canvas.width < cut.canvas.height
        switch cut.family {
        case .master, .meme, .plate, .showcase:
            // Every side is a whole number of cells at its cut's scale — 224,
            // 288 and 320 × 3 are all multiples of 32. The vertical rest sat
            // at 264 once (8.25 points per cell: every fourth column an eighth
            // wider) and then at 256, one grid step under its 288 punch, so
            // the punch read as breathing. Both aspects rest at 224 now and
            // punch two steps; the vertical frame is taller, not larger.
            let quiet = cut.family == .plate || cut.family == .showcase
            return Format(spriteSide: 224, punchSide: 288, heroSide: 320, duoSide: 160,
                          wordmark: 35, caption: 21, tag: 14,
                          vertical: vertical, gifSafe: false, rich: true,
                          plate: cut.family == .plate,
                          // A PLATE keeps the master's captions and hides them:
                          // an empty slot is a different height than a real
                          // line, and that moves the sprite — the one thing a
                          // plate may not do, since it exists to be keyed
                          // against the titled master frame for frame. The
                          // showcase really has no text and is keyed against
                          // nothing, so it alone empties.
                          captions: cut.family == .meme ? SizzleScript.memeCaptions
                              : cut.family == .showcase ? [:] : SizzleScript.captions,
                          // The meme shouts at five cells (35pt), still on the grid.
                          captionScale: cut.family == .meme ? 5.0 / 3.0 : 1,
                          type: !quiet,
                          furniture: !quiet,
                          grounds: cut.grounds, looks: cut.looks,
                          // Three cells, or the platform band rounded UP to
                          // whole cells (23 × 7 = 161 on the 640pt canvas).
                          bottomMargin: vertical
                              ? (cut.canvas.height * 0.25 / 7).rounded(.up) * 7 : 21,
                          frame: 1.0 / Double(cut.fps))
        case .readme:
            return Format(spriteSide: 128, punchSide: 128, heroSide: 128,
                          duoSide: 96, wordmark: 20, caption: 12, tag: 8,
                          vertical: false, gifSafe: cut.fps == 10, rich: false,
                          plate: false, captions: SizzleScript.readmeCaptions, captionScale: 1,
                          type: true, furniture: false,
                          grounds: cut.grounds, looks: cut.looks,
                          bottomMargin: 12, frame: 1.0 / Double(cut.fps))
        }
    }

    // MARK: - The camera

    /// One frame's camera: the sprite side, a whole-point offset, and how
    /// present the (constant-size) bubble is — it fades through every zoom,
    /// or it would read as detaching from a growing head.
    struct Shot {
        var side: CGFloat
        var offset: CGPoint = .zero
        var bubbleFade: Double = 1
    }

    /// Pure in (chapter, localT, fmt): plates match titled framing
    /// frame-for-frame, and the meme cut's windows enter these curves
    /// mid-move. Every master segment plays at 1×, so a move authored here
    /// is the move the viewer sees.
    static func shot(for chapter: SizzleScript.Chapter, t: Double,
                     fmt: Format) -> Shot {
        var shot = Shot(side: fmt.spriteSide)
        guard fmt.rich else { return shot }

        switch chapter {
        case .wake:
            // The rise-in: he steps up into frame in whole-pixel increments.
            shot.offset.y = ((1 - Ease.smoothstep(min(1, t / 0.7))) * 28).rounded()

        case .mirror:
            // The face punch rides the thinking beat: two grid steps up over
            // [0.6, 2.15], the dots fading with the zoom. The master's window
            // enters at 1.0, mid-punch — so frame 0 IS the face, which is the
            // poster frame socials thumbnail. Then the roster beat slides him
            // aside: a reveal, not a punch, on slow 0.9s edges, or ninety
            // points in a third of a second reads as a yank.
            let inU = Ease.smoothstep(min(1, max(0, (t - 0.6) / 0.25)))
            let outU = Ease.smoothstep(min(1, max(0, (t - 1.8) / 0.35)))
            let zoom = inU * (1 - outU)
            shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * zoom
            shot.offset.y = (16 * zoom).rounded()
            shot.bubbleFade = 1 - zoom
            // The roster is a landscape idea: a 270pt panel beside a 224pt
            // crab has no room on a 360pt-wide frame without landing on the
            // caption, so the portrait cut carries the session signal in the
            // bubble and its tool badge alone, and does not slide.
            if !fmt.vertical {
                let rosterU = Ease.window(t - 2.5, duration: 2.5, edge: 0.9)
                shot.offset.x -= (60 * rosterU).rounded()
            }

        case .glyphs:
            // ONE punch in the chapter, on the merged PR — the beat that
            // earns it. Four identical punches at 0.7s was a drum machine,
            // and it hid the four different gestures under it.
            let beat = SizzleScript.glyphBeat(at: t)
            if beat.index == 1 {
                let env = Ease.window(beat.into, duration: beat.seconds, edge: 0.2)
                shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * env
            }

        case .cook:
            // The 8-bit shake, gated to the heat cascade's first second: a
            // 15Hz tick of ±1-point jitter from the same splitmix64 hash
            // everything else schedules with. Single-pixel steps are the
            // sanctioned no-snap exemption; amp is zero by local 4.0 so the
            // breath opens on a still frame.
            let amp = Ease.window(t - 3.0, duration: 1.0, edge: 0.3)
            let n = Int(t * 15)
            let dx = Double(Int(CrabAnimator.noise(n &* 31 &+ 7) * 3) - 1) * amp
            let dy = Double(Int(CrabAnimator.noise(n &* 53 &+ 11) * 3) - 1) * amp
            shot.offset = CGPoint(x: dx.rounded(), y: dy.rounded())

        case .breath:
            break   // the held breath: rest side, zero offset, by rule

        case .finale:
            // Hold wide; punch to the HERO stop with the flash — the largest
            // stop in the cut, because the payoff is the biggest thing in the
            // reel; settle back for the badge.
            let inU = Ease.smoothstep(min(1, max(0, (t - 1.2) / 0.28)))
            let outU = Ease.smoothstep(min(1, max(0, (t - 3.8) / 0.5)))
            let zoom = inU * (1 - outU)
            shot.side = fmt.spriteSide + (fmt.heroSide - fmt.spriteSide) * zoom

        case .montage:
            break   // a montage cuts on content; the camera holds

        case .duet:
            break   // one second, two crabs, one pounce — the frame holds

        case .outro:
            break   // the goodnight stays locked
        }
        return shot
    }

    // MARK: - Entry

    static func render(to directory: String) -> Bool {
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for cut in SizzleScript.cuts {
            let url = dir.appendingPathComponent(cut.name)
            let ok: Bool
            if cut.name.hasSuffix(".gif") {
                var frames: [CGImage] = []
                for index in 0..<cut.frameCount {
                    guard let image = frameImage(cut: cut, index: index) else { return false }
                    frames.append(image)
                }
                ok = GifRenderer.encode(frames, to: url, frameDelay: 1.0 / Double(cut.fps))
            } else {
                ok = VideoWriter.write(to: url, fps: cut.fps, frameCount: cut.frameCount) {
                    frameImage(cut: cut, index: $0)
                }
            }
            guard ok else {
                FileHandle.standardError.write(Data("sizzle: \(cut.name) failed\n".utf8))
                return false
            }
            writeBeatMap(for: cut, beside: url)
            print("wrote \(url.path)")
        }
        return true
    }

    /// The editor's beat sidecar, named after the cut minus its extension.
    private static func writeBeatMap(for cut: SizzleScript.Cut, beside url: URL) {
        let base = url.deletingPathExtension()
        let sidecar = base.appendingPathExtension("beats.txt")
        SpriteImage.write(Data(SizzleScript.beatMap(for: cut).utf8), to: sidecar)
    }

    /// The plates: each frame lands twice — a lossless PNG (the ONLY keying
    /// source; the preview's H.264 is 4:2:0 and smears the green boundary,
    /// it exists purely to eyeball sync) and the preview stream. One pass,
    /// one frame in flight.
    static func renderPlates(to directory: String) -> Bool {
        let dir = URL(fileURLWithPath: directory)
        for cut in SizzleScript.plates {
            let seqDir = dir.appendingPathComponent(cut.name)
            try? FileManager.default.createDirectory(at: seqDir, withIntermediateDirectories: true)
            let preview = dir.appendingPathComponent("\(cut.name)-preview.mp4")
            let ok = VideoWriter.write(to: preview, fps: cut.fps, frameCount: cut.frameCount) { index in
                guard let image = frameImage(cut: cut, index: index) else { return nil }
                let rep = NSBitmapImageRep(cgImage: image)
                guard let png = rep.representation(using: .png, properties: [:]),
                      SpriteImage.write(png, to: seqDir.appendingPathComponent(
                          String(format: "frame-%04d.png", index)))
                else { return nil }
                return image
            }
            guard ok else {
                FileHandle.standardError.write(Data("plates: \(cut.name) failed\n".utf8))
                return false
            }
            writeBeatMap(for: cut, beside: dir.appendingPathComponent(cut.name))
            print("wrote \(seqDir.path) (+preview)")
        }
        return true
    }

    /// Test seam: one frame of a cut, exactly as the encoders receive it.
    static func testFrame(cut: SizzleScript.Cut, index: Int) -> CGImage? {
        frameImage(cut: cut, index: index)
    }

    /// Seams for the plate-registration test: the two type views, so their
    /// geometry can be measured without rendering a whole 1920×1080 frame.
    static func captionProbe(_ text: String, fmt: Format) -> AnyView {
        captionText(text, fmt: fmt)
    }

    static func titleProbe(fmt: Format) -> AnyView {
        titleCard(nil, sub: "probe", fmt: fmt)
    }

    // NOTE: deliberately no `.clipped()` on the frame — ImageRenderer already
    // crops at bitmap bounds, and adding the modifier made same-frame renders
    // byte-UNSTABLE over the glow's antialiased ring strokes (measured: the
    // finale frame differed run-to-run with it, identical without). The
    // determinism test is the guard.
    private static func frameImage(cut: SizzleScript.Cut, index: Int) -> CGImage? {
        let t = Double(index) / Double(cut.fps)
        guard let cue = SizzleScript.resolve(cut, at: t) else { return nil }
        var fmt = format(for: cut)
        fmt.flash = matchCutFlash(cut: cut, at: t, fmt: fmt)
        fmt.scaleFactor = cue.scaleFactor
        fmt.ink = fmt.grounds[cue.chapter]?.ink ?? Palette.kraft
        let scene = ZStack {
            scenery(for: cut, chapter: cue.chapter, t: t, fmt: fmt)
            chapterScene(cue.chapter, t: cue.localT, fmt: fmt)
            if fmt.flash > 0.001 {
                Color.white.opacity(fmt.flash)
            }
        }
        .frame(width: cut.canvas.width, height: cut.canvas.height)
        return SpriteImage.cgImage(of: scene, scale: cut.scale, isOpaque: true)
    }

    /// What stands behind him this frame. Plates override everything with
    /// the key field; a chapter with a flat ground stands on it — the room
    /// this chapter plays in, and a hard cut that changes the room is a cut
    /// the eye registers, where seven boundaries on one plate read as state
    /// toggles on a locked-off shot; the forest scrolls in CUT time, so its
    /// drift is continuous across chapter cuts.
    @ViewBuilder
    private static func scenery(for cut: SizzleScript.Cut, chapter: SizzleScript.Chapter,
                                t: Double, fmt: Format) -> some View {
        if fmt.plate {
            // The keying field: a single-entry ramp rides Backdrop's
            // whole-point, no-antialiasing path.
            Backdrop(style: .init(ramp: [Palette.keyField], foam: nil))
        } else if let ground = fmt.grounds[chapter] {
            ground.color
        } else {
            switch cut.scenery {
            case .ocean:
                Backdrop()
            case .gradient:
                // The one sanctioned gradient: showcase cuts are MP4-only,
                // where smooth ramps cost nothing. Dusk, indigo to ember.
                LinearGradient(colors: [Color(hex: 0x1B2447),
                                        Color(hex: 0x3E2C55),
                                        Color(hex: 0xB2694C)],
                               startPoint: .top, endPoint: .bottom)
            case .forest:
                ForestBackdrop(t: t)
            }
        }
    }

    /// The moving 8-bit forest: three parallax rows of pine silhouettes
    /// drifting at different speeds under a banded night sky with a static
    /// hash-dither starfield. Flat colours, whole-point geometry, pure in t.
    struct ForestBackdrop: View {
        let t: Double

        var body: some View {
            Canvas { context, size in
                Self.draw(in: &context, size: size, t: t)
            }
        }

        static func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
            // The sky: three flat bands, light to dark downward.
            let skyBands: [(Color, ClosedRange<Double>)] = [
                (Color(hex: 0x18294A), 0.0...0.28),
                (Color(hex: 0x122040), 0.28...0.52),
                (Color(hex: 0x0D1830), 0.52...0.70),
            ]
            for (color, range) in skyBands {
                // Spelled out in explicitly-typed steps rather than one nested
                // expression. `CGFloat` and `Double` are the same type on this
                // platform, so mixing them inside a four-argument initialiser
                // is legal — but it leaves the operators overloaded, and Swift
                // 6.1 gives up on the resulting expression as ambiguous where
                // 6.3 resolves it. CI runs 6.1; the desk runs 6.3. Naming the
                // edges also says what the band IS, which the nested form did
                // not: top edge, bottom edge, one pixel of overlap so adjacent
                // bands cannot leave a seam after rounding.
                let top: CGFloat = (size.height * range.lowerBound).rounded()
                let bottom: CGFloat = (size.height * range.upperBound).rounded()
                let band = CGRect(x: 0, y: top, width: size.width, height: bottom - top + 1)
                context.fill(Path(band), with: .color(color))
            }
            // Static stars: splitmix64 dither over an 8pt grid, top band only.
            for gy in 0..<Int(size.height * 0.26 / 8) {
                for gx in 0..<Int(size.width / 8) {
                    var v = UInt64(gx &+ gy &* 977) &* 0x9E37_79B9_7F4A_7C15
                    v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
                    if Double(v >> 11) / Double(1 << 53) < 0.045 {
                        context.fill(Path(CGRect(x: CGFloat(gx) * 8 + 3,
                                                 y: CGFloat(gy) * 8 + 2,
                                                 width: 2, height: 2)),
                                     with: .color(Color(hex: 0xC5D7E2).opacity(0.7)))
                    }
                }
            }
            // The ground.
            context.fill(Path(CGRect(x: 0, y: (size.height * 0.86).rounded(),
                                     width: size.width,
                                     height: size.height * 0.14 + 1)),
                         with: .color(Color(hex: 0x0A1812)))
            // Three pine rows, far to near, each drifting at its own speed.
            let layers: [(speed: Double, base: Double, height: Double, period: Double, color: Color)] = [
                (4, 0.70, 0.20, 96, Color(hex: 0x1A3A2F)),
                (10, 0.76, 0.24, 128, Color(hex: 0x142E24)),
                (18, 0.82, 0.28, 168, Color(hex: 0x0E211A)),
            ]
            for layer in layers {
                let shift = (t * layer.speed).truncatingRemainder(dividingBy: layer.period)
                let baseY = (size.height * layer.base).rounded()
                let treeH = (size.height * layer.height).rounded()
                var x = -shift.rounded() - layer.period
                while x < Double(size.width) + layer.period {
                    // One pine: three stacked, narrowing rects plus a trunk.
                    let w = layer.period * 0.5
                    for (step, frac) in [(0, 1.0), (1, 0.66), (2, 0.36)] {
                        let sw = (w * frac).rounded()
                        let sh = (treeH * 0.3).rounded()
                        context.fill(Path(CGRect(x: (x + (w - sw) / 2).rounded(),
                                                 y: baseY - sh * Double(step + 1),
                                                 width: sw, height: sh)),
                                     with: .color(layer.color))
                    }
                    context.fill(Path(CGRect(x: (x + w / 2 - 2).rounded(), y: baseY,
                                             width: 4, height: treeH * 0.12)),
                                 with: .color(layer.color))
                    x += layer.period
                }
            }
        }
    }

    /// The one motivated transition — and ONE flash, not two. The breath's
    /// last 0.12s attacks to full white, complete one frame before the cut;
    /// the finale holds that white through its first tap's plateau and then
    /// rides THAT tap's own decay down, so the bridge and the bang are a
    /// single event. Two white edges 0.2s apart would breach the
    /// photosensitivity spacing and read as a stutter; a 0.4s swell in was a
    /// fade, not a flash — light arrives faster than it leaves. Rich MP4 cuts
    /// only: a full-frame translucent white would fringe a key and explode a
    /// GIF's palette, and the readme twins must not diverge from each other.
    /// Every other chapter boundary stays a hard cut.
    static let bridgeAttack = 0.12

    static func matchCutFlash(cut: SizzleScript.Cut, at t: Double,
                              fmt: Format) -> Double {
        guard !fmt.plate, cut.family != .readme,
              let cue = SizzleScript.resolve(cut, at: t),
              let hood = SizzleScript.neighbors(in: cut, at: t) else { return 0 }
        let frame = 1.0 / Double(cut.fps)
        if cue.chapter == .breath, hood.next == .finale {
            // 1.0, not 0.9: nine tenths of white over a dark backdrop
            // composites to about #E5E5E5 — a grey, which is the same
            // washed-out complaint in a different room.
            return Ease.smoothstep((bridgeAttack + frame - hood.remaining) / bridgeAttack)
        }
        if cue.chapter == .finale, hood.previous == .breath {
            let tap = CrabView.celebrationFlashes[0]
            let plateauEnd = tap.at + CrabView.flashAttack + tap.hold
            if hood.into <= plateauEnd { return 1 }
            return 1 - Ease.smoothstep((hood.into - plateauEnd) / tap.decay)
        }
        return 0
    }

    // MARK: - Chapters

    @ViewBuilder
    private static func chapterScene(_ chapter: SizzleScript.Chapter, t: Double,
                                     fmt: Format) -> some View {
        switch chapter {
        case .wake: wakeScene(t: t, fmt: fmt)
        case .mirror: mirrorScene(t: t, fmt: fmt)
        case .glyphs: glyphsScene(t: t, fmt: fmt)
        case .cook: cookScene(t: t, fmt: fmt)
        case .breath: breathScene(t: t, fmt: fmt)
        case .finale: finaleScene(t: t, fmt: fmt)
        case .montage: montageScene(t: t, fmt: fmt)
        case .duet: duetScene(t: t, fmt: fmt)
        case .outro: outroScene(t: t, fmt: fmt)
        }
    }

    /// The wake: asleep under the wordmark, then up. No master plays it any
    /// more — product first, brand last — but the sequence tests still do.
    private static func wakeScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .wake, t: t, fmt: fmt)
        let card = Ease.smoothstep(min(1, t / typeAttack))
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, _ in
                                 var pose: CrabPose
                                 if t < 1.0 {
                                     pose = CrabAnimator.pose(mood: .sleeping, t: t)
                                 } else if t < 1.4 {
                                     let from = CrabAnimator.pose(mood: .sleeping, t: t)
                                     let to = CrabAnimator.pose(mood: .idle, t: t - 1.0, flourishes: false)
                                     pose = CrabPose.blend(from: from, to: to,
                                                           u: Ease.smoothstep((t - 1.0) / 0.4))
                                 } else {
                                     pose = CrabAnimator.pose(mood: .idle, t: t - 1.0, flourishes: false)
                                 }
                                 return sizzlePet(pose: pose, side: side, fmt: fmt)
                             },
                             top: titleCard(nil, sub: SizzleScript.tagline, fmt: fmt, star: true,
                                            presence: (card, card, card)),
                             bottom: emptySlot(fmt))
    }

    private static func mirrorScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .mirror, t: t, fmt: fmt)
        let rosterU = Ease.window(t - 2.5, duration: 2.5, edge: 0.35)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, fade in
                                 var pose: CrabPose
                                 var bubble: AnyView?
                                 if t < 2.0 {
                                     pose = CrabAnimator.pose(mood: .thinking, t: t)
                                     bubble = AnyView(ThoughtBubble(text: "", tool: nil, mood: .thinking,
                                                                    style: .dots, frozenTime: t))
                                 } else {
                                     let workT = SizzleScript.workBase + (t - 2.0)
                                     var working = CrabAnimator.pose(mood: .working, t: workT)
                                     CrabAnimator.applyPropDissolve(at: workT, to: &working)
                                     if t < 2.4 {
                                         let from = CrabAnimator.pose(mood: .thinking, t: t)
                                         working = CrabPose.blend(from: from, to: working,
                                                                  u: Ease.smoothstep((t - 2.0) / 0.4))
                                     }
                                     pose = working
                                     bubble = AnyView(ThoughtBubble(text: SizzleScript.mirrorBubble,
                                                                    tool: "Bash", mood: .working,
                                                                    style: .plain, frozenTime: t))
                                 }
                                 return sizzlePet(pose: pose, bubble: bubble,
                                                  bubbleOpacity: fade, side: side, fmt: fmt)
                             },
                             furniture: fmt.furniture && !fmt.vertical && rosterU > 0.001
                                 ? rosterCard(fmt: fmt, presence: rosterU) : nil,
                             bottom: captionSlot(for: .mirror, t: t, fmt: fmt))
    }

    private static func glyphsScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .glyphs, t: t, fmt: fmt)
        let beat = SizzleScript.glyphBeat(at: t)
        // Everything inside a beat is authored in BEAT-relative time, 0…1,
        // so a beat-and-a-half holds its gesture longer than a beat does and
        // nothing overruns into the next service. The 0.2 edges are three
        // frames on the shortest beat — the floor under every eased edge.
        let u = beat.into / beat.seconds
        let entry = SizzleScript.glyphBeats[beat.index]
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, fade in
                                 let workT = SizzleScript.workBase + 3.5 + t
                                 var pose = CrabAnimator.pose(mood: .working, t: workT)
                                 CrabAnimator.applyPropDissolve(at: workT, to: &pose)
                                 pose.serviceGlyph = entry.glyph
                                 pose.serviceGlyphVisibility = Ease.window(u, duration: 1.0, edge: 0.2)
                                 applyGlyphReaction(beat: beat.index, u: u, to: &pose)
                                 let bubble = AnyView(ThoughtBubble(text: entry.bubble, tool: "Bash",
                                                                    mood: .working, style: .plain,
                                                                    service: entry.glyph, frozenTime: t))
                                 return sizzlePet(pose: pose, bubble: bubble,
                                                  bubbleOpacity: fade, side: side, fmt: fmt)
                             },
                             furniture: fmt.furniture
                                 ? glyphFurniture(beat: beat.index, u: u, fmt: fmt) : nil,
                             bottom: captionSlot(for: .glyphs, t: t, fmt: fmt))
    }

    /// The cook as a held breath rather than a second rainbow: the fire prop,
    /// the heat cascade, the shake — and NO disco tint. The desktop fires it
    /// in this window; the reel keeps the body's colour for the finale, so
    /// the payoff is the first time he changes colour, not the second.
    private static func cookScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .cook, t: t, fmt: fmt)
        let cookT = SizzleScript.cookBase + t
        // The bubble leaves before the breath: gone by local 4.0.
        let bubbleOut = 1 - Ease.smoothstep((t - 3.6) / 0.4)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, fade in
                                 let pose = CrabAnimator.pose(mood: .cooking, t: cookT)
                                 let bubble = AnyView(ThoughtBubble(text: SizzleScript.cookBubble,
                                                                    tool: nil, mood: .cooking,
                                                                    style: .plain, frozenTime: t))
                                 return sizzlePet(pose: pose, bubble: bubble,
                                                  bubbleOpacity: fade * bubbleOut,
                                                  side: side, fmt: fmt)
                             },
                             bottom: captionSlot(for: .cook, t: t, fmt: fmt))
    }

    /// The stopdown: him at rest on the dark ground, no bubble, no type, no
    /// tint, no furniture — half a second of nothing but breathing, so the
    /// bang has a silence to break and the music editor has a drop to land.
    private static func breathScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .breath, t: t, fmt: fmt)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, _ in
                                 let pose = CrabAnimator.pose(mood: .idle, t: 40.0 + t, flourishes: false)
                                 return sizzlePet(pose: pose, side: side, fmt: fmt)
                             },
                             bottom: emptySlot(fmt))
    }

    private static func finaleScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .finale, t: t, fmt: fmt)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, _ in
                                 var pose = CrabAnimator.pose(mood: .done, t: t)
                                 CrabAnimator.applyCelebration(t: t, epic: true, to: &pose)
                                 pose.doneBadge = Ease.smoothstep(max(0, min(1, (t - SizzleScript.badgeAt) / 0.5)))
                                 // The flash rides the same chapter clock the
                                 // pose does, so the reel and the desktop
                                 // detonate on identical frames.
                                 let blanch = CrabView.epicBlanch(doneT: t)
                                 let glow = fmt.plate ? nil : AnyView(Canvas { context, size in
                                     CelebrationGlow.draw(in: &context, size: size, t: t,
                                                          bloom: !fmt.gifSafe, blanch: blanch)
                                 }
                                 .frame(width: side, height: side))
                                 // Plates KEEP the blanch: white against the
                                 // dark-red key field separates better than
                                 // terracotta does, and keyed footage must not
                                 // show him calm while the titled twin flashes.
                                 return sizzlePet(pose: pose,
                                                  tint: bodyTint(for: .finale, t: t),
                                                  blanch: blanch,
                                                  behind: glow,
                                                  side: side, fmt: fmt)
                             },
                             bottom: captionSlot(for: .finale, t: t, fmt: fmt))
    }

    /// One high-energy pose per look, each at a small local t so its
    /// one-shots actually fire on camera. Keyed by COSTUME, so a cut's own
    /// running order can be any subset in any order; a test holds the table
    /// to `Costume.allCases`, because this sat at eight entries while the
    /// order grew to ten and two costumes silently never rendered.
    static let montageMoods: [Costume: (PetMood, Double)] = [
        .ninja: (.done, 0.3), .retroBlack: (.working, SizzleScript.workBase + 1.0),
        .matrix: (.nudging, 0.5), .tiger: (.cooking, SizzleScript.cookBase + 1.0),
        .white: (.done, 0.2), .gundam: (.thinking, 1.0), .sonic: (.needsAttention, 0.3),
        .frankenstein: (.done, 0.4),
        // Arcade glows from inside, so the screen-lit working pose.
        .arcade: (.working, SizzleScript.workBase + 2.0),
        // The seasonal three: the pumpkin grins through a nudge, the turkey
        // struts a wave-adjacent done, the santa naps. The bunny is a calm
        // idle: the ears are the whole joke and they read best on a still
        // crab rather than through a pose.
        .pumpkin: (.nudging, 0.6), .turkey: (.done, 0.7), .santa: (.idle, 2.2),
        .easterBunny: (.idle, 1.4),
        // The skater rides his own beat; the Classic closer is CALM on
        // purpose — it is the loop seam, and the reel wraps back to a
        // resting crab.
        .skater: (.working, SizzleScript.workBase + 3.0),
        .none: (.idle, 1.0),
    ]

    private static func montageScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .montage, t: t, fmt: fmt)
        let looks = fmt.looks
        let cue = SizzleScript.look(in: looks, at: t)
        let to = looks[cue.index].costume
        let from = cue.index == 0 ? Costume.none : looks[cue.index - 1].costume
        // The dissolve is never longer than half the look, so the pure
        // costume shows for at least half its hold — and never a hard pop:
        // a costume changing in one frame mid-shot is the snap the rest of
        // the rig is not allowed.
        let dissolve = min(0.35, cue.seconds * 0.5)
        let u = Ease.smoothstep(min(1, cue.into / dissolve))
        let (mood, base) = Self.montageMoods[to] ?? (.idle, 1.0)
        return chapterLayout(
            fmt: fmt, camera: camera,
            petBuilder: { side, _ in
                let pose = CrabAnimator.pose(mood: mood, t: base + cue.into)
                return sizzlePet(pose: pose, costume: to,
                                 ghost: u < 1 ? from : Costume.none, costumeU: u,
                                 side: side, fmt: fmt)
            },
            bottom: captionSlot(for: .montage, t: t, fmt: fmt))
    }

    /// One second, two crabs, one pounce — the reaction shot after the
    /// payoff, and the setup for the second sleeper on the end card.
    private static func duetScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .duet, t: t, fmt: fmt)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { _, _ in
                                 var one = CrabAnimator.pose(mood: .working, t: SizzleScript.workBase + t)
                                 if t >= SizzleScript.duetPounceAt {
                                     CrabAnimator.applyPounce(elapsed: t - SizzleScript.duetPounceAt, to: &one)
                                 }
                                 let two = CrabAnimator.pose(mood: .working, t: 27.3 + t)
                                 return AnyView(HStack(spacing: -fmt.duoSide * 0.05) {
                                     sizzlePet(pose: one, side: fmt.duoSide, fmt: fmt)
                                     sizzlePet(pose: two, costume: .ninja, costumeU: 1,
                                               side: fmt.duoSide, fmt: fmt)
                                 })
                             },
                             bottom: emptySlot(fmt))
    }

    /// The button: wordmark and URL arrive a tenth apart in reading order
    /// and hold to the last frame — no decay, so the final fifteen frames
    /// carry nothing but the sleepers' breath. The meme's "SHIP IT" replaces
    /// the wordmark here; the URL is the one call to action and appears
    /// nowhere else.
    private static func outroScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .outro, t: t, fmt: fmt)
        func arrive(_ delay: Double) -> Double { Ease.smoothstep((t - delay) / typeAttack) }
        let title = fmt.captions[.outro]?.text(vertical: fmt.vertical)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { _, _ in
                                 let one = CrabAnimator.pose(mood: .sleeping, t: t)
                                 let two = CrabAnimator.pose(mood: .sleeping, t: t + 1.7)
                                 return AnyView(HStack(spacing: -fmt.duoSide * 0.05) {
                                     sizzlePet(pose: one, side: fmt.duoSide, fmt: fmt)
                                     sizzlePet(pose: two, costume: .ninja, costumeU: 1,
                                               side: fmt.duoSide, fmt: fmt)
                                 })
                             },
                             top: titleCard(title, sub: SizzleScript.url, fmt: fmt,
                                            presence: (1, arrive(0), arrive(0.1))),
                             bottom: emptySlot(fmt))
    }

    /// The body tint a chapter passes the sprite — the finale's, and ONLY the
    /// finale's. The cook's disco fires on the desktop in the same window;
    /// the reel withholds it so the payoff is the first colour change in the
    /// reel rather than the second. Pure, so a test can sweep it.
    static func bodyTint(for chapter: SizzleScript.Chapter, t: Double) -> Color? {
        chapter == .finale ? CrabView.epicTint(doneT: t) : nil
    }

    /// The mood the sprite wears at chapter-local `t` — the boundary test's
    /// fifth dimension (a hard cut must change the frame in two ways, and a
    /// mood change is one of them).
    static func mood(for chapter: SizzleScript.Chapter, t: Double, fmt: Format) -> PetMood {
        switch chapter {
        case .wake: return t < 1.0 ? .sleeping : .idle
        case .mirror: return t < 2.0 ? .thinking : .working
        case .glyphs, .duet: return .working
        case .cook: return .cooking
        case .breath: return .idle
        case .finale: return .done
        case .montage:
            let look = fmt.looks[SizzleScript.look(in: fmt.looks, at: t).index].costume
            return Self.montageMoods[look]?.0 ?? .idle
        case .outro: return .sleeping
        }
    }

    // MARK: - The pixel cards (fake repo furniture — every string fabricated)

    /// Flat-rect 8-bit cards in the bubble's recipe: square corners, a steel
    /// border by backing inset, monospaced type, fixed intrinsics. Frame
    /// space only — they never ride the camera, so punches don't scale text.
    private struct PixelCard: View {
        enum Kind {
            case prMerged
            case npmInstall(progress: Double)
            case buildPassing
            /// The roster, told in the reel's own grammar: the three
            /// fabricated sessions as name-over-activity rows behind a square
            /// mood dot. The live app's `RosterPanel` used to stand here — a
            /// 324pt vector panel with radius-10 corners at a 0.85 CTM, which
            /// ran off the right edge of a 640pt frame beside a 224pt crab and
            /// resampled its own pixel art on the way.
            case sessions
        }
        let kind: Kind

        var body: some View {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Rectangle().fill(Palette.slate))
                .padding(2)
                .background(Rectangle().fill(Palette.steel))
        }

        @ViewBuilder
        private var content: some View {
            switch kind {
            case .prMerged:
                HStack(spacing: 6) {
                    ThoughtBubble.ServiceBadge(kind: .github)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PR #47")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Palette.kraft)
                        Text("MERGED")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Palette.green)
                    }
                }
            case .npmInstall(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    Text("npm install")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.kraft)
                    // Ten discrete cells — quantised fill, no partial cells,
                    // no new colours.
                    let filled = Int(max(0, min(1, progress)) * 10)
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { cell in
                            Rectangle()
                                .fill(cell < filled ? Palette.green : Palette.steel.opacity(0.4))
                                .frame(width: 8, height: 6)
                        }
                    }
                }
            case .buildPassing:
                HStack(spacing: 0) {
                    Text(" build ")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.kraft)
                        .padding(.vertical, 3)
                        .background(Rectangle().fill(Palette.slate))
                    Text(" passing ")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.vertical, 3)
                        .background(Rectangle().fill(Palette.green))
                }
            case .sessions:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude sessions")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Palette.kraft)
                    ForEach(DemoMode.sessions, id: \.id) { session in
                        HStack(alignment: .top, spacing: 6) {
                            // A square dot, one UI cell, in the mood's own accent.
                            Rectangle()
                                .fill(Palette.accent(for: session.mood))
                                .frame(width: 6, height: 6)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.name)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Palette.kraft)
                                Text(session.activity ?? "")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Palette.steel)
                            }
                        }
                    }
                }
            }
        }
    }

    /// He reacts to what he ships — a distinct beat-sized gesture per
    /// service, all integer channels, eased inside the beat in BEAT-relative
    /// time `u` (0…1), so a longer beat holds its gesture longer and no beat
    /// overruns. npm: a nod with the eyes down. The merged PR: the right arm
    /// goes up with the card. Linear: a one-pixel head tilt. Deploy: a lean
    /// back, eyes wide.
    static func applyGlyphReaction(beat: Int, u: Double, to pose: inout CrabPose) {
        let w = Ease.window(u - 0.15, duration: 0.7, edge: 0.2)
        guard w > 0.001 else { return }
        switch beat {
        case 0:
            pose.bob += w > 0.5 ? 1 : 0
            pose.gazeY += w > 0.5 ? 1 : 0
        case 1:
            pose.armRight = max(pose.armRight, w)
        case 2:
            pose.tilt = w > 0.5 ? 1 : 0
        default:
            pose.lean += w > 0.5 ? -1 : 0
            pose.eyes = w > 0.4 ? .wide : pose.eyes
        }
    }

    /// The card each glyph beat pops: npm's progress bar, the merged PR on
    /// the push, the shields-style badge on the deploy. Linear keeps the
    /// frame clean — the diamond alone carries that beat.
    private static func glyphFurniture(beat: Int, u: Double, fmt: Format) -> AnyView? {
        let dx = fmt.spriteSide / 2 + 80
        switch beat {
        case 0: return cardPop(.npmInstall(progress: (u - 0.15) / 0.7), u: u, x: dx)
        case 1: return cardPop(.prMerged, u: u, x: -dx)
        case 3: return cardPop(.buildPassing, u: u, x: dx)
        default: return nil
        }
    }

    /// A card's pop: eased presence plus a small integer-stepped rise, in
    /// beat-relative time.
    private static func cardPop(_ kind: PixelCard.Kind, u: Double,
                                x: CGFloat) -> AnyView {
        let appear = Ease.window(u - 0.1, duration: 0.85, edge: 0.2)
        let rise = CGFloat(Int((6 * Ease.smoothstep(min(1, max(0, (u - 0.1) / 0.85)))).rounded()))
        return AnyView(PixelCard(kind: kind)
            .opacity(appear)
            .offset(x: x, y: -rise))
    }

    /// The roster beat's card: the sessions in the PixelCard recipe, to the
    /// right of the crab as he slides sixty points left to make room. Frame
    /// space, so the face punch never scales its text.
    private static func rosterCard(fmt: Format, presence: Double) -> AnyView {
        AnyView(PixelCard(kind: .sessions)
            .opacity(presence)
            .offset(x: 140))
    }

    // MARK: - The pet stack

    /// The sprite, optionally behind a glow, under an optional bubble — the
    /// live window's arrangement, reconstructed. The rig draws his shadow
    /// itself (two pools under the legs); the live window's translucent
    /// floor bar is NOT reproduced here, because none of the marketing
    /// stills carry it and a one-and-a-half-cell translucent strip is a
    /// second pixel grid in the frame.
    private static func sizzlePet(pose: CrabPose,
                                  costume: Costume = .none,
                                  ghost: Costume = .none,
                                  costumeU: Double = 1,
                                  bubble: AnyView? = nil,
                                  bubbleOpacity: Double = 1,
                                  tint: Color? = nil,
                                  blanch: Double = 0,
                                  behind: AnyView? = nil,
                                  side: CGFloat? = nil,
                                  fmt: Format) -> AnyView {
        let spriteSide = side ?? fmt.spriteSide
        let px = spriteSide / CGFloat(PixelBuffer.side)
        let crown = CGFloat(PetRootView.crownCells) * px
        let overrides = costume == .none && ghost == .none
            ? [:]
            : CostumeStyle.blendedOverrides(from: ghost == .none ? costume : ghost,
                                            to: costume, u: costumeU)
        let sprite = ZStack {
            if let behind { behind }
            PixelCanvasView(buffer: CrabRig.render(pose, costume: costume,
                                                   ghostCostume: ghost,
                                                   costumeVisibility: costumeU),
                            bodyTint: tint,
                            inkOverrides: overrides,
                            seamBleed: 0,
                            blanch: blanch)
                .frame(width: spriteSide, height: spriteSide)
        }
        if let bubble {
            // Plates keep the bubble IN LAYOUT at opacity zero — omission
            // would shift the sprite against its titled twin. Under the
            // luminance bridge the bubble fades with the frame, so nothing
            // reads through the white.
            return AnyView(VStack(spacing: -crown) {
                bubble.opacity(fmt.plate ? 0 : bubbleOpacity * (1 - fmt.flash)).zIndex(1)
                sprite
            })
        }
        return AnyView(sprite)
    }

    // MARK: - Type

    /// Type inverts the rig's first law, and says so: motion-design has
    /// release slower than arrival; type enters decelerating over 0.30s and
    /// leaves accelerating over 0.18s, because a caption that lingers on the
    /// way out is the universal default tween. The exception applies to
    /// type only, never to the character.
    static let typeAttack = 0.30
    static let typeDecay = 0.18

    /// A caption's presence at chapter-local `t`: full ink over
    /// [from, until], eased in before and out after with the type envelope.
    static func typeEnvelope(_ t: Double, from: Double, until: Double,
                             frame: Double = 1.0 / 30) -> Double {
        // The 0.18s exit is 1.8 frames at the GIF's 10fps — a snap in an
        // ease's clothes — so the decay floors at three frames of the cut.
        Ease.pulse(t - (from - typeAttack), attack: typeAttack,
                   hold: max(0, until - from), decay: max(typeDecay, 3 * frame))
    }

    /// The brand face: the wordmark's, on title and end cards only.
    static func brandFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// The product face: the pet's own monospaced type — bubbles, cards,
    /// captions, the URL.
    static func productFont(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// All-caps tracking as a ratio of the size — 0.08, inside Butterick's
    /// 5–12% band — and zero for lowercase. `.tracking(4)` was 13% at 16:9,
    /// 15% at 9:16 and 29% in the README GIF.
    static func tracking(for text: String, size: CGFloat) -> CGFloat {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased() else { return 0 }
        return (0.08 * size).rounded()
    }

    /// The title / end card: the wordmark (or a cut's own line in the brand
    /// face) over a sub line in the product face, each element with its own
    /// presence so a card can arrive in reading order. The star sting is
    /// optional: a 9×9 mark on the sprite's 7pt cell is 63pt tall and would
    /// own the end card, so the masters leave it to the README hero.
    private static func titleCard(_ title: String?, sub: String, fmt: Format,
                                  star: Bool = false,
                                  presence: (star: Double, title: Double, sub: Double) = (1, 1, 1)) -> AnyView {
        let ink = fmt.type ? fmt.ink : Color.clear
        return AnyView(VStack(spacing: fmt.cell) {
            if star {
                StarSting(cell: fmt.cell, inked: fmt.type).opacity(presence.star)
            }
            Group {
                if let title {
                    Text(title)
                        .font(brandFont(fmt.wordmark))
                        .tracking(tracking(for: title, size: fmt.wordmark))
                        .foregroundStyle(ink)
                } else {
                    Wordmark(size: fmt.wordmark, color: ink)
                }
            }
            .opacity(presence.title)
            // The sub line is the caption role — except on 9:16, where the
            // 36-character URL at 21pt is 454pt on a 360pt frame and SwiftUI
            // would wrap it; there it takes the tag role and stays one line.
            Text(sub)
                .font(productFont(fmt.vertical ? fmt.tag : fmt.caption))
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
                .opacity(presence.sub)
        })
    }

    /// The brand sting: the Claude star from the shared StarMark table, a
    /// whole-point cell size, popped with whatever ease the card rides.
    private struct StarSting: View {
        let cell: CGFloat
        /// False on a plate: the star keeps its frame and draws none of itself,
        /// so the card's height is identical and the sprite below does not move.
        var inked: Bool = true

        var body: some View {
            let rows = StarMark.art.rows
            let palette: [Character: Color] = [
                "C": Palette.flameCore, "f": Palette.flame, "y": Palette.yellow,
            ]
            Canvas { context, _ in
                guard inked else { return }
                for (rowIndex, row) in rows.enumerated() {
                    for (colIndex, char) in row.enumerated() where char != "." {
                        guard let color = palette[char] else { continue }
                        context.fill(
                            Path(CGRect(x: CGFloat(colIndex) * cell,
                                        y: CGFloat(rowIndex) * cell,
                                        width: cell, height: cell)),
                            with: .color(color))
                    }
                }
            }
            .frame(width: CGFloat(rows.map(\.count).max() ?? 0) * cell,
                   height: CGFloat(rows.count) * cell)
        }
    }

    /// A caption in the product face at the caption role's size, full ink —
    /// the shot's one message is never dimmed to look secondary.
    private static func captionText(_ text: String, fmt: Format) -> AnyView {
        let size = fmt.caption * fmt.captionScale
        return AnyView(Text(text)
            .font(productFont(size))
            .tracking(tracking(for: text, size: size))
            .multilineTextAlignment(.center)
            .foregroundStyle(fmt.type ? fmt.ink : Color.clear))
    }

    /// The bottom slot for a chapter: its caption at its authored presence,
    /// times (1 − flash) so nothing reads through the white, in a slot of
    /// FIXED height — a chapter with no caption keeps the sprite exactly
    /// where a captioned one has it.
    private static func captionSlot(for chapter: SizzleScript.Chapter, t: Double,
                                    fmt: Format) -> AnyView {
        guard let caption = fmt.captions[chapter] else { return emptySlot(fmt) }
        let presence = typeEnvelope(t, from: caption.from, until: caption.until, frame: fmt.frame)
        return AnyView(captionText(caption.text(vertical: fmt.vertical), fmt: fmt)
            .opacity(presence * (1 - fmt.flash))
            .frame(height: fmt.captionSlot, alignment: .top))
    }

    private static func emptySlot(_ fmt: Format) -> AnyView {
        AnyView(Color.clear.frame(width: 1, height: fmt.captionSlot))
    }

    /// One arrangement for every chapter, with the camera as a layout no-op:
    /// the rest-side pet occupies the slot hidden (defining the layout the
    /// type negotiates against), and the SHOT pet draws in its overlay —
    /// overlays never affect layout, so captions provably cannot move when
    /// the camera does. Type sits above punch overflow via zIndex. Margins
    /// are whole cells: three at the top, and `bottomMargin` under the slot.
    private static func chapterLayout(fmt: Format,
                                      camera: Shot,
                                      petBuilder: (CGFloat, Double) -> AnyView,
                                      furniture: AnyView? = nil,
                                      top: (some View)? = Optional<AnyView>.none,
                                      bottom: (some View)? = Optional<AnyView>.none) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: fmt.cell * 3)
            if let top { top.zIndex(1) }
            Spacer(minLength: 4)
            petBuilder(fmt.spriteSide, 1)
                .hidden()
                .overlay {
                    petBuilder(camera.side, camera.bubbleFade)
                        .offset(x: camera.offset.x, y: camera.offset.y)
                }
                // Frame-space furniture — cards and the roster live outside
                // the shot transform, so punches never scale their text.
                .overlay { if let furniture { furniture } }
            Spacer(minLength: 4)
            if let bottom {
                bottom.padding(.bottom, fmt.bottomMargin).zIndex(1)
            } else { Spacer(minLength: fmt.bottomMargin) }
        }
    }
}
