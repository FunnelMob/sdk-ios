import Foundation

/// Internal event representation
struct Event: Codable {
    let eventId: String
    let eventName: String
    let timestamp: String
    let revenue: EventRevenue?
    let parameters: [String: Any]?
    let attributionId: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventName = "event_name"
        case timestamp
        case revenue
        case parameters
        case attributionId = "attribution_id"
    }

    init(
        eventId: String,
        eventName: String,
        timestamp: String,
        revenue: EventRevenue?,
        parameters: [String: Any]?,
        attributionId: String? = nil
    ) {
        self.eventId = eventId
        self.eventName = eventName
        self.timestamp = timestamp
        self.revenue = revenue
        self.parameters = parameters
        self.attributionId = attributionId
    }

    // Custom encoding for parameters (Any type)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(revenue, forKey: .revenue)
        try container.encodeIfPresent(attributionId, forKey: .attributionId)

        if let parameters = parameters {
            let jsonData = try JSONSerialization.data(withJSONObject: parameters)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            try container.encode(AnyCodable(jsonObject), forKey: .parameters)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        eventName = try container.decode(String.self, forKey: .eventName)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        revenue = try container.decodeIfPresent(EventRevenue.self, forKey: .revenue)
        attributionId = try container.decodeIfPresent(String.self, forKey: .attributionId)

        if let anyCodable = try container.decodeIfPresent(AnyCodable.self, forKey: .parameters) {
            parameters = anyCodable.value as? [String: Any]
        } else {
            parameters = nil
        }
    }
}

/// Internal revenue representation
struct EventRevenue: Codable {
    let amount: String
    let currency: String
}

/// Attribution result from the server
public struct AttributionResult: Codable {
    public let attributionId: String
    public let attributed: Bool
    public let method: String
    public let campaignId: String?
    public let adNetwork: String?
    public let adGroupId: String?
    public let adId: String?
    public let keyword: String?
    public let confidence: Double

    enum CodingKeys: String, CodingKey {
        case attributionId = "attribution_id"
        case attributed
        case method
        case campaignId = "campaign_id"
        case adNetwork = "ad_network"
        case adGroupId = "ad_group_id"
        case adId = "ad_id"
        case keyword
        case confidence
    }
}

/// Device context for session requests
struct DeviceContextPayload: Encodable {
    let osVersion: String?
    let deviceModel: String?
    let locale: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case locale
        case timezone
    }
}

/// Session request payload
struct SessionRequest: Encodable {
    let deviceId: String
    let sessionId: String
    let platform: String
    let timestamp: String
    let isFirstSession: Bool
    let context: DeviceContextPayload?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case sessionId = "session_id"
        case platform
        case timestamp
        case isFirstSession = "is_first_session"
        case context
    }
}

/// Session response from the server
struct SessionResponse: Decodable {
    let sessionId: String
    let serverTimestamp: String
    let attribution: AttributionResult?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case serverTimestamp = "server_timestamp"
        case attribution
    }
}

/// Wrapper for encoding Any types
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
