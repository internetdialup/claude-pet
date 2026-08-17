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
    private let onPreviewMood: (PetMood?) -> Void
    private let onSetPixelSize: (Double) -> Void
    private let onSetCostume: (Costume) -> Void
    private let onToggleStepAside: () -> Void
    private let onQuit: () -> Void

    init(onToggleVisibility: @escaping () -> Void,
         onPin: @escaping (String?) -> Void,
         onPreviewMood: @escaping (PetMood?) -> Void,
         onSetPixelSize: @escaping (Double) -> Void,
         onSetCostume: @escaping (Costume) -> Void,
         onToggleStepAside: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.onToggleVisibility = onToggleVisibility
        self.onPin = onPin
        self.onPreviewMood = onPreviewMood
        self.onSetPixelSize = onSetPixelSize
        self.onSetCostume = onSetCostume
        self.onToggleStepAside = onToggleStepAside
        self.onQuit = onQuit

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

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
        item.button?.toolTip = state.bubble ?? statusLine
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(action("Show / hide pet") { [weak self] in self?.onToggleVisibility() })

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

        menu.addItem(.separator())

        let sounds = action("Sounds") { [weak self] in
            Preferences.shared.soundsEnabled.toggle()
            self?.refresh()
        }
        sounds.state = Preferences.shared.soundsEnabled ? .on : .off
        menu.addItem(sounds)

        let blips = action("Sound on every tool call") { [weak self] in
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

        let cooking = action("Notify when cooking 🔥") { [weak self] in
            Preferences.shared.cookingNotificationsEnabled.toggle()
            self?.refresh()
        }
        cooking.state = Preferences.shared.cookingNotificationsEnabled ? .on : .off
        cooking.toolTip = "Off by default — cooking starts often."

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

        // Art review: freeze the crab in each mood.
        //
        // This branch keeps the submenu on in every configuration, including
        // release builds, so the sprite can be driven by hand while working on
        // it. On `main` the same block is wrapped in `#if DEBUG`.
        let preview = NSMenuItem(title: "Preview animation", action: nil, keyEquivalent: "")
        let previewMenu = NSMenu()
        previewMenu.addItem(action("Live") { [weak self] in self?.onPreviewMood(nil) })
        previewMenu.addItem(.separator())
        for mood in PetMood.allCases {
            previewMenu.addItem(action(mood.rawValue) { [weak self] in self?.onPreviewMood(mood) })
        }
        preview.submenu = previewMenu
        menu.addItem(preview)

        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Pet") { [weak self] in self?.onQuit() })
    }

    private var statusLine: String {
        guard !state.sessions.isEmpty else { return "No Claude sessions" }
        let focused = state.focusedSession
        let name = focused?.name ?? "—"
        return "\(name): \(state.mood.rawValue)"
    }

    private func refresh() {
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
    private static func templateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 14)
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSBezierPath(ovalIn: NSRect(x: 3, y: 2.5, width: 12, height: 8))
            NSColor.black.setFill()
            body.fill()
            // Eye stalks.
            for x in [6.5, 10.5] {
                NSBezierPath(rect: NSRect(x: x, y: 9, width: 1.2, height: 3)).fill()
                NSBezierPath(ovalIn: NSRect(x: x - 1, y: 11, width: 3.2, height: 3.2)).fill()
            }
            // Claws.
            for x in [0.5, 14.5] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 4, width: 3.5, height: 4)).fill()
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
