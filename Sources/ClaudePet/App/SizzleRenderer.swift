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

    /// Per-cut layout: sprite, camera stops, and type sizes per aspect.
    struct Format {
        let spriteSide: CGFloat
        /// Camera stops. Rest is `spriteSide`; new stops are even-celled
        /// (side × scale % 32 == 0) so dwells never shimmer.
        let punchSide: CGFloat
        let faceSide: CGFloat
        let duoSide: CGFloat
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
        let captions: [SizzleScript.Chapter: String]
        let captionScale: CGFloat
        /// Title cards, captions, tags. Off for plates (they fringe keys)
        /// and showcase cuts (the operator's ruling: just show the pet).
        let type: Bool
        /// Cards and the roster. Off wherever type is off — they are text.
        let furniture: Bool
    }

    static func format(for cut: SizzleScript.Cut) -> Format {
        let vertical = cut.canvas.width < cut.canvas.height
        switch cut.family {
        case .master, .meme, .plate, .showcase:
            let base: (side: CGFloat, punch: CGFloat, word: CGFloat, cap: CGFloat, tag: CGFloat) =
                vertical ? (264, 288, 26, 15, 13) : (224, 256, 30, 16, 12)
            let quiet = cut.family == .plate || cut.family == .showcase
            return Format(spriteSide: base.side, punchSide: base.punch, faceSide: 320,
                          duoSide: 160, wordmark: base.word, caption: base.cap, tag: base.tag,
                          vertical: vertical, gifSafe: false, rich: true,
                          plate: cut.family == .plate,
                          // A PLATE keeps the master's captions and hides them:
                          // an empty string is a different height than a real
                          // line, and that moves the sprite — the one thing a
                          // plate may not do, since it exists to be keyed
                          // against the titled master frame for frame. The
                          // showcase really has no text and is keyed against
                          // nothing, so it alone empties.
                          captions: cut.family == .meme ? SizzleScript.memeCaptions
                              : cut.family == .showcase ? [:] : SizzleScript.captions,
                          captionScale: cut.family == .meme ? 1.6 : 1,
                          type: !quiet,
                          furniture: !quiet)
        case .readme:
            return Format(spriteSide: 128, punchSide: 128, faceSide: 128,
                          duoSide: 96, wordmark: 14, caption: 9, tag: 8,
                          vertical: false, gifSafe: cut.fps == 10, rich: false,
                          plate: false, captions: SizzleScript.captions, captionScale: 1,
                          type: true, furniture: false)
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

    /// Pure in (chapter, localT, fmt): `.scaled` segments compress the
    /// camera with the scene, plates match titled framing frame-for-frame,
    /// and the meme cut's windows enter these curves mid-move.
    static func shot(for chapter: SizzleScript.Chapter, t: Double,
                     fmt: Format) -> Shot {
        var shot = Shot(side: fmt.spriteSide)
        guard fmt.rich else { return shot }

        switch chapter {
        case .wake:
            // The rise-in: he steps up into frame in whole-pixel increments.
            shot.offset.y = ((1 - Ease.smoothstep(min(1, t / 0.7))) * 28).rounded()

        case .mirror:
            // The face punch rides the thinking beat [0.6, 2.2] (the dots
            // fade with the zoom); the roster beat then slides him aside.
            let inU = Ease.smoothstep(min(1, max(0, (t - 0.6) / 0.25)))
            let outU = Ease.smoothstep(min(1, max(0, (t - 1.8) / 0.35)))
            let zoom = inU * (1 - outU)
            shot.side = fmt.spriteSide + (fmt.faceSide - fmt.spriteSide) * zoom
            shot.offset.y = (24 * zoom).rounded()
            shot.bubbleFade = 1 - zoom
            // A reveal, not a punch: the slide's edges are slow (0.9s), or
            // ninety points in a third of a second reads as a yank.
            let rosterU = Ease.window(t - 2.8, duration: 2.5, edge: 0.9)
            if fmt.vertical {
                shot.offset.y -= (40 * rosterU).rounded()
            } else {
                shot.offset.x -= (90 * rosterU).rounded()
            }

        case .glyphs:
            // A beat punch on each service.
            let beatT = t.truncatingRemainder(dividingBy: 1.5)
            let env = Ease.window(beatT, duration: 0.32, edge: 0.11)
            shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * env

        case .cook:
            // The 8-bit shake, gated to the heat cascade: a 15Hz tick of
            // ±1-point jitter from the same splitmix64 hash everything else
            // schedules with. Single-pixel steps are the sanctioned no-snap
            // exemption; amp is zero at the chapter's edges.
            let amp = Ease.window(t - 3.0, duration: 2.4, edge: 0.3)
            let n = Int(t * 15)
            let dx = Double(Int(CrabAnimator.noise(n &* 31 &+ 7) * 3) - 1) * amp
            let dy = Double(Int(CrabAnimator.noise(n &* 53 &+ 11) * 3) - 1) * amp
            shot.offset = CGPoint(x: dx.rounded(), y: dy.rounded())

        case .finale:
            // Hold wide; punch with the flash; settle back for the badge.
            let inU = Ease.smoothstep(min(1, max(0, (t - 1.2) / 0.28)))
            let outU = Ease.smoothstep(min(1, max(0, (t - 3.8) / 0.5)))
            let zoom = inU * (1 - outU)
            shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * zoom

        case .montage:
            // Alternating punch per look, drifting with the beat's parity.
            let beat = min(Int(t), SizzleScript.montageOrder.count - 1)
            let beatT = t - Double(beat)
            let env = Ease.window(beatT, duration: 0.32, edge: 0.11)
            let dir: CGFloat = beat % 2 == 0 ? 1 : -1
            // Full punch — the window's plateau then dwells at a sanctioned
            // stop, and half-measures read as hesitation at meme speed.
            shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * env
            shot.offset.x = (dir * 10 * env).rounded()

        case .duet:
            // The crossing pan: dwell on pet 1 to catch the pounce, cross
            // to pet 2, settle wide. ~4.8pt/frame, inside the bounds.
            let toTwo = Ease.smoothstep(min(1, max(0, (t - 1.6) / 0.8)))
            let widen = Ease.smoothstep(min(1, max(0, (t - 2.8) / 0.8)))
            shot.offset.x = ((38 - 76 * toTwo) * (1 - widen)).rounded()

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
        titleCard(SizzleScript.wordmark, sub: "probe", fmt: fmt)
    }

    // NOTE: deliberately no `.clipped()` on the frame — ImageRenderer already
    // crops at bitmap bounds, and adding the modifier made same-frame renders
    // byte-UNSTABLE over the glow's antialiased ring strokes (measured: the
    // finale frame differed run-to-run with it, identical without). The
    // determinism test is the guard.
    private static func frameImage(cut: SizzleScript.Cut, index: Int) -> CGImage? {
        let t = Double(index) / Double(cut.fps)
        guard let cue = SizzleScript.resolve(cut, at: t) else { return nil }
        let fmt = format(for: cut)
        let flash = matchCutFlash(cut: cut, at: t, fmt: fmt)
        let scene = ZStack {
            scenery(for: cut, t: t, fmt: fmt)
            chapterScene(cue.chapter, t: cue.localT, fmt: fmt)
            if flash > 0.001 {
                Color.white.opacity(flash)
            }
        }
        .frame(width: cut.canvas.width, height: cut.canvas.height)
        return SpriteImage.cgImage(of: scene, scale: cut.scale, isOpaque: true)
    }

    /// What stands behind him this frame. Plates override everything with
    /// the key field; the forest scrolls in CUT time, so its drift is
    /// continuous across chapter cuts.
    @ViewBuilder
    private static func scenery(for cut: SizzleScript.Cut, t: Double,
                                fmt: Format) -> some View {
        if fmt.plate {
            // The keying field: a single-entry ramp rides Backdrop's
            // whole-point, no-antialiasing path.
            Backdrop(style: .init(ramp: [Palette.keyField], foam: nil))
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

    /// The one motivated transition: the cook IS the finale's cause, so its
    /// exit whites out over 0.4s and the finale opens at the same white,
    /// decaying over 0.3s — a continuous luminance bridge where every other
    /// chapter boundary stays a hard cut. Rich MP4 cuts only: a full-frame
    /// translucent white would fringe a key and explode a GIF's palette,
    /// and the readme twins must not diverge from each other.
    static func matchCutFlash(cut: SizzleScript.Cut, at t: Double,
                              fmt: Format) -> Double {
        guard !fmt.plate, cut.family != .readme,
              let cue = SizzleScript.resolve(cut, at: t),
              let hood = SizzleScript.neighbors(in: cut, at: t) else { return 0 }
        // 1.0, not 0.9: nine tenths of white over a dark backdrop composites to
        // about #E5E5E5 — a grey, which is the same washed-out complaint in a
        // different room. The ramps are unchanged; only the peak is honest now.
        if cue.chapter == .cook, hood.next == .finale {
            return Ease.smoothstep(max(0, min(1, (0.4 - hood.remaining) / 0.4)))
        }
        if cue.chapter == .finale, hood.previous == .cook {
            return 1 - Ease.smoothstep(min(1, hood.into / 0.3))
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
        case .finale: finaleScene(t: t, fmt: fmt)
        case .montage: montageScene(t: t, fmt: fmt)
        case .duet: duetScene(t: t, fmt: fmt)
        case .outro: outroScene(t: t, fmt: fmt)
        }
    }

    private static func wakeScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .wake, t: t, fmt: fmt)
        let card = Ease.window(t, duration: 2.5, edge: 0.4)
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
                             top: titleCard(SizzleScript.wordmark,
                                            sub: SizzleScript.tagline,
                                            fmt: fmt).opacity(card))
    }

    private static func mirrorScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .mirror, t: t, fmt: fmt)
        let caption = Ease.window(t - 0.4, duration: 5.1, edge: 0.3)
        let rosterU = Ease.window(t - 2.8, duration: 2.5, edge: 0.35)
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
                             furniture: fmt.furniture && rosterU > 0.001
                                 ? rosterCard(fmt: fmt, presence: rosterU) : nil,
                             bottom: captionText(fmt.captions[.mirror] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func glyphsScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .glyphs, t: t, fmt: fmt)
        let beat = min(Int(t / 1.5), SizzleScript.glyphBeats.count - 1)
        let beatT = t - Double(beat) * 1.5
        let entry = SizzleScript.glyphBeats[beat]
        let caption = Ease.window(t - 0.3, duration: 5.5, edge: 0.3)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, fade in
                                 let workT = SizzleScript.workBase + 3.5 + t
                                 var pose = CrabAnimator.pose(mood: .working, t: workT)
                                 CrabAnimator.applyPropDissolve(at: workT, to: &pose)
                                 pose.serviceGlyph = entry.glyph
                                 pose.serviceGlyphVisibility = Ease.window(beatT, duration: 1.5, edge: 0.3)
                                 applyGlyphReaction(beat: beat, beatT: beatT, to: &pose)
                                 let bubble = AnyView(ThoughtBubble(text: entry.bubble, tool: "Bash",
                                                                    mood: .working, style: .plain,
                                                                    service: entry.glyph, frozenTime: t))
                                 return sizzlePet(pose: pose, bubble: bubble,
                                                  bubbleOpacity: fade, side: side, fmt: fmt)
                             },
                             furniture: fmt.furniture
                                 ? glyphFurniture(beat: beat, beatT: beatT, fmt: fmt) : nil,
                             bottom: captionText(fmt.captions[.glyphs] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func cookScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .cook, t: t, fmt: fmt)
        let cookT = SizzleScript.cookBase + t
        let caption = Ease.window(t - 0.3, duration: 5.5, edge: 0.3)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, fade in
                                 let pose = CrabAnimator.pose(mood: .cooking, t: cookT)
                                 let bubble = AnyView(ThoughtBubble(text: SizzleScript.cookBubble,
                                                                    tool: nil, mood: .cooking,
                                                                    style: .plain, frozenTime: t))
                                 return sizzlePet(pose: pose, bubble: bubble,
                                                  bubbleOpacity: fade,
                                                  tint: CrabView.discoTint(cookingT: cookT),
                                                  side: side, fmt: fmt)
                             },
                             bottom: captionText(fmt.captions[.cook] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func finaleScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .finale, t: t, fmt: fmt)
        let caption = Ease.window(t - 0.3, duration: 2.7, edge: 0.4)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { side, _ in
                                 var pose = CrabAnimator.pose(mood: .done, t: t)
                                 CrabAnimator.applyCelebration(t: t, epic: true, to: &pose)
                                 pose.doneBadge = Ease.smoothstep(max(0, min(1, (t - 8.2) / 0.5)))
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
                                                  tint: CrabView.epicTint(doneT: t),
                                                  blanch: blanch,
                                                  behind: glow,
                                                  side: side, fmt: fmt)
                             },
                             bottom: captionText(fmt.captions[.finale] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func montageScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .montage, t: t, fmt: fmt)
        let order = SizzleScript.montageOrder
        let beat = min(Int(t), order.count - 1)
        let beatT = t - Double(beat)
        let from = beat == 0 ? Costume.none : order[beat - 1]
        let to = order[beat]
        let u = Ease.smoothstep(min(1, beatT / 0.35))

        // A different high-energy pose per look, each at a small local t so
        // its one-shots actually fire on camera.
        let moods: [(PetMood, Double)] = [
            (.done, 0.3), (.working, SizzleScript.workBase + 1.0), (.nudging, 0.5),
            (.cooking, SizzleScript.cookBase + 1.0), (.done, 0.2), (.thinking, 1.0),
            (.needsAttention, 0.3), (.done, 0.4),
        ]
        let (mood, base) = moods[beat]
        let tagOpacity = Ease.window(beatT, duration: 1.0, edge: 0.25)
        return chapterLayout(
            fmt: fmt, camera: camera,
            petBuilder: { side, _ in
                let pose = CrabAnimator.pose(mood: mood, t: base + beatT)
                return sizzlePet(pose: pose, costume: to,
                                 ghost: u < 1 ? from : Costume.none, costumeU: u,
                                 side: side, fmt: fmt)
            },
            top: captionText(fmt.captions[.montage] ?? "", fmt: fmt,
                             size: fmt.wordmark),
            bottom: captionText(to.title, fmt: fmt,
                                color: tagColor(for: to)).opacity(tagOpacity))
    }

    private static func duetScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .duet, t: t, fmt: fmt)
        let caption = Ease.window(t - 0.3, duration: 3.5, edge: 0.3)
        return chapterLayout(fmt: fmt, camera: camera,
                             petBuilder: { _, _ in
                                 var one = CrabAnimator.pose(mood: .working, t: SizzleScript.workBase + t)
                                 if t >= 1.2 {
                                     CrabAnimator.applyPounce(elapsed: t - 1.2, to: &one)
                                 }
                                 let two = CrabAnimator.pose(mood: .working, t: 27.3 + t)
                                 return AnyView(HStack(spacing: -fmt.duoSide * 0.05) {
                                     sizzlePet(pose: one, side: fmt.duoSide, fmt: fmt)
                                     sizzlePet(pose: two, costume: .ninja, costumeU: 1,
                                               side: fmt.duoSide, fmt: fmt)
                                 })
                             },
                             bottom: captionText(fmt.captions[.duet] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func outroScene(t: Double, fmt: Format) -> some View {
        let camera = shot(for: .outro, t: t, fmt: fmt)
        let card = Ease.smoothstep(min(1, t / 0.4))
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
                             top: titleCard(fmt.captions[.outro] ?? SizzleScript.wordmark,
                                            sub: SizzleScript.url,
                                            fmt: fmt).opacity(card))
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
            }
        }
    }

    /// He reacts to what he ships — a distinct beat-sized gesture per
    /// service, all integer channels, all eased inside the beat so
    /// `.scaled` compresses them with everything else. npm: a nod with the
    /// eyes down. The merged PR: the right arm goes up with the card.
    /// Linear: a one-pixel head tilt. Deploy: a lean back, eyes wide.
    static func applyGlyphReaction(beat: Int, beatT: Double, to pose: inout CrabPose) {
        let u = Ease.window(beatT - 0.25, duration: 0.9, edge: 0.3)
        guard u > 0.001 else { return }
        switch beat {
        case 0:
            pose.bob += u > 0.5 ? 1 : 0
            pose.gazeY += u > 0.5 ? 1 : 0
        case 1:
            pose.armRight = max(pose.armRight, u)
        case 2:
            pose.tilt = u > 0.5 ? 1 : 0
        default:
            pose.lean += u > 0.5 ? -1 : 0
            pose.eyes = u > 0.4 ? .wide : pose.eyes
        }
    }

    /// The card each glyph beat pops: npm's progress bar, the merged PR on
    /// the push, the shields-style badge on the deploy. Linear keeps the
    /// frame clean — the diamond alone carries that beat.
    private static func glyphFurniture(beat: Int, beatT: Double, fmt: Format) -> AnyView? {
        let dx = fmt.spriteSide / 2 + 80
        switch beat {
        case 0: return cardPop(.npmInstall(progress: (beatT - 0.2) / 1.1), beatT: beatT, x: dx)
        case 1: return cardPop(.prMerged, beatT: beatT, x: -dx)
        case 3: return cardPop(.buildPassing, beatT: beatT, x: dx)
        default: return nil
        }
    }

    /// A card's pop: eased presence plus a small integer-stepped rise.
    private static func cardPop(_ kind: PixelCard.Kind, beatT: Double,
                                x: CGFloat) -> AnyView {
        let appear = Ease.window(beatT - 0.15, duration: 1.25, edge: 0.22)
        let rise = CGFloat(Int((6 * Ease.smoothstep(min(1, max(0, (beatT - 0.15) / 1.25)))).rounded()))
        return AnyView(PixelCard(kind: kind)
            .opacity(appear)
            .offset(x: x, y: -rise))
    }

    /// The roster beat's decorated panel — the still renderer's exact chain,
    /// on the sizzle's own backdrop. Fixed elapsed 7.0 so the fabricated
    /// sessions hold still mid-shot.
    private static func rosterCard(fmt: Format, presence: Double) -> AnyView {
        AnyView(RosterPanel(state: DemoMode.state(at: 7.0),
                            pinnedID: DemoMode.sessions[1].id,
                            onPin: { _ in }, scrolls: false)
            .environment(\.colorScheme, .dark)
            .background(Palette.slate)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(fmt.vertical ? 1.0 : 0.85)   // vector text — CTM-safe
            .opacity(presence)
            .offset(x: fmt.vertical ? 0 : 178,
                    y: fmt.vertical ? 205 : 0))
    }

    // MARK: - The pet stack

    /// The sprite over its ground shadow, optionally behind a glow, under an
    /// optional bubble — the live window's arrangement, reconstructed.
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
                // The floor's opinion, same numbers as the live window.
                // Suppressed on plates: translucent black over green keys
                // as a hole.
                .overlay(alignment: .top) {
                    if !fmt.plate {
                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 20 * px, height: 1.5 * px)
                            .offset(y: 25 * px)
                    }
                }
        }
        if let bubble {
            // Plates keep the bubble IN LAYOUT at opacity zero — omission
            // would shift the sprite against its titled twin.
            return AnyView(VStack(spacing: -crown) {
                bubble.opacity(fmt.plate ? 0 : bubbleOpacity).zIndex(1)
                sprite
            })
        }
        return AnyView(sprite)
    }

    // MARK: - Type

    private static func titleCard(_ title: String, sub: String, fmt: Format) -> AnyView {
        AnyView(VStack(spacing: fmt.tag * 0.8) {
            StarSting(cell: (fmt.tag * 0.45).rounded(), inked: fmt.type)
            Text(title)
                .font(.system(size: fmt.wordmark, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundStyle(fmt.type ? Palette.kraft : Color.clear)
            Text(sub)
                .font(.system(size: fmt.tag, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(fmt.type ? Palette.kraft.opacity(0.7) : Color.clear)
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

    private static func captionText(_ text: String, fmt: Format,
                                    size: CGFloat? = nil,
                                    color: Color? = nil) -> AnyView {
        AnyView(Text(text)
            .font(.system(size: (size ?? fmt.caption) * fmt.captionScale,
                          weight: .heavy, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundStyle(fmt.type ? (color ?? Palette.kraft.opacity(size == nil ? 0.85 : 1))
                                       : Color.clear))
    }

    /// The montage tag's colour: the costume's own key colour — the first
    /// ink bright enough to be VIVID on the dark field (luminance ≥ 0.3,
    /// well past bare 3:1 legibility, because a tag is branding, not body
    /// text). The ninja's shadowed shell fails and his headband red tags
    /// him instead; retroBlack's darks all fail and fall back to kraft;
    /// Classic tags in his own terracotta.
    static func tagColor(for costume: Costume) -> Color {
        if costume == .none {
            let body = SpriteTint.bodyRGB
            return Color(red: body.r, green: body.g, blue: body.b)
        }
        let inks = CostumeStyle.of(costume).inks
        for slot in [PixelBuffer.Ink.body, .costumeA, .costumeB, .costumeC] {
            guard let ink = inks[slot] else { continue }
            let luminance = 0.2126 * ink.r + 0.7152 * ink.g + 0.0722 * ink.b
            if luminance >= 0.3 {
                return Color(red: ink.r, green: ink.g, blue: ink.b)
            }
        }
        return Palette.kraft
    }

    /// One arrangement for every chapter, with the camera as a layout no-op:
    /// the rest-side pet occupies the slot hidden (defining the layout the
    /// type negotiates against), and the SHOT pet draws in its overlay —
    /// overlays never affect layout, so captions provably cannot move when
    /// the camera does. Type sits above punch overflow via zIndex.
    private static func chapterLayout(fmt: Format,
                                      camera: Shot,
                                      petBuilder: (CGFloat, Double) -> AnyView,
                                      furniture: AnyView? = nil,
                                      top: (some View)? = Optional<AnyView>.none,
                                      bottom: (some View)? = Optional<AnyView>.none) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: fmt.vertical ? 40 : 8)
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
                bottom.padding(.bottom, fmt.vertical ? 44 : 12).zIndex(1)
            } else { Spacer(minLength: fmt.vertical ? 44 : 12) }
        }
    }
}
