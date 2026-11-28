import Foundation

/// A signal that a watched folder's top level may have changed.
public enum WatchSignal: Sendable, Hashable {
    /// Something changed; take a new snapshot.
    case changed
    /// Events were lost; take a full snapshot (3.5 "full scan").
    case mustRescan
    /// The folder itself was renamed, moved or deleted (C2), or its volume went away (C5).
    case rootChanged
}

/// Watches the top level of one folder.
public protocol FolderWatcher: Sendable {
    func signals() -> AsyncStream<WatchSignal>
    func stop()
}

/// Polls a folder's listing. Portable; used in tests on Linux and as a fallback.
public final class PollingFolderWatcher: FolderWatcher {
    let path: String
    let interval: Duration
    private let task = TaskHolder()

    public init(path: String, interval: Duration = .milliseconds(200)) {
        self.path = path
        self.interval = interval
    }

    public func signals() -> AsyncStream<WatchSignal> {
        let (stream, continuation) = AsyncStream.makeStream(of: WatchSignal.self)
        let path = self.path
        let interval = self.interval
        let rootIdentity = FileSystem.status(atPath: path)?.identity
        // The baseline is taken now, not when the task first runs, so a change made right
        // after `signals()` returns is never folded into it.
        let baseline = Self.fingerprint(path)
        let watchTask = Task.detached {
            var last = baseline
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                let identity = FileSystem.status(atPath: path)?.identity
                if identity == nil || identity != rootIdentity {
                    continuation.yield(.rootChanged)
                    continue
                }
                let current = Self.fingerprint(path)
                if current != last {
                    last = current
                    continuation.yield(.changed)
                }
            }
            continuation.finish()
        }
        task.set(watchTask)
        continuation.onTermination = { _ in watchTask.cancel() }
        return stream
    }

    public func stop() { task.cancel() }

    static func fingerprint(_ path: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for name in (try? FileSystem.entries(ofDirectory: path)) ?? [] {
            if let status = FileSystem.status(atPath: FileSystem.join(path, name)) {
                result[name + "|" + status.identity.description] = status.modification + Double(status.size)
            }
        }
        return result
    }
}

/// Holds a task so a watcher can cancel it.
final class TaskHolder: Sendable {
    private let storage = SendableBox<Task<Void, Never>?>(nil)

    func set(_ task: Task<Void, Never>) { storage.value = task }
    func cancel() { storage.value?.cancel() }
}

import Synchronization

final class SendableBox<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>
    init(_ value: Value) { mutex = Mutex(value) }
    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}

#if canImport(CoreServices) && !os(Linux)
import CoreServices

/// One FSEvents stream per watched folder, with file-level events, 0.3 s latency and a
/// watch on the root (3.5). The last event ID is reported so it can be saved and replayed
/// from at launch.
public final class FSEventsFolderWatcher: FolderWatcher, @unchecked Sendable {
    // @unchecked: the stream reference is only touched on `queue`.
    private let path: String
    private let sinceWhen: FSEventStreamEventId
    private let onEventID: @Sendable (UInt64) -> Void
    private let queue = DispatchQueue(label: "com.yourcompany.Untitled.fsevents", qos: .utility)
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<WatchSignal>.Continuation?

    public init(path: String, sinceEventID: UInt64?, onEventID: @escaping @Sendable (UInt64) -> Void) {
        self.path = path
        self.sinceWhen = sinceEventID.map { FSEventStreamEventId($0) } ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        self.onEventID = onEventID
    }

    public func signals() -> AsyncStream<WatchSignal> {
        let (stream, continuation) = AsyncStream.makeStream(of: WatchSignal.self)
        queue.sync {
            self.continuation = continuation
            self.start()
        }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        return stream
    }

    private func start() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        let callback: FSEventStreamCallback = { _, info, count, _, eventFlags, eventIDs in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsFolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handle(count: count, flags: eventFlags, ids: eventIDs)
        }
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [path] as CFArray,
                                                sinceWhen, 0.3, flags) else {
            continuation?.yield(.mustRescan)
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    private func handle(count: Int, flags: UnsafePointer<FSEventStreamEventFlags>, ids: UnsafePointer<FSEventStreamEventId>) {
        var signal: WatchSignal = .changed
        for index in 0..<count {
            let flag = Int(flags[index])
            if flag & kFSEventStreamEventFlagRootChanged != 0 || flag & kFSEventStreamEventFlagUnmount != 0 {
                signal = .rootChanged
            } else if signal != .rootChanged,
                      flag & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped) != 0 {
                signal = .mustRescan
            }
        }
        if count > 0 { onEventID(UInt64(ids[count - 1])) }
        continuation?.yield(signal)
    }

    public func stop() {
        queue.async { [self] in
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            stream = nil
            continuation?.finish()
            continuation = nil
        }
    }

    /// The current event ID, saved when a folder starts being watched.
    public static var currentEventID: UInt64 { UInt64(FSEventsGetCurrentEventId()) }
}
#endif
