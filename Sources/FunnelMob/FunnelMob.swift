import Foundation
#if canImport(Security)
import Security
#endif

/// Callback type for attribution results
public typealias AttributionCallback = (AttributionResult?) -> Void

/// Callback type for remote config loaded events
public typealias ConfigLoadedCallback = ([String: Any]) -> Void

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
    private var userId: String?
    private var userProperties: [String: Any]?
    private var remoteConfig: [String: Any]?
    private var configCallbacks: [ConfigLoadedCallback] = []

    private static let keychainService = "com.funnelmob.attribution"
    private static let keychainAccount = "attribution_result"
    private static let userIdKey = "com.funnelmob.userId"
    private static let configKey = "com.funnelmob.config"
    private static let configTimestampKey = "com.funnelmob.config.ts"
    private static let configCacheTTL: TimeInterval = 300 // 5 minutes

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

        restoreUserId()
        startSession()
        loadCachedConfig()
        fetchRemoteConfig()
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

    // MARK: - Remote Config

    /// Get a single remote config value by key.
    /// - Parameters:
    ///   - key: The config key
    /// - Returns: The value, or nil if not found
    public func getConfig(_ key: String) -> Any? {
        return remoteConfig?[key]
    }

    /// Get a single remote config value with a default.
    /// - Parameters:
    ///   - key: The config key
    ///   - defaultValue: Value to return if key not found
    /// - Returns: The config value or the default
    public func getConfig<T>(_ key: String, default defaultValue: T) -> T {
        return (remoteConfig?[key] as? T) ?? defaultValue
    }

    /// Get all remote config values.
    /// - Returns: A copy of all config key-value pairs
    public func getAllConfig() -> [String: Any] {
        return remoteConfig ?? [:]
    }

    /// Register a callback that fires when remote config is loaded.
    /// If config has already been loaded, the callback fires immediately.
    /// - Parameter callback: Called with the config dictionary
    public func onConfigLoaded(_ callback: @escaping ConfigLoadedCallback) {
        configCallbacks.append(callback)

        if let config = remoteConfig {
            callback(config)
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
        eventQueue.flush(using: networkClient, configuration: config, userId: userId)
    }

    /// Enable or disable tracking
    /// - Parameter enabled: Whether tracking is enabled
    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        Logger.info("Tracking \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - User Identification

    /// Set the user ID for identified users.
    /// Sends an identify request to the server and attaches the user ID to all subsequent events.
    /// - Parameter userId: The user identifier (must be non-empty)
    public func setUserId(_ userId: String) {
        guard !userId.isEmpty else {
            Logger.error("setUserId: userId cannot be empty")
            return
        }

        self.userId = userId
        persistUserId(userId)
        Logger.info("User ID set: \(userId)")
        sendIdentify()
    }

    /// Set user properties for the current identified user.
    /// Properties are merged with existing properties.
    /// Requires setUserId() to be called first.
    /// - Parameter properties: User properties to set
    public func setUserProperties(_ properties: [String: Any]) {
        guard userId != nil else {
            Logger.error("setUserProperties: call setUserId() first")
            return
        }

        if var existing = self.userProperties {
            for (key, value) in properties {
                existing[key] = value
            }
            self.userProperties = existing
        } else {
            self.userProperties = properties
        }

        Logger.debug("User properties updated")
        sendIdentify()
    }

    /// Clear the current user ID (e.g., on logout).
    /// Subsequent events will not include a user_id.
    public func clearUserId() {
        userId = nil
        userProperties = nil
        UserDefaults.standard.removeObject(forKey: Self.userIdKey)
        Logger.info("User ID cleared")
    }

    // MARK: - Private

    private func sendIdentify() {
        guard let config = configuration, let userId = userId else { return }

        let context = deviceInfo.toContext()
        let request = IdentifyRequest(
            deviceId: deviceInfo.deviceId,
            userId: userId,
            platform: "ios",
            timestamp: ISO8601DateFormatter.funnelMob.string(from: Date()),
            userProperties: userProperties,
            context: DeviceContextPayload(
                osVersion: context.osVersion,
                deviceModel: context.deviceModel,
                locale: context.locale,
                timezone: context.timezone
            )
        )

        networkClient.sendIdentify(request, configuration: config) { result in
            switch result {
            case .success:
                Logger.debug("Identify request sent")
            case .failure(let error):
                Logger.error("Identify request failed: \(error)")
            }
        }
    }

    private func persistUserId(_ userId: String) {
        UserDefaults.standard.set(userId, forKey: Self.userIdKey)
    }

    private func restoreUserId() {
        if let stored = UserDefaults.standard.string(forKey: Self.userIdKey) {
            self.userId = stored
            Logger.debug("Restored user ID: \(stored)")
        }
    }

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

    // MARK: - Remote Config (Private)

    private func fetchRemoteConfig() {
        guard let config = configuration else { return }

        networkClient.fetchConfig(configuration: config) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let configData):
                self.remoteConfig = configData
                self.saveCachedConfig(configData)
                Logger.debug("Remote config loaded")
                self.notifyConfigCallbacks(configData)
            case .failure(let error):
                Logger.error("Failed to fetch remote config: \(error)")
            }
        }
    }

    private func loadCachedConfig() {
        let defaults = UserDefaults.standard
        guard let ts = defaults.object(forKey: Self.configTimestampKey) as? Date else { return }
        guard Date().timeIntervalSince(ts) < Self.configCacheTTL else { return }
        guard let data = defaults.data(forKey: Self.configKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        self.remoteConfig = json
        Logger.debug("Loaded cached remote config")
    }

    private func saveCachedConfig(_ config: [String: Any]) {
        let defaults = UserDefaults.standard
        if let data = try? JSONSerialization.data(withJSONObject: config) {
            defaults.set(data, forKey: Self.configKey)
            defaults.set(Date(), forKey: Self.configTimestampKey)
        }
    }

    private func notifyConfigCallbacks(_ config: [String: Any]) {
        for callback in configCallbacks {
            callback(config)
        }
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
