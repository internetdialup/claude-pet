import SwiftUI

/// Renders the sizzle reel — `SizzleScript`'s chapters, in every cut.
///
/// The scenes bypass `CrabView` and drive `CrabRig` with the pure functions,
/// exactly as `ReelRenderer` does: every effect the live pet earns from
/// latches and clocks is reconstructed here from a deterministic chapter
/// clock. No `Date()`, no randomness, `Backdrop(phase: 0)` — the same
/// invocation produces the same bytes.
@MainActor
enum SizzleRenderer {

    /// Per-cut layout: sprite and type sizes tuned per aspect.
    struct Format {
        let spriteSide: CGFloat
        let duoSide: CGFloat
        let wordmark: CGFloat
        let caption: CGFloat
        let tag: CGFloat
        let vertical: Bool
        /// GIF cuts skip the finale's radial bloom — a smooth ramp would
        /// smuggle hundreds of colours into the global palette.
        let gifSafe: Bool
    }

    static func format(for cut: SizzleScript.Cut) -> Format {
        if cut.canvas.width < cut.canvas.height {
            return Format(spriteSide: 264, duoSide: 160, wordmark: 26, caption: 15,
                          tag: 13, vertical: true, gifSafe: false)
        }
        if cut.fps == 10 || cut.canvas.width <= 320 {
            return Format(spriteSide: 128, duoSide: 96, wordmark: 14, caption: 9,
                          tag: 8, vertical: false, gifSafe: cut.fps == 10)
        }
        return Format(spriteSide: 224, duoSide: 160, wordmark: 30, caption: 16,
                      tag: 12, vertical: false, gifSafe: false)
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

    /// Test seam: one frame of a cut, exactly as the encoders receive it.
    static func testFrame(cut: SizzleScript.Cut, index: Int) -> CGImage? {
        frameImage(cut: cut, index: index)
    }

    private static func frameImage(cut: SizzleScript.Cut, index: Int) -> CGImage? {
        let t = Double(index) / Double(cut.fps)
        guard let cue = SizzleScript.resolve(cut, at: t) else { return nil }
        let fmt = format(for: cut)
        let scene = ZStack {
            Backdrop()
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
        // Asleep, then the 0.4s cross-ease into idle — the same blend the
        // live MoodClock would run, driven by our own u.
        var pose: CrabPose
        if t < 1.0 {
            pose = CrabAnimator.pose(mood: .sleeping, t: t)
        } else if t < 1.4 {
            let from = CrabAnimator.pose(mood: .sleeping, t: t)
            let to = CrabAnimator.pose(mood: .idle, t: t - 1.0, flourishes: false)
            pose = CrabPose.blend(from: from, to: to, u: Ease.smoothstep((t - 1.0) / 0.4))
        } else {
            pose = CrabAnimator.pose(mood: .idle, t: t - 1.0, flourishes: false)
        }
        let card = Ease.window(t, duration: 2.5, edge: 0.4)
        return chapterLayout(fmt: fmt,
                             pet: sizzlePet(pose: pose, fmt: fmt),
                             top: titleCard(SizzleScript.wordmark,
                                            sub: SizzleScript.tagline,
                                            fmt: fmt).opacity(card))
    }

    private static func mirrorScene(t: Double, fmt: Format) -> some View {
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
            bubble = AnyView(ThoughtBubble(text: SizzleScript.mirrorBubble, tool: "Bash",
                                           mood: .working, style: .plain, frozenTime: t))
        }
        let caption = Ease.window(t - 0.4, duration: 5.1, edge: 0.3)
        return chapterLayout(fmt: fmt,
                             pet: sizzlePet(pose: pose, bubble: bubble, fmt: fmt),
                             bottom: captionText(SizzleScript.captions[.mirror] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func glyphsScene(t: Double, fmt: Format) -> some View {
        let beat = min(Int(t / 1.5), SizzleScript.glyphBeats.count - 1)
        let beatT = t - Double(beat) * 1.5
        let entry = SizzleScript.glyphBeats[beat]
        let workT = SizzleScript.workBase + 3.5 + t
        var pose = CrabAnimator.pose(mood: .working, t: workT)
        CrabAnimator.applyPropDissolve(at: workT, to: &pose)
        pose.serviceGlyph = entry.glyph
        pose.serviceGlyphVisibility = Ease.window(beatT, duration: 1.5, edge: 0.3)
        let bubble = AnyView(ThoughtBubble(text: entry.bubble, tool: "Bash",
                                           mood: .working, style: .plain,
                                           service: entry.glyph, frozenTime: t))
        let caption = Ease.window(t - 0.3, duration: 5.5, edge: 0.3)
        return chapterLayout(fmt: fmt,
                             pet: sizzlePet(pose: pose, bubble: bubble, fmt: fmt),
                             bottom: captionText(SizzleScript.captions[.glyphs] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func cookScene(t: Double, fmt: Format) -> some View {
        let cookT = SizzleScript.cookBase + t
        let pose = CrabAnimator.pose(mood: .cooking, t: cookT)
        let bubble = AnyView(ThoughtBubble(text: SizzleScript.cookBubble, tool: nil,
                                           mood: .cooking, style: .plain, frozenTime: t))
        let caption = Ease.window(t - 0.3, duration: 5.5, edge: 0.3)
        return chapterLayout(fmt: fmt,
                             pet: sizzlePet(pose: pose, bubble: bubble,
                                            tint: CrabView.discoTint(cookingT: cookT),
                                            fmt: fmt),
                             bottom: captionText(SizzleScript.captions[.cook] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func finaleScene(t: Double, fmt: Format) -> some View {
        var pose = CrabAnimator.pose(mood: .done, t: t)
        CrabAnimator.applyCelebration(t: t, epic: true, to: &pose)
        pose.doneBadge = Ease.smoothstep(max(0, min(1, (t - 8.2) / 0.5)))
        let glow = Canvas { context, size in
            CelebrationGlow.draw(in: &context, size: size, t: t, bloom: !fmt.gifSafe)
        }
        .frame(width: fmt.spriteSide, height: fmt.spriteSide)
        let caption = Ease.window(t - 0.3, duration: 2.7, edge: 0.4)
        return chapterLayout(fmt: fmt,
                             pet: sizzlePet(pose: pose,
                                            tint: CrabView.epicTint(doneT: t),
                                            behind: AnyView(glow), fmt: fmt),
                             bottom: captionText(SizzleScript.captions[.finale] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func montageScene(t: Double, fmt: Format) -> some View {
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
        let pose = CrabAnimator.pose(mood: mood, t: base + beatT)

        let tagOpacity = Ease.window(beatT, duration: 1.0, edge: 0.25)
        return chapterLayout(
            fmt: fmt,
            pet: sizzlePet(pose: pose, costume: to,
                           ghost: u < 1 ? from : Costume.none, costumeU: u, fmt: fmt),
            top: captionText(SizzleScript.captions[.montage] ?? "", fmt: fmt,
                             size: fmt.wordmark),
            bottom: captionText(to.title, fmt: fmt).opacity(tagOpacity))
    }

    private static func duetScene(t: Double, fmt: Format) -> some View {
        var one = CrabAnimator.pose(mood: .working, t: SizzleScript.workBase + t)
        if t >= 1.2 {
            CrabAnimator.applyPounce(elapsed: t - 1.2, to: &one)
        }
        let two = CrabAnimator.pose(mood: .working, t: 27.3 + t)
        let caption = Ease.window(t - 0.3, duration: 3.5, edge: 0.3)
        let pair = HStack(spacing: -fmt.duoSide * 0.05) {
            sizzlePet(pose: one, side: fmt.duoSide, fmt: fmt)
            sizzlePet(pose: two, costume: .ninja, costumeU: 1,
                      side: fmt.duoSide, fmt: fmt)
        }
        return chapterLayout(fmt: fmt, pet: AnyView(pair),
                             bottom: captionText(SizzleScript.captions[.duet] ?? "",
                                                 fmt: fmt).opacity(caption))
    }

    private static func outroScene(t: Double, fmt: Format) -> some View {
        let one = CrabAnimator.pose(mood: .sleeping, t: t)
        let two = CrabAnimator.pose(mood: .sleeping, t: t + 1.7)
        let card = Ease.smoothstep(min(1, t / 0.4))
        let pair = HStack(spacing: -fmt.duoSide * 0.05) {
            sizzlePet(pose: one, side: fmt.duoSide, fmt: fmt)
            sizzlePet(pose: two, costume: .ninja, costumeU: 1,
                      side: fmt.duoSide, fmt: fmt)
        }
        return chapterLayout(fmt: fmt, pet: AnyView(pair),
                             top: titleCard(SizzleScript.wordmark,
                                            sub: SizzleScript.url,
                                            fmt: fmt).opacity(card))
    }

    // MARK: - The pet stack

    /// The sprite over its ground shadow, optionally behind a glow, under an
    /// optional bubble — the live window's arrangement, reconstructed.
    private static func sizzlePet(pose: CrabPose,
                                  costume: Costume = .none,
                                  ghost: Costume = .none,
                                  costumeU: Double = 1,
                                  bubble: AnyView? = nil,
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
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 20 * px, height: 1.5 * px)
                        .offset(y: 25 * px)
                }
        }
        if let bubble {
            return AnyView(VStack(spacing: -crown) {
                bubble.zIndex(1)
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
            .font(.system(size: size ?? fmt.caption, weight: .heavy, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundStyle(Palette.kraft.opacity(size == nil ? 0.85 : 1)))
    }

    /// One arrangement for every chapter: optional card/caption above, the
    /// pet in the middle, optional caption below — vertical cuts get more
    /// air around the type.
    private static func chapterLayout(fmt: Format,
                                      pet: AnyView,
                                      top: (some View)? = Optional<AnyView>.none,
                                      bottom: (some View)? = Optional<AnyView>.none) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: fmt.vertical ? 40 : 8)
            if let top { top }
            Spacer(minLength: 4)
            pet
            Spacer(minLength: 4)
            if let bottom { bottom.padding(.bottom, fmt.vertical ? 44 : 12) }
            else { Spacer(minLength: fmt.vertical ? 44 : 12) }
        }
    }
}
