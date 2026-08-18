import Testing
import Foundation
@testable import ClaudePet

/// The service-glyph classifier: pure string work, no fixtures, no isolation.
@Suite("Service glyph classifier")
struct ServiceGlyphClassifierTests {

    @Test("Each family's commands land on their glyph")
    func familiesClassify() {
        let table: [(String, ServiceGlyph?)] = [
            ("npm install", .npm),
            ("npm run build", .npm),
            ("yarn add left-pad", .npm),
            ("pnpm i", .npm),
            ("bun test", .npm),
            ("git push origin main", .github),
            ("git push --force origin main debug/preview-tools", .github),
            ("gh pr create --fill", .github),
            ("gh release view v1.4.0", .github),
            ("gh repo clone x/y", .github),
            ("vercel deploy --prod", .deploy),
            ("docker build -t pet .", .deploy),
            ("docker push registry/pet", .deploy),
            ("fly deploy", .deploy),
            ("flyctl deploy", .deploy),
            // The boundaries: near misses stay dark.
            ("git commit -m 'ship it'", nil),
            ("git pull --rebase", nil),
            ("docker run -it ubuntu", nil),
            ("ls -la", nil),
            ("swift build", nil),
        ]
        for (command, expected) in table {
            #expect(ServiceGlyph.classify(tool: "Bash", command: command) == expected,
                    "\(command) → \(String(describing: expected))")
        }
    }

    @Test("Compound commands follow precedence: github > deploy > npm")
    func compoundPrecedence() {
        #expect(ServiceGlyph.classify(tool: "Bash", command: "npm run build && git push") == .github)
        #expect(ServiceGlyph.classify(tool: "Bash", command: "docker build . && npm ci") == .deploy)
        #expect(ServiceGlyph.classify(tool: "Bash", command: "yarn build && vercel deploy") == .deploy)
    }

    @Test("Case never matters")
    func caseInsensitive() {
        #expect(ServiceGlyph.classify(tool: "Bash", command: "NPM INSTALL") == .npm)
        #expect(ServiceGlyph.classify(tool: "Bash", command: "Git Push origin main") == .github)
    }

    @Test("Linear rides the MCP tool name — and the UUID slug is a documented miss")
    func linearByName() {
        #expect(ServiceGlyph.classify(tool: "mcp__linear__save_issue", command: nil) == .linear)
        #expect(ServiceGlyph.classify(tool: "mcp__Linear__list_issues", command: nil) == .linear)
        // claude.ai connectors slug by UUID; there is nothing to recognise.
        #expect(ServiceGlyph.classify(tool: "mcp__01a88bab-d470__save_issue", command: nil) == nil)
        // A non-MCP tool never claims linear, whatever its name says.
        #expect(ServiceGlyph.classify(tool: "LinearThing", command: nil) == nil)
    }

    @Test("Toolcalls with nothing to say stay dark")
    func quietTools() {
        #expect(ServiceGlyph.classify(tool: "Read", command: nil) == nil)
        #expect(ServiceGlyph.classify(tool: "Bash", command: nil) == nil)
        #expect(ServiceGlyph.classify(tool: "Bash", command: "") == nil)
    }
}

/// The latch on the session: stamped by ingest, renewed by matches, bridged
/// across the thinking beat, retired by the landing or the linger.
///
/// Registry fixtures ride `FinaleFixture`'s add-only idiom — a scratch
/// `CLAUDE_PET_HOME`, never the real `~/.claude/` (the redline).
@Suite("Service glyph latch", .serialized)
@MainActor
struct ServiceGlyphLatchTests {

    private func quietCoordinator(_ ids: [String]) throws -> ActivityCoordinator {
        try FinaleFixture.register(ids)
        let coordinator = ActivityCoordinator()
        coordinator.start()
        coordinator.stop()
        return coordinator
    }

    private func session(_ coordinator: ActivityCoordinator, _ id: String) throws -> ClaudeSession {
        try #require(coordinator.state.sessions.first { $0.id == id }, "session \(id) missing")
    }

    @Test("The stamp survives the thinking beat and unmatched tools, and renews on a match")
    func latchLifecycle() throws {
        let id = "glyph-lifecycle"
        let coordinator = try quietCoordinator([id])
        let start = Date()

        coordinator.ingest([ActivityEvent(
            sessionID: id,
            kind: .toolStarted(name: "Bash", detail: "Install deps", command: "npm install"),
            timestamp: start)])
        #expect(try session(coordinator, id).serviceGlyph == .npm)
        #expect(coordinator.state.serviceGlyph == .npm, "the state mirrors the focused session")

        // The pause between commands, and a tool that says nothing about
        // services: the glyph holds, the stamp does not move.
        coordinator.ingest([
            ActivityEvent(sessionID: id, kind: .toolFinished(name: "Bash")),
            ActivityEvent(sessionID: id, kind: .thinking),
            ActivityEvent(sessionID: id, kind: .toolStarted(name: "Read", detail: "package.json")),
        ])
        let held = try session(coordinator, id)
        #expect(held.serviceGlyph == .npm)
        #expect(held.serviceGlyphAt == start, "an unmatched tool must not renew the stamp")

        // A fresh match renews; a different family replaces.
        let pushAt = start.addingTimeInterval(1)
        coordinator.ingest([ActivityEvent(
            sessionID: id,
            kind: .toolStarted(name: "Bash", detail: nil, command: "git push origin main"),
            timestamp: pushAt)])
        let flipped = try session(coordinator, id)
        #expect(flipped.serviceGlyph == .github)
        #expect(flipped.serviceGlyphAt == pushAt)

        // The landing retires it with the sprint.
        coordinator.ingest([ActivityEvent(sessionID: id, kind: .turnEnded)])
        #expect(try session(coordinator, id).serviceGlyph == nil)
        #expect(coordinator.state.serviceGlyph == nil)
    }

    @Test("The linger expires a glyph nothing renews")
    func lingerExpires() throws {
        let id = "glyph-linger"
        let coordinator = try quietCoordinator([id])

        let linger = ActivityCoordinator.serviceGlyphLinger
        ActivityCoordinator.serviceGlyphLinger = 0.2
        defer { ActivityCoordinator.serviceGlyphLinger = linger }

        // Stamped just inside the shrunken linger: alive.
        coordinator.ingest([ActivityEvent(
            sessionID: id,
            kind: .toolStarted(name: "Bash", detail: nil, command: "yarn build"),
            timestamp: Date())])
        #expect(try session(coordinator, id).serviceGlyph == .npm)

        // Any recomputation past the linger clears it.
        Thread.sleep(forTimeInterval: 0.3)
        coordinator.ingest([ActivityEvent(sessionID: "not-a-session", kind: .title("tick"))])
        #expect(try session(coordinator, id).serviceGlyph == nil,
                "an unrenewed glyph must not outlive its linger")
    }

    @Test("The priming replay shows no archaeology")
    func primingStaysDark() throws {
        let id = "glyph-priming"
        let coordinator = try quietCoordinator([id])

        // A push from a minute ago, as the launch replay would deliver it:
        // stamped with event time, aged out by the same ingest's recompute.
        coordinator.ingest([ActivityEvent(
            sessionID: id,
            kind: .toolStarted(name: "Bash", detail: nil, command: "git push origin main"),
            timestamp: Date().addingTimeInterval(-60))], suppressAlerts: true)
        #expect(try session(coordinator, id).serviceGlyph == nil,
                "a stale stamp must age out in the ingest that made it")
    }
}
