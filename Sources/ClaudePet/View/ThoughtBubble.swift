import SwiftUI

/// Claw'd's speech bubble.
///
/// Styled after the official art: a flat, saturated block of colour with square
/// corners, a stepped pixel tail, and dark text — not a soft translucent macOS
/// popover.
///
/// The tail sits at the bubble's **centre**, and the bubble is centred over the
/// sprite, so the tail always points at his body no matter how long the text is.
/// An edge-anchored tail drifted off his shoulder whenever the text changed
/// length, which read as the bubble belonging to something beside him.
///
/// `@MainActor` is written down rather than inferred, for the same reason
/// `MarqueeText`'s doc gives: `View` carries it, and Swift 6.1 pushes that
/// inference onto STATIC members while 6.3 does not. `plainColumns` is read
/// from the coordinator and from the suite, so leaving it to inference means
/// the desk compiles something the runner rejects.
@MainActor
public struct ThoughtBubble: View {
    public var text: String
    public var tool: String?
    public var mood: PetMood
    public var style: PetState.BubbleStyle = .plain
    /// The service the sprint is talking to — when set, the leading glyph
    /// slot renders the 8-bit badge instead of the ASCII tool glyph.
    public var service: ServiceGlyph? = nil

    /// Renders against a fixed instant instead of the display link.
    ///
    /// The dots and the ticker derive their phase from *absolute* reference
    /// time, which is fine live and useless offline: `ImageRenderer` has no
    /// display link, so the schedule resolves to whatever wall-clock moment the
    /// render happened at and the same commit stops producing the same bytes.
    public var frozenTime: Double?

    /// Closes a marquee's loop at exactly this many seconds — offline only.
    ///
    /// A ticker's natural cycle is `(measure + gap) / speed`, which is never a
    /// frame-countable number, so any GIF that contains one shows the text
    /// decapitated at the wrap. This stretches the GAP (never the text, never
    /// the speed) so one full cycle equals the clip. The live app passes
    /// nothing and renders byte-identically.
    public var loopSeconds: Double? = nil

    /// Comp-board knobs: override the mood's bubble fill and text colour.
    ///
    /// Offline only, for art-directing the facts bubble against variants
    /// without inventing a fake mood. Nil — always, in the live app — keeps
    /// `MoodStyle` the single authority.
    public var fillOverride: Color? = nil
    public var textOverride: Color? = nil

    /// Width of the scrolling viewport. Fixed so the bubble does not resize as
    /// the ticker's content changes.
    nonisolated static let marqueeWidth: CGFloat = 150

    /// The widest the bubble is allowed to get, and the padding inside it.
    /// Hoisted out of `body` so the column count below is derived from the same
    /// numbers the layout actually uses rather than from a comment about them.
    nonisolated static let maxWidth: CGFloat = 210
    nonisolated static let insetX: CGFloat = 8

    /// How many monospaced columns the PLAIN bubble can show: **28**, READ off a
    /// render rather than computed.
    ///
    /// The arithmetic says otherwise, and the arithmetic is wrong. `maxWidth`
    /// less the padding on both sides, over the 6.62pt advance
    /// `MarqueeText.measure` uses, is 29.3 — which is where the 29 in
    /// `bubbleLinesAreShort` came from. But 6.62 is the MARQUEE's constant, a
    /// figure chosen so a scrolling line could be measured without a layout
    /// pass, and it runs a little under the real advance. A ruler rendered
    /// through this very view — 24 to 32 columns, same bubble, same font —
    /// shows 28 whole and 29 ending in an ellipsis.
    ///
    /// One column, and it had been quietly clipping the tail off any 29 for as
    /// long as the guard has existed: one vocabulary line and, when this was
    /// found, two of the short facts. Derivation is the right instinct and it
    /// is not authority. The render is.
    ///
    /// It assumes the glyph slot is empty, which is true of the case that
    /// matters: `.idle`'s `MoodStyle.glyph` is "". A tool glyph still lingering
    /// from the focused session, or a service badge inside its six seconds,
    /// takes room and costs another character or two. That exposure is old and
    /// is not the facts' alone — a fact pool holding itself to a stricter rule
    /// than his own voice keeps in the same bubble would be an inconsistency
    /// rather than a safeguard.
    nonisolated static let plainColumns = 28

