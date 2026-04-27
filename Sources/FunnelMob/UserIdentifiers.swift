import Foundation

/// iOS App Tracking Transparency status values, mirroring
/// `ATTrackingManager.AuthorizationStatus`. Defined as a string enum so the
/// SDK does not import `AppTrackingTransparency.framework` itself — the host
/// reads the live status and passes the corresponding case via
/// `FunnelMob.shared.setATTStatus(_:)`.
public enum ATTStatus: String {
    /// User granted permission to track. SDK may receive a real IDFA.
    case authorized
    /// User explicitly denied tracking.
    case denied
    /// Tracking is restricted by parental controls or device policy.
    case restricted
    /// User has not yet responded to the prompt.
    case notDetermined
}
