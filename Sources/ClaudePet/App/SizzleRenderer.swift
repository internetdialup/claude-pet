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
        /// is suppressed, the field is broadcast green.
        let plate: Bool
        /// The cut's language and its volume — the meme family shouts.
        let captions: [SizzleScript.Chapter: String]
        let captionScale: CGFloat
    }

    static func format(for cut: SizzleScript.Cut) -> Format {
        let vertical = cut.canvas.width < cut.canvas.height
        switch cut.family {
        case .master, .meme, .plate:
            let base: (side: CGFloat, punch: CGFloat, word: CGFloat, cap: CGFloat, tag: CGFloat) =
                vertical ? (264, 288, 26, 15, 13) : (224, 256, 30, 16, 12)
            return Format(spriteSide: base.side, punchSide: base.punch, faceSide: 320,
                          duoSide: 160, wordmark: base.word, caption: base.cap, tag: base.tag,
                          vertical: vertical, gifSafe: false, rich: true,
                          plate: cut.family == .plate,
                          captions: cut.family == .meme ? SizzleScript.memeCaptions
                              : cut.family == .plate ? [:] : SizzleScript.captions,
                          captionScale: cut.family == .meme ? 1.6 : 1)
        case .readme:
            return Format(spriteSide: 128, punchSide: 128, faceSide: 128,
                          duoSide: 96, wordmark: 14, caption: 9, tag: 8,
                          vertical: false, gifSafe: cut.fps == 10, rich: false,
                          plate: false, captions: SizzleScript.captions, captionScale: 1)
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
            shot.offset.y = ((1 - Ease.smoothstep(min(1, t / 1.0))) * 28).rounded()

        case .mirror:
            // The face punch rides the thinking beat [0.6, 2.2] (the dots
            // fade with the zoom); the roster beat then slides him aside.
            let inU = Ease.smoothstep(min(1, max(0, (t - 0.6) / 0.4)))
            let outU = Ease.smoothstep(min(1, max(0, (t - 1.8) / 0.4)))
            let zoom = inU * (1 - outU)
            shot.side = fmt.spriteSide + (fmt.faceSide - fmt.spriteSide) * zoom
            shot.offset.y = (24 * zoom).rounded()
            shot.bubbleFade = 1 - zoom
            let rosterU = Ease.window(t - 2.8, duration: 2.5, edge: 0.35)
            if fmt.vertical {
                shot.offset.y -= (40 * rosterU).rounded()
            } else {
                shot.offset.x -= (90 * rosterU).rounded()
            }

        case .glyphs:
            // A beat punch on each service.
            let beatT = t.truncatingRemainder(dividingBy: 1.5)
            let env = Ease.window(beatT, duration: 0.45, edge: 0.18)
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
            let inU = Ease.smoothstep(min(1, max(0, (t - 1.2) / 0.4)))
            let outU = Ease.smoothstep(min(1, max(0, (t - 3.8) / 0.7)))
            let zoom = inU * (1 - outU)
            shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * zoom

        case .montage:
            // Alternating punch per look, drifting with the beat's parity.
            let beat = min(Int(t), SizzleScript.montageOrder.count - 1)
            let beatT = t - Double(beat)
            let env = Ease.window(beatT, duration: 0.45, edge: 0.18)
            let dir: CGFloat = beat % 2 == 0 ? 1 : -1
            // Full punch — the window's plateau then dwells at a sanctioned
            // stop, and half-measures read as hesitation at meme speed.
            shot.side = fmt.spriteSide + (fmt.punchSide - fmt.spriteSide) * env
            shot.offset.x = (dir * 10 * env).rounded()

        case .duet, .outro:
            break   // pair shots stay locked
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
            print("wrote \(url.path)")
        }
        return true
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
            print("wrote \(seqDir.path) (+preview)")
        }
        return true
    }

    /// Test seam: one frame of a cut, exactly as the encoders receive it.
    static func testFrame(cut: SizzleScript.Cut, index: Int) -> CGImage? {
        frameImage(cut: cut, index: index)
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
        let scene = ZStack {
            if fmt.plate {
                // The keying field: a single-entry ramp rides Backdrop's
                // whole-point, no-antialiasing path — one coalesced rect per
                // row, every frame the same bytes.
                Backdrop(style: .init(ramp: [Palette.broadcastGreen], foam: nil))
            } else {
                Backdrop()
            }
            chapterScene(cue.chapter, t: cue.localT, fmt: fmt)
        }
        .frame(width: cut.canvas.width, height: cut.canvas.height)
        return SpriteImage.cgImage(of: scene, scale: cut.scale, isOpaque: true)
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
                             furniture: fmt.rich && !fmt.plate && rosterU > 0.001
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
                                 let bubble = AnyView(ThoughtBubble(text: entry.bubble, tool: "Bash",
                                                                    mood: .working, style: .plain,
                                                                    service: entry.glyph, frozenTime: t))
                                 return sizzlePet(pose: pose, bubble: bubble,
                                                  bubbleOpacity: fade, side: side, fmt: fmt)
                             },
                             furniture: fmt.rich && !fmt.plate
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
                                 let glow = fmt.plate ? nil : AnyView(Canvas { context, size in
                                     CelebrationGlow.draw(in: &context, size: size, t: t,
                                                          bloom: !fmt.gifSafe)
                                 }
                                 .frame(width: side, height: side))
                                 return sizzlePet(pose: pose,
                                                  tint: CrabView.epicTint(doneT: t),
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
            bottom: captionText(to.title, fmt: fmt).opacity(tagOpacity))
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
                            seamBleed: 0)
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
            Text(title)
                .font(.system(size: fmt.wordmark, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Palette.kraft)
            Text(sub)
                .font(.system(size: fmt.tag, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.kraft.opacity(0.7))
        })
    }

    private static func captionText(_ text: String, fmt: Format,
                                    size: CGFloat? = nil) -> AnyView {
        AnyView(Text(text)
            .font(.system(size: (size ?? fmt.caption) * fmt.captionScale,
                          weight: .heavy, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.kraft.opacity(size == nil ? 0.85 : 1)))
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
            if let top, !fmt.plate { top.zIndex(1) }
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
            if let bottom, !fmt.plate {
                bottom.padding(.bottom, fmt.vertical ? 44 : 12).zIndex(1)
            } else { Spacer(minLength: fmt.vertical ? 44 : 12) }
        }
    }
}
