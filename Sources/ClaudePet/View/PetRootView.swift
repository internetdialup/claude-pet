import SwiftUI

/// What lives inside the floating window: the bubble, then Claw'd.
///
/// Both are centred on the same vertical axis so the bubble's tail points at his
/// body. The surrounding margin is transparent and made click-through by
/// `PetWindowController`, so a large window does not become a large dead zone
/// over the desktop.
/// `@MainActor` is written down rather than inferred, on purpose.
///
/// `View` carries it, so this type was always main-actor state — but WHICH
/// members inherited it depended on the compiler: Swift 6.1 pushes the
/// inference onto static members and 6.3 does not. That gap is invisible from
/// a desk running the newer one, and it is how `SpriteMask`'s nonisolated hit
/// test shipped green locally and turned the CI runner red on the merge.
///
/// Spelled out here, both toolchains agree, and the `nonisolated` geometry
/// below is a promise the local build actually checks.
@MainActor
public struct PetRootView: View {
    @ObservedObject var model: PetViewModel

    /// Points per sprite pixel; the 32×32 grid renders at 32× this.
    public let pixelSize: Double

    /// The system Reduce Motion setting. SwiftUI keeps this current, so
    /// flipping it in System Settings calms him without a relaunch.
    ///
    /// Read HERE, at the live composition layer, and never inside the sprite's
    /// pure render functions — the offline renderers must not inherit the build
    /// machine's accessibility preferences, or the sizzle's byte-determinism
    /// stops being a property of the code.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The flashbang, scaled by that setting. He still celebrates with pose,
    /// hops and colour when the flash stands down — what goes away is the
    /// full-luminance strobe, which is the part worth having a switch for.
    private var flashScale: Double { reduceMotion ? 0 : 1 }

    // The geometry below is `nonisolated` deliberately, and must stay that
    // way. `PetRootView` conforms to `View`, `View` is `@MainActor`, and Swift
    // 6.1 pushes that inference onto the type's static members — so this
    // whole group was main-actor-isolated without anyone writing it down.
    //
    // None of it touches view state: it is pure arithmetic over a pixel size.
    // The window's hit test needs it from `DragHostView`, an `NSView` whose
    // `hitTest` is synchronous and nonisolated, and `PetHitRegion` is a plain
    // struct — neither can await a main actor, and neither should have to.
    //
    // This is the same trap `A colour is not main-actor state` fell into, and
    // it shipped the same way: the Swift on this desk (6.3) does not infer the
    // isolation, so it built clean locally and the CI runner (6.1) went red on
    // the merge. Local green is not a build.

    /// Transparent grid rows above his head, reserved for worn props like the
    /// hard hat. The bubble band overlaps these so the bubble sits *on* his
    /// head rather than floating a sprite-height above it.
    public nonisolated static let crownCells = 6

    /// Room for one line of bubble plus its tail.
    public nonisolated static let bubbleBand: CGFloat = 44

    public var spriteSize: CGFloat { CGFloat(Double(PixelBuffer.side) * pixelSize) }
    private var overlap: CGFloat { CGFloat(Double(Self.crownCells) * pixelSize) }

    public nonisolated static func spriteSize(pixelSize: Double) -> CGFloat {
        CGFloat(Double(PixelBuffer.side) * pixelSize)
    }

    public nonisolated static func windowSize(pixelSize: Double) -> CGSize {
        let sprite = spriteSize(pixelSize: pixelSize)
        let overlap = CGFloat(Double(crownCells) * pixelSize)
        // Wide enough that a full-length bubble, centred over him, still fits.
        return CGSize(width: max(300, sprite + 40), height: bubbleBand + sprite - overlap)
    }

    /// Where the sprite sits inside the window, in AppKit's bottom-left origin
    /// space. `AppDelegate` uses this for the click-through region, so the grab
    /// area tracks the sprite instead of guessing.
    public nonisolated static func spriteFrame(pixelSize: Double) -> CGRect {
        let window = windowSize(pixelSize: pixelSize)
        let sprite = spriteSize(pixelSize: pixelSize)
        return CGRect(x: (window.width - sprite) / 2, y: 0, width: sprite, height: sprite)
    }

