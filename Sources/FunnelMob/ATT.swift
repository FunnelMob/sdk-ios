import Foundation
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

// MARK: - ATT helpers
//
// Thin wrappers around `ATTrackingManager`. The SDK reads ATT status fresh
// on every payload build (see `currentATTStatusString()`) so changes made
// in iOS Settings are picked up automatically — no caching, no manual
// `setATTStatus` call required.

#if canImport(AppTrackingTransparency)
public extension FunnelMob {

    /// The current ATT authorization status, read live from
    /// `ATTrackingManager.trackingAuthorizationStatus`.
    ///
    /// Requires `NSUserTrackingUsageDescription` in `Info.plist`.
    @available(iOS 14, macOS 11, tvOS 14, *)
    var trackingAuthorizationStatus: ATTrackingManager.AuthorizationStatus {
        ATTrackingManager.trackingAuthorizationStatus
    }

    /// Show the iOS App Tracking Transparency prompt and report the user's
    /// decision via the completion handler. Equivalent to calling
    /// `ATTrackingManager.requestTrackingAuthorization(completionHandler:)`
    /// directly — this wrapper exists so the SDK can detect the
    /// determination and resume work that was deferred via
    /// `Configuration.waitForATTAuthorization`.
    ///
    /// `Info.plist` MUST contain a `NSUserTrackingUsageDescription` string.
    /// Without it, iOS will crash this call.
    @available(iOS 14, macOS 11, tvOS 14, *)
    func requestTrackingAuthorization(
        completion: @escaping (ATTrackingManager.AuthorizationStatus) -> Void
    ) {
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                completion(status)
            }
            self?.handleATTDetermined()
        }
    }
}
#endif

extension FunnelMob {
    /// Fresh ATT status read for the session payload. Returns one of
    /// `"authorized"`, `"denied"`, `"restricted"`, `"notDetermined"`, or
    /// nil on platforms without the framework (watchOS).
    func currentATTStatusString() -> String? {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, macOS 11, tvOS 14, *) {
            switch ATTrackingManager.trackingAuthorizationStatus {
            case .notDetermined: return "notDetermined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .authorized: return "authorized"
            @unknown default: return nil
            }
        }
        #endif
        return nil
    }

    /// True when ATT is in a determined state (authorized / denied /
    /// restricted) or when the framework is unavailable. Used to decide
    /// whether `start()` should defer.
    func isATTDetermined() -> Bool {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, macOS 11, tvOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus != .notDetermined
        }
        #endif
        return true
    }
}
