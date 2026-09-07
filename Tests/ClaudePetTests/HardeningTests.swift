import Testing
import Foundation
@testable import ClaudePet

/// The hardening round's contracts, every one against a temp directory —
/// nothing here touches the operator's `~/.claude`.
///
/// `HookInstaller.install()` is the only code in the app permitted to write past
/// the redline, and until this file it had zero tests: the merge was inline,
/// every path was hard-wired, and the shim came from a bundle `swift test`
/// cannot resolve. The bug it once shipped — an unparseable settings.json
/// silently REPLACED by a hooks-only file — is exactly the class these pin.
@Suite("Hook installer", .serialized)
@MainActor
struct HookInstallerTests {

    private struct Home {
        let root: URL
        var settings: URL { root.appendingPathComponent("settings.json") }
        var script: URL { root.appendingPathComponent("support/claude-pet-hook.sh") }
        var events: URL { root.appendingPathComponent("claude-pet-events") }
        static func make() throws -> Home {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("hook-installer-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return Home(root: root)
        }
        func write(_ json: String) throws { try Data(json.utf8).write(to: settings) }
        func read() throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        }
        func backups() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix("settings.json.bak.") }.sorted()
        }
    }

    private let shim = "#!/bin/sh\nexit 0\n"

    /// Every group in `hooks[event]`, flattened to its command strings.
    private func commands(_ root: [String: Any], _ event: String) -> [String] {
        let groups = (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
    }

    @Test("Foreign keys and foreign hooks survive; ours lands once per event")
    func foreignSurvives() throws {
        let home = try Home.make()
        try home.write("""
        {"theme":"dark","statusLine":{"type":"command","command":"~/bin/status"},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"say hi"}]}],
                  "PreCompact":[{"hooks":[{"type":"command","command":"echo compact"}]}]}}
        """)
        let backup = try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script,
                                               eventsURL: home.events, shim: shim)
        let root = try home.read()
        #expect(root["theme"] as? String == "dark")
        #expect((root["statusLine"] as? [String: Any])?["command"] as? String == "~/bin/status")
        #expect(commands(root, "PreToolUse") == ["say hi", "\"\(home.script.path)\""])
        #expect(commands(root, "PreCompact") == ["echo compact"], "an event we do not subscribe to is untouched")
        for event in HookInstaller.events {
            #expect(commands(root, event).filter { $0.contains("claude-pet-hook") }.count == 1,
                    Comment(rawValue: event))
        }
        #expect(backup != nil)
        #expect(HookInstaller.isInstalled(settingsURL: home.settings, scriptURL: home.script))
        #expect(FileManager.default.fileExists(atPath: home.events.path))
    }

    @Test("Installing twice leaves exactly one entry of ours per event")
    func idempotent() throws {
        let home = try Home.make()
        try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script, eventsURL: home.events, shim: shim)
        try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script, eventsURL: home.events, shim: shim)
        let root = try home.read()
        for event in HookInstaller.events {
            #expect(commands(root, event).count == 1, "\(event) has \(commands(root, event).count) entries")
        }
    }

    @Test("Invalid JSON is refused: nothing written, no backup, no shim")
    func refusesRatherThanResets() throws {
        let home = try Home.make()
        try home.write("{not json")
        let before = try Data(contentsOf: home.settings)
        #expect(throws: HookInstaller.HookError.self) {
            try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script,
                                      eventsURL: home.events, shim: shim)
        }
        #expect(try Data(contentsOf: home.settings) == before, "the bytes must be untouched")
        #expect(try home.backups().isEmpty, "nothing was going to change, so nothing is backed up")
        #expect(!FileManager.default.fileExists(atPath: home.script.path), "the shim is written after the parse")
    }

    @Test("A wrong-shaped hooks key is refused, not overwritten")
    func refusesMalformedHooks() throws {
        let home = try Home.make()
        try home.write(#"{"hooks":"nope"}"#)
        let before = try Data(contentsOf: home.settings)
        #expect(throws: HookInstaller.HookError.self) {
            try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script,
                                      eventsURL: home.events, shim: shim)
        }
        #expect(try Data(contentsOf: home.settings) == before)
        #expect(throws: HookInstaller.HookError.self) {
            _ = try HookInstaller.merged(into: ["hooks": ["PreToolUse": "nope"]], command: "x")
        }
    }

    @Test("No settings.json: a hooks-only file, no backup, an executable shim, no escaped slashes")
    func freshInstall() throws {
        let home = try Home.make()
        let backup = try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script,
                                               eventsURL: home.events, shim: shim)
        #expect(backup == nil, "never name a backup that was not written")
        let text = try String(contentsOf: home.settings, encoding: .utf8)
        #expect(!text.contains("\\/"), "slashes are not escaped — the file must stay readable by a human")
        // JSON escapes the quotes around the path, so compare the parsed value.
        #expect(commands(try home.read(), "Stop") == ["\"\(home.script.path)\""],
                "the command is the quoted script path")
        let mode = try FileManager.default.attributesOfItem(atPath: home.script.path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(try String(contentsOf: home.script, encoding: .utf8) == shim)
    }

    @Test("Backups are millisecond-stamped, never collide, and only the newest five survive")
    func backupsArePruned() throws {
        let home = try Home.make()
        try home.write("{}")
        for _ in 0..<7 {
            try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script,
                                      eventsURL: home.events, shim: shim)
        }
        #expect(try home.backups().count == HookInstaller.backupsKept)
    }

    @Test("Uninstall removes only ours, drops emptied arrays, and cleans up")
    func uninstallIsSurgical() throws {
        let home = try Home.make()
        try home.write("""
        {"theme":"dark","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"say hi"}]}]}}
        """)
        try HookInstaller.install(settingsURL: home.settings, scriptURL: home.script, eventsURL: home.events, shim: shim)
        let backup = try HookInstaller.uninstall(settingsURL: home.settings, scriptURL: home.script, eventsURL: home.events)
        let root = try home.read()
        #expect(root["theme"] as? String == "dark")
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(commands(root, "PreToolUse") == ["say hi"], "the foreign hook stays")
        #expect(hooks["Stop"] == nil && hooks["Notification"] == nil, "events that held only ours are gone")
        #expect(backup != nil)
        #expect(!FileManager.default.fileExists(atPath: home.script.path))
        #expect(!FileManager.default.fileExists(atPath: home.events.path))
        #expect(!HookInstaller.isInstalled(settingsURL: home.settings, scriptURL: home.script))
    }

    @Test("A foreign hook sharing our matcher group is kept when ours is stripped")
    func sharedGroupKeepsTheStranger() {
        let groups: [[String: Any]] = [
            ["matcher": "Bash", "hooks": [["type": "command", "command": "/x/claude-pet-hook.sh"],
                                          ["type": "command", "command": "notify"]]],
            ["hooks": [["type": "command", "command": "/x/claude-pet-hook.sh"]]],
            ["hooks": []],
        ]
        let kept = HookInstaller.stripped(groups)
        #expect(kept.count == 2, "the group that was only ours goes; the shared one and the empty one stay")
        let first = kept[0]["hooks"] as? [[String: Any]]
        #expect(first?.count == 1 && first?[0]["command"] as? String == "notify")
    }

    @Test("Uninstall with no settings file still removes the shim and the drop directory")
    func uninstallWithoutSettings() throws {
        let home = try Home.make()
        try FileManager.default.createDirectory(at: home.script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(shim.utf8).write(to: home.script)
        try FileManager.default.createDirectory(at: home.events, withIntermediateDirectories: true)
        let backup = try HookInstaller.uninstall(settingsURL: home.settings, scriptURL: home.script, eventsURL: home.events)
        #expect(backup == nil)
        #expect(!FileManager.default.fileExists(atPath: home.script.path))
        #expect(!FileManager.default.fileExists(atPath: home.events.path))
    }
}