    /// Maps a point in view coordinates to a sprite-grid cell, or nil when the
    /// point is off the sprite square. View y runs upward from the window's
    /// bottom; the buffer's y runs downward from its top row, hence the flip.
    ///
    /// The one copy. The window's hit test, the floor-bug pounce and the tests
    /// all ask here — it used to be private on `PetInstance` and restated by
    /// hand in the test suite, which is how a mapping quietly drifts away from
    /// its own test.
    public nonisolated static func spriteCell(for point: CGPoint, pixelSize: Double) -> (x: Int, y: Int)? {
        guard pixelSize > 0 else { return nil }
        let frame = spriteFrame(pixelSize: pixelSize)
        guard frame.contains(point) else { return nil }
        return (Int((point.x - frame.minX) / pixelSize),
                PixelBuffer.side - 1 - Int((point.y - frame.minY) / pixelSize))
    }

    /// The rest-pose torso in view coordinates — the window-drag handle.
    /// `CrabRig`'s body block (cols 6–25, rows 10–20) through the same y-flip
    /// the click-to-cell mapping uses. Rest pose on purpose: drags start on a
    /// calm pet, and a handle that bobbed with him would be unlearnable.
    public nonisolated static func torsoFrame(pixelSize: Double) -> CGRect {
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
                let live = model.transientBubble.flatMap { $0.until > Date() ? $0 : nil }
                let transient = live?.text
                // Sleeping lines are shown, not suppressed.
                //
                // This read `mood != .sleeping ? bubble : nil` for as long as
                // the sleeping pool has existed, which made that whole pool
                // dead code: `ActivityCoordinator`'s `.sleeping` branch drew a
                // line one window in four and the view discarded every one of
                // them. `vocab.swift`'s own note — "shown occasionally, not on
                // every frame" — describes a behaviour nobody could see.
                //
                // The occasionally is enforced where it belongs, at the draw:
                // three windows in four he says nothing at all.
                let stateText = model.state.bubble
                if let text = transient ?? stateText, !text.isEmpty {
                    ThoughtBubble(
                        text: text,
                        tool: transient == nil ? model.state.tool : nil,
                        // A transient wears its OWN mood's styling rather than
                        // the live one, because it is not reporting the live
                        // one — but which mood is now the caller's to say. It
                        // was hardcoded `.done` while every transient was a
                        // celebration, and `.done`'s glyph is a checkmark: fine
                        // in front of "Bug fixed", wrong in front of a hello,
                        // where it reads as a notification rather than a
                        // greeting.
                        mood: transient == nil ? model.state.mood : (live?.mood ?? .done),
                        // A transient used to be forced `.plain`, which was
                        // fine while every one of them was a short pounce line.
                        // The skate lines are not: one of them is 31 columns
                        // and the plain bubble stops at 28. Routed by length,
                        // through the same call the facts and tips use, so
                        // there is one rule about when a line scrolls rather
                        // than three.
                        style: transient.map { ActivityCoordinator.bubbleStyle(for: $0) }
                            ?? model.state.bubbleStyle,
                        service: transient == nil ? model.state.serviceGlyph : nil,
                        knowledge: transient == nil
                            && model.state.bubbleTone == .knowledge
                    )
                    // Asymmetric on purpose: he now speaks and goes quiet
                    // several times a minute, and a symmetric fade reads as
                    // blinking. A slower exit makes a burst read as FINISHING
                    // rather than being cut off.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.28)),
                        removal: .opacity.animation(.easeIn(duration: 0.45))))
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
                    CelebrationGlow(since: started.timeIntervalSinceReferenceDate,
                                    flashSince: flashScale > 0
                                        ? model.moodClock.currentEpoch(for: .done) : nil)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
                }

                // The flash's spill, behind him and on his clock. Both tiers
                // get it — the plain celebration is the common case, and it is
                // the one the operator sees most.
                if model.state.mood == .done, model.state.celebrating, flashScale > 0,
                   let epoch = model.moodClock.currentEpoch(for: .done) {
                    FlashHalo(since: epoch, epic: model.state.epicCelebration)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
                }

                // A plan is waiting on the operator. Gold breathes around him
                // until it is answered, or until it has asked ten times.
                if let latch = model.previewLatch, latch.effect == .beacon {
                    WaitingLight(since: latch.since, endedAt: latch.endedAt,
                                 isPreview: true)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
                } else if model.state.mood == .nudging,
                          let epoch = model.moodClock.currentEpoch(for: .nudging) {
                    WaitingLight(since: epoch)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
                }

                if let party = model.rainbowStartedAt {
                    RainbowRays(since: party.timeIntervalSinceReferenceDate)
                        .frame(width: spriteSize, height: spriteSize)
                        .allowsHitTesting(false)
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
                    helloSince: model.helloStartedAt?.timeIntervalSinceReferenceDate,
                    helloEndedAt: model.helloEndedAt?.timeIntervalSinceReferenceDate,
                    clickedAt: model.clickedAt?.timeIntervalSinceReferenceDate,
                    rainbowSince: model.rainbowStartedAt?.timeIntervalSinceReferenceDate,
                    petSince: model.pettingStartedAt?.timeIntervalSinceReferenceDate,
                    petEndedAt: model.pettingEndedAt?.timeIntervalSinceReferenceDate,
                    pouncedAt: model.pouncedAt?.timeIntervalSinceReferenceDate,
                    snackSince: model.snackStartedAt?.timeIntervalSinceReferenceDate,
                    rudeWakeSince: model.rudeWakeStartedAt?.timeIntervalSinceReferenceDate,
                    shadesSince: model.shadesStartedAt?.timeIntervalSinceReferenceDate,
                    shadesEndedAt: model.shadesEndedAt?.timeIntervalSinceReferenceDate,
                    shadesDing: model.shadesDing,
                    shadesDropping: model.shadesDropping,
                    completedAt: model.badgeCompletionAt?.timeIntervalSinceReferenceDate,
                    badgeShownAt: model.badgeShownAt?.timeIntervalSinceReferenceDate,
                    badgeEndedAt: model.badgeEndedAt?.timeIntervalSinceReferenceDate,
                    // Routed through the seam: the GitHub mark goes vector
                    // (the overlay below) and its pixel stamp stands down;
                    // every other glyph, and a failed asset load, stamps
                    // pixels exactly as before. The timestamps still flow —
                    // harmless with a nil glyph, and the overlay reads the
                    // same latch for its own envelope.
                    serviceGlyph: ServiceGlyph.pixelGlyph(for: model.serviceGlyphKind,
                                                          vectorReady: VectorServiceGlyph.available),
                    serviceGlyphShownAt: model.serviceGlyphShownAt?.timeIntervalSinceReferenceDate,
                    serviceGlyphEndedAt: model.serviceGlyphEndedAt?.timeIntervalSinceReferenceDate,
                    unseen: model.unseen,
                    previewLatch: model.previewLatch,
                    flashScale: flashScale,
                    moodClock: model.moodClock,
                    costumeClock: model.costumeClock
                )
                .frame(width: spriteSize, height: spriteSize)

                // GitHub's actual mark in the glyph box, live-only — under
                // the attention badge, over the sprite. See VectorServiceGlyph.
                if model.serviceGlyphKind == .github, VectorServiceGlyph.available {
                    Color.clear
                        .frame(width: spriteSize, height: spriteSize)
                        .overlay(alignment: .topLeading) {
                            VectorServiceGlyph(
                                shownAt: model.serviceGlyphShownAt?.timeIntervalSinceReferenceDate,
                                endedAt: model.serviceGlyphEndedAt?.timeIntervalSinceReferenceDate,
                                pixelSize: pixelSize)
                        }
                        .allowsHitTesting(false)
                }

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
    /// The flash's own epoch — `MoodClock`'s, not `celebrationStartedAt`'s.
    /// The rings brighten on the taps, and a 90ms attack has no tolerance for
    /// the skew between the two clocks. Nil outside a live celebration.
    var flashSince: Double?

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                Self.draw(in: &context, size: size,
                          t: now - since,
                          blanch: flashSince.map { CrabView.epicBlanch(doneT: now - $0) } ?? 0)
            }
        }
    }

    /// The whole performance, pure in `t`: nothing before 0, nothing after
    /// the 10s envelope closes.
    /// - Parameter bloom: the radial gradient is a smooth ramp — poison for
    ///   a GIF's global palette — so the GIF cut renders rings only.
    /// - Parameter blanch: how hard the sprite is flashing right now. The rings
    ///   ride it up so the burst brightens with the bang instead of holding a
    ///   constant glow while he detonates.
    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double,
                     bloom drawsBloom: Bool = true, blanch: Double = 0) {
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
            // A BOOST on the base 0.30, never a multiplier: at blanch 0 the
            // rings must render exactly as they always have, which is what
            // keeps the sizzle's byte-equality samples honest.
            let alpha = (1 - phase) * (0.30 + 0.45 * Ease.clamp01(blanch)) * envelope
            let rect = CGRect(x: centre.x - half, y: centre.y - half,
                              width: half * 2, height: half * 2)
            context.stroke(Path(rect), with: .color(.white.opacity(alpha)), lineWidth: px)
        }
    }
}

