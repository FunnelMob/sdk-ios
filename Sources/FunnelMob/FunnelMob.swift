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
        // Legacy fm_-prefixed names (kept for backwards compatibility)
        public static let registration = "fm_registration"
        public static let login = "fm_login"
        public static let purchase = "fm_purchase"
        public static let subscribe = "fm_subscribe"
        public static let tutorialComplete = "fm_tutorial_complete"
        public static let levelComplete = "fm_level_complete"
        public static let addToCart = "fm_add_to_cart"
        public static let checkout = "fm_checkout"

        // Standard Meta/TikTok event names.
        // addToCartStandard, purchaseStandard, and subscribeStandard use the Standard
        // suffix because the legacy fm_-prefixed names already occupy the shorter names above.
        public static let pageView = "PageView"
        public static let viewContent = "ViewContent"
        public static let search = "Search"
        public static let addToCartStandard = "AddToCart"
        public static let addToWishlist = "AddToWishlist"
        public static let initiateCheckout = "InitiateCheckout"
        public static let addPaymentInfo = "AddPaymentInfo"
        public static let purchaseStandard = "Purchase"
        public static let lead = "Lead"
        public static let completeRegistration = "CompleteRegistration"
        public static let contact = "Contact"
        public static let schedule = "Schedule"
        public static let findLocation = "FindLocation"
        public static let customizeProduct = "CustomizeProduct"
        public static let donate = "Donate"
        public static let submitApplication = "SubmitApplication"
        public static let applicationApproval = "ApplicationApproval"
        public static let download = "Download"
        public static let submitForm = "SubmitForm"
        public static let startTrial = "StartTrial"
        public static let subscribeStandard = "Subscribe"
        public static let achieveLevel = "AchieveLevel"
        public static let unlockAchievement = "UnlockAchievement"
        public static let spentCredits = "SpentCredits"
        public static let rate = "Rate"
        public static let completeTutorial = "CompleteTutorial"
        public static let activateApp = "ActivateApp"
        public static let inAppAdClick = "InAppAdClick"
        public static let inAppAdImpression = "InAppAdImpression"
    }

    // MARK: - Typed Standard Event Methods

    /// Meta only — fires on every page load
    func trackPageView(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("PageView", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — visit to a product detail, landing, or content page
    func trackViewContent(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("ViewContent", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — search performed on your site or app
    func trackSearch(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Search", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — item added to shopping cart
    func trackAddToCart(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("AddToCart", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — item added to wishlist
    func trackAddToWishlist(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("AddToWishlist", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — start of checkout process
    func trackInitiateCheckout(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("InitiateCheckout", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — payment info entered during checkout
    func trackAddPaymentInfo(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("AddPaymentInfo", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — purchase completed; value and currency are required
    func trackPurchase(value: Double, currency: String, parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Purchase", revenue: FunnelMobRevenue(amount: value, currency: currency), parameters: parameters)
    }

    /// Meta + TikTok — user submits contact information
    func trackLead(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Lead", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — user completes a registration or sign-up flow
    func trackCompleteRegistration(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("CompleteRegistration", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — any contact initiated between user and business
    func trackContact(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Contact", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — user books an appointment or reservation
    func trackSchedule(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Schedule", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — user searches for a physical business location
    func trackFindLocation(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("FindLocation", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — user customizes a product
    func trackCustomizeProduct(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("CustomizeProduct", revenue: nil, parameters: parameters)
    }

    /// Meta only — donation completed; value and currency are required
    func trackDonate(value: Double, currency: String, parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Donate", revenue: FunnelMobRevenue(amount: value, currency: currency), parameters: parameters)
    }

    /// Meta + TikTok — user submits an application
    func trackSubmitApplication(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("SubmitApplication", revenue: nil, parameters: parameters)
    }

    /// TikTok only — application previously submitted is approved
    func trackApplicationApproval(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("ApplicationApproval", revenue: nil, parameters: parameters)
    }

    /// TikTok only — user downloads a file or asset
    func trackDownload(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Download", revenue: nil, parameters: parameters)
    }

    /// TikTok legacy — use trackLead() for new implementations
    func trackSubmitForm(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("SubmitForm", revenue: nil, parameters: parameters)
    }

    /// Meta + TikTok — user begins a free trial; value and currency are required
    func trackStartTrial(value: Double, currency: String, parameters: FunnelMobEventParameters? = nil) {
        trackEvent("StartTrial", revenue: FunnelMobRevenue(amount: value, currency: currency), parameters: parameters)
    }

    /// Meta + TikTok — user starts a paid subscription; value and currency are required
    func trackSubscribe(value: Double, currency: String, parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Subscribe", revenue: FunnelMobRevenue(amount: value, currency: currency), parameters: parameters)
    }

    /// Meta only — user reaches a level in your app or game
    func trackAchieveLevel(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("AchieveLevel", revenue: nil, parameters: parameters)
    }

    /// Meta only — user completes a rewarded action or milestone
    func trackUnlockAchievement(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("UnlockAchievement", revenue: nil, parameters: parameters)
    }

    /// Meta only — user spends in-app credits or virtual currency; value is required.
    /// Note: value is passed as a parameter (not revenue) because SpentCredits uses
    /// virtual currency, which has no ISO 4217 currency code.
    func trackSpentCredits(value: Double, parameters: FunnelMobEventParameters? = nil) {
        var params = parameters ?? FunnelMobEventParameters()
        params.set("value", value: value)
        trackEvent("SpentCredits", revenue: nil, parameters: params)
    }

    /// Meta only — user submits a rating
    func trackRate(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("Rate", revenue: nil, parameters: parameters)
    }

    /// Meta only — user completes an in-app tutorial
    func trackCompleteTutorial(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("CompleteTutorial", revenue: nil, parameters: parameters)
    }

    /// Meta only — app launch or open
    func trackActivateApp(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("ActivateApp", revenue: nil, parameters: parameters)
    }

    /// Meta only — in-app ad clicked by user
    func trackInAppAdClick(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("InAppAdClick", revenue: nil, parameters: parameters)
    }

    /// Meta only — in-app ad appeared on-screen
    func trackInAppAdImpression(parameters: FunnelMobEventParameters? = nil) {
        trackEvent("InAppAdImpression", revenue: nil, parameters: parameters)
    }
}
