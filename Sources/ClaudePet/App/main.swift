import AppKit

// Entry point. Two modes: the pet itself, and an offline sprite-sheet render
// used to review the art without a display session.
let arguments = CommandLine.arguments

// Argument hygiene, before any flag is honoured. Two silent failure modes the
// battery caught:
//  - a render flag with NO value fell through every `index + 1 < count` guard
//    and launched the GUI — a script typo started an invisible pet reading the
//    live ~/.claude and blocking forever;
//  - an EMPTY value resolved to the current directory via
//    `URL(fileURLWithPath: "")`, so `--render-plates ""` dumped 49 MB wherever
//    the shell happened to be standing, and reported success.
// A tool that cannot do what was asked says so and exits 2.
let renderFlags = arguments.filter { $0.hasPrefix("--render-") }
for flag in renderFlags {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("\(flag) needs an output path\n".utf8))
        exit(2)
    }
    let value = arguments[index + 1]
    guard !value.isEmpty, !value.hasPrefix("--") else {
        FileHandle.standardError.write(Data("\(flag) needs an output path, got \(value.isEmpty ? "an empty string" : value)\n".utf8))
        exit(2)
    }
}

if let index = arguments.firstIndex(of: "--render-comps"), index + 1 < arguments.count {
    // The visual-riff tiles — art direction by comps, never committed.
    let ok = MainActor.assumeIsolated { CompBoard.render(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-solos"), index + 1 < arguments.count {
    // Four solo kickflips, one per named costume — marketing review material.
    let ok = MainActor.assumeIsolated { CostumeSampler.renderSolos(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-samples"), index + 1 < arguments.count {
    // Per-costume sample clips for marketing review — not committed media.
    let ok = MainActor.assumeIsolated { CostumeSampler.render(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-sheet"), index + 1 < arguments.count {
    let path = arguments[index + 1]
    let ok = MainActor.assumeIsolated { SpriteSheetRenderer.renderSheet(to: path) }
    print(ok ? "wrote \(path)" : "failed")
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-icon"), index + 1 < arguments.count {
    let ok = MainActor.assumeIsolated { IconRenderer.render(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-gif"), index + 1 < arguments.count {
    let ok = MainActor.assumeIsolated { GifRenderer.render(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-marketing"), index + 1 < arguments.count {
    let ok = MainActor.assumeIsolated { GifRenderer.renderMarketing(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-reel"), index + 1 < arguments.count {
    let ok = MainActor.assumeIsolated { ReelRenderer.render(to: arguments[index + 1]) }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-social"), index + 1 < arguments.count {
    // Vertical 9:16 MP4 for a social reel. Separate from `--render-reel` so a
    // multi-MB video can never land in `docs/media` by a typo.
    let root = URL(fileURLWithPath: arguments[index + 1])
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let ok = MainActor.assumeIsolated {
        ReelRenderer.renderVertical(to: root.appendingPathComponent("clawd-reel-9x16.mp4"))
            && ReelRenderer.renderLandscape(to: root.appendingPathComponent("clawd-reel-16x9.mp4"))
            && ReelRenderer.renderPoster(to: root.appendingPathComponent("clawd-reel-cover.png"))
            && ReelRenderer.renderPlates(to: root)
    }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-sizzle"), index + 1 < arguments.count {
    // The trailer: three cuts from one master script. Like `--render-social`,
    // deliberately separate from `--render-reel` so a multi-MB video can
    // never land in `docs/media` by a typo — the operator copies the
    // eyeballed README GIF over by hand.
    let ok = MainActor.assumeIsolated {
        SizzleRenderer.render(to: arguments[index + 1])
    }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-plates"), index + 1 < arguments.count {
    // Green-screen plates: lossless PNG sequences (the keying source) plus
    // H.264 previews (sync eyeballing only). Same doctrine as the other
    // heavy renders — output goes only where pointed, never docs/media.
    let ok = MainActor.assumeIsolated {
        SizzleRenderer.renderPlates(to: arguments[index + 1])
    }
    exit(ok ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--probe") {
    // `--probe [seconds]`. The default is long enough to attach the feeds and
    // fold what is already on disk, but shorter than any decay horizon — so
    // watching a session settle to idle needs an explicit, longer window.
    // Parsed through the clamp: `Double("nan")` and `Double("inf")` succeed,
    // so a bare `?? 3` never fires for the arguments most likely to be
    // nonsense — nan probed nothing and inf probed forever.
    let seconds = arguments.count > index + 1 ? Probe.clampedDuration(arguments[index + 1]) ?? 3 : 3
    MainActor.assumeIsolated { Probe.run(seconds: seconds) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Agent app: no dock icon, no menu bar takeover. Mirrors LSUIElement for the
// case where the binary is run outside the .app bundle.
app.setActivationPolicy(.accessory)
app.run()
