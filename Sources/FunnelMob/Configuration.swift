import Foundation

/// Configuration options for the FunnelMob SDK
public struct FunnelMobConfiguration {

    /// API key for authentication
    public let apiKey: String

    /// Log level for debugging
    public var logLevel: LogLevel

    /// Interval between automatic event flushes (in seconds)
    public var flushInterval: TimeInterval

    /// Maximum number of events per batch
    public var maxBatchSize: Int

    /// Optional override for the API base URL. When `nil`, the SDK uses the
    /// production endpoint (`https://api.funnelmob.com`). The SDK appends
    /// `/v1/<endpoint>` itself, so pass the host root only
    /// (e.g. `http://localhost:3080` for the iOS simulator). Trailing
    /// slashes are stripped.
    public var customURL: String?

    /// Whether the SDK starts its active components (attribution session,
    /// flush timer, lifecycle observers, automatic Install/ActivateApp events,
    /// remote config fetch) immediately when `initialize(with:)` is called.
    ///
    /// Defaults to `true`. Set to `false` when you need to defer the SDK's
    /// network and event activity until you have obtained user consent
    /// (e.g., ATT, GDPR). When `false`, you must call
    /// `FunnelMob.shared.start()` after consent is granted.
    ///
    /// By calling `start()` you represent that you have obtained any user
    /// consent required by applicable law.
    public var autoStart: Bool

    /// Whether the SDK should defer its first session POST and event flushes
    /// until the user has responded to the iOS App Tracking Transparency
    /// prompt.
    ///
    /// Defaults to `false` (no waiting — the SDK starts immediately and
    /// reads the live ATT status on every payload).
    ///
    /// When `true`, `start()` enters a waiting state until ATT is
    /// determined (authorized/denied/restricted). Events tracked while
    /// waiting are buffered and flushed once the user responds. The host
    /// MUST eventually present the ATT prompt — typically via
    /// `FunnelMob.shared.requestTrackingAuthorization { ... }` — or the
    /// SDK will wait indefinitely.
    ///
    /// No-op on platforms without `AppTrackingTransparency` (watchOS):
    /// the SDK starts immediately as if this flag were `false`.
    public var waitForATTAuthorization: Bool

    /// Whether the EventQueue re-queues a batch on retryable send failures
    /// (5xx, 429, generic network errors) instead of dropping it. Defaults
    /// to `false`.
    ///
    /// Why default-off: the backend `events` table is currently a plain
    /// `MergeTree` (no `event_id` dedup). Until it migrates to
    /// `ReplacingMergeTree(inserted_at)` keyed on `event_id`, a successful
    /// POST whose response is lost (TCP RST after server commit, gateway
    /// timeout) becomes a duplicate row on retry — and revenue events
    /// would be double-counted. Set to `true` only in environments where
    /// you accept duplicates, or once backend dedup ships.
    public var enableRetryQueue: Bool

    /// Log level options
    public enum LogLevel: Int, Comparable {
        case none = 0
        case error = 1
        case warning = 2
        case info = 3
        case debug = 4
        case verbose = 5

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Initialize configuration with required parameters
    /// - Parameters:
    ///   - apiKey: API key for authentication
    public init(apiKey: String) {
        self.apiKey = apiKey
        self.logLevel = .none
        self.flushInterval = 30.0
        self.maxBatchSize = 100
        self.customURL = nil
        self.autoStart = true
        self.waitForATTAuthorization = false
        self.enableRetryQueue = false
    }
}

// MARK: - Builder Pattern

public extension FunnelMobConfiguration {

    /// Set log level
    func with(logLevel: LogLevel) -> FunnelMobConfiguration {
        var config = self
        config.logLevel = logLevel
        return config
    }

    /// Set flush interval
    func with(flushInterval: TimeInterval) -> FunnelMobConfiguration {
        var config = self
        config.flushInterval = max(1.0, flushInterval)
        return config
    }

    /// Set max batch size
    func with(maxBatchSize: Int) -> FunnelMobConfiguration {
        var config = self
        config.maxBatchSize = min(100, max(1, maxBatchSize))
        return config
    }

    /// Override the API base URL. Pass the host root without `/v1`
    /// (e.g. `http://localhost:3080` from the iOS simulator pointing at
    /// a backend on the host machine). Trailing slashes are trimmed.
    func with(customURL: String?) -> FunnelMobConfiguration {
        var config = self
        if let url = customURL {
            var trimmed = url
            while trimmed.hasSuffix("/") {
                trimmed.removeLast()
            }
            config.customURL = trimmed.isEmpty ? nil : trimmed
        } else {
            config.customURL = nil
        }
        return config
    }

    /// Configure whether the SDK starts automatically on `initialize(with:)`.
    /// Pass `false` to defer all network activity and event tracking until
    /// `FunnelMob.shared.start()` is called.
    func with(autoStart: Bool) -> FunnelMobConfiguration {
        var config = self
        config.autoStart = autoStart
        return config
    }

    /// Defer the first session POST and event flushes until the user has
    /// responded to the iOS ATT prompt. The host must eventually call
    /// `FunnelMob.shared.requestTrackingAuthorization { ... }` (or the
    /// underlying `ATTrackingManager` API) or the SDK waits indefinitely.
    func with(waitForATTAuthorization: Bool) -> FunnelMobConfiguration {
        var config = self
        config.waitForATTAuthorization = waitForATTAuthorization
        return config
    }

    /// Enable the retry queue: re-queue batches that fail with retryable
    /// errors (5xx / 429 / network) instead of dropping them. Default
    /// `false` until backend `events` table grows `event_id` dedup —
    /// see `FunnelMobConfiguration.enableRetryQueue` for rationale.
    func with(enableRetryQueue: Bool) -> FunnelMobConfiguration {
        var config = self
        config.enableRetryQueue = enableRetryQueue
        return config
    }
}