/// The drop directory: whole payloads, deleted on read — and never a read the
/// redline would call unbounded.
@Suite("Hook server", .serialized)
struct HookServerTests {

    private func events() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-events-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ActivityEvent] = []
        func add(_ new: [ActivityEvent]) { lock.lock(); items += new; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
    }

    @Test("An oversized event file is deleted unread; a normal one is delivered and deleted")
    func sizeCap() throws {
        let dir = try events()
        let box = Box()
        let server = HookServer(events: dir) { box.add($0) }
        let big = dir.appendingPathComponent("1-1-1.json")
        let padding = String(repeating: "x", count: HookServer.maxEventBytes + 1024)
        try Data("{\"session_id\":\"S\",\"hook_event_name\":\"Stop\",\"pad\":\"\(padding)\"}".utf8).write(to: big)
        let small = dir.appendingPathComponent("2-2-2.json")
        try Data("{\"session_id\":\"S\",\"hook_event_name\":\"Stop\"}".utf8).write(to: small)

        server.drainNow()

        #expect(box.count == 1, "only the small event is delivered")
        #expect(!FileManager.default.fileExists(atPath: big.path), "the oversized file is removed, never parsed")
        #expect(!FileManager.default.fileExists(atPath: small.path), "the delivered file is consumed")
    }

    @Test("The bubble's fallback detail never carries the home directory")
    func homeIsAbbreviated() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let json = #"{"session_id":"S","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cd HOME/Code && swift build"}}"#
            .replacingOccurrences(of: "HOME", with: home)
        let event = try #require(HookServer.parse(Data(json.utf8)))
        guard case .toolStarted(_, let detail, let command) = event.kind else { Issue.record("wrong kind"); return }
        #expect(detail == "cd ~/Code && swift build")
        #expect(command?.hasPrefix("cd \(home)") == true, "the raw command stays on the event for the classifier")
    }
}

