import Testing
import Foundation
@testable import ClaudePet

/// **The registry, read the way Claude Code writes it now.**
///
/// Claude Code 2.1.280's session registry carries `status` (busy / shell /
/// waiting / idle), `waitingFor`, `statusUpdatedAt`, `kind` and `version` — the
/// things the pet used to infer — and it rewrites each file IN PLACE, which a
/// directory watch cannot hear. Every file here is synthetic, under the scratch
/// `CLAUDE_PET_HOME` or a temp directory — the redline.
@Suite("Session registry, as written today")
struct RegistryScanTests {

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ dir: URL, _ name: String, _ payload: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: payload).write(to: dir.appendingPathComponent(name))
    }

    private func base(_ id: String) -> [String: Any] {
        ["pid": Int(getpid()), "sessionId": id, "cwd": "/tmp/work"]
    }

    @Test("A mistyped optional costs that field, not the session")
    func mistypedOptionalKeepsTheSession() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        var payload = base("typed")
        payload["name"] = ["unexpected": "object"]
        payload["startedAt"] = "not a number"
        try write(dir, "1.json", payload)
        guard case .session(let session)? = SessionRegistry.scan(in: dir)["1.json"] else {
            Issue.record("a mistyped optional dropped the whole session"); return
        }
        #expect(session.id == "typed")
        #expect(session.name == "work", "a name that won't decode falls back to the cwd's")
    }

    @Test("The new fields are read, and the file is remembered")
    func newFieldsAreRead() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        var payload = base("fields")
        payload["status"] = "waiting"
        payload["waitingFor"] = "permission prompt"
        payload["statusUpdatedAt"] = 1_790_000_000_000.0
        payload["version"] = "2.1.280"
        try write(dir, "42.json", payload)
        guard case .session(let session)? = SessionRegistry.scan(in: dir)["42.json"] else {
            Issue.record("the session was not read"); return
        }
        #expect(session.status == "waiting")
        #expect(session.waitingFor == "permission prompt")
        #expect(session.statusUpdatedAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(session.claudeVersion == "2.1.280")
        #expect(session.registryFile == "42.json")
    }

    /// Claude Code's own roster keeps interactive and background sessions and
    /// skips spares, parked jobs and daemons. "Interactive only" was the first
    /// reading, and it would have hidden real `bg` sessions.
    @Test("The roster keeps interactive, bg, missing and unknown kinds, and skips the rest")
    func rosterFilter() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let cases: [(String, [String: Any], Bool)] = [
            ("interactive.json", ["kind": "interactive"], true),
            ("bg.json", ["kind": "bg"], true),
            ("nokind.json", [:], true),
            ("future.json", ["kind": "something-new"], true),
            ("daemon.json", ["kind": "daemon"], false),
            ("worker.json", ["kind": "daemon-worker"], false),
            ("spare.json", ["kind": "bg", "spare": true], false),
            ("parked.json", ["kind": "bg", "parkedJobId": "job-1"], false),
        ]
        for (name, extra, _) in cases {
            try write(dir, name, base(name).merging(extra) { $1 })
        }
        let scan = SessionRegistry.scan(in: dir)
        for (name, _, kept) in cases {
            var isSession = false
            if case .session? = scan[name] { isSession = true }
            #expect(isSession == kept, "\(name) should \(kept ? "be on" : "be off") the roster")
        }
    }

    @Test("An empty or keyless file is unreadable, not a session and not skipped")
    func unreadableFiles() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appendingPathComponent("torn.json"))
        try write(dir, "keyless.json", ["pid": Int(getpid()), "cwd": "/tmp/work"])
        let scan = SessionRegistry.scan(in: dir)
        var torn = false, keyless = false
        if case .unreadable? = scan["torn.json"] { torn = true }
        if case .unreadable? = scan["keyless.json"] { keyless = true }
        #expect(torn, "an empty file — a torn read — must read as unreadable")
        #expect(keyless, "a file with no sessionId must read as unreadable")
    }

    /// The whole `/clear` fix rests on this: the file keeps its name and its
    /// inode, only its contents change, and the fingerprint must notice.
    @Test("An in-place rewrite changes the registry fingerprint")
    func inPlaceRewriteIsNoticed() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        try write(dir, "7.json", base("before-clear"))
        let before = SessionRegistry.fingerprint(of: dir)
        // Same length, so the size alone cannot give it away.
        let handle = try FileHandle(forWritingTo: dir.appendingPathComponent("7.json"))
        Thread.sleep(forTimeInterval: 0.01)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: base("after--clear")))
        try handle.close()
        #expect(SessionRegistry.fingerprint(of: dir) != before,
                "an in-place rewrite went unnoticed — /clear would follow a dead transcript")
    }
}

/// The same registry, through the coordinator. Files go in under the scratch
/// `CLAUDE_PET_HOME` with unique names and are never wiped, and every test runs
/// its registration and adoption in one synchronous main-actor stretch — the
/// `FinaleFixture` discipline, so no other suite can interleave.
@Suite("Session registry, in the coordinator", .serialized)
@MainActor
struct RegistryStatusCoordinatorTests {

