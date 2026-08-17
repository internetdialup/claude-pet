import Foundation
import AppKit

/// The **only** code path in this app permitted to write inside `~/.claude/`
/// — the redline. Every guarantee of it is enforced here:
/// user-initiated, shows the exact change, backs up first, merges only `hooks`.
@MainActor
public enum HookInstaller {

    /// Events the pet subscribes to. `Notification` is the only source of
    /// permission-prompt awareness — the transcript does not record it.
    static let events = ["PreToolUse", "PostToolUse", "Stop", "SessionEnd", "Notification"]

    public static var scriptURL: URL {
        // Installed next to the app's support data so the hook keeps working if
        // the .app is moved.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Preferences.suiteName)
            .appendingPathComponent("claude-pet-hook.sh")
    }

    public static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: ClaudeHome.settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any]
        else { return false }
        return hooks.keys.contains { events.contains($0) }
            && FileManager.default.fileExists(atPath: scriptURL.path)
    }

    /// Show the operator exactly what will change, then apply it on approval.
    public static func promptAndInstall() {
        let alert = NSAlert()
        alert.messageText = isInstalled ? "Reinstall Claude Pet hooks?" : "Install Claude Pet hooks?"
        alert.informativeText = """
        This adds a `hooks` entry to:
          \(ClaudeHome.settings.path)

        for the events: \(events.joined(separator: ", ")).

        Each hook runs:
          \(scriptURL.path)
        which appends one small JSON file to \(ClaudeHome.events.path) and always \
        exits 0, so it can never block or slow a Claude session.

        Your existing settings.json is copied to settings.json.bak.<timestamp> \
        first, and only the `hooks` key is modified.

        Without hooks the pet still works by watching files — it just reacts a \
        little slower and cannot detect permission prompts.
        """
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
            let backupLine = backup.map { "\n\nBackup saved at:\n  \($0.path)" }
                ?? "\n\nThere was no existing settings.json, so no backup was needed."
            done.informativeText = """
            Wrote hook script to:
              \(scriptURL.path)

            Updated:
              \(ClaudeHome.settings.path)\(backupLine)

            Restart your Claude Code sessions to pick the hooks up.
            """
            done.runModal()
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "Hook installation failed"
            failure.informativeText = "\(error.localizedDescription)\n\nNothing was changed."
            failure.runModal()
        }
    }

    /// - Returns: the absolute path of the backup that was written, or nil when
    ///   there was no existing `settings.json` to back up (Durability Honesty —
    ///   never name a path that was not written).
    @discardableResult
    static func install() throws -> URL? {
        let fm = FileManager.default

        // 1. Write the shim.
        // Resolve the shim before touching anything, so a missing resource fails
        // before settings.json has been modified.
        let shim = try shimSource()
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: ClaudeHome.events, withIntermediateDirectories: true)
        try shim.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // 2. Back up settings.json before touching it. `backup` stays nil when
        //    there was no file to copy, so the success dialog never names a
        //    path that does not exist (Durability Honesty).
        var backup: URL?
        var root: [String: Any] = [:]

        if fm.fileExists(atPath: ClaudeHome.settings.path) {
            let destination = ClaudeHome.root.appendingPathComponent(
                "settings.json.bak.\(Int(Date().timeIntervalSince1970))"
            )
            try fm.copyItem(at: ClaudeHome.settings, to: destination)
            backup = destination

            let data = try Data(contentsOf: ClaudeHome.settings)
            // Refuse rather than reset. Falling back to an empty dictionary here
            // meant an unparseable settings.json was silently REPLACED by a
            // hooks-only file, destroying statusLine, theme, plugins and
            // permissions. A backup existing is not an excuse for doing that.
            guard let parsed = try? JSONSerialization.jsonObject(with: data),
                  let object = parsed as? [String: Any] else {
                throw HookError.unreadableSettings(backup: destination)
            }
            root = object
        }

        // 3. Merge only the `hooks` key, preserving any hooks already there.
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command: [String: Any] = ["type": "command", "command": "\"\(scriptURL.path)\""]
        for event in events {
            var matchers = hooks[event] as? [[String: Any]] ?? []
            matchers.removeAll { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
                return inner.contains { ($0["command"] as? String)?.contains("claude-pet-hook") == true }
            }
            matchers.append(["hooks": [command]])
            hooks[event] = matchers
        }
        root["hooks"] = hooks

        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: ClaudeHome.settings, options: .atomic)
        return backup
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

    enum HookError: LocalizedError {
        case missingShim
        case unreadableSettings(backup: URL)

        var errorDescription: String? {
            switch self {
            case .missingShim:
                "The bundled hook script is missing. Rebuild Claude Pet with ./run.sh."
            case .unreadableSettings(let backup):
                """
                \(ClaudeHome.settings.path) is not valid JSON, so it was left untouched \
                rather than overwritten. A copy was made at \(backup.path). Fix the JSON \
                and try again.
                """
            }
        }
    }
}
