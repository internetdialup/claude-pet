import Foundation

/// Reads `~/.claude/sessions/<pid>.json` and reports which Claude Code processes
/// are actually alive.
///
/// Registry files outlive the processes that wrote them — a crashed session
/// leaves its file behind. Liveness therefore needs two checks: the PID must
/// exist, and its start time must still match `procStart`. Without the second
/// check a recycled PID resurrects a dead session and the pet lies.
public enum SessionRegistry {

    /// What one registry file holds. `pid`, `sessionId` and `cwd` are required —
    /// without them there is no session. Everything else is decoded FIELD BY
    /// FIELD with `try?`, so a type change in any one optional costs that field
    /// and not the session.
    ///
    /// 🔎 It was a plain `Decodable` with `String?` optionals, and a
    /// present-but-mistyped optional throws: the day Claude Code turned `name`
    /// or `startedAt` into anything else, every session would have vanished and
    /// the pet would have looked exactly like a quiet desk.
    struct RegistryFile: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let startedAt: Double?     // milliseconds since epoch
        let procStart: String?
        let name: String?
        /// `busy`, `shell`, `waiting` or `idle` — written by Claude Code 2.1.280,
        /// absent from older builds.
        let status: String?
        /// With `waiting`: what for — "permission prompt", "input needed".
        let waitingFor: String?
        let statusUpdatedAt: Double?   // milliseconds since epoch
        /// `interactive`, `bg`, `daemon`, `daemon-worker`.
        let kind: String?
        let spare: Bool?
        /// A parked job carries a `parkedJobId`; its value does not matter.
        let parked: Bool
        let version: String?

        private enum Key: String, CodingKey {
            case pid, sessionId, cwd, startedAt, procStart, name, status, waitingFor,
                 statusUpdatedAt, kind, spare, parkedJobId, version
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            pid = try c.decode(Int32.self, forKey: .pid)
            sessionId = try c.decode(String.self, forKey: .sessionId)
            cwd = try c.decode(String.self, forKey: .cwd)
            startedAt = try? c.decodeIfPresent(Double.self, forKey: .startedAt)
            procStart = try? c.decodeIfPresent(String.self, forKey: .procStart)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            waitingFor = try? c.decodeIfPresent(String.self, forKey: .waitingFor)
            statusUpdatedAt = try? c.decodeIfPresent(Double.self, forKey: .statusUpdatedAt)
            kind = try? c.decodeIfPresent(String.self, forKey: .kind)
            spare = try? c.decodeIfPresent(Bool.self, forKey: .spare)
            parked = c.contains(.parkedJobId)
            version = try? c.decodeIfPresent(String.self, forKey: .version)
        }

        /// Claude Code's own roster keeps interactive and background sessions
        /// and skips spares, parked jobs and daemons — and so does the pet.
        ///
        /// Not "interactive only": that was the first reading, and it would have
        /// hidden real `bg` sessions. A missing kind (older builds, every test
        /// fixture) is kept, and so is an unknown one — failing to see a session
        /// is the worse mistake.
        var belongsOnRoster: Bool {
            if spare == true || parked { return false }
            switch kind {
            case "daemon", "daemon-worker": return false
            default: return true
            }
        }
    }

    /// One registry file, as read.
    public enum Entry: Sendable {
        case session(ClaudeSession)
        /// Readable, but not a live roster session — a dead pid, a spare, a
        /// parked job, a daemon.
        case skipped
        /// Present but unreadable. Usually a torn read — Claude Code truncates
        /// the file and then writes it — which is why a session whose file reads
        /// this way is KEPT, not dropped. If it persists, it is a format.
        case unreadable
    }

    /// Every `*.json` in the registry, keyed by filename.
    public static func scan(in directory: URL = ClaudeHome.sessions) -> [String: Entry] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [:] }

        var result: [String: Entry] = [:]
        for url in entries where url.pathExtension == "json" {
            let filename = url.lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(RegistryFile.self, from: data)
            else { result[filename] = .unreadable; continue }

            guard file.belongsOnRoster, isAlive(pid: file.pid, procStart: file.procStart)
            else { result[filename] = .skipped; continue }

            result[filename] = .session(ClaudeSession(
                id: file.sessionId,
                pid: file.pid,
                name: ActivityCoordinator.displaySafe(
                    file.name ?? URL(fileURLWithPath: file.cwd).lastPathComponent, limit: 80),
                cwd: file.cwd,
                procStart: file.procStart ?? "",
                startedAt: Date(timeIntervalSince1970: (file.startedAt ?? 0) / 1000),
                status: file.status,
                waitingFor: file.waitingFor,
                statusUpdatedAt: file.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                claudeVersion: file.version,
                registryFile: filename
            ))
        }
        return result
    }

    /// Every live session, one per session id — the first by filename wins, so
    /// the choice is stable run to run.
    public static func liveSessions() -> [ClaudeSession] {
        var seen = Set<String>()
        return scan().sorted { $0.key < $1.key }
            .compactMap { entry -> ClaudeSession? in
                if case .session(let session) = entry.value { return session }
                return nil
            }
            .filter { seen.insert($0.id).inserted }
    }

    /// A cheap fingerprint of the registry directory — each file's name,
    /// modification time and size — so the tick can skip a re-read when
    /// nothing moved.
    static func fingerprint(of directory: URL = ClaudeHome.sessions) -> [String: String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return [:] }
        var print: [String: String] = [:]
        for url in entries where url.pathExtension == "json" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            print[url.lastPathComponent] = "\(modified)|\(values?.fileSize ?? -1)"
        }
        return print
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