/// The waiting light: gold breathing around him while a plan sits unanswered.
///
/// `.nudging` is the only mood whose whole purpose is to be noticed, and
/// `MoodStyle` already paints it gold everywhere — accent, bubble fill — except
/// on him. This is that colour finally reaching the pet.
///
/// Live-only by construction, the same argument `FlashHalo` and `RainbowTrails`
/// run on: offline renderers compose `CrabView` directly and never see this
/// file, so the radial ramp can never reach a GIF's global palette. That is
/// why a smooth gradient is allowed here and banned on the sprite.
///
/// Two decisions here are worth arguing with rather than reading past.
///
/// **The first breath is at eighteen seconds, not immediately.** The frozen
/// sentinel's `cycle > 0` hands that over for free, and it turns the light
/// into an escalation: he leans, bobs and holds the plan out on his own
/// first, and the light only starts if that did not work.
///
/// **It gives up after three minutes.** An always-on-top pet must not breathe
/// at an empty chair two hundred times, and if you are away from the desk that
/// is exactly what a heartbeat with no cap does. The pose keeps asking; the
/// menu bar and the notification carry the durable signal; the light stops.
/// That cap, not the alpha, is what keeps this civil — it is the number to
/// turn if it ever feels naggy.
///
/// `@MainActor` is written down for the reason `PetRootView`'s doc gives:
/// `View` carries it, but 6.1 pushes the inference onto static members and
/// 6.3 does not, so leaving it implicit means the local build and the CI
/// runner disagree about `breath`. Spelled out, plus `nonisolated` on the
/// schedule, both toolchains agree — and the local build actually checks it.
@MainActor
struct WaitingLight: View {
    /// `MoodClock`'s epoch for the nudge — the same clock the bubble's cadence
    /// runs on, so the light breathes with the words rather than beside them.
    let since: Double

