import AppKit
import SwiftUI

/// The app's first ordinary window.
///
/// Everything else here is chrome-free by design — `PetWindow` is borderless,
/// `.floating`, and refuses to become key so clicks fall through to the desktop.
/// A tool window wants the exact opposite of all three, so it gets its own
/// controller rather than a flag on that one.
///
/// 🔎 `close()` nulls the content view, and that is not tidiness. Ordering a
/// window out leaves its SwiftUI host alive and its `TimelineView` ticking
/// forever — `PetWindowController` carries the same scar, earned when every
/// size change left another animating ghost behind it.
@MainActor
final class SketchWindowController: NSObject, NSWindowDelegate {

    let window: NSWindow
    private var onClose: (() -> Void)?

    init(rootView: some View, title: String, size: CGSize, onClose: (() -> Void)? = nil) {
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ClawdSketchpad")
        self.onClose = onClose
        super.init()
        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        // The app is an accessory when it hosts the pet; a tool window has to
        // ask for focus explicitly or it opens behind whatever you were in.
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.delegate = nil
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.onClose?()
            self.window.contentView = nil
        }
    }
}
