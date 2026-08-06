import Foundation

/// Reads `~/.claude/sessions/<pid>.json` and reports which Claude Code processes
/// are actually alive.
///
/// Registry files outlive the processes that wrote them — a crashed session
/// leaves its file behind. Liveness therefore needs two checks: the PID must
/// exist, and its start time must still match `procStart`. Without the second
/// check a recycled PID resurrects a dead session and the pet lies.
public enum SessionRegistry {

    /// The subset of the registry file we depend on.
    private struct RegistryFile: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let startedAt: Double?     // milliseconds since epoch
        let procStart: String?
        let name: String?
    }

    /// Every live session, unsorted.
    public static func liveSessions() -> [ClaudeSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: ClaudeHome.sessions, includingPropertiesForKeys: nil
        ) else { return [] }

        var sessions: [ClaudeSession] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(RegistryFile.self, from: data)
            else { continue }

            guard isAlive(pid: file.pid, procStart: file.procStart) else { continue }

            sessions.append(ClaudeSession(
                id: file.sessionId,
                pid: file.pid,
                name: file.name ?? URL(fileURLWithPath: file.cwd).lastPathComponent,
                cwd: file.cwd,
                procStart: file.procStart ?? "",
                startedAt: Date(timeIntervalSince1970: (file.startedAt ?? 0) / 1000)
            ))
        }
        // A single Claude Code process can be re-registered; keep one per session id.
        var seen = Set<String>()
        return sessions.filter { seen.insert($0.id).inserted }
    }

    /// `kill(pid, 0)` proves *a* process exists; `procStart` proves it is *the*
    /// process. Both must hold.
    public static func isAlive(pid: Int32, procStart: String?) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) != 0 {
            // ESRCH means gone. EPERM means it exists but is not ours, which for
            // our own `claude` processes should not happen — treat as dead.
            return false
        }
        guard let procStart, !procStart.isEmpty else { return true }
        guard let actual = processStartEpoch(pid: pid) else { return true }
        guard let declared = parseProcStart(procStart, actual: actual) else { return true }
        // A second of slack: the kernel records microseconds, the string does not.
        return abs(actual - declared) <= 1.5
    }

    /// Kernel start time for `pid`, in seconds since the epoch.
    static func processStartEpoch(pid: Int32) -> TimeInterval? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return TimeInterval(info.kp_proc.p_starttime.tv_sec)
    }

    /// Parses Claude Code's `procStart` (`ps lstart` style, e.g.
    /// "Thu Aug  6 17:46:31 2026") into an instant.
    ///
    /// The zone is not stated in the string, and on this machine Claude Code
    /// writes it in UTC while `ps` prints local time. Rather than assume either,
    /// try both and accept whichever lands on the process's real start instant —
    /// comparing formatted strings made every live session look dead.
    static func parseProcStart(_ value: String, actual: TimeInterval? = nil) -> TimeInterval? {
        let normalized = normalized(value)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"

        var candidates: [TimeInterval] = []
        for zone in [TimeZone(identifier: "UTC"), TimeZone.current].compactMap({ $0 }) {
            formatter.timeZone = zone
            if let date = formatter.date(from: normalized) {
                candidates.append(date.timeIntervalSince1970)
            }
        }
        guard !candidates.isEmpty else { return nil }
        guard let actual else { return candidates[0] }
        return candidates.min { abs($0 - actual) < abs($1 - actual) }
    }

    /// `ps` pads the day of month with a space ("Aug  6"); collapse whitespace so
    /// parsing is about the instant, not the formatting.
    static func normalized(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
