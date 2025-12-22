import Foundation

/// Configuration options for the FunnelMob SDK
public struct FunnelMobConfiguration {

    /// Application identifier (e.g., bundle ID)
    public let appId: String

    /// API key for authentication
    public let apiKey: String

    /// Environment (production or sandbox)
    public var environment: Environment

    /// Log level for debugging
    public var logLevel: LogLevel

    /// Interval between automatic event flushes (in seconds)
    public var flushInterval: TimeInterval

    /// Maximum number of events per batch
    public var maxBatchSize: Int

    /// Environment options
    public enum Environment {
        case production
        case sandbox

        var baseURL: String {
            switch self {
            case .production:
                return "https://api.funnelmob.com/v1"
            case .sandbox:
                return "https://sandbox.funnelmob.com/v1"
            }
        }
    }

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
    ///   - appId: Application identifier
    ///   - apiKey: API key for authentication
    public init(appId: String, apiKey: String) {
        self.appId = appId
        self.apiKey = apiKey
        self.environment = .production
        self.logLevel = .none
        self.flushInterval = 30.0
        self.maxBatchSize = 100
    }
}

// MARK: - Builder Pattern

public extension FunnelMobConfiguration {

    /// Set environment
    func with(environment: Environment) -> FunnelMobConfiguration {
        var config = self
        config.environment = environment
        return config
    }

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
