import Foundation

/// Prints the `PetState` the pet would be showing right now, then exits.
///
/// Exists so the activity pipeline can be verified against the operator's real
/// sessions without needing a screenshot of the floating window — the sprite is
/// reviewed with `--render-sheet`, and the data is reviewed here. Read-only:
/// this touches nothing under `~/.claude/` except to read — that is the redline.
@MainActor
enum Probe {
    /// A duration off the command line, or nil for anything a probe cannot
    /// honour. `Double` parses "nan", "inf" and "1e30" perfectly happily, so
    /// the check has to live where the string becomes a number — the only
    /// place still holding both what was typed and whether anything was. An
    /// hour is longer than any probe anyone means and short of everything
    /// that overflows on the way to a frame count.
    nonisolated static func clampedDuration(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite, value > 0 else { return nil }
        return min(value, 3600)
    }

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
        for session in state.sessions where session.subagentCount > 0 || session.awaitingApproval {
            print("  ! \(session.name): agents=\(session.subagentCount) "
                  + "awaitingApproval=\(session.awaitingApproval) "
                  + "toolsIn60s=\(session.recentToolCalls.count)")
        }
        for session in state.sessions {
            let detail = session.activeTaskLabel ?? session.activity ?? session.title ?? "—"
            print("  • \(session.name)  [\(session.mood.rawValue)]  \(session.projectName)")
            print("      \(detail)")
        }
        coordinator.stop()
    }
}
