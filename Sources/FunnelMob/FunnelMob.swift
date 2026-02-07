import Foundation

/// Main entry point for the FunnelMob SDK
public final class FunnelMob {

    /// Shared singleton instance
    public static let shared = FunnelMob()

    private var configuration: FunnelMobConfiguration?
    private var isEnabled = true
    private let eventQueue: EventQueue
    private let networkClient: NetworkClient
    private let deviceInfo: DeviceInfo

    private init() {
        self.eventQueue = EventQueue()
        self.networkClient = NetworkClient()
        self.deviceInfo = DeviceInfo()
    }

    // MARK: - Initialization

    /// Initialize the SDK with configuration
    /// - Parameter configuration: SDK configuration
    public func initialize(with configuration: FunnelMobConfiguration) {
        guard self.configuration == nil else {
            Logger.warning("FunnelMob already initialized")
            return
        }

        self.configuration = configuration
        Logger.logLevel = configuration.logLevel
        Logger.info("FunnelMob initialized")

        startSession()
    }

    // MARK: - Event Tracking

    /// Track a custom event
    /// - Parameter name: Event name
    public func trackEvent(_ name: String) {
        trackEvent(name, revenue: nil, parameters: nil)
    }

    /// Track an event with parameters
    /// - Parameters:
    ///   - name: Event name
    ///   - parameters: Custom parameters
    public func trackEvent(_ name: String, parameters: FunnelMobEventParameters) {
        trackEvent(name, revenue: nil, parameters: parameters)
    }

    /// Track a revenue event
    /// - Parameters:
    ///   - name: Event name
    ///   - revenue: Revenue information
    public func trackEvent(_ name: String, revenue: FunnelMobRevenue) {
        trackEvent(name, revenue: revenue, parameters: nil)
    }

    /// Track a revenue event with parameters
    /// - Parameters:
    ///   - name: Event name
    ///   - revenue: Revenue information
    ///   - parameters: Custom parameters
    public func trackEvent(
        _ name: String,
        revenue: FunnelMobRevenue?,
        parameters: FunnelMobEventParameters?
    ) {
        guard isEnabled else {
            Logger.debug("Tracking disabled, ignoring event: \(name)")
            return
        }

        guard configuration != nil else {
            Logger.error("FunnelMob not initialized. Call initialize(with:) first.")
            return
        }

        // Validate event name
        guard let validatedName = validateEventName(name) else {
            Logger.error("Invalid event name: \(name)")
            return
        }

        let event = Event(
            eventId: UUID().uuidString,
            eventName: validatedName,
            timestamp: ISO8601DateFormatter.funnelMob.string(from: Date()),
            revenue: revenue?.toEventRevenue(),
            parameters: parameters?.dictionary
        )

        eventQueue.enqueue(event)
        Logger.debug("Event queued: \(name)")
    }

    // MARK: - Control

    /// Force send queued events immediately
    public func flush() {
        guard let config = configuration else { return }
        eventQueue.flush(using: networkClient, configuration: config)
    }

    /// Enable or disable tracking
    /// - Parameter enabled: Whether tracking is enabled
    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        Logger.info("Tracking \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Private

    private func startSession() {
        // TODO: Implement session tracking
        Logger.debug("Session started")
    }

    private func validateEventName(_ name: String) -> String? {
        guard !name.isEmpty else { return nil }
        guard name.count <= 100 else { return nil }

        let pattern = "^[a-zA-Z][a-zA-Z0-9_]*$"
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            return nil
        }

        return name
    }
}

// MARK: - Standard Events

public extension FunnelMob {
    /// Standard event names for common actions
    enum StandardEvent {
        public static let registration = "fm_registration"
        public static let login = "fm_login"
        public static let purchase = "fm_purchase"
        public static let subscribe = "fm_subscribe"
        public static let tutorialComplete = "fm_tutorial_complete"
        public static let levelComplete = "fm_level_complete"
        public static let addToCart = "fm_add_to_cart"
        public static let checkout = "fm_checkout"
    }
}
