import Testing
import Foundation
@testable import ClaudePet

@Suite("Session identity")
struct SessionTests {

    /// Encoding rule verified against the real directory names Claude Code
    /// creates under `~/.claude/projects/`. The fixture uses a synthetic path:
    /// this repo is public, and a test is a poor place to publish someone's
    /// username and machine name.
    ///
    /// It still exercises the awkward parts of a real path — a space-hyphen-space
    /// run collapsing to three dashes, and a curly apostrophe.
    @Test("cwd encodes to Claude Code's project directory name")
    func projectDirectoryEncoding() {
        let cwd = "/Users/dev/Documents/Documents - Dev’s Laptop/Git/claude-pet"
        #expect(ClaudeSession.encodeProjectDirectory(cwd)
                == "-Users-dev-Documents-Documents---Dev-s-Laptop-Git-claude-pet")
    }

    @Test("Spaces, dots and punctuation all collapse to dashes")
    func encodingEdgeCases() {
        #expect(ClaudeSession.encodeProjectDirectory("/a/b.c") == "-a-b-c")
        #expect(ClaudeSession.encodeProjectDirectory("/x/My Project!") == "-x-My-Project-")
    }

    /// Formats this process's real start time the way Claude Code does, in a
    /// given zone.
    private func procStartString(pid: Int32, zone: TimeZone) -> String? {
        guard let epoch = SessionRegistry.processStartEpoch(pid: pid) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        formatter.timeZone = zone
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }

    /// Regression: Claude Code writes `procStart` in **UTC** while `ps` prints
    /// local time. Comparing formatted strings made every live session on a
    /// non-UTC machine look dead, and the pet reported zero sessions while ten
    /// were running.
    @Test("procStart is accepted whether written in UTC or local time")
    func livenessAcrossTimeZones() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let utc = try #require(procStartString(pid: pid, zone: TimeZone(identifier: "UTC")!))
        let local = try #require(procStartString(pid: pid, zone: .current))

        #expect(SessionRegistry.isAlive(pid: pid, procStart: utc))
        #expect(SessionRegistry.isAlive(pid: pid, procStart: local))
    }

    @Test("A missing or empty procStart falls back to the PID check alone")
    func livenessWithoutStartTime() {
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(SessionRegistry.isAlive(pid: pid, procStart: nil))
        #expect(SessionRegistry.isAlive(pid: pid, procStart: ""))
    }

    /// The PID-reuse guard. Without the `procStart` comparison a stale registry
    /// file whose PID has been recycled would resurrect a dead session.
    @Test("A live PID with a mismatched start time counts as dead")
    func pidReuseIsRejected() {
        let pid = ProcessInfo.processInfo.processIdentifier
        #expect(SessionRegistry.isAlive(pid: pid, procStart: "Thu Jan  1 00:00:00 1970") == false)
    }

    @Test("An impossible PID is dead")
    func deadPID() {
        #expect(SessionRegistry.isAlive(pid: 999_999, procStart: nil) == false)
        #expect(SessionRegistry.isAlive(pid: 0, procStart: nil) == false)
    }

    @Test("ps-style padded dates compare equal to single-spaced ones")
    func startTimeNormalisation() {
        #expect(SessionRegistry.normalized("Thu Aug  6 17:46:31 2026")
                == SessionRegistry.normalized("Thu Aug 6 17:46:31 2026"))
    }
}

