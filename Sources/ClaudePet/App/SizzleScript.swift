import SwiftUI

/// The sizzle reel's master script: nine chapters, eight cuts, two plates.
///
/// Everything here is data — the renderer walks it with a frame clock and
/// pure pose functions, so the same chapter renders byte-identically at any
/// canvas. Every string is fabricated (the anonymity rule for recordings:
/// nothing real ever enters a committed asset). Chapter clocks are LOCAL;
/// the dice-locked chapters carry base offsets chosen so the deterministic
/// schedules actually fire on camera:
/// - `cookBase = 269.0`: the cooking beat lands the fire prop and the heat
///   cascade window [272.0, 274.4) inside the two-second shot. The disco
///   tint also fires in this window on the desktop; the reel does not pass
///   it — no body colour before the finale's own colour is a reel rule.
/// - `workBase = 20.0`: working spell cycle 1 rolls the terminal, with the
///   0.35s eased prop pick-up at the spell seam for free.
///
/// **The grid.** The masters are cut to 120 BPM: a beat is 0.5s (fifteen
/// frames exactly at 30fps), a bar is 2.0s. Every segment boundary lands on
/// a beat; the finale, the montage and the outro open on bar lines. Every
/// master segment is a `.window` — the chapter plays at 1×, never
/// time-stretched — because a 0.32s ease compressed 4.7× is a two-frame
/// snap wearing an ease's clothes. The operator lays the track in Premiere
/// from the beats sidecar; the reel is silent by construction.
@MainActor
enum SizzleScript {

    enum Chapter: CaseIterable {
        case wake, mirror, glyphs, cook, finale, montage, duet, outro
        /// The stopdown: half a second of a resting crab on a quiet ground
        /// between the cook and the bang, so the picture carves the drop the
        /// music will make. Appended last — enum order is load-bearing.
        case breath
    }

    /// One entry of a cut: play `seconds` of `chapter`.
    struct Segment {
        enum Kind {
            /// Enter the chapter's fixed local clock at `offset` — for the
            /// dice-locked chapters, where mid-effect entry is a cut, not a
            /// snap.
            case window(offset: Double)
            /// Re-lay the chapter's beats proportionally into `seconds`.
            /// Legal only where the compression stays under 2× — no master
            /// cut uses it any more.
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

    /// What stands behind him when a chapter has no flat ground of its own.
    /// Ocean is the README classic; the gradient is the showcase's dusk, the
    /// operator's named pick and MP4-only, so the GIF palette doctrine never
    /// meets it.
    enum Scenery { case ocean, gradient, forest }

    /// A flat marketing ground and the ink that reads on it. The colours are
    /// `MarketingPalette`'s — the operator's swatch sheet is the single
    /// source — and the ink is authored per ground: kraft on the dark ones,
    /// slate on the light, never white.
    struct Ground: Equatable {
        let name: String
        let color: Color
        let ink: Color

        static let cream = Ground(name: "cream", color: MarketingPalette.cream, ink: Palette.slate)
        static let cobalt = Ground(name: "cobalt", color: MarketingPalette.cobalt, ink: Palette.kraft)
        static let gold = Ground(name: "gold", color: MarketingPalette.gold, ink: Palette.slate)
        static let sky = Ground(name: "sky", color: MarketingPalette.sky, ink: Palette.slate)
    }

    /// One look of a montage: the costume and how long it holds.
    struct Look: Equatable {
        let costume: Costume
        let seconds: Double
    }

    struct Cut {
        let name: String
        /// Canvas in points; frames render at `canvas × scale` pixels.
        let canvas: CGSize
        let scale: CGFloat
        let fps: Int32
        let family: Family
        var scenery: Scenery = .ocean
        /// Per-chapter flat grounds. A chapter without an entry stands on
        /// `scenery`. A ground change on a downbeat IS the chapter transition.
        var grounds: [Chapter: Ground] = [:]
        /// The montage's running order for THIS cut, with a hold per look.
        var looks: [Look] = SizzleScript.masterLooks
        let segments: [Segment]
        var seconds: Double { segments.reduce(0) { $0 + $1.seconds } }
        var frameCount: Int { Int((seconds * Double(fps)).rounded()) }
        var looksSeconds: Double { looks.reduce(0) { $0 + $1.seconds } }

