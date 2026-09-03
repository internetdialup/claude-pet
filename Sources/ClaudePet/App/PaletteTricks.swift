import SwiftUI

/// The palette-tricks sets: Claw'd at the centre of the super-graphics
/// grounds, 4:5 portrait, doing one trick per clip — the operator's
/// marketing-feed spec. `ClaudePet --render-palette-tricks <dir>` writes two
/// sets, review material, never committed:
///
/// - `costumes/`: each ground paired with ONE costume, picked for contrast
///   (sonic pops on lemon, the gundam on violet, tiger on lilac, ninja on
///   mint, the skater's terracotta on azure), across all six tricks.
/// - `tricks/`: BASIC Claw'd, every trick on every ground — the plain set.
/// - `vfx/`: no board at all — his own effects looping on each ground,
///   through the same envelopes the secret-menu previews use.
/// - `states/`: the message states — each mood with a REAL line from its own
///   pool in the bubble, one ground each.
/// - `bubbles/`: basic Claw'd, a trick, and a REAL line off the skate shout
///   decks in his speech bubble — a sample that says marketing copy is a
///   sample of nothing, so every line here is one he actually says. The
///   golden-board line rides an actually-golden board: the jackpot is spent,
///   not faked.
///
/// Each clip is stance → trick → stance, the bookends repeating one fixed
/// stance instant so the loop seam is zero-pixel by construction.
@MainActor
enum PaletteTricks {

    static let frameDelay = 0.1
    /// 4:5 portrait, the operator's ratio; the sprite rides a hair under
    /// centre the way their sample sheet places him.
    static let canvas = CGSize(width: 640, height: 800)
    static let spriteSide: CGFloat = 320

    static let grounds: [(name: String, color: Color)] = [
        ("cream", MarketingPalette.cream),
        ("lemon", MarketingPalette.lemon),
        ("coral", MarketingPalette.coral),
        ("pink", MarketingPalette.pink),
        ("grape", MarketingPalette.grape),
        ("gold", MarketingPalette.gold),
        ("cobalt", MarketingPalette.cobalt),
        ("sky", MarketingPalette.sky),
    ]

    /// Ground → costume, by contrast — one wardrobe per ground now that
    /// there are eight of each.
    static let wardrobePairs: [(ground: (name: String, color: Color), costume: Costume)] = [
        (grounds[0], .retroBlack), (grounds[1], .sonic), (grounds[2], .gundam),
        (grounds[3], .ninja), (grounds[4], .skater), (grounds[5], .arcade),
        (grounds[6], .tiger), (grounds[7], .frankenstein),
    ]

    static let tricks: [CrabAnimator.Flourish] =
        [.ollie, .kickflip, .varialFlip, .manual, .shoveIt, .nollie, .cruise]

    /// Trick → (line, golden). All real lines; the reserved gold line pays
    /// for itself with a genuinely golden deck.
    static let bubbleCast: [(trick: CrabAnimator.Flourish, line: String, golden: Bool)] = [
        (.ollie, "Tony Clawd 900 🦅", false),
        (.kickflip, "Do a Kickflip 🛹!", false),
        (.varialFlip, "Kowbunga 🤙!", false),
        (.manual, "Sponsor me 🛹", false),
        (.shoveIt, "Kowbunga 🤙!", false),
        (.nollie, "Nollie! Nose first 🛹", false),
        (.cruise, "GOLD BOARD. No notes 🏆", true),
    ]

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        let costumesDir = root.appendingPathComponent("costumes")
        let bubblesDir = root.appendingPathComponent("bubbles")
        do {
            try FileManager.default.createDirectory(at: costumesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bubblesDir, withIntermediateDirectories: true)
        } catch { return false }

        let tricksDir = root.appendingPathComponent("tricks")
        let vfxDir = root.appendingPathComponent("vfx")
        let statesDir = root.appendingPathComponent("states")
        do {
            try FileManager.default.createDirectory(at: tricksDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: vfxDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: statesDir, withIntermediateDirectories: true)
        } catch { return false }

        // The plain set: basic Claw'd, every trick on every ground — and the
        // steezed ollie beside the clean one, since on the desk it is a die.
        for ground in grounds {
            for trick in tricks {
                let name = "clawd-\(trick.rawValue)-\(ground.name).gif"
                guard clip(trick: trick, ground: ground.color, costume: .none,
                           line: nil, golden: false,
                           to: tricksDir.appendingPathComponent(name)) else { return false }
            }
            guard clip(trick: .ollie, ground: ground.color, costume: .none,
                       line: nil, golden: false, steeze: true,
                       to: tricksDir.appendingPathComponent("clawd-ollie-steeze-\(ground.name).gif"))
            else { return false }
        }