    private func payload(_ id: String, status: String? = nil, updated: Date? = nil,
                         waitingFor: String? = nil, cwd: String = "work") -> [String: Any] {
        // FIRST, before anything reads `ClaudeHome.root`. It is a process-wide
        // `static let`: the first read pins it, and the first draft of this
        // file read it here, before the redirect — the root latched onto the
        // real ~/.claude and the fixture's redline precondition trapped the run
        // before a byte was written. The precondition did its job; this is the
        // line that means it never has to.
        _ = FinaleFixture.redirect
        var payload: [String: Any] = [
            "pid": Int(getpid()), "sessionId": id,
            "cwd": ClaudeHome.root.appendingPathComponent(cwd).path,
            "startedAt": Date().timeIntervalSince1970 * 1000, "name": "registry-\(id)",
        ]
        if let status { payload["status"] = status }
        if let updated { payload["statusUpdatedAt"] = updated.timeIntervalSince1970 * 1000 }
        if let waitingFor { payload["waitingFor"] = waitingFor }
        return payload
    }

    /// Writes IN PLACE when the file exists — truncate, then write — because
    /// that is what Claude Code does, and an atomic write (temp file, rename)
    /// would fire the directory watcher and hide the very bug under test.
    private func register(_ file: String, _ payload: [String: Any]) throws {
        _ = FinaleFixture.redirect
        let real = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        precondition(ClaudeHome.root.path != real.path, "the redline: never the real ~/.claude")
        try FileManager.default.createDirectory(at: ClaudeHome.sessions, withIntermediateDirectories: true)
        let url = ClaudeHome.sessions.appendingPathComponent(file)
        let data = try JSONSerialization.data(withJSONObject: payload)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url)
        }
    }

    private func adopt(_ file: String, _ payload: [String: Any]) throws -> ActivityCoordinator {
        try register(file, payload)
        let coordinator = ActivityCoordinator()
        coordinator.start()
        coordinator.stop()
        return coordinator
    }

    private func session(_ coordinator: ActivityCoordinator, _ id: String) -> ClaudeSession? {
        coordinator.state.sessions.first { $0.id == id }
    }

    @Test("busy lifts an idle session to thinking before the first reply lands")
    func busyLiftsIdle() throws {
        let coordinator = try adopt("registry-busy.json", payload("reg-busy", status: "idle"))
        defer { coordinator.stop() }
        #expect(session(coordinator, "reg-busy")?.mood == .idle)
        try register("registry-busy.json", payload("reg-busy", status: "busy", updated: Date()))
        coordinator.refreshSessions()
        #expect(session(coordinator, "reg-busy")?.mood == .thinking)
    }

    @Test("waiting shows as needing you, with what it is waiting for")
    func waitingNeedsYou() throws {
        let coordinator = try adopt("registry-wait.json", payload("reg-wait", status: "busy"))
        defer { coordinator.stop() }
        try register("registry-wait.json",
                     payload("reg-wait", status: "waiting", updated: Date(), waitingFor: "permission prompt"))
        coordinator.refreshSessions()
        let after = session(coordinator, "reg-wait")
        #expect(after?.mood == .needsAttention)
        #expect(after?.activity?.lowercased().contains("permission") == true,
                "the bubble should say what it is waiting for, got \(after?.activity ?? "nil")")
    }

    /// Nothing decays while Claude Code says the session is busy or waiting.
    /// The control session, with no status, decays on the same clock — which
    /// is what proves the hold is doing something.
    @Test("A busy status holds the mood against decay; no status decays as before")
    func busyHoldsAgainstDecay() throws {
        let coordinator = try adopt("registry-hold.json", payload("reg-hold", status: "busy", updated: Date()))
        defer { coordinator.stop() }
        try register("registry-bare.json", payload("reg-bare"))
        coordinator.refreshSessions()
        coordinator.ingest([ActivityEvent(sessionID: "reg-bare", kind: .thinking, timestamp: Date())])
        coordinator.recompute(now: Date().addingTimeInterval(4_000))
        #expect(session(coordinator, "reg-hold")?.mood == .thinking, "a busy session decayed")
        #expect(session(coordinator, "reg-bare")?.mood == .idle, "precondition: without a status it decays")
    }

    /// The wiring only: a turn the transcript never ended is ended by the
    /// registry's idle, with no badge. The rule's edges — stale idles, the grace,
    /// the moods it applies to — are pinned as a pure function in
    /// `RegistryEndsTurnTests`, because advancing a coordinator's clock here races
    /// `MoodDecayTests.withFastDecay`, which shrinks the shared decay limits to
    /// 0.2 s across `await`s. (The first draft asserted a stale control stayed
    /// `.working` at +8 s, and it failed exactly once, in a full parallel run.)
    @Test("An idle registry ends a stalled turn quietly")
    func idleEndsAStalledTurnQuietly() throws {
        let start = Date()
        let coordinator = try adopt("registry-idle.json", payload("reg-idle", status: "busy", updated: start))
        defer { coordinator.stop() }
        coordinator.ingest([ActivityEvent(sessionID: "reg-idle", kind: .toolStarted(name: "Edit", detail: nil),
                                          timestamp: start.addingTimeInterval(1))])
        try register("registry-idle.json", payload("reg-idle", status: "idle", updated: start.addingTimeInterval(2)))
        coordinator.refreshSessions()
        coordinator.recompute(now: start.addingTimeInterval(8))
        let ended = session(coordinator, "reg-idle")
        #expect(ended?.mood == .idle, "a newer idle should end the stalled turn")
        #expect(ended?.completionBadgeAt == nil, "a quiet ending earns no badge")
    }

    @Test("/clear: the same file names a new session, and the old one retires")
    func clearSwapsTheSession() throws {
        let coordinator = try adopt("registry-clear.json", payload("reg-before-clear"))
        defer { coordinator.stop() }
        #expect(session(coordinator, "reg-before-clear") != nil)
        try register("registry-clear.json", payload("reg-after-clear"))
        coordinator.refreshSessions()
        #expect(session(coordinator, "reg-after-clear") != nil, "the new session was not adopted")
        #expect(session(coordinator, "reg-before-clear") == nil, "the old session outlived its /clear")
    }

    @Test("A torn read keeps the session; a deleted file does not")
    func tornReadKeepsTheSession() throws {
        let coordinator = try adopt("registry-torn.json", payload("reg-torn"))
        defer { coordinator.stop() }
        let url = ClaudeHome.sessions.appendingPathComponent("registry-torn.json")
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.close()
        coordinator.refreshSessions()
        #expect(session(coordinator, "reg-torn") != nil, "a file caught mid-rewrite dropped the session")
        try FileManager.default.removeItem(at: url)
        coordinator.refreshSessions()
        #expect(session(coordinator, "reg-torn") == nil, "precondition: a deleted file does retire it")
    }

    @Test("A session whose cwd moves follows it")
    func cwdMoveIsFollowed() throws {
        let coordinator = try adopt("registry-move.json", payload("reg-move", cwd: "work"))
        defer { coordinator.stop() }
        try register("registry-move.json", payload("reg-move", cwd: "work-worktree"))
        coordinator.refreshSessions()
        #expect(session(coordinator, "reg-move")?.cwd.hasSuffix("work-worktree") == true)
    }
}