        /// Which look is on at montage-local `t`: its index, how far into
        /// it we are, and its hold. Past the end, the last look holds.
        func look(at t: Double) -> (index: Int, into: Double, seconds: Double) {
            SizzleScript.look(in: looks, at: t)
        }
    }

    // MARK: - The clocks

    static let cookBase = 269.0
    static let workBase = 20.0

    /// The tempo the masters are cut to. 120 gives a beat of exactly fifteen
    /// frames at 30fps and a bar of sixty; half-beats (7.5 frames) are legal
    /// for events inside a shot but never for a boundary.
    nonisolated static let bpm = 120.0
    nonisolated static let beat = 60.0 / bpm
    nonisolated static let bar = beat * 4

    /// Whether `t` sits on a beat of the grid.
    nonisolated static func isOnBeat(_ t: Double) -> Bool {
        let beats = t / beat
        return abs(beats - beats.rounded()) < 1e-6
    }

    /// Master chapter durations. For the chapters every cut windows into
    /// (mirror, cook, finale) this is the length of the authored
    /// performance; for the rest it is the reel length the chapter is
    /// authored AT, so a `.window(offset: 0)` plays it at 1×. Sum: 32.0.
    static let masterSeconds: [Chapter: Double] = [
        .wake: 1.0, .mirror: 5.5, .glyphs: glyphBeatSeconds.reduce(0, +), .cook: 6.0,
        .finale: 10.0, .montage: masterLooks.reduce(0) { $0 + $1.seconds },
        .duet: 1.0, .outro: 3.0, .breath: 0.5,
    ]

    /// The canonical running order of every look — the README's roster and
    /// the coverage the pose table is held to. Ends on Classic so any loop
    /// seam is a mood-only cut.
    static let montageOrder: [Costume] =
        [.ninja, .retroBlack, .matrix, .tiger, .white, .gundam, .sonic, .frankenstein,
         .arcade, .pumpkin, .turkey, .santa, .easterBunny, .skater, .none]

    /// The masters' montage: four looks in five beats — short, short, then
    /// two holds — with the ninja planted first (he is the outro's second
    /// sleeper) and Classic closing. Fifteen looks at 0.213s was an asset
    /// scroll; nobody registers a costume in six frames.
    nonisolated static let masterLooks: [Look] = [
        Look(costume: .ninja, seconds: 0.5), Look(costume: .gundam, seconds: 0.5),
        Look(costume: .skater, seconds: 0.75), Look(costume: .none, seconds: 0.75),
    ]

    /// The README loop's six, at a pace a reader can register at 10fps.
    nonisolated static let readmeLooks: [Look] = [
        Look(costume: .ninja, seconds: 0.9), Look(costume: .gundam, seconds: 0.9),
        Look(costume: .sonic, seconds: 0.9), Look(costume: .easterBunny, seconds: 0.9),
        Look(costume: .skater, seconds: 0.9), Look(costume: .none, seconds: 1.0),
    ]

    /// The meme's five, faster, with the same two holds.
    nonisolated static let memeLooks: [Look] = [
        Look(costume: .ninja, seconds: 0.4), Look(costume: .gundam, seconds: 0.4),
        Look(costume: .sonic, seconds: 0.6), Look(costume: .skater, seconds: 0.4),
        Look(costume: .none, seconds: 0.6),
    ]

    /// The glyph chapter shows every service, one beat each — and the beats
    /// are a table, not a period: beat, beat-and-a-half, beat, beat-and-a-
    /// half. Four at exactly 0.7s was a for-loop's rhythm.
    static let glyphBeats: [(glyph: ServiceGlyph, bubble: String)] = [
        (.npm, "npm install"),
        (.github, "git push --force"),
        (.linear, "LIN-407 in review"),
        (.deploy, "vercel deploy --prod"),
    ]
    nonisolated static let glyphBeatSeconds: [Double] = [0.5, 0.75, 0.5, 0.75]

