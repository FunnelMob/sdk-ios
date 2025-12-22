import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Device information collector
struct DeviceInfo {

    /// Unique device identifier (IDFV or generated UUID)
    var deviceId: String {
        #if canImport(UIKit) && !os(watchOS)
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        #endif
        return getOrCreateDeviceId()
    }

    /// Operating system name
    var osName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "Unknown"
        #endif
    }

    /// Operating system version
    var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Device model
    var deviceModel: String {
        #if canImport(UIKit) && !os(watchOS)
        return UIDevice.current.model
        #else
        return getDeviceModelIdentifier()
        #endif
    }

    /// App version
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// App build number
    var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    /// User locale
    var locale: String {
        Locale.current.identifier
    }

    /// User timezone
    var timezone: String {
        TimeZone.current.identifier
    }

    // MARK: - Private

    private let deviceIdKey = "com.funnelmob.deviceId"

    private func getOrCreateDeviceId() -> String {
        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            return stored
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    private func getDeviceModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

// MARK: - Context Generation

extension DeviceInfo {

    func toContext() -> DeviceContext {
        DeviceContext(
            appVersion: appVersion,
            osName: osName,
            osVersion: osVersion,
            deviceModel: deviceModel,
            locale: locale,
            timezone: timezone
        )
    }
}

struct DeviceContext: Encodable {
    let appVersion: String
    let osName: String
    let osVersion: String
    let deviceModel: String
    let locale: String
    let timezone: String
}
