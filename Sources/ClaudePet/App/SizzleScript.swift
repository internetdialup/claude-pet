import Foundation

/// The sizzle reel's master script: eight chapters, three cuts.
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
    enum Family { case master, readme, meme, plate }

    struct Cut {
        let name: String
        /// Canvas in points; frames render at `canvas × scale` pixels.
        let canvas: CGSize
        let scale: CGFloat
        let fps: Int32
        let family: Family
        let segments: [Segment]
        var seconds: Double { segments.reduce(0) { $0 + $1.seconds } }
        var frameCount: Int { Int((seconds * Double(fps)).rounded()) }
    }

    // MARK: - The clocks

    static let cookBase = 269.0
    static let workBase = 20.0

    /// Master chapter durations, in play order. Sum: exactly 45.0.
    static let masterSeconds: [Chapter: Double] = [
        .wake: 2.5, .mirror: 5.5, .glyphs: 6.0, .cook: 6.0,
        .finale: 10.0, .montage: 8.0, .duet: 4.0, .outro: 3.0,
    ]

    /// The montage's running order — ends on Classic so the README GIF's
    /// loop seam is a mood-only cut.
    static let montageOrder: [Costume] =
        [.ninja, .retroBlack, .matrix, .tiger, .white, .gundam, .sonic, .none]

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
        .montage: "8 LOOKS",
        .duet: "summon a second",
    ]

    static let mirrorBubble = "Wiring the pipeline"
    static let cookBubble = "Absolutely cooking 🔥"

    /// The meme cut's language: two words, maximum volume.
    static let memeCaptions: [Chapter: String] = [
        .glyphs: "HE SHIPS",
        .cook: "HE COOKS",
        .finale: "BIG ONE",
        .montage: "8 LOOKS",
        .outro: "SHIP IT",
    ]

    // MARK: - The cuts

    static let landscape = Cut(
        name: "sizzle-16x9.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .master,
        segments: Chapter.allCases.map {
            Segment(chapter: $0, kind: .scaled, seconds: masterSeconds[$0] ?? 0)
        })

    static let vertical = Cut(
        name: "sizzle-9x16.mp4",
        canvas: CGSize(width: 360, height: 640), scale: 3, fps: 30,
        family: .master,
        segments: [
            Segment(chapter: .wake, kind: .scaled, seconds: 2.0),
            Segment(chapter: .glyphs, kind: .scaled, seconds: 4.0),
            Segment(chapter: .cook, kind: .window(offset: 1.5), seconds: 3.5),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 10.0),
            Segment(chapter: .montage, kind: .scaled, seconds: 8.0),
            Segment(chapter: .duet, kind: .scaled, seconds: 2.5),
            Segment(chapter: .outro, kind: .scaled, seconds: 2.0),
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

    static let cuts: [Cut] = [landscape, vertical, readme, readmeVideo, meme]

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