    /// Which glyph beat is on at chapter-local `t`: index, time into it, its
    /// length. The last beat holds past the table's end.
    nonisolated static func glyphBeat(at t: Double) -> (index: Int, into: Double, seconds: Double) {
        var cursor = 0.0
        for (index, seconds) in glyphBeatSeconds.enumerated() {
            if t < cursor + seconds || index == glyphBeatSeconds.count - 1 {
                return (index, t - cursor, seconds)
            }
            cursor += seconds
        }
        return (0, t, glyphBeatSeconds[0])
    }

    /// Where the glyph beats start, chapter-local.
    static var glyphBeatStarts: [Double] {
        var starts: [Double] = []
        var cursor = 0.0
        for seconds in glyphBeatSeconds { starts.append(cursor); cursor += seconds }
        return starts
    }

    /// The finale's own events besides the flashes, chapter-local: the two
    /// re-armed hops the rig plays, and the badge landing.
    static var finaleHops: [Double] { CrabAnimator.celebrationHops }
    static let badgeAt = 8.2

    /// When pet one pounces in the duet, chapter-local — early, because the
    /// duet is one second at 1× and the landing is what the cut leaves out.
    static let duetPounceAt = 0.3

    /// Which look is on at montage-local `t` for a running order: index, time
    /// into it, its hold. Past the end, the last look holds.
    nonisolated static func look(in looks: [Look], at t: Double) -> (index: Int, into: Double, seconds: Double) {
        var cursor = 0.0
        for (index, look) in looks.enumerated() {
            if t < cursor + look.seconds || index == looks.count - 1 {
                return (index, t - cursor, look.seconds)
            }
            cursor += look.seconds
        }
        return (0, t, looks.first?.seconds ?? 1)
    }

    // MARK: - The words (all fabricated)

    /// The tagline under the wordmark on the README hero. The masters carry
    /// no title card any more — product first, brand last — so this rides
    /// only the wake chapter, which no master plays.
    static let tagline = "what Claude Code is doing,\non your desktop"
    static let url = "github.com/internetdialup/claude-pet"

    /// A caption: authored for each canvas with its own line break (SwiftUI
    /// never wraps reel type), with the chapter-local window it is at full
    /// ink — it eases in over 0.30s before `from` and out over 0.18s after
    /// `until` — and the frame that pays it off, or nil for a tease whose
    /// proof is the next chapter.
    struct Caption: Equatable {
        let wide: String
        let tall: String
        let proves: Double?
        let from: Double
        let until: Double

        func text(vertical: Bool) -> String { vertical ? tall : wide }
    }

    /// The masters' three lines. Three, not six: the bubbles and the cards
    /// already say the specific thing in the product's own voice, and a
    /// caption that narrates what the frame shows is the reel not trusting
    /// its picture. The glyph chapter, the breath, the finale and the duet
    /// carry no caption at all.
    static let captions: [Chapter: Caption] = [
        // On from the master's first frame (the window enters at 1.0), paid
        // off by the working bubble at 2.0–2.4, gone half a second before
        // the cut.
        .mirror: Caption(wide: "mirrors your Claude Code sessions",
                         tall: "mirrors your\nClaude Code sessions",
                         proves: 2.2, from: 1.0, until: 3.32),
        // The tease. Proof is the next chapter.
        .cook: Caption(wide: "big one incoming...", tall: "big one incoming...",
                       proves: nil, from: 2.0, until: 3.32),
        // The count may exceed the looks shown; the second look is the proof.
        .montage: Caption(wide: "\(montageOrder.count) LOOKS",
                          tall: "\(montageOrder.count) LOOKS",
                          proves: 0.5, from: 0.0, until: 1.82),
    ]

