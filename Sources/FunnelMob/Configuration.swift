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
}
