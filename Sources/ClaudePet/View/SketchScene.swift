import SwiftUI

/// 🎨 **What a sketch IS** — the composition model, and the one function that
/// draws it.
///
/// A sketch is an ordered stack of layers over a flat ground, looping over a
/// whole number of beats at 120. Nothing here knows whether it is being watched
/// live or written to a file.
///
/// 🔎 **The rule the whole tool hangs on: `scene` is pure in `t`.** The live
/// window and the exporter call this same function with different clocks, which
/// is the only reason the GIF you get is the loop you were watching rather than
/// a near-miss of it. It is the house convention — `PetRootView` states it in
/// the same words for the sizzle renderer — and `theSceneIsPureInT` pins it.
@MainActor
enum SketchScene {

    // MARK: - Shapes

    /// A canvas and the whole-cell sprite side that sits in it.
    ///
    /// Every sprite side is a multiple of 32, so a cell is a whole number of
    /// points; every canvas dimension is even, because H.264 refuses odd ones
    /// outright. Both are pinned by `everyShapeIsWholeCellAndEven`.
    struct Shape: Sendable {
        let name: String
        let canvas: CGSize
        let sprite: CGFloat
        var cell: CGFloat { sprite / CGFloat(PixelBuffer.side) }
    }

    /// 1:1 for a post, 4:5 for a feed, 9:16 for a reel, 16:9 for a slide. The
    /// numbers are the ones the shipped renderers already settled on rather
    /// than fresh guesses.
    nonisolated static let shapes: [Shape] = [
        Shape(name: "1x1",  canvas: CGSize(width: 640,  height: 640),  sprite: 576),
        Shape(name: "4x5",  canvas: CGSize(width: 1080, height: 1350), sprite: 896),
        Shape(name: "9x16", canvas: CGSize(width: 1080, height: 1920), sprite: 896),
        Shape(name: "16x9", canvas: CGSize(width: 640,  height: 360),  sprite: 320),
    ]

    // MARK: - The clock

    /// 120 BPM, the house grid, same as every cut in this repo.
    nonisolated static let beat = 0.5
    /// 20fps — and not by taste. A GIF stores its delay in whole centiseconds,
    /// and 1/20 is exactly 0.05 where 1/30 is not, so this is the fastest rate
    /// that survives the round trip unchanged.
    nonisolated static let fps = 20
    nonisolated static let frameDelay = 0.05
    /// MP4 has no such constraint, so the video goes out smoother.
    nonisolated static let videoFps: Int32 = 30

    // MARK: - Presets

    /// Canvas-plane layers: everything already written as `draw(in:size:t:)`.
    enum CanvasPreset: String, CaseIterable, Codable, Sendable {
        case party, rays, glow, forest, waiting

        var title: String {
            switch self {
            case .party:   "Party ground"
            case .rays:    "Rainbow rays"
            case .glow:    "Celebration rings"
            case .forest:  "Forest parallax"
            case .waiting: "Waiting light"
            }
        }
    }

    /// Sprite-plane layers: everything already written as `draw(_:inout PixelBuffer …)`.
    enum SpritePreset: String, CaseIterable, Codable, Sendable {
        case snow, hearts, leaves, pumpkins, easterGround, fireworks
        case ledge, bushes, groundRush, comboTrail, boardFire, swell

        var title: String {
            switch self {
            case .snow:         "Snowfall"
            case .hearts:       "Rising hearts"
            case .leaves:       "Falling leaves"
            case .pumpkins:     "Floor pumpkins"
            case .easterGround: "Easter ground"
            case .fireworks:    "Fireworks"
            case .ledge:        "Ledge"
            case .bushes:       "Hedge (parallax)"
            case .groundRush:   "Ground rush"
            case .comboTrail:   "Combo trail"
            case .boardFire:    "Board on fire"
            case .swell:        "Surf swell"
            }
        }
    }

    /// What Claw'd is doing. Three families, because the rig already has three.
    enum PetKind: String, CaseIterable, Codable, Sendable {
        case mood, flourish, effect
    }

    // MARK: - A layer

    /// A colour the stack can persist. SwiftUI's `Color` is not `Codable`, and
    /// a sketch that forgot its palette on every rebuild would be no tool.
    struct RGBA: Codable, Equatable, Sendable {
        var r: Double, g: Double, b: Double, a: Double

        var color: Color { Color(red: r, green: g, blue: b, opacity: a) }

