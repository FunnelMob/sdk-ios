import Foundation

/// Thread-safe event queue with persistence
final class EventQueue {

    private var events: [Event] = []
    private let lock = NSLock()
    private let persistenceKey = "com.funnelmob.events"

    init() {
        loadPersistedEvents()
    }

    /// Add event to queue. Returns the new queue size.
    @discardableResult
    func enqueue(_ event: Event) -> Int {
        lock.lock()
        defer { lock.unlock() }

        events.append(event)
        persistEvents()
        return events.count
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

    /// Drop every queued event from memory and persistent storage.
    /// Used when the user revokes consent — GDPR requires the SDK to
    /// stop processing further data, including data already in flight
    /// to the network layer.
    func clear() {
        lock.lock()
        defer { lock.unlock() }

        events.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    /// Prepend a previously-dequeued batch back to the queue after a
    /// retryable send failure. Preserves event ordering: the failed
    /// batch retries first, before any newer events tracked while the
    /// in-flight POST was outstanding.
    func requeue(_ batch: [Event]) {
        lock.lock()
        defer { lock.unlock() }

        events.insert(contentsOf: batch, at: 0)
        persistEvents()
    }

    /// Flush all events
    func flush(using client: NetworkClient, configuration: FunnelMobConfiguration, userId: String? = nil) {
        let batch = dequeue(maxCount: configuration.maxBatchSize)
        guard !batch.isEmpty else { return }

        Logger.debug("Flushing \(batch.count) events")
        client.sendEvents(batch, configuration: configuration, userId: userId) { [weak self] result in
            switch result {
            case .success:
                Logger.debug("Events sent successfully")
            case .failure(let error):
                guard error.isRetryable else {
                    Logger.error("Dropped \(batch.count) events (non-retryable): \(error)")
                    return
                }
                // Retry queue is gated behind a config flag because the backend
                // `events` table lacks `event_id` dedup. With dedup off, retrying
                // a POST whose response was lost duplicates rows. Default off.
                if configuration.enableRetryQueue {
                    self?.requeue(batch)
                    Logger.warning("Re-queued \(batch.count) events: \(error)")
                } else {
                    Logger.error("Dropped \(batch.count) events (retryable, but enableRetryQueue=false): \(error)")
                }
            }
        }
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
