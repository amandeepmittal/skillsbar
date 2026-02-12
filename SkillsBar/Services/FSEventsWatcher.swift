import Foundation
import CoreServices

final class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void
    private let paths: [String]

    init(paths: [String], callback: @escaping ([String]) -> Void) {
        self.paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        self.callback = callback
    }

    func start() {
        guard !paths.isEmpty else { return }

        let pathsCFArray = paths as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsCFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency for debouncing
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    fileprivate func handleEvent(paths: [String]) {
        callback(paths)
    }
}

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
    let changedPaths = (unsafeBitCast(eventPaths, to: CFArray.self) as? [String]) ?? []
    DispatchQueue.main.async {
        watcher.handleEvent(paths: changedPaths)
    }
}
