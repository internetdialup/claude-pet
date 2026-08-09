import SwiftUI
import AppKit

/// Renders composed scenes — the pet in a framed shot, the roster, the bubbles,
/// the props — entirely from code.
///
/// The reel this replaces was a screen recording, and a screen recording carries
/// whatever the operating system chose to draw at capture time. A real
/// notification banner from an unrelated project was frozen into all 192 frames
/// of the README hero and published (`docs/ctx-orientation.md`, Knob v1.2.1).
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
    static let verticalSpriteSide: CGFloat = 264

    /// Renders the 15-second vertical reel as an MP4.
    ///
    /// MP4 rather than GIF because a reel cannot be a GIF — and at 1080×1920 a
    /// GIF would be both enormous and stuck at 256 colours, which is exactly the
    /// constraint the committed loops are designed around and this is not.
    static func renderVertical(to url: URL) -> Bool {
        let total = DemoMode.reelSeconds
        let count = Int((total * Double(verticalFPS)).rounded())
        var images: [CGImage] = []
        images.reserveCapacity(count)

        for index in 0..<count {
            let elapsed = Double(index) / Double(verticalFPS)
            guard let image = SpriteImage.cgImage(of: verticalScene(at: elapsed),
                                                  scale: verticalScale, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return VideoWriter.write(images, to: url, fps: verticalFPS)
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

    /// One frame of the vertical reel.
    ///
    /// The ocean ramp already darkens top to bottom, which is why it suits a
    /// tall frame better than a wide one — the surface sits behind the wordmark
    /// and the abyss behind the feet, with no extra work.
    @ViewBuilder
    static func verticalScene(at elapsed: Double) -> some View {
        let cue = DemoMode.reelCue(at: elapsed)
        let t = cue.since
        let party = cue.beat.rainbow
        let mood = party ? (CrabView.rainbowMood(elapsed: t) ?? cue.beat.mood) : cue.beat.mood

        var pose = CrabAnimator.pose(mood: mood, t: t)
        let _ = { if party { pose.mouth = .open } }()

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

                VStack(spacing: 0) {
                    ThoughtBubble(text: cue.beat.bubble ?? "",
                                  tool: cue.beat.tool,
                                  mood: cue.beat.mood,
                                  style: cue.beat.style,
                                  frozenTime: t)
                    PixelCanvasView(buffer: CrabRig.render(pose),
                                    bodyTint: party ? CrabView.rainbowTint(elapsed: t) : nil,
                                    seamBleed: 0)
                        .frame(width: verticalSpriteSide, height: verticalSpriteSide)
                }

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
    }

    // MARK: - The hero

    /// The demo script, rendered frame by frame.
    static func renderHero(to url: URL) -> Bool {
        var images: [CGImage] = []
        var elapsed = 0.0
        while elapsed < DemoMode.totalSeconds {
            guard let image = SpriteImage.cgImage(of: heroScene(at: elapsed),
                                                  scale: heroScale, isOpaque: true)
            else { return false }
            images.append(image)
            elapsed += heroFrameDelay
        }
        return GifRenderer.encode(images, to: url, frameDelay: heroFrameDelay)
    }

    /// One frame of the reel.
    @ViewBuilder
    static func heroScene(at elapsed: Double) -> some View {
        let cue = DemoMode.cue(at: elapsed)
        // Beat-relative, so the one-shot moods fire. `MoodClock` does this for
        // the live app; offline there is nothing to rebase the clock but us.
        let t = cue.since
        let party = cue.beat.rainbow
        let mood = party ? (CrabView.rainbowMood(elapsed: t) ?? cue.beat.mood) : cue.beat.mood

        var pose = CrabAnimator.pose(mood: mood, t: t)
        let _ = { if party { pose.mouth = .open } }()

        ZStack {
            Backdrop()
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
        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(shown, id: \.self) { mood in
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
        .padding(18)
        .background(Palette.Ocean.abyss)

        return SpriteImage.write(SpriteImage.png(of: sheet, scale: 2, isOpaque: true), to: url)
    }

    /// Every prop in one strip, so the README's list of them is concrete.
    ///
    /// On slate rather than the ocean: five of the twelve props are drawn in
    /// `screenDark`/`screenLight` navy — the terminal, the servers, the z's, the
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