    /// The README loop's two: the thesis and the tease. It has four chapters
    /// and the rule wants two of them bare — and a counter that says fifteen
    /// over a loop that shows six is the mismatch a reader would notice.
    static let readmeCaptions: [Chapter: Caption] = captions.filter { $0.key != .montage }

    static let mirrorBubble = "Wiring the pipeline"
    static let cookBubble = "Absolutely cooking 🔥"

    /// The meme cut's language: two words, maximum volume — three times, not
    /// five. "HE SHIPS" over cards that already say "MERGED" and a counter
    /// over a wardrobe that is plainly a wardrobe were the reel not trusting
    /// its own picture; type still owns under half the runtime. The outro
    /// line replaces the wordmark on the end card.
    static let memeCaptions: [Chapter: Caption] = [
        .cook: Caption(wide: "HE COOKS", tall: "HE COOKS", proves: 3.0, from: 2.4, until: 3.32),
        .finale: Caption(wide: "BIG ONE", tall: "BIG ONE", proves: 0.3, from: 0.0, until: 2.52),
        // The end card holds to the last frame; `until` is the segment's end.
        .outro: Caption(wide: "SHIP IT", tall: "SHIP IT", proves: 0.6, from: 0.3, until: 1.0),
    ]

    // MARK: - The grounds

    /// A room per chapter, four colours: the thesis on cobalt (the social
    /// preview's world), the shipping beats on gold, the kitchen on cream, a
    /// cut to the dark room for the breath and the bang, sky for the
    /// wardrobe, cream for the duet and goodnight — the bookend with the
    /// banner. A ground change on the downbeat IS the chapter transition; on
    /// 9:16, where the crab has no room to slide aside, it is what makes the
    /// mirror→glyphs cut a cut.
    ///
    /// The wardrobe's ground is the one the CONTRAST test chose: the ninja is
    /// near-black and the gundam near-white, and sky is the only swatch both
    /// clear by luminance while the terracotta clears it by hue. Gold lost
    /// the gundam; every dark ground lost the ninja.
    static let masterGrounds: [Chapter: Ground] = [
        .wake: .cream, .mirror: .cobalt, .glyphs: .gold, .cook: .cream,
        .breath: .cobalt, .finale: .cobalt, .montage: .sky, .duet: .cream, .outro: .cream,
    ]

    // MARK: - The cuts

    /// The operator's runtime law: every clip under 25 seconds. On the grid
    /// that is 49 beats, 24.5s — and the finale keeps its whole ten (the
    /// payoff IS the star), so the other seven chapters share 14.5.
    ///
    /// Cold open on the thesis: frame 0 is him mid face-punch with the thesis
    /// line up, the poster frame socials thumbnail. The brand rides the end
    /// card alone.
    static let masterSegments: [Segment] = [
        Segment(chapter: .mirror, kind: .window(offset: 1.0), seconds: 3.0),
        Segment(chapter: .glyphs, kind: .window(offset: 0), seconds: 2.5),
        Segment(chapter: .cook, kind: .window(offset: 2.0), seconds: 2.0),
        Segment(chapter: .breath, kind: .window(offset: 0), seconds: 0.5),
        Segment(chapter: .finale, kind: .window(offset: 0), seconds: 10.0),
        Segment(chapter: .montage, kind: .window(offset: 0), seconds: 2.5),
        Segment(chapter: .duet, kind: .window(offset: 0), seconds: 1.0),
        Segment(chapter: .outro, kind: .window(offset: 0), seconds: 3.0),
    ]

    static let landscape = Cut(
        name: "sizzle-16x9.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .master, grounds: masterGrounds,
        segments: masterSegments)

    /// The vertical master carries the same edit — including the thesis
    /// chapter it used to skip — with its own camera offsets and type sizes.
    static let vertical = Cut(
        name: "sizzle-9x16.mp4",
        canvas: CGSize(width: 360, height: 640), scale: 3, fps: 30,
        family: .master, grounds: masterGrounds,
        segments: masterSegments)

