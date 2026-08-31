import SwiftUI

/// Single-costume sample clips, for choosing what the marketing uses next.
///
/// One GIF per costume: the character on the sky, his own effect firing ON
/// CAMERA, a real line in the bubble, and one flourish. Invoked with
/// `ClaudePet --render-samples <dir>`; the output is review material, not a
/// committed asset — which is why it has no entry in the README's media set.
///
/// The costume effects ride dice on the wall of `t` (`CrabCostume`'s
/// `effectWindow`, 97-family salts), so each sample's clock does not start at
/// zero: `t0` is chosen so the effect's first reliable window lands about two
/// seconds in. Those instants were solved from the same splitmix64 the app
/// rolls — the ninja's shuriken, for one, first flies at t=90, and a clip
/// opening at zero would show a costume and no effect.
@MainActor
enum CostumeSampler {

    static let frameDelay = 0.1

    /// A sample's length is its LINE's: long enough for one whole marquee
    /// cycle plus a beat of gap, rounded to a whole frame, and handed to the
    /// bubble as `loopSeconds` so the wrap closes seamlessly. A plain line
    /// needs no cycle and gets the six-second floor. This is the operator's
    /// "size clips to the scroll" call, applied per clip.
    static func seconds(for line: String) -> Double {
        guard ActivityCoordinator.bubbleStyle(for: line) == .marquee else { return 6.0 }
        let travel = Double(MarqueeText.measure(line) / MarqueeText.speed)
        return max(6.0, ((travel + 1.2) * 10).rounded(.up) / 10)
    }

    /// costume · where its clock opens · flourish and its onset within the
    /// clip · what he says. Every line is a REAL one — facts from the pools,
    /// shouts from the skate deck — because a sample that says marketing copy
    /// is a sample of nothing.
    static let cast: [(costume: Costume, t0: Double,
                       flourish: CrabAnimator.Flourish, onset: Double,
                       line: String)] = [
        (.ninja,        88.0, .wave,       3.4, "Red-teaming a model means trying hard to make it misbehave 😈"),
        (.gundam,       10.0, .wiggle,     3.6, "Anthropic's AI Safety Levels are modeled on biosafety levels"),
        (.sonic,         3.0, .scuttle,    3.4, "Claude Code launched as a coding agent in your terminal"),
        (.frankenstein, 33.0, .wiggle,     3.6, "Constitutional AI trains a model against written principles"),
        (.retroBlack,   31.0, .stretch,    3.6, "Claude is reachable by API, not only a chat window"),
        (.matrix,        4.0, .lookAround, 3.2, "A token can be a whole word or just a piece of one"),
        (.white,         4.0, .jump,       3.4, "Anthropic was founded in 2021 🧡"),
        (.tiger,         4.0, .stretch,    3.2, "Temperature controls how much a model's output varies"),
        (.arcade,        4.0, .kickflip,   1.6, "Do a Kickflip 🛹!"),
    ]