    /// Presentation comes from `MoodStyle`, so a new mood is one entry there
    /// rather than three switches here.
    private var fill: Color { fillOverride ?? mood.style.bubbleFill }
    private var foreground: Color { textOverride ?? mood.style.bubbleText }

    private var glyph: String {
        if style == .dots { return "" }        // the dots are the whole message
        if style == .marquee { return "▮" }
        guard let tool else { return mood.style.glyph }
        return Self.glyph(forTool: tool)
    }

    /// Tool glyphs. A tool always wins over the mood's own glyph, because it
    /// says something more specific about what is happening right now.
    static func glyph(forTool tool: String) -> String {
        switch tool {
        case "Bash": ">_"
        case "Read", "NotebookEdit": "[]"
        case "Write", "Edit": "//"
        case "Grep", "Glob": "?"
        case "WebFetch", "WebSearch": "@"
        case "Task", "Agent": "*"
        default: ">"
        }
    }

    private var font: Font { .system(size: 11, weight: .bold, design: .monospaced) }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                if let service, style != .dots {
                    // The dots stay wordless AND badgeless — reasoning is
                    // reasoning, whoever it is about.
                    ServiceBadge(kind: service)
                } else if !glyph.isEmpty {
                    Text(glyph)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                switch style {
                case .dots:
                    PulsingDots(color: foreground, frozenTime: frozenTime)
                case .marquee:
                    MarqueeText(text: text, font: font, width: Self.marqueeWidth,
                                frozenTime: frozenTime, loopSeconds: loopSeconds)
                case .plain:
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if mood == .nudging, style == .plain {
                    // The plan is ready and he wants a verdict: a slow, eased
                    // pulse on the check, always present so the bubble never
                    // changes width, never brighter than the text it trails.
                    Clocked(frozenTime: frozenTime) { t in
                        Text("✓")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(Palette.green)
                            .opacity(0.25 + 0.75 * Ease.smoothstep(0.5 + 0.5 * sin(t * .pi)))
                    }
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Self.insetX)
            .padding(.vertical, 6)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .background(Rectangle().fill(fill))
            .overlay {
                // An occasional light sweep across the bubble when he is asking
                // for something — attention drawn by motion, not by colour.
                if mood == .needsAttention || mood == .nudging {
                    BubbleShimmer(frozenTime: frozenTime)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            // Stepped tail, centred. Built from two squares rather than a
            // triangle so it stays on the pixel grid.
            VStack(spacing: 0) {
                Rectangle().fill(fill).frame(width: 8, height: 4)
                Rectangle().fill(fill).frame(width: 4, height: 4)
            }
        }
    }

    /// The 8-bit service badge in the bubble's glyph slot: the sprite's own
    /// bitmap (`ServiceGlyph.art`) at two points a cell, in brand-evocative
    /// colours on a kraft backing square so it survives every bubble fill.
    /// Static — no clock, so offline renders are deterministic for free.
    /// Internal, not private: the sizzle's pixel cards wear the same badge.
    struct ServiceBadge: View {
        let kind: ServiceGlyph

        // Internal, not private: `badgeCoversTheLegend` reads it, because an
        // art change that adds a legend character the badge does not map
        // fails SILENTLY here (see the `guard let color` below) rather than
        // loudly. The two renditions are separately tuned on purpose — npm's
        // badge red is not `Palette.alert` either.
        nonisolated static let colors: [ServiceGlyph: [Character: Color]] = [
            .npm: ["r": Color(red: 0.796, green: 0.220, blue: 0.216),   // npm red
                   "p": .white],
            .github: ["d": Palette.slateSoft,       // the tile
                      "p": Palette.kraft],          // the creature
            .linear: ["l": Color(red: 0.369, green: 0.416, blue: 0.824), // linear violet
                      "s": .white],
            .deploy: ["s": Palette.steel, "l": Palette.screenLight,
                      "f": Palette.flame, "e": Palette.ember],
        ]

        var body: some View {
            let art = kind.art
            let cell: CGFloat = 2
            let side = CGFloat(art.rows.map(\.count).max() ?? 0) * cell
            Canvas { context, _ in
                context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)),
                             with: .color(Palette.kraft.opacity(0.35)))
                for (rowIndex, row) in art.rows.enumerated() {
                    for (colIndex, char) in row.enumerated() where char != "." {
                        guard let color = Self.colors[kind]?[char] else { continue }
                        context.fill(
                            Path(CGRect(x: CGFloat(colIndex) * cell,
                                        y: CGFloat(rowIndex) * cell,
                                        width: cell, height: cell)),
                            with: .color(color))
                    }
                }
            }
            // Square, matching the backing fill above — the old
            // row-derived height clipped it for every glyph shorter than it
            // is wide, and left the four badges disagreeing on size.
            .frame(width: side, height: side)
        }
    }
}

