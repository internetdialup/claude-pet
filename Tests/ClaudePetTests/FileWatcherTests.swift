import Testing
import Foundation
@testable import ClaudePet

/// The watcher's durability contract.
///
/// A kernel file-system source watches an inode, not a path, so a file that is
/// REPLACED rather than appended to takes the watch with it. The watcher does
/// not fail when that happens — it goes silent, which is worse, because the pet
/// then decays to idle over a session that is still working and stays there
/// until the app is relaunched.
@Suite("File watcher", .serialized)
struct FileWatcherTests {

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Waits for `count` to move, rather than sleeping a fixed guess — the
    /// re-arm is asynchronous and a fixed sleep would make this flaky by
    /// construction.
    private func waitForChange(_ counter: Counter, from: Int,
                               timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if counter.count > from { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test("It still hears the file after an atomic replace")
    func survivesAtomicReplace() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("transcript.jsonl")
        try "line 1\n".write(to: file, atomically: false, encoding: .utf8)

        let counter = Counter()
        let queue = DispatchQueue(label: "watcher-test")
        let watcher = try #require(FileWatcher(url: file, queue: queue, coalesce: 0.05) {
            counter.bump()
        })
        defer { watcher.cancel() }

        // A plain append: the ordinary case, and the control.
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data("line 2\n".utf8))
        try handle.close()
        #expect(await waitForChange(counter, from: 0), "a plain append went unheard")

        // Write-temp-then-rename — what an atomic save, a log rotation and an
        // iCloud materialisation all do to a file behind your back.
        let afterAppend = counter.count
        try "line 1\nline 2\nline 3\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(await waitForChange(counter, from: afterAppend), "the replace itself went unheard")

        // The real assertion: the watch followed the path to the NEW inode.
        // Before the re-arm existed this is where it went permanently deaf.
        try? await Task.sleep(for: .milliseconds(400))
        let beforeFinal = counter.count
        let reopened = try FileHandle(forWritingTo: file)
        reopened.seekToEndOfFile()
        reopened.write(Data("line 4\n".utf8))
        try reopened.close()
        #expect(await waitForChange(counter, from: beforeFinal),
                "the watcher went deaf after the file was replaced")
    }

    @Test("A directory watch survives its contents being replaced")
    func survivesDirectoryChurn() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = dir.appendingPathComponent("93450.json")
        try "{}".write(to: entry, atomically: false, encoding: .utf8)

        let counter = Counter()
        let queue = DispatchQueue(label: "watcher-dir-test")
        let watcher = try #require(FileWatcher(url: dir, queue: queue, coalesce: 0.05) {
            counter.bump()
        })
        defer { watcher.cancel() }

        try "{\"a\":1}".write(to: entry, atomically: true, encoding: .utf8)
        #expect(await waitForChange(counter, from: 0), "the registry write went unheard")

        try? await Task.sleep(for: .milliseconds(300))
        let before = counter.count
        try "{}".write(to: dir.appendingPathComponent("99999.json"),
                       atomically: true, encoding: .utf8)
        #expect(await waitForChange(counter, from: before),
                "a new session file went unnoticed")
    }

    @Test("Cancelling stops it for good, re-arm included")
    func cancelIsFinal() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.jsonl")
        try "a\n".write(to: file, atomically: false, encoding: .utf8)

        let counter = Counter()
        let queue = DispatchQueue(label: "watcher-cancel-test")
        let watcher = try #require(FileWatcher(url: file, queue: queue, coalesce: 0.05) {
            counter.bump()
        })
        watcher.cancel()

        try "a\nb\n".write(to: file, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(counter.count == 0, "a cancelled watcher kept reporting")
    }
}
