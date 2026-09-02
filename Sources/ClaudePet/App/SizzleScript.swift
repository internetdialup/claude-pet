import Foundation

/// The sizzle reel's master script: eight chapters, six cuts, two plates.
///
/// Everything here is data — the renderer walks it with a frame clock and
/// pure pose functions, so the same chapter renders byte-identically at any
/// canvas. Every string is fabricated (the anonymity rule for recordings:
/// nothing real ever enters a committed asset). Chapter clocks are LOCAL;
/// the dice-locked chapters carry base offsets chosen so the deterministic
/// schedules actually fire on camera:
/// - `cookBase = 269.0`: the cooking beat lands the fire prop, the heat
///   cascade window [272.0, 274.4) and a full eased disco ([270, 275)) in
///   one six-second shot.
/// - `workBase = 20.0`: working spell cycle 1 rolls the terminal, with the
///   0.35s eased prop pick-up at the spell seam for free.
@MainActor
enum SizzleScript {

    enum Chapter: CaseIterable {
        case wake, mirror, glyphs, cook, finale, montage, duet, outro
    }

    /// One entry of a cut: play `seconds` of `chapter`.
    struct Segment {
        enum Kind {
            /// Enter the chapter's fixed local clock at `offset` — for the
            /// dice-locked chapters, where mid-effect entry is a cut, not a
            /// snap.
            case window(offset: Double)
            /// Re-lay the chapter's beats proportionally into `seconds`.
            case scaled
        }
        let chapter: Chapter
        let kind: Kind
        let seconds: Double
    }

    /// What kind of output a cut is — the renderer's Format dispatches on
    /// this, never on canvas/fps heuristics (the meme cut is heuristically
    /// identical to the landscape master).
    enum Family { case master, readme, meme, plate, showcase }

    /// What stands behind him. Ocean is the committed-asset classic;
    /// gradient and forest are showcase scenery — MP4-only by usage, so the
    /// GIF palette doctrine never meets the gradient.
    enum Scenery { case ocean, gradient, forest }

    struct Cut {
        let name: String
        /// Canvas in points; frames render at `canvas × scale` pixels.
        let canvas: CGSize
        let scale: CGFloat
        let fps: Int32
        let family: Family
        var scenery: Scenery = .ocean
        let segments: [Segment]
        var seconds: Double { segments.reduce(0) { $0 + $1.seconds } }
        var frameCount: Int { Int((seconds * Double(fps)).rounded()) }
    }

    // MARK: - The clocks

    static let cookBase = 269.0
    static let workBase = 20.0

    /// Master chapter durations, in play order. Sum: exactly 45.0.
    ///
    /// The montage is `montageOrder.count` seconds BY CONSTRUCTION — one beat
    /// per look. It sat at 8.0 while the order grew to ten, which silently cut
    /// Arcade and Classic from every cut and left the README loop seam a
    /// costume pop; and the obvious fix alone would have indexed one second
    /// past the renderer's pose table and trapped. The two seconds came out of
    /// the finale, which at ten was the longest chapter by a wide margin.
    static let masterSeconds: [Chapter: Double] = [
        .wake: 2.5, .mirror: 5.5, .glyphs: 6.0, .cook: 6.0,
        .finale: 8.0, .montage: Double(montageOrder.count), .duet: 4.0, .outro: 3.0,
    ]

    /// The montage's running order — ends on Classic so the README GIF's
    /// loop seam is a mood-only cut.
    static let montageOrder: [Costume] =
        [.ninja, .retroBlack, .matrix, .tiger, .white, .gundam, .sonic, .frankenstein,
         .arcade, .pumpkin, .turkey, .santa, .none]

    /// The glyph chapter shows every service, one eased beat each.
    static let glyphBeats: [(glyph: ServiceGlyph, bubble: String)] = [
        (.npm, "npm install"),
        (.github, "git push --force"),
        (.linear, "LIN-407 in review"),
        (.deploy, "vercel deploy --prod"),
    ]

    // MARK: - The words (all fabricated)

    static let wordmark = "CLAUDE PET"
    static let tagline = "what Claude Code is doing,\non your desktop"
    static let url = "github.com/internetdialup/claude-pet"

    static let captions: [Chapter: String] = [
        .mirror: "he mirrors your Claude Code sessions",
        .glyphs: "he knows what you're shipping",
        .cook: "when it cooks, he cooks",
        .finale: "and when a big one lands…",
        .montage: "13 LOOKS",
        .duet: "summon a second",
    ]

    static let mirrorBubble = "Wiring the pipeline"
    static let cookBubble = "Absolutely cooking 🔥"

    /// The meme cut's language: two words, maximum volume.
    static let memeCaptions: [Chapter: String] = [
        .glyphs: "HE SHIPS",
        .cook: "HE COOKS",
        .finale: "BIG ONE",
        .montage: "13 LOOKS",
        .outro: "SHIP IT",
    ]

    // MARK: - The cuts