/// A flat white band sweeping the bubble once in a while. Scheduled with the
/// animator's dice so it fires on some cycles and rests on others, and shaped
/// by `sin(π·u)` so it fades in and out inside its own traverse — the sweep
/// obeys the same no-snap rule as the sprite. Never fires in cycle zero, so a
/// frozen render at t=0 shows a clean bubble.
private struct BubbleShimmer: View {
    let frozenTime: Double?

    private static let cycle = 7.0
    private static let traverse = 0.6

    var body: some View {
        Clocked(frozenTime: frozenTime) { t in
            GeometryReader { geo in
                let cycle = Int(floor(t / Self.cycle))
                let since = t - Double(cycle) * Self.cycle
                let fires = cycle > 0 && CrabAnimator.noise(cycle &* 19 &+ 13) < 0.5
                if fires, since < Self.traverse {
                    let u = since / Self.traverse
                    Rectangle()
                        .fill(Palette.white)
                        .frame(width: 8)
                        .opacity(0.28 * sin(.pi * u))
                        .offset(x: (geo.size.width + 16) * u - 8)
                }
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}

/// Runs its content against the display link, or against a fixed instant when
/// an offline renderer supplies one.
private struct Clocked<Content: View>: View {
    let frozenTime: Double?
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if let frozenTime {
            content(frozenTime)
        } else {
            TimelineView(.animation) { content($0.date.timeIntervalSinceReferenceDate) }
        }
    }
}

/// Three squares filling in one at a time, then clearing — the universal
/// "still thinking" tell, with no words to go stale.
private struct PulsingDots: View {
    let color: Color
    let frozenTime: Double?

    /// Seconds per dot.
    private let step = 0.34

    var body: some View {
        Clocked(frozenTime: frozenTime) { elapsed in
            let lit = Int(elapsed / step) % 4      // 0…3, so there is a rest beat
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .opacity(index < lit ? 1 : 0.22)
                }
            }
        }
        .frame(height: 13)
        .padding(.horizontal, 2)
    }
}

/// A single line of text scrolling right-to-left, looping seamlessly.
///
/// Driven by `TimelineView` rather than a repeating `withAnimation`, so it costs
/// nothing when the bubble is not on screen and cannot leave a timer running
/// after the view goes away.
/// `@MainActor` is written down rather than inferred, for the reason
/// `PetRootView`'s doc gives: `View` carries it, and Swift 6.1 pushes that
/// inference onto STATIC members while 6.3 does not. Spelling it out means the
/// local build checks the same thing CI does — without it, `readSeconds` was
/// nonisolated here and main-actor isolated on the runner, and the mismatch
/// only surfaced after a push.
@MainActor
struct MarqueeText: View {
    let text: String
    let font: Font
    let width: CGFloat
    let frozenTime: Double?
    /// See `ThoughtBubble.loopSeconds`. Nil live, a clip length offline.
    var loopSeconds: Double? = nil

