import Foundation

/// Watches a directory or file for changes and coalesces the notifications.
///
/// `DispatchSource` fires per-write, and Claude Code writes a transcript line at
/// a time, so a busy session would otherwise wake us dozens of times a second.
/// Coalescing to a short window turns that into one read per burst.
///
/// **It re-arms itself, and that is not optional.** A kernel file-system source
/// watches an *inode*, not a path: the moment the file at that path is replaced
/// rather than appended to, the descriptor still refers to the old, unlinked
/// inode and every subsequent write is silent. The watcher does not fail — it
/// goes deaf, which is worse, because nothing upstream can tell.
///
/// Replacement is not an edge case. An atomic save (write-temp-then-rename) is
/// the normal way to write a file safely, log rotation does it by definition,
/// and iCloud materialising a dataless file does it behind your back. The pet
/// then sits at whatever it last heard, decays to idle, and stays idle until
/// the app is relaunched — while a freshly started copy reads the same session
/// as busy, because its watchers are new.
final class FileWatcher: @unchecked Sendable {
    // Safety: every mutation of `source`, `descriptor`, `pending`, `cancelled`
    // and `retries` happens under `lock`. The DispatchSource itself is
    // thread-safe, and `cancel()` is idempotent.
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?
    private var cancelled = false
    private var retries = 0

    private let url: URL
    private let queue: DispatchQueue
    private let coalesce: TimeInterval
    private let onChange: @Sendable () -> Void

    /// How long to keep trying to re-open a path that has gone missing. During
    /// a rename the gap is sub-millisecond; a file that stays gone for a minute
    /// belongs to a session that `reapDeadSessions` will retire anyway.
    private static let retryInterval: TimeInterval = 0.25
    private static let maxRetries = 240

    /// - Parameters:
    ///   - url: file or directory to watch. Must exist.
    ///   - coalesce: quiet period before `onChange` fires.
    init?(url: URL, queue: DispatchQueue, coalesce: TimeInterval = 0.12,
          onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.queue = queue
        self.coalesce = coalesce
        self.onChange = onChange
        guard arm() else { return nil }
    }

    /// Opens the path and starts a source on it. Returns false when the path
    /// cannot be opened right now.
    @discardableResult
    private func arm() -> Bool {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Read the mask before anything else touches the source.
            let mask = self.currentMask()
            // Report first: a replacement is itself a change, and whatever was
            // written between the swap and the re-arm is caught by the read
            // this schedules.
            self.scheduleChange()
            if mask.contains(.delete) || mask.contains(.rename) { self.rearm() }
        }
        source.setCancelHandler { close(fd) }

        lock.lock()
        guard !cancelled else {
            lock.unlock()
            source.cancel()
            return false
        }
        self.source = source
        self.descriptor = fd
        self.retries = 0
        lock.unlock()

        source.resume()
        return true
    }

    private func currentMask() -> DispatchSource.FileSystemEvent {
        lock.lock()
        defer { lock.unlock() }
        return source?.data ?? []
    }

    /// Tears the dead source down and opens the path again, retrying while it
    /// is briefly absent mid-rename.
    private func rearm() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        source?.cancel()          // the cancel handler closes the descriptor
        source = nil
        descriptor = -1
        lock.unlock()

        queue.asyncAfter(deadline: .now() + Self.retryInterval) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stop = self.cancelled || self.retries >= Self.maxRetries
            self.retries += 1
            self.lock.unlock()
            guard !stop else { return }

            if self.arm() {
                // Anything written while we were deaf is still on disk; the
                // readers all work forward from a byte offset, so one more
                // change notification is enough to collect it.
                self.scheduleChange()
            } else {
                self.rearm()
            }
        }
    }

    private func scheduleChange() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        pending?.cancel()
        let work = DispatchWorkItem(block: onChange)
        pending = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + coalesce, execute: work)
    }

    private let lock = NSLock()

    func cancel() {
        lock.lock()
        cancelled = true
        pending?.cancel()
        pending = nil
        let dying = source
        source = nil
        descriptor = -1
        lock.unlock()
        dying?.cancel()
    }

    deinit { cancel() }
}
