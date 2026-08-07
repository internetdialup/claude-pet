import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = PetViewModel()
    private let coordinator = ActivityCoordinator()
    private var windowController: PetWindowController?
    private var menuBar: MenuBarController?
    private var roster: NSPopover?

    /// Overrides the live feed while the operator previews a mood from the menu.
    private var debugMood: PetMood?
    /// `--demo`: run the scripted reel instead of real activity, for recording.
    private var demoTimer: Timer?
    private var demoStartedAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()

        coordinator.onChange = { [weak self] state in
            guard let self, self.debugMood == nil, !self.demoMood else { return }
            self.model.state = state
            self.menuBar?.update(state: state)
        }
        coordinator.onAlert = { [weak self] mood, session in
            self?.handleAlert(mood: mood, session: session)
        }
        coordinator.start()

        menuBar = MenuBarController(
            onToggleVisibility: { [weak self] in self?.toggleVisibility() },
            onPin: { [weak self] id in self?.coordinator.pin(sessionID: id) },
            onPreviewMood: { [weak self] mood in self?.previewMood(mood) },
            onSetPixelSize: { [weak self] size in
                Preferences.shared.pixelSize = size
                self?.buildWindow()
            },
            onQuit: { NSApp.terminate(nil) }
        )

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if CommandLine.arguments.contains("--demo") { startDemo() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    /// Builds (or rebuilds, after a size change) the floating window.
    ///
    /// The window is recreated rather than resized because its size, its
    /// content, and its click-through region all derive from `pixelSize`.
    private func buildWindow() {
        let wasHidden = windowController.map { !$0.isVisible } ?? false
        // Close, not just hide. `hide()` only orders the window out; the old
        // NSWindow and its SwiftUI host stayed alive and kept ticking their
        // TimelineView, so every size change added another animating ghost.
        windowController?.close()

        let pixelSize = Preferences.shared.pixelSize
        let size = PetRootView.windowSize(pixelSize: pixelSize)
        // Only the sprite band accepts clicks; the rest of the window is
        // transparent and click-through. `PetRootView` owns the layout maths so
        // the grab area cannot drift away from the character.
        let interactive = PetRootView.spriteFrame(pixelSize: pixelSize)

        let controller = PetWindowController(
            contentSize: size,
            interactiveRect: interactive,
            rootView: PetRootView(model: model, pixelSize: pixelSize)
        )
        controller.onClick = { [weak self] clicks in
            guard let self else { return }
            // 🎉🪄 Poke him three times and he throws a party.
            if clicks >= 3 {
                self.model.rainbowStartedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabView.rainbowDuration) {
                    self.model.rainbowStartedAt = nil
                }
            }
            // Squash first, roster second — the reaction is feedback for the
            // click, and the roster is what the click is for.
            self.model.clickedAt = Date()
            self.toggleRoster()
            // Clear it once the animation is done so the view drops back to its
            // mood frame rate instead of holding 30fps forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + CrabAnimator.clickDuration + 0.1) {
                self.model.clickedAt = nil
            }
        }
        controller.onHover = { [weak self] hovering in
            self?.model.hoverStartedAt = hovering ? Date() : nil
        }
        windowController = controller
        if !wasHidden { controller.show() }
    }

    /// Replays `DemoMode.script` on a loop, ignoring real sessions.
    private func startDemo() {
        demoStartedAt = Date()
        demoMood = true
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.demoStartedAt else { return }
                let elapsed = Date().timeIntervalSince(started)
                let state = DemoMode.state(at: elapsed, sessions: self.model.state.sessions)
                self.model.state = state
                self.menuBar?.update(state: state)

                // Hold the rainbow for exactly the beat that asks for it. Its
                // start is pinned to the beat's own start so the hue cycle lines
                // up with the beat rather than drifting against it.
                if DemoMode.beat(at: elapsed).rainbow {
                    if self.model.rainbowStartedAt == nil {
                        self.model.rainbowStartedAt = Date()
                    }
                } else {
                    self.model.rainbowStartedAt = nil
                }
            }
        }
    }

    /// Set while the demo reel owns the display, so live updates stay out.
    private var demoMood = false

    // MARK: - Interactions

    private func toggleVisibility() {
        guard let controller = windowController else { return }
        controller.isVisible ? controller.hide() : controller.show()
    }

    private func toggleRoster() {
        guard let window = windowController?.window, let contentView = window.contentView else { return }

        if let existing = roster, existing.isShown {
            existing.performClose(nil)
            roster = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: RosterPanel(
                state: model.state,
                pinnedID: Preferences.shared.pinnedSessionID,
                onPin: { [weak self] id in
                    self?.coordinator.pin(sessionID: id)
                    self?.roster?.performClose(nil)
                }
            )
        )
        popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        roster = popover
    }

    /// Freezes the pet in one mood so the art can be reviewed live. Selecting
    /// "Live" hands control back to the coordinator.
    private func previewMood(_ mood: PetMood?) {
        debugMood = mood
        guard let mood else {
            model.state = coordinator.state
            return
        }

        // Show what the mood actually looks like in use. Labelling the bubble
        // "preview: working" meant the one thing you could not preview was the
        // bubble.
        let bubble: String?
        let style: PetState.BubbleStyle
        switch mood {
        case .idle:
            bubble = VocabShoutouts.line(for: .idle, seed: Int(Date().timeIntervalSince1970))
            style = .plain
        case .thinking:
            bubble = "…"
            style = .dots
        case .working:
            bubble = "Running a build"
            style = .plain
        case .cooking:
            bubble = "🔥 Cooking"
            style = .plain
        case .nudging:
            bubble = VocabShoutouts.line(for: .planReady, seed: Int(Date().timeIntervalSince1970))
            style = .plain
        case .done:
            bubble = ActivityCoordinator.celebration
            style = .plain
        case .needsAttention:
            bubble = VocabShoutouts.line(for: .needsYou, seed: Int(Date().timeIntervalSince1970))
            style = .plain
        case .sleeping:
            bubble = nil
            style = .plain
        }

        model.state = PetState(mood: mood,
                               bubble: bubble,
                               tool: mood == .working ? "Bash" : nil,
                               sessions: model.state.sessions,
                               focusedSessionID: model.state.focusedSessionID,
                               attentionCount: 0,
                               bubbleStyle: style)
    }

    private func handleAlert(mood: PetMood, session: ClaudeSession) {
        switch mood {
        case .needsAttention:
            SoundBank.play(.chirp)
            postNotification(title: "\(session.name) needs you",
                             body: session.activity ?? "Claude is waiting on a response.")
        case .done:
            SoundBank.play(.chime)
            // Only notify about completion when the operator is elsewhere.
            if !NSApp.isActive {
                postNotification(title: "\(session.name) finished",
                                 body: session.title ?? session.projectName)
            }
        default:
            break
        }
    }

    private func postNotification(title: String, body: String) {
        guard Preferences.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
