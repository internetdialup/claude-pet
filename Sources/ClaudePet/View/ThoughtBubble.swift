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

    /// Width of the scrolling viewport. Fixed so the bubble does not resize as
    /// the ticker's content changes.
    private static let marqueeWidth: CGFloat = 150

    /// Presentation comes from `MoodStyle`, so a new mood is one entry there
    /// rather than three switches here.
    private var fill: Color { mood.style.bubbleFill }
    private var foreground: Color { mood.style.bubbleText }

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
                    MarqueeText(text: text, font: font, width: Self.marqueeWidth, frozenTime: frozenTime)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: 210, alignment: .leading)
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

/// Three squares filling in one at a time, then clearing — the universal
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
private struct MarqueeText: View {
    let text: String
    let font: Font
    let width: CGFloat
    let frozenTime: Double?

    /// Points per second.
    private let speed: CGFloat = 26
    /// Blank space between the end of one pass and the start of the next.
    private let gap: CGFloat = 34

    var body: some View {
        Clocked(frozenTime: frozenTime) { elapsed in
            let measured = Self.measure(text) + gap
            let offset = measured > 0
                ? -CGFloat(elapsed * Double(speed)).truncatingRemainder(dividingBy: measured)
                : 0

            HStack(spacing: gap) {
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
    private static func measure(_ text: String) -> CGFloat {
        CGFloat(text.count) * 6.62
    }
}