    /// Reference time it was dismissed, while the release plays out.
    var endedAt: Double?

    /// Review mode: the real breath on a short rest, from the selection's own
    /// t=0, with no give-up cap. All three are things a preview has to see
    /// past — an effect whose first breath is eighteen seconds out and whose
    /// last is three minutes out is not reviewable on its real schedule.
    var isPreview = false

    /// The review loop's rest. **4.0s, not the live 18** — the rest is part of
    /// the effect and has to be visible, but 3.4 seconds of nothing after
    /// clicking a menu item reads as a broken menu rather than as a pause.
    /// This was measured: the first version rested 3.4s and looked broken 57%
    /// of the time.
    nonisolated static let previewPeriod = 4.0

    /// The preview's breath: the real 2.6s window on that shorter rest.
    ///
    /// `Ease.window`'s own `guard t > 0` is what makes it start dark and
    /// breathe UP. The live light gets that from `cycle > 0`; the first
    /// version of this preview hard-coded `t = 18 + now % 6`, which jumped
    /// straight past it into an arbitrary point of cycle 1 — a full gold ring
    /// arriving in one frame, 43% of the time.
    nonisolated static func previewBreath(t: Double) -> Double {
        Ease.window(t.truncatingRemainder(dividingBy: previewPeriod),
                    duration: 2.6, edge: 1.3)
    }

