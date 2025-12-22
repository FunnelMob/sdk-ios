import Foundation

/// Revenue information for purchase events
public struct FunnelMobRevenue {

    /// Revenue amount
    public let amount: Decimal

    /// ISO 4217 currency code (e.g., "USD", "EUR")
    public let currency: String

    /// Create revenue with amount and currency
    /// - Parameters:
    ///   - amount: Revenue amount
    ///   - currency: ISO 4217 currency code
    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }

    /// Create revenue from Double with currency
    /// - Parameters:
    ///   - amount: Revenue amount as Double
    ///   - currency: ISO 4217 currency code
    public init(amount: Double, currency: String) {
        self.amount = Decimal(amount)
        self.currency = currency.uppercased()
    }

    /// Convert to internal event revenue format
    internal func toEventRevenue() -> EventRevenue {
        EventRevenue(
            amount: formatAmount(),
            currency: currency
        )
    }

    private func formatAmount() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Convenience Initializers

public extension FunnelMobRevenue {

    /// Create USD revenue
    static func usd(_ amount: Decimal) -> FunnelMobRevenue {
        FunnelMobRevenue(amount: amount, currency: "USD")
    }

    /// Create USD revenue from Double
    static func usd(_ amount: Double) -> FunnelMobRevenue {
        FunnelMobRevenue(amount: amount, currency: "USD")
    }

    /// Create EUR revenue
    static func eur(_ amount: Decimal) -> FunnelMobRevenue {
        FunnelMobRevenue(amount: amount, currency: "EUR")
    }

    /// Create EUR revenue from Double
    static func eur(_ amount: Double) -> FunnelMobRevenue {
        FunnelMobRevenue(amount: amount, currency: "EUR")
    }

    /// Create GBP revenue
    static func gbp(_ amount: Decimal) -> FunnelMobRevenue {
        FunnelMobRevenue(amount: amount, currency: "GBP")
    }

    /// Create GBP revenue from Double
    static func gbp(_ amount: Double) -> FunnelMobRevenue {
        FunnelMobRevenue(amount: amount, currency: "GBP")
    }
}
