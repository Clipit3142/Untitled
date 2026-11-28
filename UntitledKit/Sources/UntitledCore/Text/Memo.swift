import Synchronization

/// A small thread-safe cache for values derived from style settings (compiled vocabulary,
/// never-include keys). Bounded, so a long session with many styles cannot grow it forever.
final class Memo<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private let storage = Mutex<[Key: Value]>([:])
    private let limit: Int

    init(limit: Int = 64) {
        self.limit = limit
    }

    func value(for key: Key, make: () -> Value) -> Value {
        if let cached = storage.withLock({ $0[key] }) { return cached }
        let made = make()
        storage.withLock { cache in
            if cache.count >= limit { cache.removeAll(keepingCapacity: true) }
            cache[key] = made
        }
        return made
    }
}