    /// No dice, deliberately. `.nudging`'s `BubbleCadence` is `chance: 1.0`,
    /// documented as "a heartbeat that never skips, for the states that exist
    /// to get you", and an 18s period matches it. A state that exists to be
    /// noticed should not roll for whether it is noticed.
    nonisolated static func breath(nudgeT t: Double) -> Double {
        let cycle = Int(floor(t / 18))
        guard cycle > 0, cycle <= 10 else { return 0 }
        return Ease.window(t - Double(cycle) * 18, duration: 2.6, edge: 1.3)
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate - since
                // `draw` owns no schedule at all now — the body picks which one
                // is running, which is also what lets the preview fold its
                // release in before anything is drawn.
                var breath = isPreview ? Self.previewBreath(t: t) : Self.breath(nudgeT: t)
                if isPreview, let endedAt {
                    let endedT = max(0, endedAt - since)
                    breath *= 1 - Ease.smoothstep((t - endedT) / 1.3)
                }
                Self.draw(in: &context, size: size, breath: breath)
            }
        }
    }

    /// `CelebrationGlow`'s two halves at a fraction of the volume: one
    /// pixel-snapped ring over a soft bloom. Whole-point centre for the same
    /// reason it gives — a fractional centre antialiases the stroke and picks
    /// up run-to-run noise.
    static func draw(in context: inout GraphicsContext, size: CGSize, breath: Double) {
        guard breath > 0.001 else { return }

        // Typed in small steps rather than one big mixed expression: CGFloat
        // and Double are the same type here but not to a 6.1 type-checker,
        // which abandons large mixed arithmetic as ambiguous.
        let px: Double = size.width / Double(PixelBuffer.side)
        let centre = CGPoint(x: (size.width / 2).rounded(),
                             y: (size.height * 0.55).rounded())

        // Every size below is bounded so the shape never meets the frame.
        // `FlashHalo`'s doc has the argument: the window has almost no margin
        // around the sprite, so anything that reaches the bound at non-zero
        // alpha is clipped into a hard straight line rather than fading out.
        // I drew it at CelebrationGlow's radii first and the ring's top edge
        // was sliced flat at the peak of every breath.
        let radius: Double = size.width * (0.22 + 0.12 * breath)
        let bloom = Gradient(colors: [Palette.yellow.opacity(0.16 * breath), .clear])
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                   width: radius * 2, height: radius * 2)),
            with: .radialGradient(bloom, center: centre, startRadius: 0, endRadius: radius))

        // Half-width in cells, centred at 0.55 of the height: 12 keeps the
        // lower edge at row 29.6 of 32, inside the frame at full breath.
        let cells: Double = (7 + 5 * breath).rounded()
        let half: Double = cells * px
        let rect = CGRect(x: centre.x - half, y: centre.y - half,
                          width: half * 2, height: half * 2)
        context.stroke(Path(rect),
                       with: .color(Palette.flameCore.opacity(0.22 * breath)),
                       lineWidth: px)
    }
}

/// The flash's spill: a soft white bloom on the same clock as the sprite's
/// blanch, so he reads as EMITTING light rather than merely being repainted.
///
/// Bounded to the sprite square on purpose. The window is only a couple of
/// dozen points taller than the sprite and has **no margin at all below his
/// feet**, so a bloom any wider than this meets the window's bottom bound at
/// non-zero alpha and draws a hard white line under him on every flash.
///
/// Live-only by construction: offline renderers compose `CrabView` directly and
/// never see this file, so the radial ramp can never reach a GIF's palette or a
/// chroma key — the same argument `RainbowTrails` runs on.
struct FlashHalo: View {
    /// `MoodClock`'s epoch for the done mood — the SAME clock the sprite's
    /// blanch uses. Do not "simplify" this to `celebrationStartedAt`: that is
    /// stamped from `Date()` at state intake, and the resulting skew would put
    /// the spill visibly out of phase with a 90ms attack.
    let since: Double
    let epic: Bool

    /// Peak centre alpha. The sprite goes to 100%; the air around him at 42%
    /// reads as light spilling off him without becoming a screen event.
    static let peakAlpha = 0.42

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate - since
                let blanch = epic ? CrabView.epicBlanch(doneT: t)
                                  : CrabView.celebrationBlanch(doneT: t)
                guard blanch > 0.001 else { return }
                // Whole-point centre, matching CelebrationGlow: on an epic the
                // two effects must share an origin, and fractional centres are
                // what put LSB noise into antialiased edges here before.
                let centre = CGPoint(x: (size.width / 2).rounded(),
                                     y: (size.height * 0.55).rounded())
                // 0.45 × side from a 0.55h centre puts alpha at zero exactly on
                // the nearest frame boundary, so the disc never meets a clip
                // edge while still lit.
                let radius = size.width * 0.45
                let ramp = Gradient(colors: [Palette.white.opacity(Self.peakAlpha * blanch),
                                             .clear])
                context.fill(
                    Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .radialGradient(ramp, center: centre,
                                          startRadius: 0, endRadius: radius))
            }
        }
    }
}