    /// The operator's runtime law: every clip under 25 seconds. The finale
    /// keeps its whole ten — the payoff IS the star — and everything else
    /// compresses around it through `.scaled`, camera included.
    static let landscape = Cut(
        name: "sizzle-16x9.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .master,
        segments: [
            Segment(chapter: .wake, kind: .scaled, seconds: 1.0),
            Segment(chapter: .mirror, kind: .scaled, seconds: 3.0),
            Segment(chapter: .glyphs, kind: .scaled, seconds: 2.8),
            Segment(chapter: .cook, kind: .window(offset: 2.0), seconds: 2.0),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 10.0),
            Segment(chapter: .montage, kind: .scaled, seconds: 3.2),
            Segment(chapter: .duet, kind: .scaled, seconds: 1.2),
            Segment(chapter: .outro, kind: .scaled, seconds: 1.0),
        ])

    static let vertical = Cut(
        name: "sizzle-9x16.mp4",
        canvas: CGSize(width: 360, height: 640), scale: 3, fps: 30,
        family: .master,
        segments: [
            Segment(chapter: .wake, kind: .scaled, seconds: 1.0),
            Segment(chapter: .glyphs, kind: .scaled, seconds: 2.8),
            Segment(chapter: .cook, kind: .window(offset: 1.5), seconds: 2.5),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 10.0),
            Segment(chapter: .montage, kind: .scaled, seconds: 4.0),
            Segment(chapter: .duet, kind: .scaled, seconds: 1.6),
            Segment(chapter: .outro, kind: .scaled, seconds: 1.2),
        ])

    static let readme = Cut(
        name: "sizzle-readme.gif",
        canvas: CGSize(width: 320, height: 180), scale: 2, fps: 10,
        family: .readme,
        segments: [
            Segment(chapter: .mirror, kind: .window(offset: 1.6), seconds: 3.0),
            Segment(chapter: .cook, kind: .window(offset: 1.2), seconds: 3.0),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 8.0),
            Segment(chapter: .montage, kind: .scaled, seconds: 5.5),
        ])

    /// The README cut again at 30fps, for socials that reject GIFs.
    static let readmeVideo = Cut(
        name: "sizzle-readme.mp4",
        canvas: readme.canvas, scale: readme.scale, fps: 30,
        family: .readme,
        segments: readme.segments)

    /// The meme cut: the greatest hits at attention-span speed. Windows
    /// enter the master camera curves mid-move; scaled segments compress
    /// beats and camera together. 10.4s — the operator's law, twice over:
    /// "people have shit attention spans", then "it needs to be faster".
    static let meme = Cut(
        name: "sizzle-meme.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .meme,
        segments: [
            Segment(chapter: .mirror, kind: .window(offset: 0.4), seconds: 1.2),
            Segment(chapter: .glyphs, kind: .scaled, seconds: 1.6),
            Segment(chapter: .cook, kind: .window(offset: 2.7), seconds: 1.2),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 3.2),
            Segment(chapter: .montage, kind: .scaled, seconds: 2.4),
            Segment(chapter: .outro, kind: .scaled, seconds: 0.8),
        ])

    /// The hook cut: 0.6s of the finale's flash as a cold open — the
    /// retention pattern socials reward — then the landscape master
    /// verbatim. 24.8s, still inside the law.
    ///
    /// The offset tracks the flash schedule and must keep doing so. It used to
    /// be 1.0, which worked only because the old tint pulsed every 1.2s and any
    /// window caught something; the flashbang fires on a sparse schedule, so
    /// 1.0 would now open on a decay tail. 2.05 lands on the epic apex tap AND
    /// the 1.2× transform's peak — he swells a fifth and detonates, which is a
    /// better cold open than the one this replaces. `hookOpensOnTheBang` fails
    /// if the schedule ever moves out from under it.
    static let hook = Cut(
        name: "sizzle-hook.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .master,
        segments: [Segment(chapter: .finale, kind: .window(offset: 2.05), seconds: 0.6)]
            + landscape.segments)

    /// The showcase cuts: the masters' choreography with the type stripped —
    /// "i dont need the text just show off the pet" — on the dusk gradient
    /// (the operator's pick). Bubbles and glyphs stay: they are the product,
    /// not the marketing.
    static let showcaseGradient = Cut(
        name: "showcase-gradient.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .showcase, scenery: .gradient,
        // No title card means the sleeping wake is dead air: text-free cuts
        // open on the thinking beat, face punch seconds away.
        segments: Array(landscape.segments.dropFirst()))

    static let showcaseGradientTall = Cut(
        name: "showcase-gradient-9x16.mp4",
        canvas: CGSize(width: 360, height: 640), scale: 3, fps: 30,
        family: .showcase, scenery: .gradient,
        segments: Array(vertical.segments.dropFirst()))

    /// The forest cuts left the render set on the operator's verdict: dark
    /// moving pine rows are worst-case low-luma motion for 8 Mbps H.264 —
    /// the "lighting glitch" was macroblocking, amplified by the finale
    /// glow over dark bands. ForestBackdrop stays in code; the fix path if
    /// it returns is a bitrate bump in VideoWriter.
    static let cuts: [Cut] = [landscape, vertical, readme, readmeVideo, meme, hook,
                              showcaseGradient, showcaseGradientTall]

    /// The green-screen plates: the master cuts' segments VERBATIM — the
    /// camera is pure in (chapter, localT, format), so every plate frame's
    /// sprite geometry matches the titled frame's and keyed footage stays
    /// in sync. A separate array so --render-sizzle doesn't implicitly drag
    /// 2310 more frames; --render-plates walks these.
    static let plate16x9 = Cut(
        name: "plate-16x9",
        canvas: landscape.canvas, scale: 3, fps: 30,
        family: .plate,
        segments: landscape.segments)

    static let plate9x16 = Cut(
        name: "plate-9x16",
        canvas: vertical.canvas, scale: 3, fps: 30,
        family: .plate,
        segments: vertical.segments)

    static let plates: [Cut] = [plate16x9, plate9x16]

    // MARK: - The beat map

    /// The editor's sidecar: every chapter boundary and intra-chapter beat as
    /// a TSV timeline, so music hits snap to cuts in Premiere without
    /// frame-counting. Labels are raw values only — nothing real leaks.
    static func beatMap(for cut: Cut) -> String {
        var lines = ["# \(cut.name) beats v1"]
        var cursor = 0.0

        func emit(_ time: Double, _ kind: String, _ label: String) {
            lines.append(String(format: "%.3f\t%@\t%@", time, kind, label))
        }

        for segment in cut.segments {
            emit(cursor, "chapter", String(describing: segment.chapter))

            // Intra-chapter beats at explicit master times, mapped through the
            // segment's clock. Explicit times rather than a (period, labels)
            // cadence because the finale's hits are the flashbang schedule,
            // which is deliberately irregular — and those are exactly the beats
            // an edit wants to cut music to.
            let beats: [(time: Double, label: String)]
            let kind: String
            switch segment.chapter {
            case .glyphs:
                beats = glyphBeats.enumerated().map { (Double($0.offset) * 1.5, $0.element.glyph.rawValue) }
                kind = "glyph"
            case .montage:
                beats = montageOrder.enumerated().map { (Double($0.offset) * 1.0, $0.element.rawValue) }
                kind = "look"
            case .finale:
                beats = (CrabView.celebrationFlashes + [CrabView.epicFlash])
                    .map { ($0.at, "flash") }
                kind = "flash"
            default:
                beats = []
                kind = ""
            }
            switch segment.kind {
            case .window(let offset):
                for beat in beats {
                    guard beat.time >= offset, beat.time < offset + segment.seconds else { continue }
                    emit(cursor + (beat.time - offset), kind, beat.label)
                }
            case .scaled:
                let master = masterSeconds[segment.chapter] ?? segment.seconds
                let factor = master / segment.seconds
                for beat in beats where beat.time < master {
                    emit(cursor + beat.time / factor, kind, beat.label)
                }
            }
            cursor += segment.seconds
        }
        emit(cursor, "end", "-")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The segment neighbourhood at a cut-time: who came before, who comes
    /// next, and how much of the current segment remains — the match cut's
    /// ingredients.
    static func neighbors(in cut: Cut, at t: Double)
        -> (previous: Chapter?, next: Chapter?, into: Double, remaining: Double)? {
        var cursor = 0.0
        for (index, segment) in cut.segments.enumerated() {
            if t < cursor + segment.seconds {
                return (index > 0 ? cut.segments[index - 1].chapter : nil,
                        index + 1 < cut.segments.count ? cut.segments[index + 1].chapter : nil,
                        t - cursor,
                        cursor + segment.seconds - t)
            }
            cursor += segment.seconds
        }
        return nil
    }

    // MARK: - The clock walk

    /// Maps a cut-time to (chapter, chapter-local t, segment progress 0…1).
    ///
    /// `.window` enters the chapter's own clock at the offset; `.scaled`
    /// plays the chapter from zero, compressed or trimmed to the segment
    /// (the scene functions treat local t proportionally where beats allow).
    /// `scaleFactor` is how much faster than master the segment plays.
    static func resolve(_ cut: Cut, at t: Double)
        -> (chapter: Chapter, localT: Double, scaleFactor: Double)? {
        var cursor = 0.0
        for segment in cut.segments {
            if t < cursor + segment.seconds {
                let within = t - cursor
                switch segment.kind {
                case .window(let offset):
                    return (segment.chapter, offset + within, 1)
                case .scaled:
                    let master = masterSeconds[segment.chapter] ?? segment.seconds
                    let factor = master / segment.seconds
                    return (segment.chapter, within * factor, factor)
                }
            }
            cursor += segment.seconds
        }
        return nil
    }
}
