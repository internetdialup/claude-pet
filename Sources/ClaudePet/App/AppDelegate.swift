import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    /// The pets, in slot order. Exactly one today; a summoned second appends.
    /// Instances persist across window rebuilds — see `PetInstance`.
    private var pets: [PetInstance] = []
    private let coordinator = ActivityCoordinator()
    private var menuBar: MenuBarController?
    private var roster: NSPopover?
    /// The window the roster is anchored to, so its `acceptsKey` can be
    /// cleared on ANY close — including the transient click-away, which the
    /// old explicit-toggle-only reset missed, leaving the pet window able to
    /// steal the caret on the next poke.
    private weak var rosterAnchor: PetWindow?

    /// Convenience: the original pet. Slot 0 always exists after launch.
    private var primary: PetInstance { pets[0] }

    /// Overrides the live feed while the operator previews a mood from the menu.
    private var debugMood: PetMood?
    /// `--demo`: run the scripted reel instead of real activity, for recording.
    private var demoTimer: Timer?
    private var demoStartedAt: Date?
    /// Set while the demo reel owns the display, so live updates stay out.
    private var demoMood = false

    /// `UNUserNotificationCenter.current()` RAISES — it does not return nil —
    /// when the process has no bundle identifier, which is every `swift run`
    /// and every bare `.build/debug/ClaudePet` the README documents. Looked up
    /// once behind an identity check so a run from source posts no banner
    /// instead of aborting to raise one. This check must not be "simplified"
    /// back out: it looks redundant from inside a packaged build, which is the
    /// only place it looks redundant.
    @MainActor
    private enum Notifier {
        static let center: UNUserNotificationCenter? =
            Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies of the APP is a bug, not company: a rebuild opened over a
        // running copy (or a plain double-open) left both on the desktop.
        // Latest wins — the copy the operator just launched is the one they
        // mean, so it asks the elders to quit rather than quitting itself.
        // Politely: terminate(), never forceTerminate. Skipped without a
        // bundle identity (bare `swift run` development runs). A second PET is
        // a different thing entirely: one process, two windows.
        if let identity = Bundle.main.bundleIdentifier {
            let ourPID = ProcessInfo.processInfo.processIdentifier
            for elder in NSRunningApplication.runningApplications(withBundleIdentifier: identity)
            where elder.processIdentifier != ourPID {
                elder.terminate()
            }
        }

        let pet = PetInstance(slot: 0)
        pet.onRosterRequested = { [weak self, weak pet] in
            guard let self, let pet else { return }
            self.toggleRoster(anchoredTo: pet)
        }
        pets = [pet]
        pet.rebuildWindow()

        coordinator.onChange = { [weak self] slot, state in
            guard let self else { return }
            if slot == 0 {
                // Preview and demo own pet 1's face; the coordinator resumes
                // when they let go. Pet 2 is always live — freezing him was
                // never the menu row's promise.
                guard self.debugMood == nil, !self.demoMood else { return }
                self.primary.take(state: state)
                self.menuBar?.update(state: state)
            } else if slot < self.pets.count {
                self.pets[slot].take(state: state)
            }
        }
        coordinator.onAlert = { [weak self] mood, session in
            self?.handleAlert(mood: mood, session: session)
        }
        coordinator.onCookingProgress = { [weak self] milestone, session in
            self?.postCookProgress(milestone, session: session)
        }
        coordinator.start()

        menuBar = MenuBarController(
            onToggleVisibility: { [weak self] in self?.primary.toggleVisibility() },
            onPin: { [weak self] id in self?.coordinator.pin(sessionID: id) },
            onPreviewMood: { [weak self] mood in self?.previewMood(mood) },
            onSetPixelSize: { [weak self] size in
                Preferences.shared.pixelSize = size
                self?.pets.forEach { $0.rebuildWindow() }
            },
            onSetCostume: { [weak self] costume in
                Preferences.shared.costume = costume
                self?.primary.model.costume = costume
            },
            onToggleStepAside: { [weak self] in
                guard let self else { return }
                Preferences.shared.stepsAsideForVideo.toggle()
                // Act on each pet's cached answer now — the watches only call
                // back on belief CHANGES, and any film is already believed.
                for pet in self.pets {
                    if Preferences.shared.stepsAsideForVideo {
                        pet.stepAsideIfWanted()
                    } else {
                        pet.surfaceFromFilm()
                    }
                }
            },
            onTogglePersistency: { [weak self] in
                Preferences.shared.persistent.toggle()
                self?.pets.forEach { $0.applyPersistency() }
            },
            onToggleSecondPet: { [weak self] in
                guard let self else { return }
                self.pets.count > 1 ? self.dismissSecondPet() : self.summonSecondPet()
            },
            onPinSecond: { [weak self] id in self?.coordinator.pin(slot: 1, sessionID: id) },
            onSetSecondCostume: { [weak self] costume in
                Preferences.shared.pet2Costume = costume
                guard let self, self.pets.count > 1 else { return }
                self.pets[1].model.costume = costume
            },
            onQuit: { NSApp.terminate(nil) }
        )
        primary.model.costume = Preferences.shared.costume
        primary.startFilmWatch()

        Notifier.center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if CommandLine.arguments.contains("--demo") {
            startDemo()
        } else if Preferences.shared.pet2Enabled {
            // The summon survives relaunches; the demo reel keeps a single
            // performer by rule.
            summonSecondPet()
        }
    }

    // MARK: - The second pet

    private func summonSecondPet() {
        guard pets.count == 1 else { return }
        let pet = PetInstance(slot: 1)
        pet.onRosterRequested = { [weak self, weak pet] in
            guard let self, let pet else { return }
            self.toggleRoster(anchoredTo: pet)
        }
        pets.append(pet)
        // Each pet dodges the other's spot when a drag-release snap would
        // stack them; only the app knows about siblings.
        for (index, each) in pets.enumerated() {
            each.siblingFrame = { [weak self] in
                guard let self, self.pets.count > 1 else { return nil }
                return self.pets[1 - index].controller?.window.frame
            }
        }
        pet.model.costume = Preferences.shared.pet2Costume
        pet.rebuildWindow()
        pet.startFilmWatch()
        coordinator.setSlots(2)
        Preferences.shared.pet2Enabled = true
    }

    private func dismissSecondPet() {
        guard pets.count == 2 else { return }
        pets[1].teardown()
        pets.removeLast()
        primary.siblingFrame = nil
        coordinator.setSlots(1)
        Preferences.shared.pet2Enabled = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        pets.forEach { $0.teardown() }
        coordinator.stop()
    }

    // MARK: - Demo and preview (pet 1 only, by rule)

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
                self.primary.model.state = state
                self.menuBar?.update(state: state)
                self.primary.refreshBubbleGrab()

                // Hold the rainbow for exactly the beat that asks for it. Its
                // start is pinned to the beat's own start so the hue cycle
                // lines up with the beat rather than drifting against it.
                if DemoMode.beat(at: elapsed).rainbow {
                    if self.primary.model.rainbowStartedAt == nil {
                        self.primary.model.rainbowStartedAt = Date()
                    }
                } else {
                    self.primary.model.rainbowStartedAt = nil
                }
            }
        }
    }

    /// Freezes pet 1 in one mood so the art can be reviewed live. Selecting
    /// "Live" hands control back to the coordinator.
    private func previewMood(_ mood: PetMood?) {
        debugMood = mood
        defer { primary.refreshBubbleGrab() }
        guard let mood else {
            primary.model.state = coordinator.state
            return
        }

        // Show what the mood actually looks like in use. Labelling the bubble
        // "preview: working" meant the one thing you could not preview was the
        // bubble. Text comes from the mood's own style, falling back to its
        // vocabulary — so a preview always shows real content.
        let bubble = mood.style.previewBubble
            ?? Vocab.line(for: mood.shoutoutOccasion, seed: Int(Date().timeIntervalSince1970))
        let style: PetState.BubbleStyle = mood == .thinking ? .dots : .plain

        primary.model.state = PetState(mood: mood,
                                       bubble: bubble,
                                       tool: mood == .working ? "Bash" : nil,
                                       sessions: primary.model.state.sessions,
                                       focusedSessionID: primary.model.state.focusedSessionID,
                                       attentionCount: 0,
                                       bubbleStyle: style)
    }

    // MARK: - Roster

    private func toggleRoster(anchoredTo pet: PetInstance) {
        guard let window = pet.controller?.window,
              let contentView = window.contentView else { return }

        if let existing = roster, existing.isShown {
            existing.performClose(nil)   // popoverDidClose clears the anchor
            return
        }

        // The popover needs a key window to be clickable; the pet does not —
        // the delegate callback below revokes the capability on ANY close.
        window.acceptsKey = true
        window.makeKey()
        rosterAnchor = window

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: RosterPanel(
                // Always the primary state: it always carries the full session
                // list, where a solo-session slot 1 would honestly-but-uselessly
                // say "nothing running".
                state: primary.model.state,
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

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.rosterAnchor?.acceptsKey = false
            self.rosterAnchor = nil
            self.roster = nil
        }
    }

    // MARK: - Alerts

    private func handleAlert(mood: PetMood, session: ClaudeSession) {
        // A finished turn retires its cooking-progress card either way — a
        // stale 75% bar must never sit under the chimed Done.
        if NotificationNudge.event(for: mood) == .finished {
            Notifier.center?.removeDeliveredNotifications(withIdentifiers: ["cook-\(session.id)"])
        }
        // Chirps and banners over a film are the same disease as a pet over a
        // film — suppressed if ANY pet's display has one, whether or not he
        // steps aside for it.
        guard !pets.contains(where: { $0.filmPlaying }) else { return }
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

    /// The cooking card: posted at cook start, silently replaced in place at
    /// each quarter (same identifier, passive interruption — updates the
    /// banner and the Notification Center entry without re-chiming), retired
    /// by the Done alert. Opt-in via the cooking toggle, like the transition
    /// notification this path replaces.
    private func postCookProgress(_ milestone: ActivityCoordinator.CookMilestone,
                                  session: ClaudeSession) {
        guard Preferences.shared.notificationsEnabled,
              Preferences.shared.cookingNotificationsEnabled,
              !pets.contains(where: { $0.filmPlaying }) else { return }

        let content = UNMutableNotificationContent()
        content.threadIdentifier = session.id
        content.sound = nil
        switch milestone {
        case .started:
            let copy = NotificationNudge.copy(for: .cooking, seed: Int(Date().timeIntervalSince1970))
            content.title = copy.title
            content.body = "\(copy.body) — \(session.name)"
            content.interruptionLevel = .active
        case .fraction(let pct):
            content.title = "Cooking — \(session.name)"
            content.body = Self.progressBar(pct)
            content.interruptionLevel = .passive
        }
        let request = UNNotificationRequest(identifier: "cook-\(session.id)",
                                            content: content, trigger: nil)
        Notifier.center?.add(request)
    }

    /// An 8-cell text bar — the most progress a notification can honestly
    /// hold. `▓▓▓▓░░░░ 50%`.
    static func progressBar(_ percent: Int) -> String {
        let clamped = max(0, min(100, percent))
        let filled = clamped * 8 / 100
        return String(repeating: "▓", count: filled)
            + String(repeating: "░", count: 8 - filled)
            + " \(clamped)%"
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
        Notifier.center?.add(request)
    }
}