        init(r: Double, g: Double, b: Double, a: Double = 1) {
            (self.r, self.g, self.b, self.a) = (r, g, b, a)
        }

        /// Through sRGB explicitly — a colour from a picker can arrive in a
        /// space whose components mean something else entirely.
        init(_ color: Color) {
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
            self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent),
                      b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
        }
    }

    /// One entry in the stack.
    ///
    /// Deliberately flat and string-keyed rather than an enum with associated
    /// values: the stack is persisted to JSON between runs so a rebuild does
    /// not cost you your setup, and a flat shape survives that without a
    /// hand-written coder.
    struct Layer: Codable, Identifiable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable { case canvas, sprite, pet, bubble, custom }

        var id = UUID()
        var kind: Kind
        /// Raw value of `CanvasPreset` or `SpritePreset`, by `kind`.
        var preset: String = ""
        var petKind: PetKind = .flourish
        /// Raw value of `PetMood`, `Flourish` or `PreviewEffect`, by `petKind`.
        var petName: String = ""
        var costume: String = Costume.none.rawValue
        /// The one generic knob: how much of this layer is on, 0…1. Different
        /// layers spend it differently — the party's envelope, the rush's
        /// visibility, the trail's score — and a slider is a slider.
        var amount: Double = 1

        // MARK: …and the bubble's own

        var text: String = "Let's build something awesome!"
        /// `plain` types, `marquee` scrolls, `dots` says nothing at all.
        var bubbleStyle: String = "plain"
        var mood: String = PetMood.idle.rawValue
        /// Nil means the mood's own colour, which is what the app ships.
        var fill: RGBA? = nil
        var ink: RGBA? = nil
        /// Nil is the product's monospaced bold — the one face whose advance
        /// the bubble's geometry was measured against.
        var fontName: String? = nil
        var fontSize: Double = Double(ThoughtBubble.defaultFontSize)
        var typeSpeed: Double = TypewriterText.charsPerSecond
        /// A multiplier on the bubble's automatic size, not its whole size.
        ///
        /// 🔎 The bubble does not scale with the frame on its own, and left
        /// alone that reads wrong rather than merely small: live it is about
        /// three times his width, and against a 576pt sprite at its intrinsic
        /// 276 it comes out at half — the proportion inverted. `bubbleFit`
        /// below restores the relationship; this is the knob on top of it.
        var bubbleScale: Double = 1
        /// Nudge from the anchor, in whole cells, so it stays on the grid.
        var offsetCellsX: Int = 0
        var offsetCellsY: Int = 0

        var title: String {
            switch kind {
            case .canvas: CanvasPreset(rawValue: preset)?.title ?? preset
            case .sprite: SpritePreset(rawValue: preset)?.title ?? preset
            case .pet:    "Claw'd · \(petName)"
            case .bubble: "Bubble · \(bubbleStyle)"
            case .custom: "Sketch.swift"
            }
        }

        var resolvedStyle: PetState.BubbleStyle {
            switch bubbleStyle {
            case "marquee": .marquee
            case "dots":    .dots
            default:        .plain
            }
        }
    }

    /// A whole sketch.
    struct Stack: Codable, Equatable, Sendable {
        var groundIndex: Int = 0
        var shapeIndex: Int = 0
        /// Loop length in beats. Eight is four seconds, the house default.
        var beats: Int = 8
        var layers: [Layer] = []

        var seconds: Double { Double(beats) * SketchScene.beat }
        var frameCount: Int { Int((seconds * Double(SketchScene.fps)).rounded()) }
        var videoFrameCount: Int { Int((seconds * Double(SketchScene.videoFps)).rounded()) }

        var ground: Color { MarketingPalette.all[groundIndex % MarketingPalette.all.count] }
        var shape: Shape { SketchScene.shapes[shapeIndex % SketchScene.shapes.count] }

        /// What a fresh sketchpad opens on: him, mid-half-cab, on cream.
        static let starter = Stack(layers: [
            Layer(kind: .pet, petKind: .flourish, petName: CrabAnimator.Flourish.halfCab.rawValue),
        ])
    }

    // MARK: - The pose for a pet layer

    /// 🔎 A FROZEN base, for the same reason every looping clip in this repo
    /// uses one: the ordinary `flourishPose` builds its base from the trick's
    /// own clock, so a breathing, blinking idle would put a second seam at
    /// every loop boundary on its own schedule.
    static var stance: CrabPose {
        var stance = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false)
        stance.gazeX = 0
        stance.gazeY = 0
        return stance
    }

    static func pose(for layer: Layer, t: Double) -> CrabPose {
        switch layer.petKind {
        case .mood:
            let mood = PetMood(rawValue: layer.petName) ?? .idle
            return CrabAnimator.pose(mood: mood, t: t, flourishes: false)
        case .flourish:
            let kind = CrabAnimator.Flourish(rawValue: layer.petName) ?? .halfCab
            // Past its duration `flourishPose` hands the base back whole, so a
            // loop longer than the trick gets a still tail for free.
            return CrabAnimator.flourishPose(kind, at: t, base: stance)
        case .effect:
            let effect = CrabAnimator.PreviewEffect(rawValue: layer.petName) ?? .hearts
            var pose = stance
            CrabAnimator.applyPreview(CrabAnimator.PreviewFrame(effect: effect, t: t), to: &pose)
            return pose
        }
    }

    // MARK: - The scene

    /// The whole sketch at `t` loop-local seconds. Pure in `t`.
    @ViewBuilder
    static func scene(_ stack: Stack, t: Double) -> some View {
        let shape = stack.shape
        ZStack {
            stack.ground
            ForEach(stack.layers) { layer in
                layerView(layer, t: t, shape: shape, loopSeconds: stack.seconds)
            }
        }
        .frame(width: shape.canvas.width, height: shape.canvas.height)
        .clipped()
    }

    /// One layer, as its own view — which is what keeps the stack's order
    /// honest across two planes that cannot share a buffer.
    /// Where the bubble hangs when nothing has nudged it.
    ///
    /// His crown sits about a fifth of the sprite box above its centre, and the
    /// bubble's tail wants to just clear it — so the band's own height comes
    /// off as well. Approximate on purpose: the offset steppers are there
    /// because a 32-cell character wearing fifteen different costumes does not
    /// have one true head height.
    private static func bubbleAnchorY(_ shape: Shape) -> CGFloat {
        -(shape.sprite * 0.19 + PetRootView.bubbleBand / 2)
    }

    /// How much to grow the bubble so it reads at the frame's scale.
    ///
    /// Pinned to the canvas rather than to the sprite: at its widest the bubble
    /// should take about three quarters of the frame, which is the proportion
    /// it holds live against a desktop pet. `ThoughtBubble.maxWidth` is the
    /// widest it can ever draw itself, so that is the number to divide.
    static func bubbleFit(_ shape: Shape) -> CGFloat {
        shape.canvas.width * 0.75 / ThoughtBubble.maxWidth
    }

    @ViewBuilder
    private static func layerView(_ layer: Layer, t: Double, shape: Shape,
                                  loopSeconds: Double) -> some View {
        switch layer.kind {
        case .canvas:
            Canvas(rendersAsynchronously: false) { context, size in
                drawCanvasPreset(CanvasPreset(rawValue: layer.preset),
                                 in: &context, size: size, t: t,
                                 amount: layer.amount, cell: shape.cell)
            }
            .frame(width: shape.canvas.width, height: shape.canvas.height)
            .allowsHitTesting(false)

        case .sprite:
            spriteLayer(shape: shape) { b in
                drawSpritePreset(SpritePreset(rawValue: layer.preset), into: &b,
                                 t: t, amount: layer.amount, loopSeconds: loopSeconds)
            }

        case .pet:
            let costume = Costume(rawValue: layer.costume) ?? .none
            PixelCanvasView(buffer: CrabRig.render(pose(for: layer, t: t), costume: costume),
                            inkOverrides: CostumeStyle.blendedOverrides(from: costume,
                                                                        to: costume, u: 1),
                            seamBleed: 0)
                .frame(width: shape.sprite, height: shape.sprite)

        case .bubble:
            // 🔎 `typesOnFrozenClock: true` is the whole reason this round
            // touched a product view. Everywhere else a frozen clock shows the
            // finished line, because a still caught mid-word is nobody's
            // picture; here the frozen clock IS the loop clock, so it types.
            //
            // `loopSeconds` only matters to the marquee, and there it is not
            // optional: offline the scroll sits at phase 0 unless a renderer
            // says how long one pass should take.
            ThoughtBubble(text: layer.text,
                          tool: nil,
                          mood: PetMood(rawValue: layer.mood) ?? .idle,
                          style: layer.resolvedStyle,
                          frozenTime: t,
                          loopSeconds: layer.resolvedStyle == .marquee ? loopSeconds : nil,
                          fillOverride: layer.fill?.color,
                          textOverride: layer.ink?.color,
                          fontName: layer.fontName,
                          fontSize: CGFloat(layer.fontSize),
                          typesOnFrozenClock: true,
                          charsPerSecond: layer.typeSpeed)
                .scaleEffect(bubbleFit(shape) * CGFloat(layer.bubbleScale))
                .offset(x: CGFloat(layer.offsetCellsX) * shape.cell,
                        y: bubbleAnchorY(shape) + CGFloat(layer.offsetCellsY) * shape.cell)

        case .custom:
            ZStack {
                spriteLayer(shape: shape) { b in Sketch.drawSprite(&b, t: t) }
                Canvas(rendersAsynchronously: false) { context, size in
                    Sketch.drawCanvas(in: &context, size: size, t: t)
                }
                .frame(width: shape.canvas.width, height: shape.canvas.height)
                .allowsHitTesting(false)
            }
        }
    }

    /// A sprite-plane layer in its own buffer. `seamBleed: 0` because the
    /// ground below is opaque and the default half-pixel overdraw would draw a
    /// one-sided fringe down every silhouette.
    @ViewBuilder
    private static func spriteLayer(shape: Shape,
                                    _ draw: (inout PixelBuffer) -> Void) -> some View {
        var buffer = PixelBuffer()
        let _ = draw(&buffer)
        PixelCanvasView(buffer: buffer, seamBleed: 0)
            .frame(width: shape.sprite, height: shape.sprite)
    }

    // MARK: - Preset dispatch

    private static func drawCanvasPreset(_ preset: CanvasPreset?,
                                         in context: inout GraphicsContext,
                                         size: CGSize, t: Double,
                                         amount: Double, cell: CGFloat) {
        switch preset {
        case .party:
            PartyGround.draw(in: &context, size: size, t: t, party: amount, cell: cell)
        case .rays:
            RainbowRays.draw(in: &context, size: size, t: t)
        case .glow:
            // `bloom: false` — the gradient under the rings is poison for a
            // GIF's global palette, and the file says so itself.
            CelebrationGlow.draw(in: &context, size: size, t: t, bloom: false)
        case .forest:
            SizzleRenderer.ForestBackdrop.draw(in: &context, size: size, t: t)
        case .waiting:
            // Its input is an envelope rather than a clock, so the slider sets
            // the depth and `t` does the breathing — one breath every two
            // seconds, which is four beats.
            WaitingLight.draw(in: &context, size: size,
                              breath: amount * (0.5 + 0.5 * sin(.pi * t)))
        case nil:
            break
        }
    }

    private static func drawSpritePreset(_ preset: SpritePreset?,
                                         into b: inout PixelBuffer,
                                         t: Double, amount: Double,
                                         loopSeconds: Double) {
        switch preset {
        case .snow:         HolidayAmbience.drawSnow(&b, phase: t)
        case .hearts:       HolidayAmbience.drawHearts(&b, phase: t)
        case .leaves:       HolidayAmbience.drawLeaves(&b, phase: t)
        case .pumpkins:     HolidayAmbience.drawFloorPumpkins(&b)
        case .easterGround: HolidayAmbience.drawEasterGround(&b)
        case .fireworks:    HolidayAmbience.drawFireworks(&b, progress: t - floor(t),
                                                          cycle: Int(floor(t)))
        case .ledge:        CrabRig.drawLedge(&b, travel: t - floor(t))
        case .bushes:       CrabRig.drawBushes(&b, travel: t - floor(t))
        case .groundRush:   CrabRig.drawGroundRush(&b, travel: t - floor(t), visibility: amount)
        case .comboTrail:   CrabRig.drawComboTrail(&b, dy: 0, combo: amount, phase: t)
        case .boardFire:    CrabRig.drawBoardFire(&b, dx: 0, dy: 0, phase: t)
        case .swell:
            // One wave per loop, not per second — the surf set's progress is
            // the whole ride, and cycling it at 1Hz is a flicker, not a swell.
            SurfSet.drawSwell(&b, progress: loopSeconds > 0 ? t / loopSeconds : 0)
        case nil:           break
        }
    }
}
