import SwiftUI
import AppKit

/// Renders composed scenes — the pet in a framed shot, the roster, the bubbles,
/// the props — entirely from code.
///
/// The reel this replaces was a screen recording, and a screen recording carries
/// whatever the operating system chose to draw at capture time. A real
/// notification banner from an unrelated project was frozen into all 192 frames
/// of the README hero and published (see the v1.2.1 notes in CHANGELOG.md).
/// The repair only worked because the desktop behind it was flat black, and the
/// history rewrite that finished the job only worked because nobody had cloned
/// yet. Both of those escape hatches are gone.
///
/// Nothing here touches a screen, so there is nothing to leak; and like every
/// other asset in `docs/media`, the same commit produces the same bytes.
///
/// Invoked with `ClaudePet --render-reel <output-dir>`.
@MainActor
enum ReelRenderer {

    /// Points. Rendered at 2×, giving the 640×360 the README sizes the hero at.
    static let heroCanvas = CGSize(width: 320, height: 180)
    static let heroScale: CGFloat = 2

    /// 10 fps — exactly 10 centiseconds, which is what GIF stores. 12 fps would
    /// round to 8cs and play at a rate the frames were not sampled at.
    static let heroFrameDelay = 0.1

    /// Sprite edge in points, a whole multiple of the 32-cell grid so every cell
    /// lands on whole pixels at `heroScale`.
    ///
    /// Larger than the shipped default: the old hero framed him at 12% of its
    /// width and the top 40% of the frame was empty. He is the subject, so he
    /// gets to be the size of one.
    static let spriteSide: CGFloat = 128

    // MARK: - Vertical social reel

    /// 9:16 in points; ×3 gives 1080×1920, the size Instagram wants.
    static let verticalCanvas = CGSize(width: 360, height: 640)
    static let verticalScale: CGFloat = 3
    /// 30fps — what social players expect, and it divides 15s exactly.
    static let verticalFPS: Int32 = 30
    /// Bigger than the hero's: a reel is watched at thumb size on a phone, so
    /// the subject has to survive being a few centimetres tall.
    /// A whole number of cells at ×3 (256×3 = 768, a multiple of 32). 264 was
    /// 8.25 points per cell and smeared every fourth column.
    static let verticalSpriteSide: CGFloat = 256

    /// 16:9 in points; ×3 gives 1920×1080.
    static let landscapeCanvas = CGSize(width: 640, height: 360)
    static let landscapeSpriteSide: CGFloat = 224

    /// Renders the 15-second vertical reel as an MP4.
    ///
    /// MP4 rather than GIF because a reel cannot be a GIF — and at 1080×1920 a
    /// GIF would be both enormous and stuck at 256 colours, which is exactly the
    /// constraint the committed loops are designed around and this is not.
    static func renderVertical(to url: URL) -> Bool {
        encodeReel(to: url) { verticalScene(at: $0) }
    }

    /// The same fifteen seconds, laid out wide — for platforms that want 16:9.
    static func renderLandscape(to url: URL) -> Bool {
        encodeReel(to: url) { landscapeScene(at: $0) }
    }

    /// Renders the reel script frame by frame and encodes it.
    ///
    /// Both aspects run the same clock and the same beats, so the timing cannot
    /// drift between cuts.
    static func encodeReel<V: View>(to url: URL, scene: (Double) -> V) -> Bool {
        // STREAMED, one frame in flight. Buffering all 450 3x frames into an
        // array peaked at 2.37 GB RSS — measured — while the strictly heavier
        // sizzle render sat under 700 MB because it already used this
        // overload. The array bought nothing but the footprint.
        let count = Int((DemoMode.reelSeconds * Double(verticalFPS)).rounded())
        return VideoWriter.write(to: url, fps: verticalFPS, frameCount: count) { index in
            SpriteImage.cgImage(of: scene(Double(index) / Double(verticalFPS)),
                                scale: verticalScale, isOpaque: true)
        }
    }

