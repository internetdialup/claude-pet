import Foundation

/// Reads `~/.claude/tasks/<sessionId>/*.json`.
///
/// Claude Code already writes a present-progressive label for the task it is
/// working on (`activeForm`, e.g. "Forking Bamboo doctrine"). That is a better
/// bubble string than anything we could synthesise from tool names, so it wins
/// the preference order in `ActivityCoordinator`.
public enum TaskWatcher {

    private struct TaskFile: Decodable {
        let id: String?
        let subject: String?
        let activeForm: String?
        let status: String?
    }

    /// The `activeForm` (falling back to `subject`) of the in-progress task, or
    /// `nil` when nothing is in progress.
    public static func activeTask(in directory: URL) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return nil }

        // Task files are numbered; lowest id in progress is the current one.
        let tasks = entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (Int, TaskFile)? in
                guard let data = try? Data(contentsOf: url),
                      let task = try? JSONDecoder().decode(TaskFile.self, from: data)
                else { return nil }
                let order = Int(url.deletingPathExtension().lastPathComponent) ?? Int.max
                return (order, task)
            }
            .sorted { $0.0 < $1.0 }

        guard let current = tasks.first(where: { $0.1.status == "in_progress" })?.1 else { return nil }
        return current.activeForm ?? current.subject
    }
}
