import Foundation

// MARK: - ISO8601DateFormatter Extension

extension ISO8601DateFormatter {

    /// FunnelMob standard date formatter with milliseconds
    static let funnelMob: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}
