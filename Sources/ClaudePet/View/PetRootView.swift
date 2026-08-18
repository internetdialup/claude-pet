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

    /// The rest-pose torso in view coordinates — the window-drag handle.
    /// `CrabRig`'s body block (cols 6–25, rows 10–20) through the same y-flip
    /// the click-to-cell mapping uses. Rest pose on purpose: drags start on a
    /// calm pet, and a handle that bobbed with him would be unlearnable.
    public static func torsoFrame(pixelSize: Double) -> CGRect {
        let sprite = spriteFrame(pixelSize: pixelSize)
        return CGRect(
            x: sprite.minX + CGFloat(CrabRig.bodyX) * pixelSize,
            y: sprite.minY + CGFloat(PixelBuffer.side - CrabRig.bodyY - CrabRig.bodyH) * pixelSize,
            width: CGFloat(CrabRig.bodyW) * pixelSize,
            height: CGFloat(CrabRig.bodyH) * pixelSize)
    }

    public var body: some View {
        VStack(spacing: -overlap) {
            ZStack {
                // A transient line (the pounce one-liner) outranks the state's
                // bubble and may appear even while he sleeps.
                let transient = model.transientBubble.flatMap { $0.until > Date() ? $0.text : nil }
                let stateText = model.state.mood != .sleeping ? model.state.bubble : nil
                if let text = transient ?? stateText, !text.isEmpty {
                    ThoughtBubble(
                        text: text,
                        tool: transient == nil ? model.state.tool : nil,
                        mood: transient == nil ? model.state.mood : .done,
                        style: transient == nil ? model.state.bubbleStyle : .plain,
                        service: transient == nil ? model.state.serviceGlyph : nil
                    )
                    .transition(.opacity)
                    .id(text)
                }
            }
            .frame(height: PetRootView.bubbleBand, alignment: .bottom)
            // The bubble overlaps the sprite by `overlap`, and SwiftUI draws
            // later siblings on top — without this the sprite ate the bubble's
            // tail. ReelRenderer carried the same fix; the live view never did.
            .zIndex(1)

            ZStack(alignment: .topTrailing) {
                // The world behind him: the 8-bit shadow he stands on, and —
                // during an epic finale — the glow. Neither exists in offline
                // renders, which compose CrabView directly.
                Color.clear
                    .frame(width: spriteSize, height: spriteSize)
                    .overlay(alignment: .top) {
                        // A flat 0.15 block under the footline (legs end at
                        // grid row 24) — the floor's opinion, not the rig's.
                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(width: 20 * pixelSize, height: 1.5 * pixelSize)
                            .offset(y: 25 * pixelSize)
                    }
                    .allowsHitTesting(false)

                if let started = model.celebrationStartedAt {
                    CelebrationGlow(since: started.timeIntervalSinceReferenceDate)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
                }

                if let party = model.rainbowStartedAt {
                    RainbowTrails(since: party.timeIntervalSinceReferenceDate,
                                  side: spriteSize)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
                }

                CrabView(
                    mood: model.state.mood,
                    costume: model.costume,
                    celebrating: model.state.celebrating,
                    epicCelebration: model.state.epicCelebration,
                    taskFraction: model.state.taskFraction,
                    hoverSince: model.hoverStartedAt?.timeIntervalSinceReferenceDate,
                    hoverEndedAt: model.hoverEndedAt?.timeIntervalSinceReferenceDate,
                    clickedAt: model.clickedAt?.timeIntervalSinceReferenceDate,
                    rainbowSince: model.rainbowStartedAt?.timeIntervalSinceReferenceDate,
                    petSince: model.pettingStartedAt?.timeIntervalSinceReferenceDate,
                    petEndedAt: model.pettingEndedAt?.timeIntervalSinceReferenceDate,
                    pouncedAt: model.pouncedAt?.timeIntervalSinceReferenceDate,
                    snackSince: model.snackStartedAt?.timeIntervalSinceReferenceDate,
                    completedAt: model.badgeCompletionAt?.timeIntervalSinceReferenceDate,
                    badgeShownAt: model.badgeShownAt?.timeIntervalSinceReferenceDate,
                    badgeEndedAt: model.badgeEndedAt?.timeIntervalSinceReferenceDate,
                    serviceGlyph: model.serviceGlyphKind,
                    serviceGlyphShownAt: model.serviceGlyphShownAt?.timeIntervalSinceReferenceDate,
                    serviceGlyphEndedAt: model.serviceGlyphEndedAt?.timeIntervalSinceReferenceDate,
                    moodClock: model.moodClock,
                    costumeClock: model.costumeClock
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

/// The epic finale's backdrop: a soft radial bloom under three expanding
/// 8-bit square rings, all inside one 10s eased envelope. The drawing is
/// `draw(in:size:t:)` — pure in `t` — so the live TimelineView here and the
/// offline sizzle renderer share one implementation and cannot drift.
struct CelebrationGlow: View {
    let since: Double

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                Self.draw(in: &context, size: size,
                          t: timeline.date.timeIntervalSinceReferenceDate - since)
            }
        }
    }

    /// The whole performance, pure in `t`: nothing before 0, nothing after
    /// the 10s envelope closes.
    /// - Parameter bloom: the radial gradient is a smooth ramp — poison for
    ///   a GIF's global palette — so the GIF cut renders rings only.
    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double,
                     bloom drawsBloom: Bool = true) {
        let envelope = Ease.window(t, duration: 10, edge: 0.9)
        guard envelope > 0.001 else { return }
        let px = size.width / Double(PixelBuffer.side)
        // Whole-point centre: the rings' whole read is "pixel-snapped", and a
        // fractional centre betrayed it — antialiased stroke edges that also
        // rasterise with run-to-run LSB noise under load, which broke the
        // sizzle's byte-determinism guarantee.
        let centre = CGPoint(x: (size.width / 2).rounded(),
                             y: (size.height * 0.55).rounded())

        // The bloom: warm light swelling with the envelope.
        if drawsBloom {
            let radius = size.width * (0.30 + 0.18 * envelope)
            let bloom = Gradient(colors: [Palette.flameCore.opacity(0.35 * envelope), .clear])
            context.fill(
                Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .radialGradient(bloom, center: centre, startRadius: 0, endRadius: radius))
        }

        // The burst: three pixel-snapped square rings expanding on a
        // staggered loop, fading as they grow.
        for ring in 0..<3 {
            let phase = (t * 0.5 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
            let cells = (6 + phase * 10).rounded()
            let half = cells * px
            let alpha = (1 - phase) * 0.30 * envelope
            let rect = CGRect(x: centre.x - half, y: centre.y - half,
                              width: half * 2, height: half * 2)
            context.stroke(Path(rect), with: .color(.white.opacity(alpha)), lineWidth: px)
        }
    }
}

/// The party's chromatic afterimages: the same pure party pose pipeline at
/// time-shifted offsets, silhouetted so a single hue-shifted tint colours the
/// whole figure, stacked behind the live sprite at stepped opacity. Live-only
/// by construction — offline renderers never compose PetRootView; the shifted
/// tints are nil while elapsed < kΔ (clean birth) and the trapezoid ends them
/// by 4.0s, so latch removal is never the ease.
private struct RainbowTrails: View {
    let since: Double
    let side: CGFloat

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate - since
            ZStack {
                trail(elapsed: elapsed, k: 2).opacity(0.18)
                trail(elapsed: elapsed, k: 1).opacity(0.35)
            }
        }
    }

    @ViewBuilder
    private func trail(elapsed: Double, k: Int) -> some View {
        let shifted = elapsed - Double(k) * 0.09
        if shifted > 0,
           let mood = CrabView.rainbowMood(elapsed: shifted),
           let tint = CrabView.rainbowTint(elapsed: shifted) {
            PixelCanvasView(buffer: CrabRig.render(
                                CrabAnimator.pose(mood: mood, t: shifted)).silhouette(),
                            bodyTint: tint, seamBleed: 0)
                .frame(width: side, height: side)
        }
    }
}