/// The party's backdrop: eight flat-filled wedges of quantised hue rotating
/// slowly behind him, alpha riding the party's trapezoid. Flat fills only —
/// no gradients, so a GIF's global palette survives it — and the drawing is
/// pure in `t` for the same determinism reasons as the glow.
struct RainbowRays: View {
    let since: Double

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                Self.draw(in: &context, size: size,
                          t: timeline.date.timeIntervalSinceReferenceDate - since)
            }
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double) {
        let amount = Ease.window(t, duration: 4.0, edge: 0.4)
        guard amount > 0.001 else { return }
        let centre = CGPoint(x: (size.width / 2).rounded(),
                             y: (size.height * 0.55).rounded())
        let reach = size.width * 0.9
        let spin = t * 0.15 * 2 * .pi
        for ray in 0..<8 {
            let base = spin + Double(ray) / 8 * 2 * .pi
            let hue = Double(ray) / 8
            var path = Path()
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + cos(base) * reach,
                                     y: centre.y + sin(base) * reach))
            path.addLine(to: CGPoint(x: centre.x + cos(base + 0.22) * reach,
                                     y: centre.y + sin(base + 0.22) * reach))
            path.closeSubpath()
            context.fill(path, with: .color(Color(hue: hue, saturation: 0.7,
                                                  brightness: 0.9)
                .opacity(0.10 * amount)))
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
    /// Nobody can see him: the display is asleep, or his window is fully
    /// covered by another. The timeline drops to a crawl.
    ///
    /// **A rate input, never a pose input.** `render(at:)` stays a pure
    /// function of `time`; this only changes how often it is asked. A slow
    /// tick rather than `frozenTime`, which would also disable hover, the
    /// click latches, the badge and the glyph — the point is to stop drawing,
    /// not to stop being a pet.
    @Published public var unseen = false
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
    /// One rare effect forced on for review, with the instant it was chosen.
    /// Nil in every normal run — this exists so the schedules can be seen past.
    ///
    /// The epoch travels WITH the effect rather than beside it, so a preview
    /// always has its own t=0 to ease in from, and the render state can outlive
    /// the operator's intent long enough to ease back out.
    @Published public var previewLatch: CrabAnimator.PreviewLatch?
    /// Press-and-hold petting, same two-ended shape as hover.
    @Published public var pettingStartedAt: Date?
    @Published public var pettingEndedAt: Date?
    /// A floor bug was just caught.
    @Published public var pouncedAt: Date?
    /// The first-run hello — the one wave a brand-new install gets.
    /// Two-ended like hover, but both ends are set at once: nothing
    /// comes along later to finish it the way a pointer leaving does.
    @Published public var helloStartedAt: Date?
    @Published public var helloEndedAt: Date?
    /// The shrimp snack began — a double-poke on an idle crab's body feeds
    /// him. (The original sleeping-click trigger was stillborn; the poke
    /// ladder gave the shrimp its comeback.)
    @Published public var snackStartedAt: Date?
    /// A sleeping crab was poked awake — the rude-wake sequence is playing.
    @Published public var rudeWakeStartedAt: Date?
    /// The deal-with-it latch: a flaired fun fact arrived (the shades drop)
    /// and left (the standard prop fade). `shadesDropping` is a RATE input
    /// only — it holds the 30fps tier for the fall's beat, never a pose.
    @Published public var shadesStartedAt: Date?
    @Published public var shadesEndedAt: Date?
    @Published public var shadesDing = false
    @Published public var shadesDropping = false
    /// A short-lived line that outranks the state's bubble — the pounce
    /// one-liner, the skate shout, the first-run hello. Cleared by its own
    /// deadline.
    ///
    /// `mood` is the styling it wears, not a claim about what he is doing:
    /// `.done` for the celebrations, `.idle` for the greeting, which is the
    /// same green without the checkmark.
    @Published public var transientBubble: (text: String, until: Date, mood: PetMood)?
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
