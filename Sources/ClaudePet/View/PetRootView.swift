import SwiftUI

/// What lives inside the floating window: the bubble, then Claw'd.
///
/// Both are centred on the same vertical axis so the bubble's tail points at his
/// body. The surrounding margin is transparent and made click-through by
/// `PetWindowController`, so a large window does not become a large dead zone
/// over the desktop.
public struct PetRootView: View {
    @ObservedObject var model: PetViewModel

    /// Points per sprite pixel; the 32×32 grid renders at 32× this.
    public let pixelSize: Double

    /// Transparent grid rows above his head, reserved for worn props like the
    /// hard hat. The bubble band overlaps these so the bubble sits *on* his
    /// head rather than floating a sprite-height above it.
    public static let crownCells = 6

    /// Room for one line of bubble plus its tail.
    public static let bubbleBand: CGFloat = 44

    public var spriteSize: CGFloat { CGFloat(Double(PixelBuffer.side) * pixelSize) }
    private var overlap: CGFloat { CGFloat(Double(Self.crownCells) * pixelSize) }

    public static func spriteSize(pixelSize: Double) -> CGFloat {
        CGFloat(Double(PixelBuffer.side) * pixelSize)
    }

    public static func windowSize(pixelSize: Double) -> CGSize {
        let sprite = spriteSize(pixelSize: pixelSize)
        let overlap = CGFloat(Double(crownCells) * pixelSize)
        // Wide enough that a full-length bubble, centred over him, still fits.
        return CGSize(width: max(300, sprite + 40), height: bubbleBand + sprite - overlap)
    }

    /// Where the sprite sits inside the window, in AppKit's bottom-left origin
    /// space. `AppDelegate` uses this for the click-through region, so the grab
    /// area tracks the sprite instead of guessing.
    public static func spriteFrame(pixelSize: Double) -> CGRect {
        let window = windowSize(pixelSize: pixelSize)
        let sprite = spriteSize(pixelSize: pixelSize)
        return CGRect(x: (window.width - sprite) / 2, y: 0, width: sprite, height: sprite)
    }

    public var body: some View {
        VStack(spacing: -overlap) {
            ZStack {
                if let text = model.state.bubble, !text.isEmpty, model.state.mood != .sleeping {
                    ThoughtBubble(
                        text: text,
                        tool: model.state.tool,
                        mood: model.state.mood,
                        style: model.state.bubbleStyle
                    )
                    .transition(.opacity)
                    .id(text)
                }
            }
            .frame(height: PetRootView.bubbleBand, alignment: .bottom)

            ZStack(alignment: .topTrailing) {
                CrabView(
                    mood: model.state.mood,
                    hoverSince: model.hoverStartedAt?.timeIntervalSinceReferenceDate,
                    clickedAt: model.clickedAt?.timeIntervalSinceReferenceDate,
                    rainbowSince: model.rainbowStartedAt?.timeIntervalSinceReferenceDate
                )
                .frame(width: spriteSize, height: spriteSize)

                if model.state.attentionCount > 0 {
                    Text("\(model.state.attentionCount)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Palette.white)
                        .frame(width: 18, height: 18)
                        .background(Rectangle().fill(Palette.alert))
                }
            }
            .frame(width: spriteSize, height: spriteSize)
        }
        .frame(
            width: PetRootView.windowSize(pixelSize: pixelSize).width,
            height: PetRootView.windowSize(pixelSize: pixelSize).height,
            alignment: .bottom
        )
        .animation(.easeInOut(duration: 0.2), value: model.state.bubble)
    }
}

/// Bridges the `ActivityCoordinator`'s state into SwiftUI.
@MainActor
public final class PetViewModel: ObservableObject {
    @Published public var state: PetState = .sleeping
    /// When the pointer arrived on him, or nil if it is elsewhere. Stored as a
    /// start time rather than a flag so the greeting can play as a timeline.
    @Published public var hoverStartedAt: Date?
    /// When he was last poked. Cleared once the reaction has played out.
    @Published public var clickedAt: Date?
    /// When the party started. 🎉🪄
    @Published public var rainbowStartedAt: Date?
    public init() {}
}