/// Bridges the `ActivityCoordinator`'s state into SwiftUI.
@MainActor
public final class PetViewModel: ObservableObject {
    @Published public var state: PetState = .sleeping
    /// When the pointer arrived on him, or nil if it is elsewhere. Stored as a
    /// start time rather than a flag so the greeting can play as a timeline.
    @Published public var hoverStartedAt: Date?
    /// When the pointer left, while the greeting eases back out. `hoverStartedAt`
    /// stays set through the release; both clear once it has finished.
    @Published public var hoverEndedAt: Date?
    /// When he was last poked. Cleared once the reaction has played out.
    @Published public var clickedAt: Date?
    /// When the party started. 🎉🪄
    @Published public var rainbowStartedAt: Date?
    /// The wardrobe, mirrored from `Preferences` so the sprite re-renders on a
    /// costume change.
    @Published public var costume: Costume = .none
    /// Press-and-hold petting, same two-ended shape as hover.
    @Published public var pettingStartedAt: Date?
    @Published public var pettingEndedAt: Date?
    /// A floor bug was just caught.
    @Published public var pouncedAt: Date?
    /// The sleeping-click shrimp snack began.
    @Published public var snackStartedAt: Date?
    /// A short-lived line that outranks the state's bubble — the pounce
    /// one-liner. Cleared by its own deadline.
    @Published public var transientBubble: (text: String, until: Date)?
    /// The completion badge's identity and appearance latches, managed by
    /// AppDelegate from published state changes.
    @Published public var badgeCompletionAt: Date?
    @Published public var badgeShownAt: Date?
    @Published public var badgeEndedAt: Date?
    /// The service glyph's kind and appearance latches, managed by
    /// PetInstance on the badge pattern — a kind change dips through zero.
    @Published public var serviceGlyphKind: ServiceGlyph?
    @Published public var serviceGlyphShownAt: Date?
    @Published public var serviceGlyphEndedAt: Date?
    /// When the epic finale began — the glow layer's own t=0, latched by
    /// PetInstance from published state (never from MoodClock, whose epoch
    /// rebases on blends).
    @Published public var celebrationStartedAt: Date?
    /// This pet's own view-state clocks — never the shared singletons, which
    /// exist only as defaults for bare constructions. Two pets rebasing one
    /// clock would restart each other's one-shot beats.
    public let moodClock = MoodClock()
    public let costumeClock = CostumeClock()
    public init() {}
}
