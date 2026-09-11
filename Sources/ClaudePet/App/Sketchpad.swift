import AppKit
import SwiftUI

/// ✏️ **The sketchpad: a place with no ceremony.**
///
/// Everything else that renders in this repo is a product surface — it gets a
/// shot list, a beat sidecar, kill-tested pins and a Knob entry, and it should.
/// This gets none of that, on purpose. It exists so *"what happens if the rings
/// go backwards"* costs twenty seconds instead of an evening. Anything that
/// turns out good graduates into the app properly, with the full ceremony,
/// deliberately.
///
/// **It never ships.** There is no menu item; the only way in is running the
/// binary with `--sketchpad`, exactly like every `--render-*` mode, so nobody
/// who installs the DMG can reach it. Output lands in `build/sketches`, which
/// `.gitignore` already covers whole.
@MainActor
enum Sketchpad {

    private static var controller: SketchWindowController?
    private static var model: SketchModel?

    // MARK: - Where things land

    /// Relative to wherever you ran the binary from — which in practice is the
    /// repo root, and `build/` is gitignored there. Never `docs/media`.
    static var directory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/sketches", isDirectory: true)
    }

    private static var stackURL: URL { directory.appendingPathComponent("stack.json") }

    /// 🔎 The stack survives a rebuild, and it has to. Sketches are authored in
    /// Swift, so trying an idea means relaunching the app — and a tool that
    /// forgot your setup every four seconds would be worse than no tool.
    private static func loadStack() -> SketchScene.Stack {
        guard let data = try? Data(contentsOf: stackURL),
              let stack = try? JSONDecoder().decode(SketchScene.Stack.self, from: data)
        else { return .starter }
        return stack
    }

    private static func saveStack(_ stack: SketchScene.Stack) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(stack) else { return }
        try? data.write(to: stackURL)
    }

    // MARK: - Opening

    static func open() {
        if let controller {
            controller.show()
            return
        }
        let model = SketchModel(stack: loadStack())
        Self.model = model

        let view = SketchView(
            model: model,
            onExportGIF: { exportGIF() },
            onExportVideo: { exportVideo() })

        let controller = SketchWindowController(
            rootView: view,
            title: "Claw'd · Sketchpad",
            size: CGSize(width: 840, height: 620),
            onClose: {
                if let stack = Self.model?.stack { saveStack(stack) }
                Self.controller = nil
                Self.model = nil
            })
        Self.controller = controller
        controller.show()
    }

    // MARK: - Export

    /// GIF at 20fps. The stride and the stored delay are the same number by
    /// construction — a GIF keeps its delay in whole centiseconds, so passing
    /// one rate and sampling at another is the classic way to ship a clip that
    /// plays at a speed nobody chose.
    static func exportGIF() {
        guard let model else { return }
        saveStack(model.stack)
        model.status = writeGIF(model.stack, to: directory).map(describe) ?? "GIF export failed"
    }

    /// The GIF path, free of the window — so a test can exercise the whole
    /// pipeline without a button, which is where a silent break would live.
    @discardableResult
    static func writeGIF(_ stack: SketchScene.Stack, to directory: URL) -> URL? {
        var images: [CGImage] = []
        images.reserveCapacity(stack.frameCount)
        for index in 0..<stack.frameCount {
            // Strides by the SAME number handed to `encode` below. They are one
            // constant on purpose; two would be a clip that plays off-rate.
            let t = Double(index) * SketchScene.frameDelay
            guard let image = SpriteImage.cgImage(of: SketchScene.scene(stack, t: t),
                                                  scale: 1, isOpaque: true) else { return nil }
            images.append(image)
        }
        let url = prepared("sketch-\(stack.shape.name).gif", in: directory)
        return GifRenderer.encode(images, to: url,
                                  frameDelay: SketchScene.frameDelay) ? url : nil
    }

    /// MP4 at 30fps, **streamed** — one frame in flight. `ReelRenderer` records
    /// what the alternative costs: buffering a cut's frames peaked at 2.37 GB.
    static func exportVideo() {
        guard let model else { return }
        saveStack(model.stack)
        model.status = writeVideo(model.stack, to: directory).map(describe) ?? "MP4 export failed"
    }

    /// The MP4 path, free of the window.
    @discardableResult
    static func writeVideo(_ stack: SketchScene.Stack, to directory: URL) -> URL? {
        let url = prepared("sketch-\(stack.shape.name).mp4", in: directory)
        let ok = VideoWriter.write(to: url, fps: SketchScene.videoFps,
                                   frameCount: stack.videoFrameCount) { index in
            let t = Double(index) / Double(SketchScene.videoFps)
            return SpriteImage.cgImage(of: SketchScene.scene(stack, t: t),
                                       scale: 1, isOpaque: true)
        }
        return ok ? url : nil
    }

    private static func prepared(_ name: String, in directory: URL) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    private static func describe(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return "\(url.lastPathComponent) · \(size / 1024) KB\nbuild/sketches/"
    }
}

/// The sketchpad's own application delegate.
///
/// 🔎 Deliberately **not** a branch inside `AppDelegate`. That one stands up the
/// activity coordinator, the file watchers and the hook surface — the whole
/// apparatus that reads the operator's live Claude Code session data. A drawing
/// tool has no business anywhere near any of it, and the cheapest way to
/// guarantee that is to never construct it.
///
/// It also runs `.regular` rather than `.accessory`, so the window can take
/// keyboard focus and gets a real menu bar.
@MainActor
final class SketchpadDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.installMainMenu()
        Sketchpad.open()
    }

    /// 🔎 A menu, purely so the text field can be pasted into.
    ///
    /// This is not cosmetic and it is not obvious. `NSTextField` does not
    /// implement Cmd-V itself — cut, copy, paste and select-all reach the first
    /// responder as MENU KEY EQUIVALENTS. A binary launched without a main menu
    /// has none, so the shortcuts do nothing at all, silently, and a bubble you
    /// cannot paste a line into is a bubble you will not use. The rest of the
    /// app never needed one because it runs as an accessory with no text entry
    /// anywhere.
    ///
    /// String selectors rather than `#selector`, because these live on the
    /// responder chain rather than on any type this file can name.
    private static func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sketchpad",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
        ] {
            edit.addItem(withTitle: title, action: Selector((selector)), keyEquivalent: key)
        }
        edit.addItem(.separator())
        for (title, selector, key) in [
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
        ] {
            edit.addItem(withTitle: title, action: Selector((selector)), keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    /// Closing the window ends the session — it is a tool, not a daemon.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