    static let readme = Cut(
        name: "sizzle-readme.gif",
        canvas: CGSize(width: 320, height: 180), scale: 2, fps: 10,
        family: .readme, looks: readmeLooks,
        segments: [
            Segment(chapter: .mirror, kind: .window(offset: 1.6), seconds: 3.0),
            Segment(chapter: .cook, kind: .window(offset: 1.2), seconds: 3.0),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 8.0),
            Segment(chapter: .montage, kind: .window(offset: 0), seconds: 5.5),
        ])

    /// The README cut again at 30fps, for socials that reject GIFs.
    static let readmeVideo = Cut(
        name: "sizzle-readme.mp4",
        canvas: readme.canvas, scale: readme.scale, fps: 30,
        family: .readme, looks: readmeLooks,
        segments: readme.segments)

    /// The meme cut: the greatest hits at attention-span speed, every
    /// chapter at 1× — "people have shit attention spans", then "it needs
    /// to be faster", and the answer is shorter windows, not a faster actor.
    static let meme = Cut(
        name: "sizzle-meme.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .meme, grounds: masterGrounds, looks: memeLooks,
        segments: [
            Segment(chapter: .mirror, kind: .window(offset: 0.4), seconds: 1.2),
            Segment(chapter: .glyphs, kind: .window(offset: 0), seconds: 2.5),
            Segment(chapter: .cook, kind: .window(offset: 2.4), seconds: 1.6),
            Segment(chapter: .finale, kind: .window(offset: 0), seconds: 3.2),
            Segment(chapter: .montage, kind: .window(offset: 0), seconds: 2.4),
            Segment(chapter: .outro, kind: .window(offset: 0), seconds: 1.0),
        ])

    /// The hook cut: one beat less a frame of the finale's apex as a cold
    /// open — the retention pattern socials reward — then the master
    /// verbatim. 24.9s, still inside the law.
    ///
    /// The offset tracks the flash schedule and must keep doing so. 2.05
    /// lands on the epic apex tap AND the 1.2× transform's peak — he swells
    /// a fifth and detonates. 0.4s still covers the tap's whole white plateau
    /// (2.29–2.43); `hookOpensOnTheBang` fails if the schedule ever moves out
    /// from under it.
    static let hook = Cut(
        name: "sizzle-hook.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .master, grounds: masterGrounds,
        segments: [Segment(chapter: .finale, kind: .window(offset: 2.05), seconds: 0.4)]
            + masterSegments)

    /// The showcase cuts: the masters' choreography with the type stripped —
    /// "i dont need the text just show off the pet" — on the dusk gradient
    /// (the operator's pick). Bubbles and glyphs stay: they are the product,
    /// not the marketing.
    static let showcaseGradient = Cut(
        name: "showcase-gradient.mp4",
        canvas: CGSize(width: 640, height: 360), scale: 3, fps: 30,
        family: .showcase, scenery: .gradient,
        segments: masterSegments)

    static let showcaseGradientTall = Cut(
        name: "showcase-gradient-9x16.mp4",
        canvas: CGSize(width: 360, height: 640), scale: 3, fps: 30,
        family: .showcase, scenery: .gradient,
        segments: masterSegments)

    /// The forest cuts left the render set on the operator's verdict: dark
    /// moving pine rows are worst-case low-luma motion for 8 Mbps H.264 —
    /// the "lighting glitch" was macroblocking, amplified by the finale
    /// glow over dark bands. ForestBackdrop stays in code; the fix path if
    /// it returns is a bitrate bump in VideoWriter.
    static let cuts: [Cut] = [landscape, vertical, readme, readmeVideo, meme, hook,
                              showcaseGradient, showcaseGradientTall]

    /// The key plates: the master cuts' segments VERBATIM — the camera is
    /// pure in (chapter, localT, format), so every plate frame's sprite
    /// geometry matches the titled frame's and keyed footage stays in
    /// sync. A separate array so --render-sizzle doesn't implicitly drag
    /// 1470 more frames; --render-plates walks these.
    static let plate16x9 = Cut(
        name: "plate-16x9",
        canvas: landscape.canvas, scale: 3, fps: 30,
        family: .plate,
        segments: masterSegments)

