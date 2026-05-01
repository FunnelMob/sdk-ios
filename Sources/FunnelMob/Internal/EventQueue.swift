import Foundation

/// Thread-safe event queue with persistence
final class EventQueue {

    /// Hard cap on the number of events held in memory + persistence.
    /// When `enqueue()` would exceed this, the OLDEST event is dropped
    /// (FIFO eviction) so a sustained backend outage can't grow the queue
    /// unboundedly. Same cap applies after a `requeue()` prepends a
    /// failed batch — events at the tail are dropped first.
    static let maxQueueSize: Int = 1000

    /// Maximum number of times a batch may be re-queued before it's
    /// dropped. Protects against poison-pill events that fail every
    /// retry forever.
    static let maxRetryAttempts: Int = 5

    /// Hard cap on backoff sleep between retries (seconds).
    static let maxBackoffSeconds: TimeInterval = 60.0

    /// Random jitter added to every backoff (0…this seconds).
    static let maxJitterSeconds: TimeInterval = 1.0

    private var events: [Event] = []
    private let lock = NSLock()
    private let persistenceKey = "com.funnelmob.events"

    /// In-flight guard so two near-simultaneous flush triggers (timer +
    /// lifecycle hook) don't dequeue / re-queue overlapping batches and
    /// scramble ordering. Mirrors `FunnelMob.isReFireInFlight`.
    private var isFlushInFlight = false

    /// Earliest wall-clock time at which the next flush may run.
    /// Bumped on every retryable failure to implement exponential
    /// backoff. `nil` = no wait pending.
    private var nextFlushAllowedAt: Date?

    init() {
        loadPersistedEvents()
    }

    /// Add event to queue. Returns the new queue size. When the cap is
    /// exceeded the oldest event is dropped (FIFO).
    @discardableResult
    func enqueue(_ event: Event) -> Int {
        lock.lock()
        defer { lock.unlock() }

        events.append(event)
        if events.count > Self.maxQueueSize {
            let dropped = events.count - Self.maxQueueSize
            events.removeFirst(dropped)
            Logger.warning("Queue size exceeded \(Self.maxQueueSize); dropped \(dropped) oldest event(s)")
        }
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
        nextFlushAllowedAt = nil
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    /// Prepend a previously-dequeued batch back to the queue after a
    /// retryable send failure. Preserves event ordering: the failed
    /// batch retries first, before any newer events tracked while the
    /// in-flight POST was outstanding.
    ///
    /// Re-serializes the entire queue to UserDefaults on every call
    /// (O(n)); bounded by `maxQueueSize` so the cost is capped.
    func requeue(_ batch: [Event]) {
        lock.lock()
        defer { lock.unlock() }

        events.insert(contentsOf: batch, at: 0)
        if events.count > Self.maxQueueSize {
            let dropped = events.count - Self.maxQueueSize
            // Drop the TAIL: the re-queued failed batch keeps retry
            // priority, newer events arriving after it lose first.
            events.removeLast(dropped)
            Logger.warning("Queue size exceeded \(Self.maxQueueSize) after requeue; dropped \(dropped) newest event(s)")
        }
        persistEvents()
    }

    /// Flush all events. Returns immediately when (a) another flush is
    /// in flight, or (b) we're inside an active backoff window from a
    /// prior retryable failure.
    func flush(using client: NetworkClient, configuration: FunnelMobConfiguration, userId: String? = nil) {
        lock.lock()
        if isFlushInFlight {
            lock.unlock()
            Logger.debug("flush() skipped: another flush is already in flight")
            return
        }
        if let nextAt = nextFlushAllowedAt, Date() < nextAt {
            lock.unlock()
            Logger.debug("flush() skipped: backoff active until \(nextAt)")
            return
        }
        isFlushInFlight = true
        lock.unlock()

        let batch = dequeue(maxCount: configuration.maxBatchSize)
        guard !batch.isEmpty else {
            lock.lock(); isFlushInFlight = false; lock.unlock()
            return
        }

        Logger.debug("Flushing \(batch.count) events")
        client.sendEvents(batch, configuration: configuration, userId: userId) { [weak self] result in
            guard let self = self else { return }

            // Always release the in-flight latch before returning.
            defer {
                self.lock.lock()
                self.isFlushInFlight = false
                self.lock.unlock()
            }

            switch result {
            case .success:
                Logger.debug("Events sent successfully")
                self.lock.lock()
                self.nextFlushAllowedAt = nil
                self.lock.unlock()

            case .failure(let error):
                guard error.isRetryable else {
                    Logger.error("Dropped \(batch.count) events (non-retryable): \(error)")
                    return
                }
                guard configuration.enableRetryQueue else {
                    Logger.error("Dropped \(batch.count) events (retryable, but enableRetryQueue=false): \(error)")
                    return
                }

                // Bump every event's attemptCount; if any has now
                // exceeded the cap, the whole batch is poison.
                var bumped = batch
                for i in bumped.indices {
                    bumped[i].attemptCount += 1
                }
                let maxAttempts = bumped.map { $0.attemptCount }.max() ?? 0
                if maxAttempts > Self.maxRetryAttempts {
                    Logger.error("Dropped \(bumped.count) events (max retries \(Self.maxRetryAttempts) exceeded): \(error)")
                    return
                }

                self.requeue(bumped)
                let nextAt = Self.computeNextFlushAt(attemptCount: maxAttempts)
                self.lock.lock()
                self.nextFlushAllowedAt = nextAt
                self.lock.unlock()
                let waitMs = Int(nextAt.timeIntervalSinceNow * 1000)
                Logger.warning("Re-queued \(bumped.count) events (attempt \(maxAttempts)/\(Self.maxRetryAttempts)); next flush allowed in \(waitMs)ms: \(error)")
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

    /// Exponential backoff with jitter: `2^n` seconds capped at
    /// `maxBackoffSeconds`, plus 0–1s jitter.
    static func computeNextFlushAt(attemptCount: Int) -> Date {
        let base = min(pow(2.0, Double(attemptCount)), maxBackoffSeconds)
        let jitter = Double.random(in: 0...maxJitterSeconds)
        return Date().addingTimeInterval(base + jitter)
    }
}
