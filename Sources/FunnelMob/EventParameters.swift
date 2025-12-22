import Foundation

/// Container for custom event parameters
public struct FunnelMobEventParameters {

    private var storage: [String: Any] = [:]

    /// Create empty parameters
    public init() {}

    /// Set a string parameter
    public mutating func set(_ key: String, value: String) {
        storage[key] = value
    }

    /// Set an integer parameter
    public mutating func set(_ key: String, value: Int) {
        storage[key] = value
    }

    /// Set a double parameter
    public mutating func set(_ key: String, value: Double) {
        storage[key] = value
    }

    /// Set a boolean parameter
    public mutating func set(_ key: String, value: Bool) {
        storage[key] = value
    }

    /// Get the underlying dictionary
    internal var dictionary: [String: Any]? {
        storage.isEmpty ? nil : storage
    }
}

// MARK: - Convenience Initializers

public extension FunnelMobEventParameters {

    /// Create parameters from a dictionary
    /// - Parameter dictionary: Dictionary of parameters
    init(_ dictionary: [String: Any]) {
        for (key, value) in dictionary {
            switch value {
            case let string as String:
                storage[key] = string
            case let int as Int:
                storage[key] = int
            case let double as Double:
                storage[key] = double
            case let bool as Bool:
                storage[key] = bool
            default:
                // Skip unsupported types
                break
            }
        }
    }
}

// MARK: - ExpressibleByDictionaryLiteral

extension FunnelMobEventParameters: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        self.init()
        for (key, value) in elements {
            switch value {
            case let string as String:
                storage[key] = string
            case let int as Int:
                storage[key] = int
            case let double as Double:
                storage[key] = double
            case let bool as Bool:
                storage[key] = bool
            default:
                break
            }
        }
    }
}