/// The small clamps and sanitisers.
@Suite("Display and input hygiene")
struct DisplayHygieneTests {

    @Test("A usage percentage is finite and inside 0…100, or it is not shown")
    func percentClamp() {
        #expect(StatusTicker.percent(42.4) == 42)
        #expect(StatusTicker.percent(0) == 0 && StatusTicker.percent(100) == 100)
        #expect(StatusTicker.percent(1e300) == nil, "Int(1e300) would trap the process")
        #expect(StatusTicker.percent(-1e300) == nil)
        #expect(StatusTicker.percent(250) == nil)
        #expect(StatusTicker.percent(.nan) == nil && StatusTicker.percent(.infinity) == nil)
        #expect(StatusTicker.percent(nil) == nil)
    }

    @Test("A cache with no timestamp is not fresh")
    func noTimestampIsStale() {
        let cache = StatusTicker.UsageCache(writtenAt: nil, fiveHourPercent: 10, sevenDayPercent: nil, contextUsedPercent: nil)
        #expect(!StatusTicker.isFresh(cache, now: Date()))
        let stamped = StatusTicker.UsageCache(writtenAt: Date().timeIntervalSince1970, fiveHourPercent: 10,
                                              sevenDayPercent: nil, contextUsedPercent: nil)
        #expect(StatusTicker.isFresh(stamped, now: Date()))
    }

    @Test("Control, format and separator characters never reach a screen surface")
    func displaySafe() {
        func safe(_ raw: String) -> String { ActivityCoordinator.displaySafe(raw) }
        #expect(safe("main\u{202E}evil") == "main evil", "a bidi override becomes a space")
        #expect(safe("a\u{200B}b") == "a b", "a zero-width space becomes a space")
        #expect(safe("line\u{2028}line\u{2029}line") == "line line line")
        #expect(safe("cr\r\nlf\ttab") == "cr lf tab")
        #expect(safe("  padded   out  ") == "padded out", "runs collapse and the ends are trimmed")
        #expect(ActivityCoordinator.displaySafe(String(repeating: "x", count: 500), limit: 80).count == 80)
        // The old condense contract still holds.
        #expect(ActivityCoordinator.condense("git add .\ngit commit") == "git add . git commit")
    }

    @Test("The home directory becomes ~ wherever it appears")
    func abbreviatingHome() {
        #expect(PathDisplay.abbreviatingHome("cd /Users/dev/Code && ls /Users/dev/x", home: "/Users/dev")
                == "cd ~/Code && ls ~/x")
        #expect(PathDisplay.abbreviatingHome("/opt/thing", home: "/Users/dev") == "/opt/thing")
        #expect(PathDisplay.abbreviatingHome("/x/y", home: "/") == "/x/y", "a root home abbreviates nothing")
    }

    @Test("An unchanged journal is counted from the memo, not parsed again")
    func journalCache() throws {
        let workflows = FileManager.default.temporaryDirectory
            .appendingPathComponent("workflows-\(UUID().uuidString)")
        let run = workflows.appendingPathComponent("wf_1")
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        let journal = run.appendingPathComponent("journal.jsonl")
        try Data("{\"type\":\"started\"}\n{\"type\":\"started\"}\n{\"type\":\"result\"}\n".utf8).write(to: journal)
        let cache = WorkloadWatcher.JournalCache()
        let now = Date()
        #expect(WorkloadWatcher.workflowAgentsInFlight(workflows: workflows, now: now, cache: cache) == 1)
        #expect(WorkloadWatcher.workflowAgentsInFlight(workflows: workflows, now: now, cache: cache) == 1)
        #expect(cache.parses == 1, "the second tick must not re-parse an unchanged journal")
        try Data("{\"type\":\"started\"}\n{\"type\":\"started\"}\n{\"type\":\"result\"}\n{\"type\":\"started\"}\n".utf8)
            .write(to: journal)
        #expect(WorkloadWatcher.workflowAgentsInFlight(workflows: workflows, now: now, cache: cache) == 2)
        #expect(cache.parses == 2, "a changed journal is parsed once more")
    }
}