    static func render(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(root.path): \(error)\n".utf8))
            return false
        }
        for member in cast {
            let frames = Int((seconds(for: member.line) / frameDelay).rounded())
            var images: [CGImage] = []
            for frame in 0..<frames {
                let local = Double(frame) * frameDelay
                guard let image = SpriteImage.cgImage(of: scene(member, at: local),
                                                      scale: 2, isOpaque: true)
                else { return false }
                images.append(image)
            }
            let name = "sample-\(member.costume.rawValue).gif"
            guard GifRenderer.encode(images, to: root.appendingPathComponent(name),
                                     frameDelay: frameDelay) else { return false }
        }
        print("wrote \(cast.count) samples to \(root.path)")
        return true
    }

    // MARK: - The solos

    /// The trick, alone — the drip-feed inventory. `--render-solos <dir>`.
    ///
    /// **On the board the whole way through.** The first cut snapped him back
    /// to a bare-footed idle at the landing — the board vanished under him,
    /// which was the operator's "jarred down". Measured fix: the kickflip's
    /// t=0 stance and its landing frame differ by only 260 pixels (same feet,
    /// same board), so the clip holds `flourishPose(.kickflip, 0)` on BOTH
    /// sides of the flip. Frame 0 and frame N are literally the same render —
    /// a zero-pixel seam — and the landing "cut" back to stance is a 260px
    /// micro-step smaller than any ordinary frame of the flip itself.
    ///
    /// One GIF per costume x shout, because the operator is drip-feeding
    /// socials with variants. Clip length is the SHOUT's: plain lines get the
    /// short clip, a scrolling line gets long enough to finish one full read
    /// before it eases out.
    static let soloCast: [Costume] = [.none, .ninja, .retroBlack, .gundam]

    /// Both board tricks. The stance-hold loop works for either because both
    /// begin and end within ~260px of the same on-board stance — measured on
    /// the committed flourish GIFs before the axis was added, not assumed.
    /// The varial is the kickflip plus the shove-it's 180° board rotation;
    /// the rig has no plain pop shove-it, by the operator's own veto.
    static let soloTricks: [CrabAnimator.Flourish] = [.kickflip, .varialFlip]

    /// The deck lines he really shouts, plus the operator's campaign lines.
    ///
    /// Campaign lines live HERE and not in `vocab.swift` deliberately: the
    /// live skate bubble shows for 3.4 seconds and `skateLinesFitTheirWindow`
    /// holds every deck line to that. "Johnny Tsunami once said…" needs 11.9
    /// seconds of scroll — a marketing line, authored by the operator for
    /// clips that can afford it, and it would break the live invariant.
    static let soloShouts: [(slug: String, line: String)] = [
        ("tony",     "Tony Clawd 900 🦅"),
        ("kowbunga", "Kowbunga 🤙!"),
        ("kickflip", "Do a Kickflip 🛹!"),
        ("meat",     "See you at the Hall of Meat 🍖!"),
        ("tsunami",  "Johnny Tsunami once said — Go Big or Go Home 🤙"),
    ]

    static let soloLead = 0.8
    /// Both tricks share a duration today; asking the flourish keeps this true
    /// if they ever stop sharing one.
    static func soloLanding(for trick: CrabAnimator.Flourish) -> Double {
        soloLead + trick.duration
    }

    static func soloSeconds(for line: String, trick: CrabAnimator.Flourish) -> Double {
        let landing = soloLanding(for: trick)
        guard ActivityCoordinator.bubbleStyle(for: line) == .marquee else {
            return ((landing + 2.6) * 10).rounded() / 10
        }
        let travel = Double(MarqueeText.measure(line) / MarqueeText.speed)
        return ((landing + travel + 1.6) * 10).rounded(.up) / 10
    }

    static func renderSolos(to directory: String) -> Bool {
        let root = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("could not create \(root.path): \(error)\n".utf8))
            return false
        }
        for costume in soloCast {
            for trick in soloTricks {
                for shout in soloShouts {
                    let seconds = soloSeconds(for: shout.line, trick: trick)
                    let frames = Int((seconds / frameDelay).rounded())
                    var images: [CGImage] = []
                    for frame in 0..<frames {
                        guard let image = SpriteImage.cgImage(
                            of: soloScene(costume, trick: trick, shout: shout.line,
                                          seconds: seconds,
                                          at: Double(frame) * frameDelay),
                            scale: 2, isOpaque: true)
                        else { return false }
                        images.append(image)
                    }
                    // The kickflip keeps its unsuffixed names, so every file
                    // the operator has already pulled stays where it was.
                    let name = trick == .kickflip
                        ? "solo-\(costume.rawValue)-\(shout.slug).gif"
                        : "solo-\(costume.rawValue)-\(shout.slug)-varial.gif"
                    guard GifRenderer.encode(images, to: root.appendingPathComponent(name),
                                             frameDelay: frameDelay) else { return false }
                }
            }
        }
        print("wrote \(soloCast.count * soloTricks.count * soloShouts.count) solos to \(root.path)")
        return true
    }

    @ViewBuilder
    private static func soloScene(_ costume: Costume, trick: CrabAnimator.Flourish,
                                  shout: String, seconds: Double,
                                  at local: Double) -> some View {
        let landing = soloLanding(for: trick)
        let inFlip = local >= soloLead && local < landing
        let pose = inFlip
            ? CrabAnimator.flourishPose(trick, at: local - soloLead)
            : CrabAnimator.flourishPose(trick, at: 0)   // on the board, both ends
        // Shout rises just after touchdown, gone before the final frame.
        let opacity = Ease.amount(now: local, since: landing + 0.1,
                                  endedAt: seconds - 0.9)

        ZStack {
            MarketingBackdrop.warmWhite
            VStack(spacing: 0) {
                ThoughtBubble(text: shout, tool: nil, mood: .idle,
                              style: ActivityCoordinator.bubbleStyle(for: shout),
                              frozenTime: max(0, local - landing - 0.1),
                              fillOverride: Palette.slate,
                              textOverride: .white)
                    .opacity(opacity)
                PixelCanvasView(
                    buffer: CrabRig.render(pose, costume: costume),
                    inkOverrides: CostumeStyle.blendedOverrides(from: costume, to: costume, u: 1),
                    seamBleed: 0)
                    .frame(width: 128, height: 128)
            }
            .offset(y: 8)
        }
        .frame(width: 280, height: 200)
    }

    @ViewBuilder
    private static func scene(_ member: (costume: Costume, t0: Double,
                                         flourish: CrabAnimator.Flourish, onset: Double,
                                         line: String),
                              at local: Double) -> some View {
        // The effect clock runs from t0; the flourish is spliced at its onset
        // the way the wardrobe strip does it, over the STILL idle pose so the
        // loop point does not catch a breath mid-cycle.
        let t = member.t0 + local
        let inFlourish = local >= member.onset && local < member.onset + member.flourish.duration
        let pose = inFlourish
            ? CrabAnimator.flourishPose(member.flourish, at: local - member.onset)
            : CrabAnimator.pose(mood: .idle, t: 0, flourishes: false)
        // The costume effects read `propPhase` as their clock; splicing the
        // flourish must not reset it or the sampled window walks off camera.
        var staged = pose
        let _ = { staged.propPhase = t }()

        ZStack {
            Backdrop(style: .sky)
            VStack(spacing: 0) {
                ThoughtBubble(text: member.line, tool: nil, mood: .idle,
                              style: ActivityCoordinator.bubbleStyle(for: member.line),
                              frozenTime: local,
                              loopSeconds: seconds(for: member.line))
                PixelCanvasView(
                    buffer: CrabRig.render(staged, costume: member.costume),
                    inkOverrides: CostumeStyle.blendedOverrides(from: member.costume,
                                                               to: member.costume, u: 1),
                    seamBleed: 0)
                    .frame(width: 128, height: 128)
            }
            .offset(y: 8)
        }
        .frame(width: 300, height: 200)
        .background(Palette.Ocean.abyss)
    }
}
