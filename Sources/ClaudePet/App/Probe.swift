import Foundation

/// Prints the `PetState` the pet would be showing right now, then exits.
///
/// Exists so the activity pipeline can be verified against the operator's real
/// sessions without needing a screenshot of the floating window — the sprite is
/// reviewed with `--render-sheet`, and the data is reviewed here. Read-only:
/// this touches nothing under `~/.claude/` except to read (`Bamboo.md` §5).
@MainActor
enum Probe {
    static func run(seconds: Double) {
        let coordinator = ActivityCoordinator()
        coordinator.start()

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        let state = coordinator.state
        print("mood:      \(state.mood.rawValue)")
        print("bubble:    \(state.bubble ?? "—")")
        print("tool:      \(state.tool ?? "—")")
        print("focused:   \(state.focusedSession?.name ?? "—")")
        print("attention: \(state.attentionCount)")
        print("sessions:  \(state.sessions.count)")
        for session in state.sessions {
            let detail = session.activeTaskLabel ?? session.activity ?? session.title ?? "—"
            print("  • \(session.name)  [\(session.mood.rawValue)]  \(session.projectName)")
            print("      \(detail)")
        }
        coordinator.stop()
    }
}
