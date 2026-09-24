import CoreServices
import Foundation

/// Watches a folder tree with FSEvents and calls `handler` (coalesced by `latency`) when anything changes.
public final class FolderWatcher: @unchecked Sendable {
    // Mutable state is only touched in init and stop(), which callers serialise.
    private var stream: FSEventStreamRef?
    private let handler: @Sendable () -> Void
    private let queue = DispatchQueue(label: "AsterMark.FolderWatcher", qos: .utility)

    public init(url: URL, latency: TimeInterval = 0.5, handler: @escaping @Sendable () -> Void) {
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().handler()
        }
        let path = url.resolvingSymlinksInPath().path
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