    static let plate9x16 = Cut(
        name: "plate-9x16",
        canvas: vertical.canvas, scale: 3, fps: 30,
        family: .plate,
        segments: masterSegments)

    static let plates: [Cut] = [plate16x9, plate9x16]

    // MARK: - The beat map

    /// The editor's sidecar: the grid, every chapter boundary and every
    /// visible event inside a chapter as a TSV timeline, so music and foley
    /// snap to the picture in Premiere without frame-counting. Labels are
    /// raw values only — nothing real leaks.
    ///
    /// Kinds: chapter · punch · roster · glyph · stopdown · flash-irregular
    /// (the finale's taps are off-grid by design) · hop · badge · look ·
    /// pounce · card · end.
    static func beatMap(for cut: Cut) -> String {
        var lines = ["# \(cut.name) beats v2",
                     String(format: "# grid %.0fbpm beat %.3fs bar %.3fs", bpm, beat, bar)]
        var cursor = 0.0

        func emit(_ time: Double, _ kind: String, _ label: String) {
            lines.append(String(format: "%.3f\t%@\t%@", time, kind, label))
        }

        for (index, segment) in cut.segments.enumerated() {
            emit(cursor, "chapter", String(describing: segment.chapter))
            let next = index + 1 < cut.segments.count ? cut.segments[index + 1].chapter : nil

            // Intra-chapter beats at explicit chapter-local times, mapped
            // through the segment's clock. Explicit times rather than a
            // (period, labels) cadence because the finale's hits are the
            // flashbang schedule, which is deliberately irregular — and
            // those are exactly the beats an edit wants to cut music to.
            var beats: [(time: Double, kind: String, label: String)] = []
            switch segment.chapter {
            case .mirror:
                beats = [(0.6, "punch", "face")]
                // The portrait cut has no roster panel (no room beside him).
                if cut.canvas.width >= cut.canvas.height { beats.append((2.5, "roster", "sessions")) }
            case .glyphs:
                for (start, entry) in zip(glyphBeatStarts, glyphBeats) {
                    beats.append((start, "glyph", entry.glyph.rawValue))
                }
                beats.append((glyphBeatStarts[1], "punch", "merged"))
            case .breath:
                beats = [(0.0, "stopdown", next.map { String(describing: $0) } ?? "-")]
            case .finale:
                beats = (CrabView.celebrationFlashes + [CrabView.epicFlash])
                    .map { ($0.at, "flash-irregular", "tap") }
                beats += finaleHops.map { ($0, "hop", "hop") }
                beats.append((badgeAt, "badge", "done"))
            case .montage:
                var start = 0.0
                for look in cut.looks {
                    beats.append((start, "look", look.costume.rawValue))
                    start += look.seconds
                }
            case .duet:
                beats = [(duetPounceAt, "pounce", "one")]
            case .outro:
                beats = [(0.0, "card", "url")]
            case .wake, .cook:
                break
            }
            beats.sort { $0.time < $1.time }
            switch segment.kind {
            case .window(let offset):
                for beat in beats {
                    guard beat.time >= offset, beat.time < offset + segment.seconds else { continue }
                    emit(cursor + (beat.time - offset), beat.kind, beat.label)
                }
            case .scaled:
                let master = masterSeconds[segment.chapter] ?? segment.seconds
                let factor = master / segment.seconds
                for beat in beats where beat.time < master {
                    emit(cursor + beat.time / factor, beat.kind, beat.label)
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

    /// Where each segment of a cut starts, in cut time.
    static func segmentStarts(in cut: Cut) -> [Double] {
        var starts: [Double] = []
        var cursor = 0.0
        for segment in cut.segments { starts.append(cursor); cursor += segment.seconds }
        return starts
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