    /// A still from the reel, for the cover frame social platforms ask for.
    ///
    /// Taken from the cooking beat rather than frame zero: a cover is a
    /// thumbnail competing in a grid, and the fire is the one frame that reads
    /// at that size.
    static func renderPoster(to url: URL) -> Bool {
        let coverAt = DemoMode.reelScript.prefix(3).reduce(0) { $0 + $1.seconds } + 1.2
        return SpriteImage.write(
            SpriteImage.png(of: verticalScene(at: coverAt), scale: verticalScale, isOpaque: true),
            to: url)
    }

    /// The pet as both reels draw him: bubble above, sprite below, party applied.
    ///
    /// Shared so the two aspects cannot drift — the beat, the clock and the
    /// party handling live in one place and only the layout around them differs.
    @ViewBuilder
    static func reelPet(at elapsed: Double, spriteSide: CGFloat,
                        showsBubble: Bool = true) -> some View {
        let cue = DemoMode.reelCue(at: elapsed)
        let t = cue.since
        let party = cue.beat.rainbow
        let mood = party ? (CrabView.rainbowMood(elapsed: t) ?? cue.beat.mood) : cue.beat.mood

        var pose = CrabAnimator.pose(mood: mood, t: t)
        let _ = { if party { pose.mouth = .open; pose.confettiElapsed = t } }()

        // The sprite frame carries about ten empty grid rows above the body —
        // headroom the props grow into. Left alone, the bubble floats a long way
        // off his head on any beat without a tall prop. `PetRootView` solves the
        // same problem by overlapping the bubble into that crown, so reuse its
        // constant rather than inventing a second number: one cell here is
        // `spriteSide / 32`.
        let crown = CGFloat(PetRootView.crownCells) * spriteSide / CGFloat(PixelBuffer.side)

        VStack(spacing: -crown) {
            if showsBubble {
                ThoughtBubble(text: cue.beat.bubble ?? "",
                          tool: cue.beat.tool,
                          mood: cue.beat.mood,
                          style: cue.beat.style,
                          frozenTime: t)
                // Above the sprite, not below it. A VStack draws later children
                // on top, so without this the fire on the cooking beat grows up
                // through the overlap and covers its own caption. Behind the
                // bubble it reads as a flame licking up past it instead.
                .zIndex(1)
            }
            PixelCanvasView(buffer: CrabRig.render(pose),
                            bodyTint: party ? CrabView.rainbowTint(elapsed: t) : nil,
                            seamBleed: 0)
                .frame(width: spriteSide, height: spriteSide)
        }
    }

    /// One frame of a clean plate: the pet on the backdrop, centred, with no
    /// wordmark, tagline or URL.
    ///
    /// For editing elsewhere — titles, captions and calls to action get added in
    /// the edit rather than baked in, and a plate with type burned into it is
    /// worth very little to whoever is cutting it.
    @ViewBuilder
    static func plateScene(at elapsed: Double, canvas: CGSize,
                           spriteSide: CGFloat, showsBubble: Bool) -> some View {
        ZStack {
            Backdrop()
            reelPet(at: elapsed, spriteSide: spriteSide, showsBubble: showsBubble)
                // Without the bubble the group is shorter, so nudge it back to
                // where the eye expects the character to sit.
                .offset(y: showsBubble ? 0 : spriteSide * 0.06)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    /// Both aspects, with and without the speech bubble.
    static func renderPlates(to root: URL) -> Bool {
        let cuts: [(name: String, canvas: CGSize, sprite: CGFloat)] = [
            ("9x16", verticalCanvas, verticalSpriteSide),
            ("16x9", landscapeCanvas, landscapeSpriteSide),
        ]
        for cut in cuts {
            for showsBubble in [true, false] {
                let suffix = showsBubble ? "clean" : "bare"
                let url = root.appendingPathComponent("clawd-\(suffix)-\(cut.name).mp4")
                guard encodeReel(to: url, scene: {
                    plateScene(at: $0, canvas: cut.canvas,
                               spriteSide: cut.sprite, showsBubble: showsBubble)
                }) else { return false }
            }
        }
        return true
    }

    /// One frame of the 16:9 cut.
    ///
    /// Side by side rather than stacked. A wide frame only has height to spare
    /// if nothing is competing for it, and stacking a wordmark, a bubble, a
    /// sprite and a URL into 360 points leaves all four cramped. Putting the
    /// words in a left column gives the pet the full height and gives the type
    /// somewhere to breathe.
    @ViewBuilder
    static func landscapeScene(at elapsed: Double) -> some View {
        ZStack {
            Backdrop()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CLAUDE PET")
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Palette.kraft)
                        .tracking(4)
                    Text("what Claude Code is doing,\non your desktop")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.kraft.opacity(0.72))
                        .lineSpacing(3)
                    Text("github.com/internetdialup/claude-pet")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.kraft.opacity(0.6))
                        .padding(.top, 6)
                }
                .padding(.leading, 52)