@Suite("Dock magnetism")
struct DockMagnetTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 220, height: 190)

    @Test("Near the left edge, snaps flush left")
    func snapsLeft() {
        let result = DockMagnet.snap(origin: CGPoint(x: 30, y: 400), size: size, visibleFrame: screen)
        #expect(result.x == screen.minX)
    }

    @Test("Near the right edge, snaps flush right")
    func snapsRight() {
        let result = DockMagnet.snap(origin: CGPoint(x: 1190, y: 400), size: size, visibleFrame: screen)
        #expect(result.x == screen.maxX - size.width)
    }

    @Test("Near the bottom, snaps down onto the dock line")
    func snapsBottom() {
        let result = DockMagnet.snap(origin: CGPoint(x: 600, y: 20), size: size, visibleFrame: screen)
        #expect(result.y == screen.minY)
    }

    @Test("Mid-screen is left alone")
    func noSnapInTheMiddle() {
        let origin = CGPoint(x: 600, y: 400)
        let result = DockMagnet.snap(origin: origin, size: size, visibleFrame: screen)
        #expect(result == origin)
    }

    @Test("An off-screen origin is clamped back into view")
    func clampsOffscreen() {
        let result = DockMagnet.clamp(origin: CGPoint(x: -500, y: 5000), size: size, visibleFrame: screen)
        #expect(result.x == screen.minX)
        #expect(result.y == screen.maxY - size.height)
    }

    /// A bottom dock shows up as a bottom inset on `visibleFrame`; the menu bar's
    /// top inset must not be mistaken for it.
    @Test("A bottom dock is detected, and the menu bar is not")
    func detectsBottomDock() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)  // 70pt dock, 30pt menu bar
        let (edge, thickness) = DockMagnet.dockEdge(frame: frame, visibleFrame: visible)
        #expect(edge == .bottom)
        #expect(thickness == 70)
    }

    @Test("A left dock is detected")
    func detectsLeftDock() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 80, y: 0, width: 1360, height: 870)
        let (edge, thickness) = DockMagnet.dockEdge(frame: frame, visibleFrame: visible)
        #expect(edge == .left)
        #expect(thickness == 80)
    }
}

@Suite("Hook payload parsing")
struct HookParsingTests {

    @Test("PreToolUse becomes a toolStarted with its description")
    func preToolUse() throws {
        let json = """
        {"session_id":"S1","hook_event_name":"PreToolUse","tool_name":"Bash",
         "tool_input":{"command":"ls","description":"List files"}}
        """
        let event = try #require(HookServer.parse(Data(json.utf8)))
        #expect(event.sessionID == "S1")
        guard case .toolStarted(let name, let detail) = event.kind else {
            Issue.record("expected toolStarted"); return
        }
        #expect(name == "Bash")
        #expect(detail == "List files")
    }

    @Test("Notification becomes needsAttention carrying the message")
    func notification() throws {
        let json = """
        {"session_id":"S2","hook_event_name":"Notification","message":"Claude needs your permission"}
        """
        let event = try #require(HookServer.parse(Data(json.utf8)))
        guard case .needsAttention(let reason) = event.kind else {
            Issue.record("expected needsAttention"); return
        }
        #expect(reason == "Claude needs your permission")
    }

    @Test("Stop becomes turnEnded")
    func stop() throws {
        let json = #"{"session_id":"S3","hook_event_name":"Stop"}"#
        let event = try #require(HookServer.parse(Data(json.utf8)))
        guard case .turnEnded = event.kind else { Issue.record("expected turnEnded"); return }
    }

    @Test("Unknown and malformed payloads are dropped, not guessed at")
    func unknownPayloads() {
        #expect(HookServer.parse(Data(#"{"session_id":"S","hook_event_name":"PreCompact"}"#.utf8)) == nil)
        #expect(HookServer.parse(Data(#"{"hook_event_name":"Stop"}"#.utf8)) == nil)
        #expect(HookServer.parse(Data("not json".utf8)) == nil)
    }
}

@Suite("Bubble text")
struct CondenseTests {
    @Test("Short text passes through untouched")
    func shortText() {
        #expect(ActivityCoordinator.condense("List files") == "List files")
    }

    @Test("Long text is truncated with an ellipsis inside the limit")
    func longText() {
        let result = ActivityCoordinator.condense(String(repeating: "a", count: 200), limit: 20)
        #expect(result.count == 20)
        #expect(result.hasSuffix("…"))
    }

    @Test("Newlines in shell commands collapse to a single line")
    func multiline() {
        #expect(ActivityCoordinator.condense("git add .\ngit commit") == "git add . git commit")
    }
}
