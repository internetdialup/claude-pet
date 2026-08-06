import Foundation

/// Canonical locations inside the user's Claude Code home.
///
/// Read-only by default — see the redline in `Bamboo.md` §5. The only permitted
/// writer is `HookInstaller`.
public enum ClaudeHome {
    /// Overridable so tests can point at `Tests/ClaudePetTests/Fixtures/`
    /// instead of the operator's real `~/.claude/`.
    public static let root: URL = {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_PET_HOME"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }()

    public static var sessions: URL { root.appendingPathComponent("sessions") }
    public static var projects: URL { root.appendingPathComponent("projects") }
    public static var tasks: URL { root.appendingPathComponent("tasks") }
    public static var settings: URL { root.appendingPathComponent("settings.json") }
    /// Drop directory the hook shim writes into. The pet watches it.
    public static var events: URL { root.appendingPathComponent("claude-pet-events") }
}