                Spacer(minLength: 12)

                reelPet(at: elapsed, spriteSide: landscapeSpriteSide)
                    .padding(.trailing, 44)
            }
        }
        .frame(width: landscapeCanvas.width, height: landscapeCanvas.height)
        .clipped()
    }

    /// One frame of the vertical reel.
    ///
    /// The ocean ramp already darkens top to bottom, which is why it suits a
    /// tall frame better than a wide one — the surface sits behind the wordmark
    /// and the abyss behind the feet, with no extra work.
    @ViewBuilder
    static func verticalScene(at elapsed: Double) -> some View {
        ZStack {
            Backdrop()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("CLAUDE PET")
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Palette.kraft)
                        .tracking(3)
                    Text("what Claude Code is doing,\non your desktop")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.kraft.opacity(0.72))
                        .lineSpacing(2)
                }
                .padding(.top, 56)

                Spacer(minLength: 0)

                reelPet(at: elapsed, spriteSide: verticalSpriteSide)

                // Weighted lighter than the spacer above, so the pet sits just
                // below centre — where a thumb is not covering it.
                Spacer(minLength: 0).frame(maxHeight: 40)

                Text("github.com/internetdialup/claude-pet")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.kraft.opacity(0.6))
                    .padding(.bottom, 56)
            }
        }
        .frame(width: verticalCanvas.width, height: verticalCanvas.height)
        .clipped()
    }

    // MARK: - Committed assets

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch { return false }

        return renderHero(to: root.appendingPathComponent("desktop.gif"))
            && renderRoster(to: root.appendingPathComponent("roster.png"))
            && renderBubbles(to: root.appendingPathComponent("bubbles.png"))
            && renderProps(to: root.appendingPathComponent("props.png"))
            && renderFacts(to: root.appendingPathComponent("facts.png"))
            && renderCostumes(to: root.appendingPathComponent("costumes.gif"))
            && renderWordmark(to: root.appendingPathComponent("wordmark.png"))
            && renderSocialPreview(to: root.appendingPathComponent("social-preview.png"))
    }

    // MARK: - The hero

    /// The demo script, rendered frame by frame.
    ///
    /// **`reelScript`, not `script`** — fifteen seconds rather than
    /// twenty-seven and a half. The long one is the better catalogue: it walks
    /// nine beats and includes the status ticker. But this is the first thing
    /// on a store page, watched by someone deciding in a few seconds whether to
    /// keep reading, and twenty-seven is past where that decision gets made.
    ///
    /// Nothing was authored for this. `reelScript` already existed for the
    /// vertical social cut, tuned by the same hand for the same reason, and its
    /// own note makes the argument for here too: it "drops the two marquee
    /// beats — a scrolling ticker is illegible at thumb size", which is equally
    /// true of a GIF embedded at a README's column width.
    ///
    /// The cost is honest and paid elsewhere: the ticker no longer appears in
    /// the hero, so `renderFacts` shows marquee lines mid-scroll instead, in
    /// the part of the page that is actually talking about them.
    static func renderHero(to url: URL) -> Bool {
        // COUNTED, not accumulated. `while elapsed < seconds` stepping by 0.1
        // in a Double overshoots: 15.0s came out as 151 frames, because the
        // running total lands a hair under 15 on the last pass. The count is
        // exact arithmetic and the timestamps are derived from it.
        let frames = Int((DemoMode.reelSeconds / heroFrameDelay).rounded())
        var images: [CGImage] = []
        for frame in 0..<frames {
            guard let image = SpriteImage.cgImage(of: heroScene(at: Double(frame) * heroFrameDelay),
                                                  scale: heroScale, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: heroFrameDelay)
    }

    /// One frame of the reel.
    @ViewBuilder
    static func heroScene(at elapsed: Double) -> some View {
        let cue = DemoMode.reelCue(at: elapsed)
        // Beat-relative, so the one-shot moods fire. `MoodClock` does this for
        // the live app; offline there is nothing to rebase the clock but us.
        let t = cue.since
        let party = cue.beat.rainbow
        let mood = party ? (CrabView.rainbowMood(elapsed: t) ?? cue.beat.mood) : cue.beat.mood

        var pose = CrabAnimator.pose(mood: mood, t: t)
        let _ = { if party { pose.mouth = .open; pose.confettiElapsed = t } }()

        ZStack {
            // The hero wears the operator's own sky. The other reel surfaces
            // keep the ocean — this is the one frame anybody lands on.
            Backdrop(style: .sky)
            VStack(spacing: 0) {
                // Every scripted beat carries a bubble; the optional is for the
                // live path, where a state can genuinely have nothing to say.
                ThoughtBubble(text: cue.beat.bubble ?? "",
                              tool: cue.beat.tool,
                              mood: cue.beat.mood,
                              style: cue.beat.style,
                              frozenTime: t)
                PixelCanvasView(buffer: CrabRig.render(pose),
                                bodyTint: party ? CrabView.rainbowTint(elapsed: t) : nil,
                                seamBleed: 0)
                    .frame(width: spriteSide, height: spriteSide)
            }
            // Nudged down so the bubble has headroom rather than sitting on the
            // top edge of the frame.
            .offset(y: 10)
        }
        .frame(width: heroCanvas.width, height: heroCanvas.height)
        .clipped()
    }

    // MARK: - Stills

    /// The session roster.
    ///
    /// `DemoMode.sessions` was written so a recording could show this panel
    /// without publishing the operator's real project directories, and until now
    /// that safety work had never produced an asset — the README's own "click
    /// him" section illustrated the roster with a picture of the crab.
    ///
    /// Driven at t=7.0 (the working beat) with the *second* session pinned, so
    /// one still exercises three different status dots, the focus highlight, the
    /// pin badge, and the unpin button — which only appears when something is
    /// pinned and is otherwise invisible in any asset.
    static func renderRoster(to url: URL) -> Bool {
        let panel = RosterPanel(state: DemoMode.state(at: 7.0),
                                pinnedID: DemoMode.sessions.count > 1 ? DemoMode.sessions[1].id : nil,
                                onPin: { _ in },
                                scrolls: false)
            // The panel leans on semantic colours — `.secondary`, `.tertiary`,
            // `Divider` — which resolve against the *light* appearance when
            // there is no window to inherit one from, so an offline render comes
            // out near-black text on a dark plate. The live popover gets this
            // from its NSPopover; offline we have to say it.
            .environment(\.colorScheme, .dark)
            .background(Palette.slate)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(20)
            .background(Palette.Ocean.deep)

        return SpriteImage.write(SpriteImage.png(of: panel, scale: 2, isOpaque: true), to: url)
    }

    /// One bubble per mood, for the 95 lines of the vocabulary section that had
    /// no picture of the thing they are about.
    static func renderBubbles(to url: URL) -> Bool {
        let shown = PetMood.allCases.filter { $0 != .sleeping }
        // TWO columns, because the page is wide and this used to be a portrait
        // strip sitting in a full-width slot — which is what made the README's
        // right edge look ragged next to the tables.
        let split = (shown.count + 1) / 2
        let columns = [Array(shown.prefix(split)), Array(shown.dropFirst(split))]
        let sheet = HStack(alignment: .top, spacing: 28) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(column, id: \.self) { mood in
                        HStack(spacing: 12) {
                    // First line that actually fits: the sheet is showing what a
                    // bubble looks like, and one cut off mid-word demonstrates
                    // the 29-character limit rather than the bubble.
                    ThoughtBubble(text: mood.style.previewBubble
                                    ?? Vocab.lines(for: mood.shoutoutOccasion).first { $0.count <= 29 }
                                    ?? mood.rawValue,
                                  tool: mood == .working ? "Bash" : nil,
                                  mood: mood,
                                  style: mood == .thinking ? .dots : .plain,
                                  frozenTime: 0.4)
                            Text(mood.rawValue)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Palette.kraft.opacity(0.55))
                        }
                    }
                }
            }
        }
        .padding(24)
        // The hero's own sky, dimmed. Flat abyss made this read as a different
        // document from the rest of the page; the same quantised material ties
        // them together, and the scrim keeps the bubbles the subject rather
        // than letting the streak compete with them.
        .background {
            ZStack {
                Backdrop(style: .sky)
                Palette.Ocean.abyss.opacity(0.58)
            }
        }

        return SpriteImage.write(SpriteImage.png(of: sheet, scale: 2, isOpaque: true), to: url)
    }

    /// What he knows, and the two shapes it arrives in.
    ///
    /// The README claims seventy-six facts and, until this, showed none of
    /// them. It also describes the plain/ticker split in prose — which is
    /// exactly the sort of thing a picture settles in one glance.
    ///
    /// So the sheet is deliberately mixed: real lines from `FunFacts`, one
    /// short enough to sit still and the rest long enough to scroll, each drawn
    /// through the actual `ThoughtBubble` at a frozen instant rather than mocked
    /// up. The long ones are captured mid-travel, because a ticker caught at
    /// its start looks identical to a plain bubble and would prove nothing.
    static func renderFacts(to url: URL) -> Bool {
        // Word-aligned freezes. A marquee frozen at an arbitrary instant cuts a
        // word at the left edge ("pic is a public benefi"), which reads as a
        // glitch in a product still. Each offset below is the instant the
        // viewport's left edge lands exactly on a word start:
        // seconds = (characters before the word) x 6.62pt / 26pt-per-second.
        // The right edge still cuts — that is what says "this scrolls".
        //
        // Lines are drawn from the pools by TEXT, not by index, so a reordered
        // pool fails the render loudly instead of silently swapping the shot.
        let picked: [(text: String, at: Double)] = [
            ("A byte is usually eight bits", 0),                                  // plain — sits still
            ("Anthropic has published Claude's constitution 📜", 0),              // opens on word one
            ("Claw'd is unofficial fan art, not affiliated with Anthropic 🦀",
             10 * 6.62 / 26),                                                     // opens on "unofficial"
            ("Deep Blue beat a reigning world chess champion in 1997 🏆",
             17 * 6.62 / 26),                                                     // opens on "reigning"
            ("Andrej Karpathy coined 'vibe coding' in February 2025 ⚡",
             16 * 6.62 / 26),                                                     // opens on "coined"
        ]
        // Every line must really be in the pools — the sheet shows what he
        // says, not marketing copy that resembles it.
        guard picked.dropFirst().allSatisfy({ FunFacts.all.contains($0.text) }),
              FunFacts.facts(in: .compSci101).contains(picked[0].text)
        else { return false }
        let split = (picked.count + 1) / 2
        let columns = [Array(picked.prefix(split)), Array(picked.dropFirst(split))]
        let sheet = HStack(alignment: .top, spacing: 28) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(column.enumerated()), id: \.offset) { _, item in
                        ThoughtBubble(text: item.text,
                                      tool: nil,
                                      mood: .idle,
                                      style: ActivityCoordinator.bubbleStyle(for: item.text),
                                      frozenTime: item.at)
                    }
                }
            }
        }
        .padding(24)
        .background {
            ZStack {
                Backdrop(style: .sky)
                Palette.Ocean.abyss.opacity(0.58)
            }
        }

        return SpriteImage.write(SpriteImage.png(of: sheet, scale: 2, isOpaque: true), to: url)
    }

    // MARK: - The brand

    /// The README's masthead: him, the name, and one sentence, on his sky.
    ///
    /// Replaces a plain `<h1>` — a store page opens with a wordmark, not a
    /// heading. Rendered like every other committed asset (the real rig, the
    /// real backdrop, byte-reproducible) so the brand is the product rather
    /// than a graphic that resembles it.
    static func renderWordmark(to url: URL) -> Bool {
        let view = ZStack {
            Backdrop(style: .sky)
            // A light scrim: the streak crosses the tagline's tail, and white
            // on the sky's lightest stop is not legible enough for a masthead.
            Palette.Ocean.abyss.opacity(0.35)
            HStack(spacing: 22) {
                PixelCanvasView(buffer: CrabRig.render(
                                    CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)),
                                seamBleed: 0)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Pet")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Your Claude Code sessions, as a crab on your desk")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .frame(width: 640, height: 130)
        return SpriteImage.write(SpriteImage.png(of: view, scale: 2, isOpaque: true), to: url)
    }

    /// The 1280x640 card social sites unfurl when the repo link is pasted.
    ///
    /// GitHub has no API for setting it — the operator uploads this at
    /// Settings → Social preview. Without one, a LinkedIn or HN paste shows a
    /// grey auto-card, which is the first impression most people will ever get
    /// of the project.
    ///
    /// The cast is frozen mid-kickflip on purpose: a still has one instant to
    /// say "this thing is alive", and the trick at its peak is that instant.
    static func renderSocialPreview(to url: URL) -> Bool {
        // DERIVED from the cast, not restated: this sat at "onset 3.2 + 1.4"
        // while the pack retimed the onset to 4.4, and the og-image quietly
        // became a crab barely off the ground — found by the media byte-check,
        // the same way every restated constant in this repo has been found.
        let midFlip = (costumeCast[1].onsets.first ?? 0) + 1.4
        let view = ZStack {
            Backdrop(style: .sky)
            VStack(spacing: 10) {
                Text("Claude Pet")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Your Claude Code sessions, as a crab on your desk")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(costumeCast.enumerated()), id: \.offset) { index, member in
                        PixelCanvasView(
                            buffer: CrabRig.render(costumePose(member, at: midFlip),
                                                   costume: member.costume),
                            inkOverrides: CostumeStyle.blendedOverrides(from: member.costume,
                                                                       to: member.costume, u: 1),
                            seamBleed: 0)
                            .frame(width: member.side, height: member.side)
                            .offset(y: index == 1 ? 4 : -6)
                    }
                }
            }
        }
        .frame(width: 640, height: 320)
        return SpriteImage.write(SpriteImage.png(of: view, scale: 2, isOpaque: true), to: url)
    }

    // MARK: - The wardrobe

    /// Ten seconds, and the second thing on the store page.
    ///
    /// The wardrobe is the most screenshot-able thing in the app and had no
    /// picture anywhere. Three at once rather than a contact sheet of ten:
    /// three reads as a cast, ten reads as a settings screen.
    ///
    /// **Ten seconds because attention is the constraint**, not because ten is
    /// a round number. The same reasoning trimmed the hero to fifteen.
    /// Thirteen, and not a round number by accident: gundam's fact needs
    /// 11.97s for one full scroll, and the seam rule says the clip must
    /// contain a WHOLE cycle — the marquee's `loopSeconds` stretches its gap
    /// to make the cycle exactly this. Ten seconds decapitated the sentence at
    /// every wrap, which was the operator's "jarring cut". Still under the
    /// 25-second attention ceiling.
    static let costumeSeconds = 13.0

    /// Who stands where, and what they do.
    ///
    /// The outer two wiggle on deliberately different beats — synchronised
    /// idling reads as one animation drawn three times, which is the opposite
    /// of what a wardrobe strip is for. The middle one lands the kickflip,
    /// because the eye goes to the centre and that is the trick worth spending
    /// it on.
    ///
    /// Every window is closed well inside the ten seconds. Nothing may be in
    /// flight at t=0 or at the loop point, for the reason
    /// `theSleepingClipIsOneWholeBreath` gives: a clip that does not close
    /// shows a seam every time it repeats.
    /// Claw'd himself holds the centre and lands the trick. The operator's
    /// call, and the right one: the strip is the brand's second hero, and the
    /// brand is the orange crab — the costumes are his wardrobe, not his
    /// replacements. `.none` here is not "undressed", it is the mascot.
    ///
    /// **Each crab speaks for himself now** — one shared bubble made the strip
    /// a slideshow with three extras. Gundam reads an Anthropic fact the whole
    /// clip; the ninja just thinks (the dots — he is a ninja, he does not
    /// explain himself); Claw'd lands the kickflip and THEN shouts, which is
    /// the order a shout happens in. `line: nil` means the dots.
    ///
    /// **And the flanks are smaller.** 96 against Claw'd's 128 — both whole
    /// multiples of the 32-cell grid at heroScale, so no cell lands on a
    /// fractional pixel — and raised a few points, so the strip reads as a
    /// pack with the mascot at the front of it rather than a police lineup.
    static let costumeCast: [(costume: Costume, flourish: CrabAnimator.Flourish,
                              onsets: [Double], line: String?, lineFrom: Double,
                              side: CGFloat)] = [
        (.gundam, .wiggle,   [1.4, 9.6],
         "Anthropic has published Claude's constitution 📜", 0.0, 96),
        (.none,   .kickflip, [4.4], "Tony Clawd 900 🦅", 7.2, 128),
        // A wave, not a second wiggle: two crabs doing the same idle reads as
        // one animation stamped twice, which is the opposite of a wardrobe.
        (.ninja,  .wave,     [2.2, 10.4], nil, 0.0, 96),
    ]

    static func renderCostumes(to url: URL) -> Bool {
        // Counted rather than accumulated — same reason as `renderHero`.
        let frames = Int((costumeSeconds / heroFrameDelay).rounded())
        var images: [CGImage] = []
        for frame in 0..<frames {
            guard let image = SpriteImage.cgImage(of: costumeScene(at: Double(frame) * heroFrameDelay),
                                                  scale: heroScale, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: heroFrameDelay)
    }

    /// The pose for one member of the cast at `elapsed`.
    ///
    /// Outside its own window a crab holds the STILL idle pose — `t: 0` rather
    /// than `t: elapsed`. Idle breathes on a cycle that does not divide ten, so
    /// letting it run would put the three of them in a different phase at the
    /// loop point than at the start, and the seam would be the whole strip
    /// twitching once every ten seconds.
    static func costumePose(_ member: (costume: Costume, flourish: CrabAnimator.Flourish,
                                       onsets: [Double], line: String?, lineFrom: Double,
                                       side: CGFloat),
                            at elapsed: Double) -> CrabPose {
        for onset in member.onsets where elapsed >= onset
            && elapsed < onset + member.flourish.duration {
            return CrabAnimator.flourishPose(member.flourish, at: elapsed - onset)
        }
        return CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
    }

    /// One frame of the wardrobe strip.
    @ViewBuilder
    static func costumeScene(at elapsed: Double) -> some View {
        ZStack {
            Backdrop(style: .sky)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(costumeCast.enumerated()), id: \.offset) { index, member in
                    VStack(spacing: 0) {
                        // Every crab keeps a bubble SLOT even while silent, so
                        // the three stand on one baseline instead of the mute
                        // one riding up by a bubble's height.
                        Group {
                            if let line = member.line, member.lineFrom == 0 {
                                // A marquee that runs from the clip's own zero
                                // closes its loop at `costumeSeconds` exactly —
                                // that is the whole point of `loopSeconds`.
                                ThoughtBubble(text: line, tool: nil, mood: .idle,
                                              style: ActivityCoordinator.bubbleStyle(for: line),
                                              frozenTime: elapsed,
                                              loopSeconds: costumeSeconds)
                            } else if let line = member.line {
                                // The shout: eased in at the landing, eased
                                // out before the wrap, exactly as the solos do
                                // it — so the seam carries no text pop, only
                                // the marquee's single frame-step of travel.
                                ThoughtBubble(text: line, tool: nil, mood: .idle,
                                              style: .plain, frozenTime: 0)
                                    .opacity(Ease.amount(now: elapsed,
                                                         since: member.lineFrom,
                                                         endedAt: costumeSeconds - 0.7))
                            } else if member.line == nil {
                                // FROZEN dots, one phase. Their pulse cycle is
                                // 1.36s and 13.0 is not a multiple of it, so a
                                // ticking thought would twitch at the wrap. A
                                // ninja can hold a thought.
                                ThoughtBubble(text: "…", tool: nil, mood: .thinking,
                                              style: .dots, frozenTime: 0.68)
                            } else {
                                Color.clear
                            }
                        }
                        // Fixed WIDTH as well as height. The slot sized
                        // itself to its content, so the instant Claw'd's shout
                        // appeared his column widened and shoved both flanks
                        // sideways — 44k crab-band pixels moved in one frame,
                        // measured. A bubble slot is chrome; chrome does not
                        // get to relayout the cast.
                        .frame(width: 178, height: 44)
                        PixelCanvasView(
                            buffer: CrabRig.render(costumePose(member, at: elapsed),
                                                   costume: member.costume),
                            inkOverrides: CostumeStyle.blendedOverrides(from: member.costume,
                                                                       to: member.costume, u: 1),
                            seamBleed: 0)
                            .frame(width: member.side, height: member.side)
                    }
                    // The flanks stand a step behind the mascot.
                    .offset(y: index == 1 ? 6 : -8)
                }
            }
        }
        .frame(width: costumeCanvas.width, height: costumeCanvas.height)
        .background(Palette.Ocean.abyss)
    }

    /// Wider than the hero, because three crabs stand in it.
    static let costumeCanvas = CGSize(width: 560, height: 210)
    /// Whole multiples of the 32-cell grid at `heroScale`, so no cell lands on
    /// a fractional device pixel.
    static let costumeSprite: CGFloat = 112

    /// Every prop in one strip, so the README's list of them is concrete.
    ///
    /// On slate rather than the ocean: four of the twelve props are drawn in
    /// `screenDark`/`screenLight` navy — the terminal, the servers, the
    /// balloon, the phone — and navy on navy water runs about 1.4:1. This strip
    /// illustrates the rig, not the marketing scene, so it gets the ground that
    /// shows every prop rather than the one that matches the hero.
    static func renderProps(to url: URL) -> Bool {
        let props = CrabPose.Prop.allCases.filter { $0 != .none }
        let strip = HStack(spacing: 0) {
            ForEach(Array(props.enumerated()), id: \.offset) { _, prop in
                var pose = CrabPose()
                let _ = { pose.prop = prop; pose.propPhase = 0.8 }()
                ZStack {
                    Palette.slate
                    PixelCanvasView(buffer: CrabRig.render(pose), seamBleed: 0)
                }
                .frame(width: 96, height: 96)
            }
        }

        return SpriteImage.write(SpriteImage.png(of: strip, scale: 2, isOpaque: true), to: url)
    }
}
