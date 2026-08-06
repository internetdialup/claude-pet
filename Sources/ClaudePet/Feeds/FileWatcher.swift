import Foundation

/// Watches a directory or file for changes and coalesces the notifications.
///
/// `DispatchSource` fires per-write, and Claude Code writes a transcript line at
/// a time, so a busy session would otherwise wake us dozens of times a second.
/// Coalescing to a short window turns that into one read per burst.
final class FileWatcher: @unchecked Sendable {
    // Safety: `source` and `handle` are only mutated in `init` and `cancel()`,
    // and `cancel()` is idempotent. The DispatchSource itself is thread-safe.
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let queue: DispatchQueue
    private let coalesce: TimeInterval
    private var pending: DispatchWorkItem?
    private let lock = NSLock()

    /// - Parameters:
    ///   - url: file or directory to watch. Must exist.
    ///   - coalesce: quiet period before `onChange` fires.
    init?(url: URL, queue: DispatchQueue, coalesce: TimeInterval = 0.12, onChange: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.coalesce = coalesce

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self.pending = work
            self.lock.unlock()
            self.queue.asyncAfter(deadline: .now() + self.coalesce, execute: work)
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        self.source = source
        source.resume()
    }

    func cancel() {
        lock.lock()
        pending?.cancel()
        pending = nil
        lock.unlock()
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit { cancel() }
}