        // The VFX set: no board — his own effects on the preview loops.
        let effects: [(CrabAnimator.PreviewEffect, Double, String)] = [
            (.glint, 8.0, "glint"),          // two 4s passes
            (.ting, 3.0, "wink-ting"),       // two 1.5s winks
            (.idleHeart, 8.6, "idle-heart"), // two 4.3s flights
        ]
        for (index, ground) in grounds.enumerated() {
            for (effect, seconds, label) in effects {
                let name = "clawd-\(label)-\(ground.name).gif"
                guard vfxClip(effect: effect, seconds: seconds, ground: ground.color,
                              to: vfxDir.appendingPathComponent(name)) else { return false }
            }
            // …plus the party, which is its own kind of weather.
            if index < 1 {
                for g in grounds {
                    guard partyClip(ground: g.color,
                                    to: vfxDir.appendingPathComponent("clawd-party-\(g.name).gif"))
                    else { return false }
                }
            }
        }

        // The message states: each mood speaking a real line from its pool.
        let stateCast: [(PetMood, ShoutoutOccasion)] = [
            (.idle, .idle), (.thinking, .thinking), (.working, .working),
            (.cooking, .cooking), (.nudging, .planReady), (.done, .finished),
            (.needsAttention, .needsYou), (.sleeping, .sleeping),
        ]
        for (index, member) in stateCast.enumerated() {
            let ground = grounds[index % grounds.count]
            let line = Vocab.lines(for: member.1).first ?? ""
            let name = "clawd-state-\(member.0.rawValue)-\(ground.name).gif"
            guard stateClip(mood: member.0, line: line, ground: ground.color,
                            to: statesDir.appendingPathComponent(name)) else { return false }
        }

        for pair in wardrobePairs {
            for trick in tricks {
                let name = "clawd-\(trick.rawValue)-\(pair.ground.name)-\(pair.costume.rawValue).gif"
                guard clip(trick: trick, ground: pair.ground.color, costume: pair.costume,
                           line: nil, golden: false,
                           to: costumesDir.appendingPathComponent(name)) else { return false }
            }
        }
        for (index, member) in bubbleCast.enumerated() {
            let ground = grounds[index % grounds.count]
            let name = "clawd-\(member.trick.rawValue)-fact-\(ground.name).gif"
            guard clip(trick: member.trick, ground: ground.color, costume: .none,
                       line: member.line, golden: member.golden,
                       to: bubblesDir.appendingPathComponent(name)) else { return false }
        }

        // 🧢 The hats: every trick twice, once in the beanie and once in a
        // cap, cap colours rotating through the live wardrobe's own list.
        // Headwear is a live-only dice on the desk; here it is simply worn.
        let hatsDir = root.appendingPathComponent("hats")
        let specialDir = root.appendingPathComponent("special")
        do {
            try FileManager.default.createDirectory(at: hatsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: specialDir, withIntermediateDirectories: true)
        } catch { return false }
        for (index, trick) in tricks.enumerated() {
            let beanieGround = grounds[index % grounds.count]
            let capGround = grounds[(index + 4) % grounds.count]
            let capInk = CrabAnimator.capColours[index % CrabAnimator.capColours.count]
            guard clip(trick: trick, ground: beanieGround.color, costume: .none,
                       line: nil, golden: false, headwear: .blackBeanie,
                       to: hatsDir.appendingPathComponent(
                           "clawd-\(trick.rawValue)-beanie-\(beanieGround.name).gif")),
                  clip(trick: trick, ground: capGround.color, costume: .none,
                       line: nil, golden: false, headwear: .cap(capInk),
                       to: hatsDir.appendingPathComponent(
                           "clawd-\(trick.rawValue)-cap-\(capGround.name).gif"))
            else { return false }
        }

        // 💨 The Green Hill run — Sonic-Claw'd sprinting across the
        // checkered tiles, rings overhead. One clip; it owns its ground.
        guard sonicRunClip(to: specialDir.appendingPathComponent("clawd-sonic-run.gif"))
        else { return false }

