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
            self.refreshBubbleGrab()
            self.updateBadgeLatches()
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
            onSetCostume: { [weak self] costume in
                Preferences.shared.costume = costume
                self?.model.costume = costume
            },
            onToggleStepAside: { [weak self] in
                guard let self else { return }
                Preferences.shared.stepsAsideForVideo.toggle()
                // Act on the cached answer now — the watch only calls back on
                // belief CHANGES, and the film is already believed.
                if Preferences.shared.stepsAsideForVideo {
                    self.stepAsideIfWanted()
                } else if self.steppedAside {
                    self.steppedAside = false
                    if !self.petHiddenByUser { self.windowController?.fadeIn() }
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )
        model.costume = Preferences.shared.costume
        startFilmWatch()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if CommandLine.arguments.contains("--demo") { startDemo() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        filmWatch?.stop()
        coordinator.stop()
    }

    // MARK: - Stepping aside for films

    /// The three facts visibility policy is decided from. `isVisible` is never
    /// read for policy — a window faded out by the film watch reads as hidden,
    /// and one menu click would then both surface him and corrupt the
    /// bookkeeping.
    private var petHiddenByUser = false
    private var steppedAside = false
    /// The operator brought him back mid-film: an answer to THIS film, cleared
    /// when it ends.
    private var filmOverride = false
    /// The watch's current belief, cached because the preference toggles need
    /// the answer now, not the next change.
    private var filmPlaying = false
    private var filmWatch: FilmWatch?

    private func startFilmWatch() {
        let film = FilmWatch(
            geometry: { [weak self] in
                // Re-read the controller every sample: `buildWindow` replaces
                // it wholesale, and a captured window is the one that is wrong
                // at the moment it matters.
                guard let window = self?.windowController?.window else { return nil }
                return FullScreenWatch.geometry(of: PetWindowController.screen(for: window.frame))
            },
            onChange: { [weak self] playing in self?.filmChanged(playing: playing) })
        film.start()
        filmWatch = film

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.filmWatch?.reconsider() }
        }
    }

    private func filmChanged(playing: Bool) {
        filmPlaying = playing
        if playing {
            stepAsideIfWanted()
        } else {
            // The film's reason is withdrawn; so is the override it earned.
            filmOverride = false
            if steppedAside {
                steppedAside = false
                // Coming back is not a promise to appear — the operator's own
                // hide stands on its own.
                if !petHiddenByUser { windowController?.fadeIn() }
            }
        }
    }

    private func stepAsideIfWanted() {
        guard filmPlaying, Preferences.shared.stepsAsideForVideo,
              !petHiddenByUser, !filmOverride, !steppedAside,
              windowController?.isDragging != true else { return }
        steppedAside = true
        windowController?.fadeOut()
    }

    /// Builds (or rebuilds, after a size change) the floating window.
    ///
    /// The window is recreated rather than resized because its size, its
    /// content, and its click-through region all derive from `pixelSize`.
    private func buildWindow() {
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
        controller.onClick = { [weak self] clicks, location in
            guard let self else { return }
            // 🎉🪄 Poke him three times and he throws a party.
            if clicks >= 3 {
                self.model.rainbowStartedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + CrabView.rainbowDuration) {
                    self.model.rainbowStartedAt = nil
                }
            }

            // 🐛 A click on the visiting floor bug is a pounce, not a roster
            // request. The bug's schedule is pure, so ask it where it is.
            if self.model.state.mood == .idle,
               let epoch = MoodClock.shared.currentEpoch(for: .idle),
               let bug = CrabAnimator.bugPosition(idleT: Date.timeIntervalSinceReferenceDate - epoch),
               let cell = self.gridCell(for: location),
               cell.y >= 26, cell.x >= bug - 2, cell.x <= bug + 3 {
                self.model.pouncedAt = Date()
                let seed = Int(Date().timeIntervalSince1970)
                self.model.transientBubble = (Vocab.line(for: .bugCaught, seed: seed) ?? "Bug fixed",
                                              Date().addingTimeInterval(2.4))
                self.refreshBubbleGrab()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    self.model.pouncedAt = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    self.refreshBubbleGrab()
                }
                return
            }

            // 🍤 A click on a sleeping crab is a snack, not a roster request —
            // the roster stays a menu-bar away. Gated on the sprite itself:
            // with the grab halo, a click on the bubble band above a sleeping
            // crab is a grip, not a feeding.
            if self.model.state.mood == .sleeping, self.model.snackStartedAt == nil,
               self.gridCell(for: location) != nil {
                self.model.snackStartedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
                    self.model.snackStartedAt = nil
                }
                return
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
        controller.onPetStart = { [weak self] in
            self?.model.pettingStartedAt = Date()
            self?.model.pettingEndedAt = nil
        }
        controller.onPetEnd = { [weak self] in
            guard let self else { return }
            self.model.pettingEndedAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let ended = self.model.pettingEndedAt,
                      Date().timeIntervalSince(ended) >= 0.55 else { return }
                self.model.pettingStartedAt = nil
                self.model.pettingEndedAt = nil
            }
        }
        controller.onHover = { [weak self] hovering in
            guard let self else { return }
            if hovering {
                self.model.hoverStartedAt = Date()
                self.model.hoverEndedAt = nil
            } else {
                // Keep the start time so the greeting eases out from where it
                // was, then clear both once the release has played so the view
                // drops back to its mood frame rate.
                self.model.hoverEndedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, let ended = self.model.hoverEndedAt,
                          Date().timeIntervalSince(ended) >= 0.55 else { return }
                    self.model.hoverStartedAt = nil
                    self.model.hoverEndedAt = nil
                }
            }
        }
        controller.onDragEnded = { [weak self] in
            // A step-aside deferred to a held crab gets its chance now, and
            // the watch re-reads a window that may have landed on another
            // display.
            self?.filmWatch?.reconsider()
            self?.stepAsideIfWanted()
        }
        windowController = controller
        if steppedAside {
            // A rebuild mid-film (or mid-fade) must not flash a full-alpha
            // pet over it; the eventual fade-in rises from here.
            controller.prepareSteppedAside()
        } else if !petHiddenByUser {
            controller.show()
        }
    }

    /// Replays `DemoMode.script` on a loop, ignoring real sessions.
    private func startDemo() {
        demoStartedAt = Date()
        demoMood = true
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.demoStartedAt else { return }
                let elapsed = Date().timeIntervalSince(started)
                // Fabricated sessions: the roster must not publish real project
                // names into a recording.
                let state = DemoMode.state(at: elapsed)
                self.model.state = state
                self.menuBar?.update(state: state)
                self.refreshBubbleGrab()

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
        if steppedAside {
            // Bringing him back mid-film is an answer to THIS film: he stays
            // up for the rest of it and the override dies with it.
            filmOverride = true
            steppedAside = false
            controller.fadeIn()
            return
        }
        petHiddenByUser.toggle()
        petHiddenByUser ? controller.hide() : controller.show()
    }

    /// The completion badge's appearance latches. Rules: the badge waits for
    /// the done pose to relax (the crossfade dissolves the big overhead check
    /// out while the foot badge dissolves in — never two checkmarks); a
    /// completion ending for any reason — new work, focus switch away,
    /// session death — eases out through one 0.45s envelope rather than
    /// vanishing; a focus switch between two live completions swaps identity
    /// without re-running the attack, so the badge never dips.
    private func updateBadgeLatches() {
        let state = model.state
        if let live = state.completedAt {
            guard state.mood != .done else { return }   // wait out the pose
            if model.badgeCompletionAt == nil || model.badgeEndedAt != nil {
                model.badgeCompletionAt = live
                model.badgeShownAt = Date()
                model.badgeEndedAt = nil
            } else if model.badgeCompletionAt != live {
                model.badgeCompletionAt = live
            }
        } else if model.badgeCompletionAt != nil, model.badgeEndedAt == nil {
            let ended = Date()
            model.badgeEndedAt = ended
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.model.badgeEndedAt == ended else { return }
                self.model.badgeCompletionAt = nil
                self.model.badgeShownAt = nil
                self.model.badgeEndedAt = nil
            }
        }
    }

    /// The bubble band is a grab handle exactly while a bubble is visible —
    /// mirrors `PetRootView`'s display condition, so what you can see is what
    /// you can grab.
    private func refreshBubbleGrab() {
        let transient = model.transientBubble.map { $0.until > Date() } ?? false
        let stateBubble = !(model.state.bubble ?? "").isEmpty && model.state.mood != .sleeping
        windowController?.setBubbleGrabbable(transient || stateBubble)
    }

    /// Maps a click in view coordinates to a sprite-grid cell. View y runs
    /// upward from the window's bottom; the buffer's y runs downward from its
    /// top row, hence the flip.
    private func gridCell(for location: CGPoint) -> (x: Int, y: Int)? {
        let pixelSize = Preferences.shared.pixelSize
        let frame = PetRootView.spriteFrame(pixelSize: pixelSize)
        guard frame.contains(location), pixelSize > 0 else { return nil }
        let x = Int((location.x - frame.minX) / pixelSize)
        let y = PixelBuffer.side - 1 - Int((location.y - frame.minY) / pixelSize)
        return (x, y)
    }

    private func toggleRoster() {
        guard let window = windowController?.window, let contentView = window.contentView else { return }

        if let existing = roster, existing.isShown {
            existing.performClose(nil)
            roster = nil
            window.acceptsKey = false
            return
        }

        // The popover needs a key window to be clickable; the pet does not.
        window.acceptsKey = true
        window.makeKey()

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
        defer { refreshBubbleGrab() }
        guard let mood else {
            model.state = coordinator.state
            return
        }

        // Show what the mood actually looks like in use. Labelling the bubble
        // "preview: working" meant the one thing you could not preview was the
        // bubble. Text comes from the mood's own style, falling back to its
        // vocabulary — so a preview always shows real content.
        let bubble = mood.style.previewBubble
            ?? Vocab.line(for: mood.shoutoutOccasion, seed: Int(Date().timeIntervalSince1970))
        let style: PetState.BubbleStyle = mood == .thinking ? .dots : .plain

        model.state = PetState(mood: mood,
                               bubble: bubble,
                               tool: mood == .working ? "Bash" : nil,
                               sessions: model.state.sessions,
                               focusedSessionID: model.state.focusedSessionID,
                               attentionCount: 0,
                               bubbleStyle: style)
    }

    private func handleAlert(mood: PetMood, session: ClaudeSession) {
        // Chirps and banners over a film are the same disease as a pet over a
        // film — suppressed whether or not he steps aside for it.
        guard !filmPlaying else { return }
        guard let event = NotificationNudge.event(for: mood) else { return }

        switch event {
        case .needsYou: SoundBank.play(.chirp)
        case .finished: SoundBank.play(.chime)
        default: break                 // plan-ready and cooking stay silent
        }

        // Cooking fires often; it is opt-in.
        if event == .cooking, !Preferences.shared.cookingNotificationsEnabled { return }
        // Finishing is only worth a banner when you are looking elsewhere.
        if event == .finished, NSApp.isActive { return }

        let copy = NotificationNudge.copy(for: event, seed: Int(Date().timeIntervalSince1970))
        postNotification(title: copy.title,
                         body: "\(copy.body) — \(session.name)")
    }

    private func postNotification(title: String, body: String) {
        guard Preferences.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        // Claw'd's own icon, so the banner is recognisably his. Best-effort:
        // a banner without an icon is fine, a crash is not, and
        // UNNotificationAttachment rejects formats it does not like.
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let attachment = try? UNNotificationAttachment(identifier: "clawd",
                                                          url: icon,
                                                          options: nil) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
