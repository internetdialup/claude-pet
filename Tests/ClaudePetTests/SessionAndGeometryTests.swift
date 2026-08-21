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

    @Test("Two pets snapped to one corner de-stack along the edge")
    func snapDeStacks() {
        // Pet 1 already owns the bottom-right corner.
        let occupied = CGRect(x: screen.maxX - size.width, y: screen.minY,
                              width: size.width, height: size.height)
        // Pet 2 dropped near the same corner would snap to the identical
        // origin — fully hidden. Avoiding the sibling slides him along the
        // edge by his own width instead.
        let result = DockMagnet.snap(origin: CGPoint(x: screen.maxX - size.width - 10, y: 20),
                                     size: size, visibleFrame: screen, avoiding: occupied)
        #expect(result.y == screen.minY, "still on the dock line")
        #expect(result.x <= occupied.minX - size.width, "slid clear of the sibling")
        #expect(result.x >= screen.minX, "and still on screen")

        // A deliberate mid-screen overlap is left exactly alone: only the
        // snap resolution de-stacks.
        let midOverlap = CGRect(x: 600, y: 400, width: size.width, height: size.height)
        let dropped = DockMagnet.snap(origin: CGPoint(x: 610, y: 410),
                                      size: size, visibleFrame: screen, avoiding: midOverlap)
        #expect(dropped == CGPoint(x: 610, y: 410),
                "mid-screen drags are the operator's business")
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
        guard case .toolStarted(let name, let detail, let command) = event.kind else {
            Issue.record("expected toolStarted"); return
        }
        #expect(name == "Bash")
        #expect(detail == "List files", "the human description wins the detail slot")
        #expect(command == "ls", "and the raw command rides its own field")
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

/// The torso drag handle: only the stomach block moves the window, so two
/// pets on one desk stay individually grabbable.
@Suite("Torso drag handle")
@MainActor
struct TorsoDragHandleTests {

    /// The real mapping, not a copy of it. This used to restate the three
    /// lines `PetInstance` kept privately, which is how a mapping drifts away
    /// from the test that is supposed to be pinning it.
    private func cell(_ point: CGPoint, pixelSize: Double) -> (x: Int, y: Int)? {
        PetRootView.spriteCell(for: point, pixelSize: pixelSize)
    }

    /// The view point at the centre of a grid cell.
    private func point(col: Int, row: Int, pixelSize: Double) -> CGPoint {
        let frame = PetRootView.spriteFrame(pixelSize: pixelSize)
        return CGPoint(
            x: frame.minX + (Double(col) + 0.5) * pixelSize,
            y: frame.minY + (Double(PixelBuffer.side - 1 - row) + 0.5) * pixelSize)
    }

    @Test("The handle is the rig's body block at every pixel size")
    func geometryTable() {
        for px in Preferences.pixelSizes {
            let sprite = PetRootView.spriteFrame(pixelSize: px)
            let torso = PetRootView.torsoFrame(pixelSize: px)
            #expect(torso == CGRect(x: sprite.minX + 6 * px, y: 11 * px,
                                    width: 20 * px, height: 11 * px),
                    "torso drifted from the body block at pixel size \(px)")
            #expect(sprite.contains(torso), "the handle must live on him")
            let window = PetRootView.windowSize(pixelSize: px)
            #expect(CGRect(origin: .zero, size: window).contains(torso),
                    "the handle must be reachable — true even where the sprite overhangs")
        }
    }

    @Test("The handle round-trips to body cells through the click grid")
    func roundTripsToBodyCells() throws {
        for px in Preferences.pixelSizes {
            let torso = PetRootView.torsoFrame(pixelSize: px)
            // Inset corners: the extreme points that are still inside.
            for point in [CGPoint(x: torso.minX + 0.1, y: torso.minY + 0.1),
                          CGPoint(x: torso.maxX - 0.1, y: torso.maxY - 0.1)] {
                let landed = try #require(cell(point, pixelSize: px))
                #expect(landed.x >= 6 && landed.x <= 25, "col \(landed.x) off the body at \(px)")
                #expect(landed.y >= 10 && landed.y <= 20, "row \(landed.y) off the body at \(px)")
            }
        }
    }

    @Test("Eligibility: the stomach drags; claws, crown and the bug floor never do")
    func eligibilitySamples() {
        for px in Preferences.pixelSizes {
            let sprite = PetRootView.spriteFrame(pixelSize: px)
            let torso = PetRootView.torsoFrame(pixelSize: px)

            #expect(torso.contains(point(col: 15, row: 15, pixelSize: px)),
                    "the body centre is the handle")

            let leg = point(col: 8, row: 23, pixelSize: px)
            #expect(!torso.contains(leg) && CrabHitMask.body[8, 23],
                    "a leg clicks but never drags")

            #expect(!torso.contains(point(col: 15, row: 5, pixelSize: px)),
                    "the crown rows are props' airspace, not a handle")

            // The bug floor is no longer part of him: it is reachable only
            // while a bug is actually standing there (see SilhouetteHitTests).
            let bugRow = point(col: 15, row: 29, pixelSize: px)
            #expect(!torso.contains(bugRow) && sprite.contains(bugRow),
                    "a pounce click can never be mistaken for a drag")
            #expect(!CrabHitMask.body[15, 29],
                    "the empty floor is not his body")
        }
    }
}
