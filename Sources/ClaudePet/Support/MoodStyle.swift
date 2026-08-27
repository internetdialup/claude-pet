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
/// SwiftUI import; this is the View
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
    /// Where in the mood's own clock that capture starts. Zero for everything
    /// whose motion is continuous; `idle` is the exception, because its
    /// flourishes are dice-gated from cycle 1 and the seven-second period is
    /// longer than the six-second clip — anchored at zero the clip would be
    /// six seconds of a crab breathing.
    public var clipStart: Double = 0
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
                      clipStart: CrabAnimator.firstFlourishAt,
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
                      clipSeconds: 4.0, previewBubble: nil)   // from the vocabulary

        case .nudging:
            MoodStyle(accent: Palette.yellow, bubbleFill: Palette.yellow,
                      bubbleText: Palette.slate, glyph: "👀",
                      frameInterval: 1.0 / 20, clipSeconds: 4.0,
                      previewBubble: nil)          // filled from the vocabulary

        case .done:
            MoodStyle(accent: Palette.green, bubbleFill: Palette.green,
                      bubbleText: Palette.slate, glyph: "✓",
                      frameInterval: 1.0 / 30,     // one-shot motion, wants to pop
                      clipSeconds: 2.5, previewBubble: nil)   // from the vocabulary

        case .needsAttention:
            MoodStyle(accent: Palette.alert, bubbleFill: Palette.pink,
                      bubbleText: Palette.slate, glyph: "‼️",
                      frameInterval: 1.0 / 30, clipSeconds: 2.0,
                      previewBubble: nil)          // filled from the vocabulary

        case .sleeping:
            MoodStyle(accent: Palette.slateSoft, bubbleFill: Palette.slateSoft,
                      bubbleText: Palette.white, glyph: "",
                      frameInterval: 1.0 / 6,      // one slow breath
                      clipSeconds: CrabAnimator.breathPeriod, previewBubble: nil)
        }
    }

    /// The vocabulary this mood draws its bubble from.
    ///
    /// Total, so every state can carry the user's own words. What actually
    /// reaches the bubble still follows the precedence documented in
    /// `vocab.swift`: a matching rule first, then the real task text, then these.
    var shoutoutOccasion: ShoutoutOccasion {
        switch self {
        case .idle: .idle
        case .thinking: .thinking
        case .working: .working
        case .cooking: .cooking
        case .nudging: .planReady
        case .done: .finished
        case .needsAttention: .needsYou
        case .sleeping: .sleeping
        }
    }
}
