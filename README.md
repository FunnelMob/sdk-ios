# FunnelMob iOS SDK

A Mobile Measurement Partner (MMP) SDK for attributing app installs to advertising campaigns.

## Installation

### Swift Package Manager (Recommended)

In Xcode, go to **File > Add Package Dependencies...** and enter:

```
https://github.com/funnelmob/sdk-ios
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/funnelmob/sdk-ios", from: "0.1.0")
]
```

Then add `FunnelMob` to your target dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: ["FunnelMob"]
)
```

## Quick Start

```swift
import FunnelMob

// In your AppDelegate or App init
let config = FunnelMobConfiguration(
    appId: "com.example.myapp",
    apiKey: "fm_live_abc123"
)
FunnelMob.shared.initialize(with: config)

// Track events anywhere in your app
FunnelMob.shared.trackEvent("button_click")

// Flush before app terminates (optional)
FunnelMob.shared.flush()
```

### SwiftUI App

```swift
import SwiftUI
import FunnelMob

@main
struct MyApp: App {
    init() {
        let config = FunnelMobConfiguration(
            appId: "com.example.myapp",
            apiKey: "fm_live_abc123"
        )
        FunnelMob.shared.initialize(with: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Configuration

### Basic Configuration

```swift
let config = FunnelMobConfiguration(
    appId: "com.example.myapp",    // Required: Your app identifier
    apiKey: "fm_live_abc123"       // Required: Your API key
)
```

### Full Configuration with Builder

```swift
let config = FunnelMobConfiguration(appId: "com.example.myapp", apiKey: "fm_live_abc123")
    .with(environment: .production)   // Optional: .production (default) or .sandbox
    .with(logLevel: .none)            // Optional: .none, .error, .warning, .info, .debug, .verbose
    .with(flushInterval: 30.0)        // Optional: Auto-flush interval in seconds (min: 1.0, default: 30.0)
    .with(maxBatchSize: 100)          // Optional: Events per batch (1-100, default: 100)
```

### Environment Options

| Environment | Base URL |
|-------------|----------|
| `.production` | `https://api.funnelmob.com/v1` |
| `.sandbox` | `https://sandbox.funnelmob.com/v1` |

## Event Tracking

### Simple Events

```swift
FunnelMob.shared.trackEvent("level_complete")
```

### Events with Revenue

```swift
let revenue = FunnelMobRevenue.usd(29.99)
FunnelMob.shared.trackEvent("purchase", revenue: revenue)

// Other currencies
let eur = FunnelMobRevenue.eur(19.99)
let gbp = FunnelMobRevenue.gbp(14.99)
let jpy = FunnelMobRevenue(amount: 2000.0, currency: "JPY")

// Using Decimal for precision
let precise = FunnelMobRevenue(amount: Decimal(string: "99.99")!, currency: "USD")
```

### Events with Parameters

```swift
// Using mutating struct
var params = FunnelMobEventParameters()
params.set("item_id", value: "sku_123")
params.set("quantity", value: 2)
params.set("price", value: 29.99)
params.set("is_gift", value: false)

FunnelMob.shared.trackEvent("add_to_cart", parameters: params)

// Using dictionary literal (ExpressibleByDictionaryLiteral)
let params: FunnelMobEventParameters = [
    "item_id": "sku_123",
    "quantity": 2,
    "price": 29.99,
    "is_gift": false
]

FunnelMob.shared.trackEvent("add_to_cart", parameters: params)

// From a dictionary
let params = FunnelMobEventParameters([
    "item_id": "sku_123",
    "quantity": 2
])
```

### Events with Revenue and Parameters

```swift
let revenue = FunnelMobRevenue.usd(99.00)
var params = FunnelMobEventParameters()
params.set("plan", value: "annual")
params.set("trial_days", value: 7)

FunnelMob.shared.trackEvent("subscribe", revenue: revenue, parameters: params)
```

## Standard Events

Use predefined event names for consistent analytics:

```swift
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.registration)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.login)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.purchase)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.subscribe)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.tutorialComplete)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.levelComplete)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.addToCart)
FunnelMob.shared.trackEvent(FunnelMob.StandardEvent.checkout)
```

| Event | Constant | Value |
|-------|----------|-------|
| Registration | `FunnelMob.StandardEvent.registration` | `fm_registration` |
| Login | `FunnelMob.StandardEvent.login` | `fm_login` |
| Purchase | `FunnelMob.StandardEvent.purchase` | `fm_purchase` |
| Subscribe | `FunnelMob.StandardEvent.subscribe` | `fm_subscribe` |
| Tutorial Complete | `FunnelMob.StandardEvent.tutorialComplete` | `fm_tutorial_complete` |
| Level Complete | `FunnelMob.StandardEvent.levelComplete` | `fm_level_complete` |
| Add to Cart | `FunnelMob.StandardEvent.addToCart` | `fm_add_to_cart` |
| Checkout | `FunnelMob.StandardEvent.checkout` | `fm_checkout` |

## SDK Control

```swift
// Disable tracking (e.g., for GDPR compliance)
FunnelMob.shared.setEnabled(false)

// Re-enable tracking
FunnelMob.shared.setEnabled(true)

// Force send queued events immediately
FunnelMob.shared.flush()
```

## Validation

### Event Names

- Must not be empty
- Maximum 100 characters
- Must match pattern: `^[a-zA-Z][a-zA-Z0-9_]*$`
  - Must start with a letter
  - Can contain letters, numbers, and underscores
  - No hyphens, spaces, or special characters

```swift
// Valid
FunnelMob.shared.trackEvent("purchase")           // OK
FunnelMob.shared.trackEvent("level_2_complete")   // OK
FunnelMob.shared.trackEvent("buttonClick")        // OK

// Invalid (logged as errors)
FunnelMob.shared.trackEvent("2nd_level")          // Starts with number
FunnelMob.shared.trackEvent("my-event")           // Contains hyphen
FunnelMob.shared.trackEvent("")                   // Empty
```

### Currency

- Must be a 3-letter ISO 4217 code
- Automatically converted to uppercase

```swift
// Valid
FunnelMobRevenue(amount: 29.99, currency: "USD")
FunnelMobRevenue(amount: 29.99, currency: "usd")  // Converted to "USD"
```

## Error Handling

Errors are logged rather than thrown. Set `logLevel` to see validation errors:

```swift
let config = FunnelMobConfiguration(appId: "...", apiKey: "...")
    .with(logLevel: .debug)  // See validation errors in console

FunnelMob.shared.initialize(with: config)
```

Error messages appear in the console with the prefix `[FunnelMob]`.

## Requirements

- iOS 14.0+ / macOS 12.0+ / tvOS 14.0+ / watchOS 7.0+
- Swift 5.9+
- Xcode 15+

## License

MIT
