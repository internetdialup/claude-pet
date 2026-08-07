import AppKit

// Entry point. Two modes: the pet itself, and an offline sprite-sheet render
// used to review the art without a display session.
let arguments = CommandLine.arguments

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

if arguments.contains("--probe") {
    MainActor.assumeIsolated { Probe.run(seconds: 3) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Agent app: no dock icon, no menu bar takeover. Mirrors LSUIElement for the
// case where the binary is run outside the .app bundle.
app.setActivationPolicy(.accessory)
app.run()
