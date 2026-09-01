import AppKit
import ServiceManagement

/// The status-bar item. The pet has no dock icon and no window chrome, so this
/// is the only place settings can live.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var state: PetState = .sleeping

    private let onToggleVisibility: () -> Void
    private let onPin: (String?) -> Void
    private let onSetPixelSize: (Double) -> Void
    private let onSetCostume: (Costume) -> Void
    private let onToggleStepAside: () -> Void
    private let onTogglePersistency: () -> Void
    private let onToggleSecondPet: () -> Void
    private let onPinSecond: (String?) -> Void
    private let onSetSecondCostume: (Costume) -> Void
    private let onQuit: () -> Void

    init(onToggleVisibility: @escaping () -> Void,
         onPin: @escaping (String?) -> Void,
         onSetPixelSize: @escaping (Double) -> Void,
         onSetCostume: @escaping (Costume) -> Void,
         onToggleStepAside: @escaping () -> Void,
         onTogglePersistency: @escaping () -> Void,
         onToggleSecondPet: @escaping () -> Void,
         onPinSecond: @escaping (String?) -> Void,
         onSetSecondCostume: @escaping (Costume) -> Void,
         onQuit: @escaping () -> Void) {
        self.onToggleVisibility = onToggleVisibility
        self.onPin = onPin
        self.onSetPixelSize = onSetPixelSize
        self.onSetCostume = onSetCostume
        self.onToggleStepAside = onToggleStepAside
        self.onTogglePersistency = onTogglePersistency
        self.onToggleSecondPet = onToggleSecondPet
        self.onPinSecond = onPinSecond
        self.onSetSecondCostume = onSetSecondCostume
        self.onQuit = onQuit

        // SELF-HEAL before the item exists. macOS persists a status item's
        // preferred position in the app's own defaults, and a stale one
        // strands the item in a slot that no longer renders — measured live:
        // the stored slot (603pt from the right) sat EMPTY on a bar whose
        // icon cluster began 400pt further right, and the crab was simply
        // gone. The operator has hit this class before (the days-invisible
        // status item in the fork). Position memory was never a feature here,
        // so the key is dropped every launch and macOS places the item fresh
        // beside its neighbours, where it can be seen.
        // `.standard`, NOT `Preferences.suiteName`: macOS reads and writes the
        // position under the BUNDLE's own domain (`com.internetdialup.clawd`
        // since the rename), while the named suite is the settings home the
        // rename deliberately left behind. Deleting the key from the suite
        // would clean a domain the status bar never looks at.
        UserDefaults.standard
            .removeObject(forKey: "NSStatusItem Preferred Position Item-0")

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Belt to the braces above: visibility is also persistable state (a
        // Cmd-drag off the bar writes it), and a pet whose only quit lives in
        // this menu must never be invisible.
        item.isVisible = true

        if let button = item.button {
            button.image = Self.templateIcon()
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }
        menu.delegate = self
        item.menu = menu
    }

    func update(state: PetState) {
        self.state = state
        // Just the crab. A session count beside it was noise — the number is in
        // the menu's status line and in the roster, and a two-digit count made
        // the menu bar item jump around as sessions came and went.
        // `bubbleContent` before `bubble`: the bubble now goes quiet between
        // bursts, and a tooltip that blinked to the status line every time he
        // stopped talking would be hiding the live task from someone who went
        // looking for it.
        item.button?.toolTip = state.bubbleContent ?? state.bubble ?? statusLine
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(action("Show / hide pet") { [weak self] in self?.onToggleVisibility() })

        // A visibility concern, so it lives beside the visibility row.
        let persistency = action("Persistency") { [weak self] in
            self?.onTogglePersistency()
            self?.refresh()
        }
        persistency.state = Preferences.shared.persistent ? .on : .off
        persistency.toolTip = "On: floats above every window (still steps aside for video). Off: app windows cover him."
        menu.addItem(persistency)

        // Size submenu.
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let currentSize = Preferences.shared.pixelSize
        for size in Preferences.pixelSizes {
            let dimensions = Preferences.characterSize(size)
            let label = "\(Int(dimensions.width)) × \(Int(dimensions.height)) pt"
            let entry = action(label) { [weak self] in
                self?.onSetPixelSize(size)
            }
            entry.state = size == currentSize ? .on : .off
            sizeMenu.addItem(entry)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Costume submenu.
        let costumeItem = NSMenuItem(title: "Costume", action: nil, keyEquivalent: "")
        let costumeMenu = NSMenu()
        let worn = Preferences.shared.costume
        for costume in Costume.allCases {
            let entry = action(costume.title) { [weak self] in
                self?.onSetCostume(costume)
            }
            entry.state = costume == worn ? .on : .off
            costumeMenu.addItem(entry)
        }
        costumeItem.submenu = costumeMenu
        menu.addItem(costumeItem)

        // Pin submenu
        let pinItem = NSMenuItem(title: "Follow session", action: nil, keyEquivalent: "")
        let pinMenu = NSMenu()
        let pinned = Preferences.shared.pinnedSessionID
        let auto = action("Busiest session (auto)") { [weak self] in self?.onPin(nil) }
        auto.state = pinned == nil ? .on : .off
        pinMenu.addItem(auto)
        if !state.sessions.isEmpty { pinMenu.addItem(.separator()) }
        for session in state.sessions {
            let entry = action(session.name) { [weak self] in self?.onPin(session.id) }
            entry.state = pinned == session.id ? .on : .off
            entry.toolTip = session.cwd
            pinMenu.addItem(entry)
        }
        pinItem.submenu = pinMenu
        menu.addItem(pinItem)

        // The second pet: summon/dismiss, and — while he is out — his own
        // session to follow and his own wardrobe.
        let secondItem = NSMenuItem(title: "Second pet 🦀", action: nil, keyEquivalent: "")
        let secondMenu = NSMenu()
        let summoned = Preferences.shared.pet2Enabled
        secondMenu.addItem(action(summoned ? "Dismiss second pet" : "Summon second pet") { [weak self] in
            self?.onToggleSecondPet()
            self?.refresh()
        })
        if summoned {
            secondMenu.addItem(.separator())

            let followItem = NSMenuItem(title: "Follow session", action: nil, keyEquivalent: "")
            let followMenu = NSMenu()
            let pinned2 = Preferences.shared.pet2PinnedSessionID
            let auto2 = action("Busiest other session (auto)") { [weak self] in self?.onPinSecond(nil) }
            auto2.state = pinned2 == nil ? .on : .off
            followMenu.addItem(auto2)
            if !state.sessions.isEmpty { followMenu.addItem(.separator()) }
            for session in state.sessions {
                let entry = action(session.name) { [weak self] in self?.onPinSecond(session.id) }
                entry.state = pinned2 == session.id ? .on : .off
                entry.toolTip = session.cwd
                followMenu.addItem(entry)
            }
            followItem.submenu = followMenu
            secondMenu.addItem(followItem)

            let costume2Item = NSMenuItem(title: "Costume", action: nil, keyEquivalent: "")
            let costume2Menu = NSMenu()
            let worn2 = Preferences.shared.pet2Costume
            for costume in Costume.allCases {
                let entry = action(costume.title) { [weak self] in
                    self?.onSetSecondCostume(costume)
                }
                entry.state = costume == worn2 ? .on : .off
                costume2Menu.addItem(entry)
            }
            costume2Item.submenu = costume2Menu
            secondMenu.addItem(costume2Item)
        }
        secondItem.submenu = secondMenu
        menu.addItem(secondItem)

        menu.addItem(.separator())

        let sounds = action("Sounds") { [weak self] in
            Preferences.shared.soundsEnabled.toggle()
            self?.refresh()
        }
        sounds.state = Preferences.shared.soundsEnabled ? .on : .off
        menu.addItem(sounds)

        let blips = action("Service sound blips") { [weak self] in
            Preferences.shared.toolBlipEnabled.toggle()
            self?.refresh()
        }
        blips.state = Preferences.shared.toolBlipEnabled ? .on : .off
        menu.addItem(blips)

        let notifications = action("Notifications") { [weak self] in
            Preferences.shared.notificationsEnabled.toggle()
            self?.refresh()
        }
        notifications.state = Preferences.shared.notificationsEnabled ? .on : .off
        menu.addItem(notifications)

        // A switch that cannot do anything says so, rather than showing a tick.
        // macOS never registers an ad-hoc signed app with Notification Center,
        // so there is not even a row in System Settings for someone to go and
        // fix — which is exactly why this has to be said here.
        if !NotificationGrant.granted {
            notifications.isEnabled = false
            notifications.state = .off
            notifications.toolTip = NotificationGrant.unavailableReason
        }

        let cooking = action("Notify when cooking 🔥") { [weak self] in
            Preferences.shared.cookingNotificationsEnabled.toggle()
            self?.refresh()
        }
        cooking.state = Preferences.shared.cookingNotificationsEnabled ? .on : .off
        cooking.toolTip = "Off by default — cooking starts often."
        if !NotificationGrant.granted {
            cooking.isEnabled = false
            cooking.state = .off
            cooking.toolTip = NotificationGrant.unavailableReason
        }

        // The preference itself lives in Preferences; the toggle goes through
        // the app because flipping it mid-film has to act NOW (step aside or
        // come back), not on the next belief change.
        let stepAside = action("Step aside for video 🎬") { [weak self] in
            self?.onToggleStepAside()
            self?.refresh()
        }
        stepAside.state = Preferences.shared.stepsAsideForVideo ? .on : .off
        stepAside.toolTip = "He fades out while a film plays fullscreen on his display."
        menu.addItem(cooking)
        menu.addItem(stepAside)

        let login = action("Open at login") { [weak self] in
            Self.toggleLaunchAtLogin()
            self?.refresh()
        }
        login.state = Self.launchesAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let hooks = action(HookInstaller.isInstalled ? "Reinstall Claude hooks…" : "Install Claude hooks…") {
            HookInstaller.promptAndInstall()
        }
        hooks.toolTip = "Adds a hooks entry to ~/.claude/settings.json for instant reactions. Shows the change and backs up first."
        menu.addItem(hooks)

        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Pet") { [weak self] in self?.onQuit() })
    }

    private var statusLine: String {
        guard !state.sessions.isEmpty else { return "No Claude sessions" }
        let focused = state.focusedSession
        let name = focused?.name ?? "—"
        return "\(name): \(state.mood.rawValue)"
    }

    /// Rebuilds the menu. Internal rather than private so `AppDelegate` can
    /// relabel the notification rows once macOS has answered the authorization
    /// request, which lands after the menu is first built.
    func refresh() {
        menu.cancelTracking()
    }

    private func action(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        let target = MenuAction(handler: handler)
        item.target = target
        item.representedObject = target   // keeps the target alive as long as the item
        return item
    }

    // MARK: - Launch at login

    static var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggleLaunchAtLogin() {
        do {
            if launchesAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            // Registration requires a bundled, launchable .app — running the raw
            // SwiftPM binary cannot register one.
            alert.informativeText = "\(error.localizedDescription)\n\nLaunch at login needs Claude Pet to be running from ClaudePet.app (build it with ./run.sh)."
            alert.runModal()
        }
    }

    /// A small crab glyph drawn as a template image, matching the monochrome
    /// convention Claude.app uses for its own tray icon.
    /// Half a point per sprite cell — so on a retina bar every cell is exactly
    /// ONE device pixel and the grid stays hard-edged.
    ///
    /// The size is not freely tunable, which is worth knowing before anyone
    /// nudges it: a cell has to land on whole device pixels or the edges
    /// antialias, and at 2x that allows 0.5pt and 1pt and nothing between.
    /// A point per cell made him 24×15pt — wider than the clock beside him and
    /// visibly chunky. This is the next crisp stop down.
    /// The bar icon's target HEIGHT in points, with the cell derived from it.
    ///
    /// This was a raw half-point cell, and the arithmetic it produced is why
    /// the operator "wasn't seeing Claw'd in the menu bar": the resting crab's
    /// ink box is 24x15 cells, and 0.5pt a cell made the entire icon 12 x 7.5
    /// points — a speck, parked at a remembered position out in an empty
    /// stretch of a 2880-point bar. Not hidden, not off-screen, not a poisoned
    /// pref: just seven and a half points tall. Measured by probing
    /// `templateIcon().size` after screenshots proved the slot itself was
    /// blank at every zoom.
    ///
    /// Fourteen and a half points, arrived at by eye. The first repair used
    /// 16.5 — the standard glyph body height — but the crab is a WIDE sprite
    /// (24×15 ink cells), so height-matching the neighbours made him 26pt
    /// across and the operator's next report was "too large". A wide glyph has
    /// to sit a notch below the standard body to carry the same visual weight.
    /// Deriving the cell from the height means a future art change to the
    /// crab's proportions resizes the icon instead of silently shrinking it.
    static let iconHeight: CGFloat = 14.5

    /// The menu-bar crab, drawn from the rig itself.
    ///
    /// It used to be freehand bezier: an oval body, two stick eye-stalks and
    /// two oval claws that shared nothing with the character on the desktop —
    /// a circle crab standing in for a pixel one. Now the same `CrabRig` that
    /// draws him renders the icon, cropped to his inked bounding box so he
    /// fills the bar instead of floating inside the sprite's transparent
    /// margins.
    ///
    /// A template image carries only alpha, so the face cannot be drawn — the
    /// eyes and mouth are PUNCHED, left transparent inside the filled shell,
    /// which is how a stencil reads a face. That punch is load-bearing: his
    /// silhouette alone is a rectangle with legs, and it is the face that
    /// makes the shape read as him. Everything else that is ink becomes black,
    /// and macOS tints it for the light bar, the dark bar and the menu-open
    /// highlight.
    static func templateIcon() -> NSImage {
        let buffer = CrabRig.render(CrabPose())
        guard let box = SpriteMask(buffer).bounds else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        let cell = iconHeight / CGFloat(box.h)
        let size = NSSize(width: CGFloat(box.w) * cell, height: CGFloat(box.h) * cell)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            for row in 0..<box.h {
                for column in 0..<box.w {
                    let ink = buffer[box.x + column, box.y + row]
                    guard ink != .clear, ink != .eye, ink != .mouth else { continue }
                    // The buffer's rows run down from its top; an unflipped
                    // NSImage's run up from its bottom.
                    NSRect(x: CGFloat(column) * cell,
                           y: CGFloat(box.h - 1 - row) * cell,
                           width: cell, height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Boxes a closure so it can be an Objective-C menu target.
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
