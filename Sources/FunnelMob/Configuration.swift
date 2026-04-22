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
}