        print("wrote tricks/costumes/vfx/states/bubbles/hats/special drip sets to \(root.path)")
        return true
    }

    // MARK: - The triptych

    /// 1080 square, because the ask is CAROUSELS and a carousel slide is
    /// square. The shape is the one the operator's post landed in by
    /// accident: a full-height hero at two thirds of the width, two
    /// half-height sidekicks stacked beside it. Rendering it ourselves makes
    /// it the same every time instead of whatever the platform's grid feels
    /// like doing with three separate uploads.
    static let triptychSide: CGFloat = 1080
    static let triptychGutter: CGFloat = 6

    /// Three grounds, three tricks, one block. Curated rather than
    /// enumerated — a carousel is chosen, and every combination of eight
    /// grounds and seven tricks is a spreadsheet, not a feed.
    static let triptychSets: [[(ground: Int, trick: CrabAnimator.Flourish, costume: Costume)]] = [
        [(6, .kickflip, .none), (2, .ollie, .none), (0, .cruise, .none)],
        [(1, .ollie, .none), (4, .varialFlip, .none), (7, .manual, .none)],
        [(2, .varialFlip, .none), (5, .nollie, .none), (3, .shoveIt, .none)],
        [(7, .nollie, .none), (0, .kickflip, .none), (6, .ollie, .none)],
        [(4, .manual, .none), (1, .cruise, .none), (2, .kickflip, .none)],
        [(0, .shoveIt, .none), (6, .nollie, .none), (5, .varialFlip, .none)],
        [(3, .cruise, .none), (7, .ollie, .none), (1, .nollie, .none)],
        [(5, .kickflip, .skater), (3, .ollie, .sonic), (4, .varialFlip, .gundam)],
        [(2, .nollie, .ninja), (0, .manual, .retroBlack), (7, .kickflip, .tiger)],
        [(6, .varialFlip, .none), (4, .shoveIt, .none), (0, .ollie, .none)],
    ]

    static func renderTriptychs(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory).appendingPathComponent("triptych")
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        catch { return false }
        for (index, set) in triptychSets.enumerated() {
            let name = "clawd-triptych-\(String(format: "%02d", index + 1)).gif"
            guard triptych(set, to: root.appendingPathComponent(name)) else { return false }
        }
        print("wrote \(triptychSets.count) triptychs to \(root.path)")
        return true
    }

    /// Length-matched, not speed-matched: the block runs as long as its
    /// longest trick, and the shorter panels hold their own board at the
    /// head and tail. The bookends already ride, so the padding reads as two
    /// skaters waiting their turn rather than as dead frames — and every
    /// panel starts and ends on the same stance, so the loop closes.
    private static func triptych(_ set: [(ground: Int, trick: CrabAnimator.Flourish, costume: Costume)],
                                 to url: URL) -> Bool {
        let lead = 0.6, settle = 0.9
        let longest = set.map { $0.trick.duration }.max() ?? 0
        let seconds = lead + longest + settle
        let frames = Int((seconds / frameDelay).rounded())

        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            let panels = set.map { panel -> (pose: CrabPose, ground: Color, costume: Costume) in
                var stance = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false)
                stance.prop = restingBoard(for: panel.trick)
                stance.propVisibility = 1
                stance.propPhase = 0
                // Centred in the window, so a short trick waits equally at
                // both ends instead of finishing early and standing about.
                let start = lead + (longest - panel.trick.duration) / 2
                let pose = local < start || local >= start + panel.trick.duration
                    ? stance
                    : CrabAnimator.flourishPose(panel.trick, at: local - start, base: stance)
                return (pose, grounds[panel.ground].color, panel.costume)
            }
            guard let image = SpriteImage.cgImage(of: triptychScene(panels),
                                                  scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    @ViewBuilder
    private static func triptychScene(
        _ panels: [(pose: CrabPose, ground: Color, costume: Costume)]
    ) -> some View {
        // hero = 2 × sidekick in width, so 3 sidekicks plus one gutter span
        // the block; the sidekicks split the height the same way.
        let side = (triptychSide - triptychGutter) / 3
        let heroWidth = side * 2
        let sideHeight = (triptychSide - triptychGutter) / 2
        HStack(spacing: triptychGutter) {
            panel(panels[0], width: heroWidth, height: triptychSide, sprite: 480)
            VStack(spacing: triptychGutter) {
                // Smaller than half the hero on purpose: in the operator's
                // post the sidekicks read as sidekicks, not as the same crab
                // twice. A flat half would have made three equal panes.
                panel(panels[1], width: side, height: sideHeight, sprite: 200)
                panel(panels[2], width: side, height: sideHeight, sprite: 200)
            }
        }
        .frame(width: triptychSide, height: triptychSide)
        .background(Palette.white)
    }

    @ViewBuilder
    private static func panel(_ panel: (pose: CrabPose, ground: Color, costume: Costume),
                              width: CGFloat, height: CGFloat, sprite: CGFloat) -> some View {
        ZStack {
            panel.ground
            PixelCanvasView(buffer: CrabRig.render(panel.pose, costume: panel.costume),
                            inkOverrides: CostumeStyle.blendedOverrides(
                                from: panel.costume, to: panel.costume, u: 1),
                            seamBleed: 0)
                .frame(width: sprite, height: sprite)
                // He occupies the middle rows of his own grid, so a sprite
                // centred in the panel reads as sitting high. The same
                // under-centre nudge the portrait set already makes, kept
                // proportional so both panel sizes land the same.
                .offset(y: sprite * 0.106)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private static func clip(trick: CrabAnimator.Flourish, ground: Color, costume: Costume,
                             line: String?, golden: Bool,
                             headwear: CrabPose.Headwear = .none, steeze: Bool = false,
                             to url: URL) -> Bool {
        let lead = 0.6, settle = 0.9
        let seconds = lead + trick.duration + settle
        let frames = Int((seconds / frameDelay).rounded())
        // The bookends RIDE: him standing on the trick's own board at rest —
        // the operator's note, and the honest one: a board that despawns
        // between tricks reads as a magic trick, not a skate clip.
        var stance = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false)
        stance.prop = restingBoard(for: trick)
        stance.propVisibility = 1
        stance.propPhase = 0
        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            // The trick rides the SAME frozen stance the bookends hold, so
            // the only thing that changes at either seam is the trick.
            var pose = local < lead || local >= lead + trick.duration
                ? stance
                : CrabAnimator.flourishPose(trick, at: local - lead, base: stance, steeze: steeze)
            if golden { pose.goldenBoard = true }
            pose.headwear = headwear
            guard let image = SpriteImage.cgImage(
                of: scene(pose, on: ground, costume: costume, line: line, at: local),
                scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    /// Each trick's own board, flat at rest, for the riding bookends.
    private static func restingBoard(for trick: CrabAnimator.Flourish) -> CrabPose.Prop {
        switch trick {
        case .kickflip: .skateboard
        case .varialFlip: .skateboardVarial
        case .ollie: .skateboardOllie
        case .manual: .skateboardManual
        case .shoveIt: .skateboardShoveIt
        case .nollie: .skateboardNollie
        default: .skateboardRoll
        }
    }

    /// A preview-envelope effect looping on a fixed idle stance — no board.
    private static func vfxClip(effect: CrabAnimator.PreviewEffect, seconds: Double,
                                ground: Color, to url: URL) -> Bool {
        let frames = Int((seconds / frameDelay).rounded())
        let stance = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false)
        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            var pose = stance
            CrabAnimator.applyPreview(
                CrabAnimator.PreviewFrame(effect: effect, t: local), to: &pose)
            guard let image = SpriteImage.cgImage(
                of: scene(pose, on: ground, costume: .none, line: nil, at: local),
                scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    /// Three seconds of confetti on a grinning stance.
    private static func partyClip(ground: Color, to url: URL) -> Bool {
        let frames = Int((3.0 / frameDelay).rounded())
        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            var pose = CrabAnimator.pose(mood: .idle, t: 0.4, flourishes: false)
            pose.mouth = .open
            pose.confettiElapsed = local
            guard let image = SpriteImage.cgImage(
                of: scene(pose, on: ground, costume: .none, line: nil, at: local),
                scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    /// A mood loop with its real line in the bubble. Duration leans on each
    /// mood's own dominant oscillator so the wrap lands near a whole cycle.
    private static func stateClip(mood: PetMood, line: String,
                                  ground: Color, to url: URL) -> Bool {
        let seconds = mood == .sleeping ? 5.0 : 6.0
        let frames = Int((seconds / frameDelay).rounded())
        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            let pose = CrabAnimator.pose(mood: mood, t: local, flourishes: false)
            guard let image = SpriteImage.cgImage(
                of: scene(pose, on: ground, costume: .none, line: line, at: local),
                scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    // MARK: The Green Hill run

    /// Sonic's two things, per the operator: gold rings and the checkered
    /// ground. Claw'd in the sonic fit sprints right on a fixed camera — the
    /// world scrolls and he does not, the cruise's own trick — with the dash
    /// streaks riding one full window per loop and ring flights overhead.
    private static let runSeconds = 3.2
    private static let runGroundHeight: CGFloat = 176
    /// 3.2 s × 100 px/s = 320 px = four 80 px checker periods, so the loop
    /// closes on the ground as well as on him.
    private static let runScrollSpeed: CGFloat = 100

    private static func sonicRunClip(to url: URL) -> Bool {
        let frames = Int((runSeconds / frameDelay).rounded())
        let stance = CrabAnimator.pose(mood: .idle, t: 0.9, flourishes: false)
        var images: [CGImage] = []
        for frame in 0..<frames {
            let local = Double(frame) * frameDelay
            var pose = stance
            pose.legPhase = local * 12
            pose.legAmplitude = 1.4
            pose.gazeX = 1
            // The dash's own envelope stretched over the whole clip: born a
            // cell wide, peaking mid-loop, gone by the wrap — the loop seam
            // is invisible by construction. Window solved at salt 23: the
            // cycle-1 fire spans 9.0–10.6.
            pose.propPhase = 9.0 + (local / runSeconds) * 1.6
            pose.ringFlight = (local / 1.6).truncatingRemainder(dividingBy: 1)
            guard let image = SpriteImage.cgImage(of: runScene(pose, at: local),
                                                  scale: 1, isOpaque: true)
            else { return false }
            images.append(image)
        }
        return GifRenderer.encode(images, to: url, frameDelay: frameDelay)
    }

    @ViewBuilder
    private static func runScene(_ pose: CrabPose, at local: Double) -> some View {
        ZStack(alignment: .bottom) {
            MarketingPalette.sky
            GreenHillGround(scroll: CGFloat(local) * runScrollSpeed)
                .frame(width: canvas.width, height: runGroundHeight)
            PixelCanvasView(buffer: CrabRig.render(pose, costume: .sonic),
                            inkOverrides: CostumeStyle.blendedOverrides(
                                from: .sonic, to: .sonic, u: 1),
                            seamBleed: 0)
                .frame(width: spriteSide, height: spriteSide)
                .offset(y: -100)   // sneakers on the grass line
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    @ViewBuilder
    private static func scene(_ pose: CrabPose, on ground: Color, costume: Costume,
                              line: String?, at local: Double) -> some View {
        ZStack {
            ground
            if let line {
                // The sampler's bubble-over-crab stack, doubled up to the
                // portrait canvas — the scale happens before rasterising, so
                // the type stays crisp.
                VStack(spacing: 2) {
                    ThoughtBubble(text: line, tool: nil, mood: .idle,
                                  style: ActivityCoordinator.bubbleStyle(for: line),
                                  frozenTime: local)
                    PixelCanvasView(buffer: CrabRig.render(pose, costume: costume),
                                    inkOverrides: CostumeStyle.blendedOverrides(
                                        from: costume, to: costume, u: 1),
                                    seamBleed: 0)
                        .frame(width: 160, height: 160)
                }
                .scaleEffect(2)
                .offset(y: 12)
            } else {
                PixelCanvasView(buffer: CrabRig.render(pose, costume: costume),
                                inkOverrides: CostumeStyle.blendedOverrides(
                                    from: costume, to: costume, u: 1),
                                seamBleed: 0)
                    .frame(width: spriteSide, height: spriteSide)
                    .offset(y: 34)   // a hair under centre, per the operator's sheet
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

/// Green Hill Zone's ground, quoted: a grass lip over brown-and-tan
/// checkers, scrolling left. Its own palette on purpose — this is a
/// reference to a place, not a marketing colour.
private struct GreenHillGround: View {
    var scroll: CGFloat

    private static let grass = Color(hex: 0x3FD44A)
    private static let grassEdge = Color(hex: 0x1F9E3A)
    private static let tan = Color(hex: 0xD9A066)
    private static let brown = Color(hex: 0x8F5A2B)
    private static let check: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            let grassH: CGFloat = 32
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: grassH)),
                         with: .color(Self.grass))
            context.fill(Path(CGRect(x: 0, y: grassH, width: size.width, height: 8)),
                         with: .color(Self.grassEdge))
            let top = grassH + 8
            let rows = Int(((size.height - top) / Self.check).rounded(.up))
            let shift = scroll.truncatingRemainder(dividingBy: Self.check * 2)
            let columns = Int((size.width / Self.check).rounded(.up)) + 2
            for row in 0..<rows {
                for column in -2..<columns {
                    let x = CGFloat(column) * Self.check - shift
                    let dark = (row + column) % 2 == 0
                    let cell = CGRect(x: x, y: top + CGFloat(row) * Self.check,
                                      width: Self.check, height: Self.check)
                    context.fill(Path(cell), with: .color(dark ? Self.brown : Self.tan))
                }
            }
        }
    }
}