/// The registry's quiet ending, as the pure rule it is.
@Suite("Registry idle ends a turn")
struct RegistryEndsTurnTests {

    private func session(mood: PetMood, status: String?, idleAt: Date?, workedAt: Date) -> ClaudeSession {
        var session = ClaudeSession(id: "rule", pid: 1, name: "rule", cwd: "/tmp",
                                    procStart: "", startedAt: workedAt)
        session.mood = mood
        session.status = status
        session.statusUpdatedAt = idleAt
        session.lastActivity = workedAt
        return session
    }

    @Test("An idle newer than the work ends the turn once the grace has run")
    func freshIdleEnds() {
        let worked = Date(timeIntervalSince1970: 1_000)
        let s = session(mood: .working, status: "idle", idleAt: worked.addingTimeInterval(1), workedAt: worked)
        let early = ActivityCoordinator.registryEndsTurn(s, now: worked.addingTimeInterval(3))
        let late = ActivityCoordinator.registryEndsTurn(s, now: worked.addingTimeInterval(6))
        #expect(!early, "inside the grace the transcript's own ending still gets its chance")
        #expect(late)
    }

    /// The case the first draft got wrong: an idle stamped BEFORE the latest
    /// work is left over from the last turn, and ending on it would kill the
    /// turn that just began.
    @Test("An idle older than the work never ends a turn")
    func staleIdleNeverEnds() {
        let worked = Date(timeIntervalSince1970: 1_000)
        let s = session(mood: .working, status: "idle", idleAt: worked.addingTimeInterval(-5), workedAt: worked)
        let ends = ActivityCoordinator.registryEndsTurn(s, now: worked.addingTimeInterval(600))
        #expect(!ends)
    }

    @Test("Only a busy-looking turn is ended, and only by idle")
    func onlyBusyTurnsOnlyByIdle() {
        let worked = Date(timeIntervalSince1970: 1_000)
        let later = worked.addingTimeInterval(60)
        for mood in [PetMood.idle, .done, .needsAttention] {
            let ends = ActivityCoordinator.registryEndsTurn(
                session(mood: mood, status: "idle", idleAt: worked.addingTimeInterval(1), workedAt: worked),
                now: later)
            #expect(!ends, "\(mood) is not a turn in progress")
        }
        for status in ["busy", "shell", "waiting", nil] as [String?] {
            let ends = ActivityCoordinator.registryEndsTurn(
                session(mood: .working, status: status, idleAt: worked.addingTimeInterval(1), workedAt: worked),
                now: later)
            #expect(!ends, "status \(status ?? "nil") must not end a turn")
        }
    }
}