    /// Points per second. `nonisolated` because `readSeconds` is, and a
    /// nonisolated function cannot read a main-actor constant.
    nonisolated static let speed: CGFloat = 26
    /// Blank space between the end of one pass and the start of the next.
    nonisolated static let gap: CGFloat = 34

    /// When THIS utterance started scrolling.
    ///
    /// The offset used to come straight off the epoch, so a reader joined a
    /// sentence at an arbitrary midpoint. That is survivable for a label like
    /// `MODEL · Opus 5`, which has no grammar to lose, and useless for a fact.
    ///
    /// `PetRootView` tags the bubble `.id(text)`, so a new line re-mounts this
    /// view and `@State` is re-seeded — which is the whole mechanism. No new
    /// `PetState` field, nothing equality-gated churning on a 14s clock.
    @State private var began = Date.timeIntervalSinceReferenceDate

    var body: some View {
        Clocked(frozenTime: frozenTime) { now in
            // Frozen renders keep taking the caller's instant verbatim, so
            // offline output stays byte-deterministic.
            let elapsed = frozenTime == nil ? max(0, now - began) : now
            let measured = Self.cycle(for: text, loopSeconds: loopSeconds)
            let offset = measured > 0
                ? -CGFloat(elapsed * Double(Self.speed)).truncatingRemainder(dividingBy: measured)
                : 0

            HStack(spacing: Self.gap) {
                Text(text).font(font).fixedSize()
                // Second copy trails the first so the loop has no visible seam.
                Text(text).font(font).fixedSize()
            }
            .offset(x: offset)
            .frame(width: width, alignment: .leading)
            .clipped()
        }
    }

    /// Monospaced 11pt: every glyph is the same advance, so the width is
    /// countable rather than needing a layout pass.
    nonisolated static func measure(_ text: String) -> CGFloat {
        CGFloat(text.count) * 6.62
    }

    /// One full scroll cycle in POINTS: the text plus its trailing gap, or —
    /// when a clip length is supplied — that length converted through the
    /// speed, with the slack absorbed by the gap.
    ///
    /// CLAMPED to never fall below the natural cycle: a requested loop shorter
    /// than the text's own travel would run the second copy over the first,
    /// which is not a tighter loop, it is a collision. The clamp means a
    /// too-short request degrades to today's behaviour (a visible wrap)
    /// instead of to garbage.
    nonisolated static func cycle(for text: String, loopSeconds: Double?) -> CGFloat {
        guard let loopSeconds else { return measure(text) + gap }
        let requested = CGFloat(loopSeconds) * speed
        // The floor is the TEXT's width, not text-plus-gap: the gap is exactly
        // the slack this exists to stretch or shrink. Below the text itself the
        // second copy would drive over the first, so a too-short request
        // degrades to the natural cycle (today's visible wrap) instead.
        return requested >= measure(text) ? requested : measure(text) + gap
    }

    /// How long until the LAST character has reached the viewport — i.e. how
    /// long a reader needs to have seen the whole line, starting from phase 0.
    ///
    /// Not a full loop: a loop also carries the text back off the left edge
    /// and through the gap, which is 184pt of travel nobody needs to wait for.
    /// The difference is the entire length budget — a full loop allows ~44
    /// characters inside the idle slot, this allows ~68.
    ///
    /// Exposed so the copy's length can be checked against a DURATION rather
    /// than against a restated 6.62. A test that re-derives the constant keeps
    /// passing forever after someone changes the renderer.
    nonisolated static func readSeconds(for text: String, width: CGFloat) -> Double {
        Double(max(0, measure(text) - width) / speed)
    }

    /// The viewport the bubble actually gives the ticker.
    nonisolated static var viewport: CGFloat { ThoughtBubble.marqueeWidth }
}
