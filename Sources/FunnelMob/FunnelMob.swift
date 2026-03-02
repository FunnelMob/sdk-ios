import Foundation
#if canImport(Security)
import Security
#endif

/// Callback type for attribution results
public typealias AttributionCallback = (AttributionResult?) -> Void

/// Main entry point for the FunnelMob SDK
public final class FunnelMob {

    /// Shared singleton instance
    public static let shared = FunnelMob()

    private var configuration: FunnelMobConfiguration?
    private var isEnabled = true
    private let eventQueue: EventQueue
    private let networkClient: NetworkClient
    private let deviceInfo: DeviceInfo
    private var attributionId: String?
    private var attributionCallbacks: [AttributionCallback] = []

    private static let keychainService = "com.funnelmob.attribution"
    private static let keychainAccount = "attribution_result"

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

    // MARK: - Attribution

    /// Register a callback for attribution results.
    /// If attribution has already completed, the callback fires immediately.
    /// - Parameter callback: Called with the attribution result, or nil if organic
    public func onAttribution(_ callback: @escaping AttributionCallback) {
        attributionCallbacks.append(callback)

        // If we already have a stored result, fire immediately
        if let stored = loadAttribution() {
            callback(stored)
        }
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
            parameters: parameters?.dictionary,
            attributionId: attributionId
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
        // Check for existing attribution
        if let stored = loadAttribution() {
            attributionId = stored.attributionId
            Logger.debug("Loaded existing attribution")
            notifyCallbacks(stored)
            return
        }

        // First session — request attribution from server
        requestAttribution()
    }

    private func requestAttribution() {
        guard let config = configuration else { return }

        let context = deviceInfo.toContext()
        let request = SessionRequest(
            deviceId: deviceInfo.deviceId,
            sessionId: UUID().uuidString,
            platform: "ios",
            timestamp: ISO8601DateFormatter.funnelMob.string(from: Date()),
            isFirstSession: true,
            context: DeviceContextPayload(
                osVersion: context.osVersion,
                deviceModel: context.deviceModel,
                locale: context.locale,
                timezone: context.timezone
            )
        )

        networkClient.sendSession(request, configuration: config) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                if let attribution = response.attribution {
                    self.attributionId = attribution.attributionId
                    self.saveAttribution(attribution)
                    Logger.info("Attribution received")
                    self.notifyCallbacks(attribution)
                } else {
                    self.notifyCallbacks(nil)
                }
            case .failure(let error):
                Logger.error("Attribution request failed: \(error)")
                self.notifyCallbacks(nil)
            }
        }
    }

    private func notifyCallbacks(_ result: AttributionResult?) {
        for callback in attributionCallbacks {
            callback(result)
        }
    }

    // MARK: - Keychain Persistence

    private func loadAttribution() -> AttributionResult? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AttributionResult.self, from: data)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private func saveAttribution(_ attribution: AttributionResult) {
        #if canImport(Security)
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(attribution)

            // Delete any existing item first
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: Self.keychainAccount
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            // Add new item
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: Self.keychainAccount,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status != errSecSuccess {
                Logger.warning("Failed to save attribution to Keychain: \(status)")
            }
        } catch {
            Logger.warning("Failed to encode attribution: \(error)")
        }
        #endif
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
