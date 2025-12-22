import XCTest
@testable import FunnelMob

final class FunnelMobTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset state between tests
    }

    // MARK: - Configuration Tests

    func testConfigurationDefaults() {
        let config = FunnelMobConfiguration(
            appId: "com.test.app",
            apiKey: "fm_test_key"
        )

        XCTAssertEqual(config.appId, "com.test.app")
        XCTAssertEqual(config.apiKey, "fm_test_key")
        XCTAssertEqual(config.environment, .production)
        XCTAssertEqual(config.logLevel, .none)
        XCTAssertEqual(config.flushInterval, 30.0)
        XCTAssertEqual(config.maxBatchSize, 100)
    }

    func testConfigurationBuilder() {
        let config = FunnelMobConfiguration(
            appId: "com.test.app",
            apiKey: "fm_test_key"
        )
        .with(environment: .sandbox)
        .with(logLevel: .debug)
        .with(flushInterval: 10.0)
        .with(maxBatchSize: 50)

        XCTAssertEqual(config.environment, .sandbox)
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertEqual(config.flushInterval, 10.0)
        XCTAssertEqual(config.maxBatchSize, 50)
    }

    func testFlushIntervalMinimum() {
        let config = FunnelMobConfiguration(
            appId: "com.test.app",
            apiKey: "fm_test_key"
        )
        .with(flushInterval: 0.5) // Below minimum

        XCTAssertEqual(config.flushInterval, 1.0) // Should be clamped to 1.0
    }

    func testMaxBatchSizeClamped() {
        let config = FunnelMobConfiguration(
            appId: "com.test.app",
            apiKey: "fm_test_key"
        )
        .with(maxBatchSize: 200) // Above maximum

        XCTAssertEqual(config.maxBatchSize, 100) // Should be clamped to 100
    }

    // MARK: - Revenue Tests

    func testRevenueUSD() {
        let revenue = FunnelMobRevenue.usd(29.99)

        XCTAssertEqual(revenue.amount, Decimal(29.99))
        XCTAssertEqual(revenue.currency, "USD")
    }

    func testRevenueCurrencyNormalization() {
        let revenue = FunnelMobRevenue(amount: 10.0, currency: "eur")

        XCTAssertEqual(revenue.currency, "EUR")
    }

    func testRevenueFormatting() {
        let revenue = FunnelMobRevenue.usd(100)
        let eventRevenue = revenue.toEventRevenue()

        XCTAssertEqual(eventRevenue.amount, "100.00")
        XCTAssertEqual(eventRevenue.currency, "USD")
    }

    // MARK: - Event Parameters Tests

    func testEventParametersEmpty() {
        let params = FunnelMobEventParameters()

        XCTAssertNil(params.dictionary)
    }

    func testEventParametersWithValues() {
        var params = FunnelMobEventParameters()
        params.set("string_key", value: "hello")
        params.set("int_key", value: 42)
        params.set("double_key", value: 3.14)
        params.set("bool_key", value: true)

        let dict = params.dictionary
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["string_key"] as? String, "hello")
        XCTAssertEqual(dict?["int_key"] as? Int, 42)
        XCTAssertEqual(dict?["double_key"] as? Double, 3.14)
        XCTAssertEqual(dict?["bool_key"] as? Bool, true)
    }

    func testEventParametersLiteral() {
        let params: FunnelMobEventParameters = [
            "item_id": "sku_123",
            "quantity": 2
        ]

        let dict = params.dictionary
        XCTAssertEqual(dict?["item_id"] as? String, "sku_123")
        XCTAssertEqual(dict?["quantity"] as? Int, 2)
    }

    // MARK: - Environment Tests

    func testProductionBaseURL() {
        let env = FunnelMobConfiguration.Environment.production
        XCTAssertEqual(env.baseURL, "https://api.funnelmob.com/v1")
    }

    func testSandboxBaseURL() {
        let env = FunnelMobConfiguration.Environment.sandbox
        XCTAssertEqual(env.baseURL, "https://sandbox.funnelmob.com/v1")
    }
}
