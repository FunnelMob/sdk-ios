import Foundation

/// Thread-safe event queue with persistence
final class EventQueue {

    private var events: [Event] = []
    private let lock = NSLock()
    private let persistenceKey = "com.funnelmob.events"

    init() {
        loadPersistedEvents()
    }

    /// Add event to queue
    func enqueue(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }

        events.append(event)
        persistEvents()
    }

    /// Get and remove events for sending
    func dequeue(maxCount: Int) -> [Event] {
        lock.lock()
        defer { lock.unlock() }

        let count = min(maxCount, events.count)
        let batch = Array(events.prefix(count))
        events.removeFirst(count)
        persistEvents()

        return batch
    }

    /// Current queue count
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    /// Flush all events
    func flush(using client: NetworkClient, configuration: FunnelMobConfiguration) {
        let batch = dequeue(maxCount: configuration.maxBatchSize)
        guard !batch.isEmpty else { return }

        // TODO: Implement actual network sending
        Logger.debug("Flushing \(batch.count) events")
    }

    // MARK: - Persistence

    private func persistEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func loadPersistedEvents() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let persisted = try? JSONDecoder().decode([Event].self, from: data) else {
            return
        }
        events = persisted
        Logger.debug("Loaded \(events.count) persisted events")
    }
}
