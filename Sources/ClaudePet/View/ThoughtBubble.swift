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
                if !glyph.isEmpty {
                    Text(glyph)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                switch style {
                case .dots:
                    PulsingDots(color: foreground)
                case .marquee:
                    MarqueeText(text: text, font: font, width: Self.marqueeWidth)
                case .plain:
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: 210, alignment: .leading)
            .background(Rectangle().fill(fill))
            .fixedSize(horizontal: true, vertical: false)

            // Stepped tail, centred. Built from two squares rather than a
            // triangle so it stays on the pixel grid.
            VStack(spacing: 0) {
                Rectangle().fill(fill).frame(width: 8, height: 4)
                Rectangle().fill(fill).frame(width: 4, height: 4)
            }
        }
    }
}

/// Three squares filling in one at a time, then clearing — the universal
/// "still thinking" tell, with no words to go stale.
private struct PulsingDots: View {
    let color: Color

    /// Seconds per dot.
    private let step = 0.34

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
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

    /// Points per second.
    private let speed: CGFloat = 26
    /// Blank space between the end of one pass and the start of the next.
    private let gap: CGFloat = 34

    var body: some View {
        TimelineView(.animation) { timeline in
            let measured = Self.measure(text) + gap
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
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
