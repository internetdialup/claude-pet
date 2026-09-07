import Foundation
import AppKit

/// The **only** code path in this app permitted to write inside `~/.claude/`
/// — the redline. Every guarantee of it is enforced here: user-initiated,
/// shows the exact change, refuses rather than resets, backs up first, merges
/// only `hooks`, writes settings last and atomically, and can undo itself.
///
/// The merge is a pure function (`merged(into:command:)`) and every path is a
/// parameter, so the whole thing runs against a temp directory under test —
/// which it never did before, and the once-shipped bug that replaced an
/// unparseable settings.json with a hooks-only file is exactly the kind this
/// file could not catch without that.
@MainActor
public enum HookInstaller {

    /// Events the pet subscribes to. `Notification` is the only source of
    /// permission-prompt awareness — the transcript does not record it.
    nonisolated static let events = ["PreToolUse", "PostToolUse", "Stop", "SessionEnd", "Notification"]

    /// The substring every entry we write carries, and the only thing the
    /// filter looks for when removing ours.
    nonisolated static let marker = "claude-pet-hook"

    /// Backups kept beside settings.json; older ones are pruned.
    nonisolated static let backupsKept = 5

    public static var scriptURL: URL {
        // Installed next to the app's support data so the hook keeps working if
        // the .app is moved.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Preferences.suiteName)
            .appendingPathComponent("claude-pet-hook.sh")
    }

    public static var isInstalled: Bool {
        isInstalled(settingsURL: ClaudeHome.settings, scriptURL: scriptURL)
    }

