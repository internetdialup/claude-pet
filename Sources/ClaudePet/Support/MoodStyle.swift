import SwiftUI

/// Everything about how a mood *looks*, in one place.
///
/// Before this existed, each mood was described by eight separate switches
/// spread across six files — the accent colour, the bubble fill, the bubble's
/// text colour, its glyph, the render frame rate, the GIF clip length, and the
/// preview text. Adding a mood meant finding all eight, and the compiler only
/// caught you if a switch happened to be exhaustive.
///
/// Now a mood is one entry. `PetMood` itself stays in the Model layer with no
/// SwiftUI import (`development/swift-development.md` §1.2); this is the View
/// side of the same concept.
public struct MoodStyle: Sendable {
    /// Bubble border, roster status dot.
    public let accent: Color
    /// Flat bubble background.
    public let bubbleFill: Color
    /// Bubble text, chosen for contrast against `bubbleFill`.
    public let bubbleText: Color
    /// Shown before the text when no tool glyph applies.
    public let glyph: String
    /// Seconds between sprite redraws. The grid is coarse; nothing it can
    /// express needs a display-rate refresh.
    public let frameInterval: Double
    /// How much of the cycle a README GIF captures — long enough to include the
    /// slowest thing this mood does.
    public let clipSeconds: Double
    /// Bubble text used by the debug mood preview.
    public let previewBubble: String?
}

public extension PetMood {

    var style: MoodStyle {
        switch self {
        case .idle:
            MoodStyle(accent: Palette.body, bubbleFill: Palette.green,
                      bubbleText: Palette.slate, glyph: "",
                      frameInterval: 1.0 / 20, clipSeconds: 6.0,
                      previewBubble: nil)          // filled from the vocabulary

        case .thinking:
            MoodStyle(accent: Palette.sky, bubbleFill: Palette.yellow,
                      bubbleText: Palette.slate, glyph: "*",
                      frameInterval: 1.0 / 15, clipSeconds: 4.0,
                      previewBubble: "…")

        case .working:
            MoodStyle(accent: Palette.screenLight, bubbleFill: Palette.screenLight,
                      bubbleText: Palette.white, glyph: "",
                      frameInterval: 1.0 / 20, clipSeconds: 4.0,
                      previewBubble: "Running a build")

        case .cooking:
            MoodStyle(accent: Palette.flame, bubbleFill: Palette.flame,
                      bubbleText: Palette.white, glyph: "🔥",
                      frameInterval: 1.0 / 24,     // the flame wants to flicker
                      clipSeconds: 4.0, previewBubble: "🔥")

        case .nudging:
            MoodStyle(accent: Palette.yellow, bubbleFill: Palette.yellow,
                      bubbleText: Palette.slate, glyph: "👀",
                      frameInterval: 1.0 / 20, clipSeconds: 4.0,
                      previewBubble: nil)          // filled from the vocabulary

        case .done:
            MoodStyle(accent: Palette.green, bubbleFill: Palette.green,
                      bubbleText: Palette.slate, glyph: "✓",
                      frameInterval: 1.0 / 30,     // one-shot motion, wants to pop
                      clipSeconds: 2.5, previewBubble: "✅ 🥳 🎉")

        case .needsAttention:
            MoodStyle(accent: Palette.alert, bubbleFill: Palette.pink,
                      bubbleText: Palette.slate, glyph: "‼️",
                      frameInterval: 1.0 / 30, clipSeconds: 2.0,
                      previewBubble: nil)          // filled from the vocabulary

        case .sleeping:
            MoodStyle(accent: Palette.slateSoft, bubbleFill: Palette.slateSoft,
                      bubbleText: Palette.white, glyph: "",
                      frameInterval: 1.0 / 6,      // a breath and drifting z's
                      clipSeconds: 4.0, previewBubble: nil)
        }
    }

    /// The vocabulary an idle-ish mood draws its bubble from, if any.
    var shoutoutOccasion: ShoutoutOccasion? {
        switch self {
        case .idle: .idle
        case .done: .finished
        case .nudging: .planReady
        case .needsAttention: .needsYou
        default: nil
        }
    }
}
