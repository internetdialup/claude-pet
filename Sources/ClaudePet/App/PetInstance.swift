import AppKit
import SwiftUI

/// One pet on the desktop: his model, his window, his input wiring, his
/// visibility latches, and his own film watch. Everything that must exist
/// twice when a second pet is summoned lives here; everything genuinely
/// global — the coordinator, the menu bar, the roster popover, alerts, the
/// demo — stays in `AppDelegate`.
///
/// Instances are PERSISTENT across window rebuilds: a pixel-size change calls
/// `rebuildWindow()`, never replaces the instance — replacing it would reset
/// the film detector (≈10s of re-agreement, flashing the pet over a live
/// film) and lose the visibility latches.
@MainActor
final class PetInstance {
    /// 0 is the original pet; 1 the summoned second. Drives pref keys and
    /// state-slot selection.
    let slot: Int

    let model = PetViewModel()
    private(set) var controller: PetWindowController?

    /// Opens the global roster anchored to this pet's window.
    var onRosterRequested: (() -> Void)?
    /// The other pet's window frame, for snap de-stacking. Wired by the app,
    /// which is the only thing that knows about siblings.
    var siblingFrame: (() -> CGRect?)?

    // MARK: - Visibility policy
    //
    // The three facts policy is decided from. `isVisible` is never read for
    // policy — a window faded out by the film watch reads as hidden, and one
    // menu click would then both surface him and corrupt the bookkeeping.

    private(set) var petHiddenByUser = false
    private var steppedAside = false
    /// The operator brought him back mid-film: an answer to THIS film,
    /// cleared when it ends.
    private var filmOverride = false
    /// The watch's current belief, cached because preference toggles need the
    /// answer now, not the next change.
    private(set) var filmPlaying = false
    private var filmWatch: FilmWatch?
    private var screenObserver: NSObjectProtocol?

    init(slot: Int) {
        self.slot = slot
    }

    /// Stops the watch and releases the window — a dismissed second pet must
    /// leave nothing ticking. The screen-parameters observer token is stored
    /// precisely so this can remove it.
    func teardown() {
        filmWatch?.stop()
        filmWatch = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        controller?.close()
        controller = nil
    }

    // MARK: - Window

    /// Builds (or rebuilds, after a size change) the floating window. The
    /// window is recreated rather than resized because its size, content and
    /// click-through region all derive from `pixelSize`; the instance and its
    /// latches survive the swap.
    func rebuildWindow() {
        // Close, not just hide. `hide()` only orders the window out; the old
        // NSWindow and its SwiftUI host stayed alive and kept ticking their
        // TimelineView, so every size change added another animating ghost.
        controller?.close()

        let pixelSize = Preferences.shared.pixelSize
        let size = PetRootView.windowSize(pixelSize: pixelSize)
        // Only the sprite band accepts clicks; the rest of the window is
        // transparent and click-through. `PetRootView` owns the layout maths
        // so the grab area cannot drift away from the character.
        let interactive = PetRootView.spriteFrame(pixelSize: pixelSize)

        let slot = self.slot
        let controller = PetWindowController(
            contentSize: size,
            interactiveRect: interactive,
            rootView: PetRootView(model: model, pixelSize: pixelSize),
            loadPosition: { slot == 0 ? Preferences.shared.position : Preferences.shared.pet2Position },
            storePosition: { origin in
                if slot == 0 { Preferences.shared.position = origin }
                else { Preferences.shared.pet2Position = origin }
            },
            // A summoned second pet must not park exactly under the first and
            // look like a no-op: his default home sits one window further
            // along the dock edge.
            parkOffset: slot == 0 ? 0 : size.width + 12
        )
        controller.avoidingFrame = { [weak self] in self?.siblingFrame?() }
        wire(controller)
        controller.setPersistent(Preferences.shared.persistent)
        self.controller = controller
        if steppedAside {
            // A rebuild mid-film (or mid-fade) must not flash a full-alpha
            // pet over it; the eventual fade-in rises from here.
            controller.prepareSteppedAside()
        } else if !petHiddenByUser {
            controller.show()
        }
    }

    private func wire(_ controller: PetWindowController) {
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
            // request. The bug's schedule is pure, so ask it where it is —
            // through THIS pet's clock; the shared one is nobody's clock now.
            if self.model.state.mood == .idle,
               let epoch = self.model.moodClock.currentEpoch(for: .idle),
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
            self.onRosterRequested?()
            // Clear it once the animation is done so the view drops back to
            // its mood frame rate instead of holding 30fps forever.
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
    }

    // MARK: - State intake

    /// A fresh state from the coordinator: forward to the model and settle
    /// the latches that derive from it.
    func take(state: PetState) {
        // The glow's own t=0: latched on the epic edge, released when the
        // celebration ends (the envelope is long done by then).
        if state.epicCelebration, model.celebrationStartedAt == nil {
            model.celebrationStartedAt = Date()
        } else if !state.celebrating, model.celebrationStartedAt != nil {
            model.celebrationStartedAt = nil
        }
        model.state = state
        refreshBubbleGrab()
        updateBadgeLatches()
    }

    // MARK: - Films

    func startFilmWatch() {
        let film = FilmWatch(
            geometry: { [weak self] in
                // Re-read the controller every sample: `rebuildWindow`
                // replaces it wholesale, and a captured window is the one
                // that is wrong at the moment it matters.
                guard let window = self?.controller?.window,
                      let screen = PetWindowController.screen(for: window.frame)
                else { return nil }   // no display → no geometry → the detector surfaces him
                return FullScreenWatch.geometry(of: screen)
            },
            onChange: { [weak self] playing in self?.filmChanged(playing: playing) })
        film.start()
        filmWatch = film

        screenObserver = NotificationCenter.default.addObserver(
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
                if !petHiddenByUser { controller?.fadeIn() }
            }
        }
    }

    func stepAsideIfWanted() {
        guard filmPlaying, Preferences.shared.stepsAsideForVideo,
              !petHiddenByUser, !filmOverride, !steppedAside,
              controller?.isDragging != true else { return }
        steppedAside = true
        controller?.fadeOut()
    }

    /// The step-aside preference was switched off (or the operator wants him
    /// back): end an active step-aside now.
    func surfaceFromFilm() {
        guard steppedAside else { return }
        steppedAside = false
        if !petHiddenByUser { controller?.fadeIn() }
    }

    func applyPersistency() {
        controller?.setPersistent(Preferences.shared.persistent)
    }

    // MARK: - Interactions

    func toggleVisibility() {
        guard let controller else { return }
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
    func refreshBubbleGrab() {
        let transient = model.transientBubble.map { $0.until > Date() } ?? false
        let stateBubble = !(model.state.bubble ?? "").isEmpty && model.state.mood != .sleeping
        controller?.setBubbleGrabbable(transient || stateBubble)
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
}