    nonisolated static func isInstalled(settingsURL: URL, scriptURL: URL) -> Bool {
        guard let root = try? readSettings(at: settingsURL),
              let hooks = root["hooks"] as? [String: Any] else { return false }
        let ours = hooks.values.contains { value in
            ((value as? [[String: Any]]) ?? []).contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains(where: isOurs)
            }
        }
        return ours && FileManager.default.fileExists(atPath: scriptURL.path)
    }

    // MARK: - Dialogs

    /// Show the operator exactly what will change — the resulting `hooks`
    /// entries as JSON, not prose — then apply it on approval.
    public static func promptAndInstall() {
        let alert = NSAlert()
        alert.messageText = isInstalled ? "Reinstall Claude Pet hooks?" : "Install Claude Pet hooks?"
        alert.informativeText = """
        This adds a `hooks` entry to \(tilde(ClaudeHome.settings.path)) for the events \
        \(events.joined(separator: ", ")). Below is the `hooks` key exactly as it will read afterwards.

        Each hook runs \(tilde(scriptURL.path)), which writes the hook's payload — tool \
        input and output included — as one JSON file in \(tilde(ClaudeHome.events.path)); \
        the pet reads and deletes it. The script always exits 0, so it can never block \
        or slow a Claude session.

        Your existing settings.json is copied to settings.json.bak.<timestamp> first (the \
        newest \(backupsKept) are kept) and only the `hooks` key is modified. \
        Remove Claude hooks… undoes all of it.
        """
        if let preview = try? previewJSON() {
            alert.accessoryView = jsonView(preview)
        }
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let backup = try install()
            let done = NSAlert()
            done.messageText = "Hooks installed"
            // Only claim a backup when one was actually written — there is
            // nothing to copy when settings.json did not exist.
            let backupLine = backup.map { "\n\nBackup saved at:\n  \(tilde($0.path))" }
                ?? "\n\nThere was no existing settings.json, so no backup was needed."
            done.informativeText = """
            Wrote hook script to:
              \(tilde(scriptURL.path))

            Updated:
              \(tilde(ClaudeHome.settings.path))\(backupLine)

            Restart your Claude Code sessions to pick the hooks up.
            """
            done.runModal()
        } catch {
            fail(error, verb: "installation")
        }
    }

    /// Remove every entry the pet wrote, the shim and the drop directory.
    public static func promptAndUninstall() {
        let alert = NSAlert()
        alert.messageText = "Remove Claude Pet hooks?"
        alert.informativeText = """
        This removes the pet's entries from the `hooks` key in \(tilde(ClaudeHome.settings.path)) \
        — nothing else in the file is touched, and hooks that are not the pet's stay — then \
        deletes \(tilde(scriptURL.path)) and \(tilde(ClaudeHome.events.path)).

        A backup of settings.json is written first. The pet keeps working by watching files; \
        it just reacts a little slower and cannot see permission prompts.
        """
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let backup = try uninstall()
            let done = NSAlert()
            done.messageText = "Hooks removed"
            done.informativeText = backup.map { "Backup saved at:\n  \(tilde($0.path))" }
                ?? "There was no settings.json to edit; the script and the drop directory are gone."
            done.runModal()
        } catch {
            fail(error, verb: "removal")
        }
    }

    private static func fail(_ error: Error, verb: String) {
        let failure = NSAlert()
        failure.alertStyle = .critical
        failure.messageText = "Hook \(verb) failed"
        // True by construction: settings.json is written LAST, after every
        // other step has succeeded.
        failure.informativeText = "\(error.localizedDescription)\n\nYour settings.json was left untouched."
        failure.runModal()
    }

    private static func tilde(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// The `hooks` key as it will read after the merge, against the current file.
    static func previewJSON() throws -> String {
        let current = try readSettings(at: ClaudeHome.settings) ?? [:]
        let merged = try merged(into: current, command: commandString(for: scriptURL))
        let data = try JSONSerialization.data(withJSONObject: merged["hooks"] ?? [:],
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func jsonView(_ text: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.isRichText = false
        view.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.string = text
        view.autoresizingMask = [.width]
        scroll.documentView = view
        return scroll
    }

    // MARK: - The merge, pure

    nonisolated static func commandString(for scriptURL: URL) -> String {
        "\"\(scriptURL.path)\""
    }

    nonisolated static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) == true
    }

    /// `root` with the pet's entry appended to every event, existing entries of
    /// ours removed first, everything else preserved. Throws rather than guess
    /// when `hooks` or `hooks[event]` exist with a shape this does not know.
    nonisolated static func merged(into root: [String: Any], command: String) throws -> [String: Any] {
        var root = root
        var hooks: [String: Any] = [:]
        if let existing = root["hooks"] {
            guard let dict = existing as? [String: Any] else { throw HookError.malformedHooks("`hooks` is not an object") }
            hooks = dict
        }
        let entry: [String: Any] = ["type": "command", "command": command]
        for event in events {
            var groups: [[String: Any]] = []
            if let existing = hooks[event] {
                guard let list = existing as? [[String: Any]] else {
                    throw HookError.malformedHooks("`hooks.\(event)` is not an array")
                }
                groups = list
            }
            groups = stripped(groups)
            groups.append(["hooks": [entry]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return root
    }

    /// `root` with every entry of ours removed; events and the `hooks` key
    /// itself go when they empty. Foreign hooks are never touched.
    nonisolated static func removed(from root: [String: Any]) throws -> [String: Any] {
        var root = root
        guard let existing = root["hooks"] else { return root }
        guard var hooks = existing as? [String: Any] else { throw HookError.malformedHooks("`hooks` is not an object") }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = stripped(groups)
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return root
    }

    /// Our entries filtered out of each group's inner `hooks` array. A group
    /// that held only ours is dropped; a group that shares a matcher with a
    /// foreign hook keeps the foreign hook — the old filter removed the whole
    /// group and took the stranger with it.
    nonisolated static func stripped(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return group }
            let kept = inner.filter { !isOurs($0) }
            if kept.isEmpty && kept.count != inner.count { return nil }
            var trimmed = group
            trimmed["hooks"] = kept
            return trimmed
        }
    }

    // MARK: - Install / uninstall

    /// Size and mtime — enough to notice that Claude Code wrote the file
    /// between our read and our write.
    nonisolated struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }

    nonisolated static func stamp(of url: URL) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Stamp(size: size, modified: modified)
    }

    /// The parsed settings, nil when the file does not exist. Refuses rather
    /// than resets: an unparseable file throws, because falling back to an
    /// empty dictionary once REPLACED a user's settings.json with a hooks-only
    /// file, destroying statusLine, theme, plugins and permissions.
    nonisolated static func readSettings(at url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
              let object = parsed as? [String: Any] else {
            throw HookError.unreadableSettings(path: url.path)
        }
        return object
    }

    nonisolated static func serialised(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root,
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Order matters, and settings.json is LAST: resolve the shim, read and
    /// parse, compute the merge, back up, write the shim, then write settings
    /// atomically — and only if nothing has written the file underneath us.
    ///
    /// - Returns: the backup that was written, or nil when there was no
    ///   existing `settings.json` to back up (never name a path that was not
    ///   written).
    @discardableResult
    static func install(settingsURL: URL = ClaudeHome.settings,
                        scriptURL: URL = Self.scriptURL,
                        eventsURL: URL = ClaudeHome.events,
                        shim: String? = nil) throws -> URL? {
        let fm = FileManager.default

        let shimText = try shim ?? shimSource()
        let before = stamp(of: settingsURL)
        let root = try readSettings(at: settingsURL) ?? [:]
        let output = try serialised(try merged(into: root, command: commandString(for: scriptURL)))

        let backup = try backUp(settingsURL)

        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: eventsURL, withIntermediateDirectories: true)
        try shimText.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        guard stamp(of: settingsURL) == before else { throw HookError.settingsChangedUnderneath }
        try output.write(to: settingsURL, options: .atomic)
        return backup
    }

    /// The inverse: our entries out of settings.json (backed up first, written
    /// atomically, refused if the file moved), then the shim and the drop
    /// directory deleted.
    @discardableResult
    static func uninstall(settingsURL: URL = ClaudeHome.settings,
                          scriptURL: URL = Self.scriptURL,
                          eventsURL: URL = ClaudeHome.events) throws -> URL? {
        let fm = FileManager.default
        var backup: URL?
        let before = stamp(of: settingsURL)
        if let root = try readSettings(at: settingsURL) {
            let output = try serialised(try removed(from: root))
            backup = try backUp(settingsURL)
            guard stamp(of: settingsURL) == before else { throw HookError.settingsChangedUnderneath }
            try output.write(to: settingsURL, options: .atomic)
        }
        try? fm.removeItem(at: scriptURL)
        try? fm.removeItem(at: eventsURL)
        return backup
    }

    /// A millisecond-stamped copy beside the file, bumped if the name is taken
    /// (two installs in one second used to throw on the second copy). The
    /// newest `backupsKept` survive; the rest are pruned.
    nonisolated static func backUp(_ settingsURL: URL) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else { return nil }
        let directory = settingsURL.deletingLastPathComponent()
        let prefix = "\(settingsURL.lastPathComponent).bak."
        var stamp = Int(Date().timeIntervalSince1970 * 1000)
        var destination = directory.appendingPathComponent("\(prefix)\(stamp)")
        while fm.fileExists(atPath: destination.path) {
            stamp += 1
            destination = directory.appendingPathComponent("\(prefix)\(stamp)")
        }
        try fm.copyItem(at: settingsURL, to: destination)
        pruneBackups(in: directory, prefix: prefix, keep: backupsKept)
        return destination
    }

    nonisolated static func pruneBackups(in directory: URL, prefix: String, keep: Int) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        // Second-stamped names from older builds are shorter and sort first,
        // i.e. oldest — which is the right order to prune them in.
        let backups = names.filter { $0.hasPrefix(prefix) }
            .sorted { ($0.count, $0) < ($1.count, $1) }
        for old in backups.dropLast(keep) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
        }
    }

    /// The shim's single home is `Sources/ClaudePet/Resources/claude-pet-hook.sh`,
    /// shipped as a bundle resource. Reading it rather than duplicating it as a
    /// string literal means the file you can read in the repo is exactly the file
    /// that gets installed.
    ///
    /// Resolved through `ResourceBundle`, never `Bundle.module`: SwiftPM's
    /// generated accessor probes the app's `bundleURL` (beside the .app, where
    /// the bundle has never been) and then an absolute path into the BUILD
    /// machine's scratch directory — and calls `fatalError` when both miss. A
    /// downloaded build died on this exact menu row before the `guard` was
    /// ever evaluated; the machine that could see it was the one machine that
    /// could not. `HookError.missingShim` was always the right answer — the
    /// optional bundle is what finally connects it to its condition.
    static func shimSource() throws -> String {
        guard let bundle = ResourceBundle.resolved,
              let url = bundle.url(forResource: "claude-pet-hook", withExtension: "sh") else {
            throw HookError.missingShim
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    enum HookError: LocalizedError, Equatable {
        case missingShim
        case unreadableSettings(path: String)
        case malformedHooks(String)
        case settingsChangedUnderneath

        var errorDescription: String? {
            switch self {
            case .missingShim:
                "The bundled hook script is missing. Rebuild Claude Pet with ./run.sh."
            case .unreadableSettings(let path):
                "\((path as NSString).abbreviatingWithTildeInPath) is not valid JSON, so it was left untouched rather than overwritten. Fix the JSON and try again."
            case .malformedHooks(let what):
                "settings.json has a `hooks` shape this installer does not understand (\(what)), so it was left untouched."
            case .settingsChangedUnderneath:
                "settings.json changed while the dialog was open — a running Claude Code session probably wrote it. Nothing was written; try again."
            }
        }
    }
}
