import Foundation

/// Per-user consent state for GDPR / DMA compliance.
///
/// Pass to `FunnelMob.shared.setConsent(_:)` to inform the SDK and backend
/// of the user's consent decisions. The four fields mirror Google Consent
/// Mode v2 and AppsFlyer's `AppsFlyerConsent` so values map 1:1 to ad
/// network requirements.
///
/// When `isUserSubjectToGDPR == true` and `hasConsentForDataUsage == false`,
/// the SDK stops dispatching new events and clears any pending queue. When
/// `isUserSubjectToGDPR == false`, the per-dimension fields are advisory
/// only; the SDK tracks normally.
public struct FunnelMobConsent {

    /// Whether the user is subject to GDPR (typically true for EEA users).
    /// When `false`, the SDK ignores the per-dimension flags and tracks
    /// normally.
    public var isUserSubjectToGDPR: Bool

    /// Whether the user granted consent for data usage (analytics,
    /// attribution). When `false` and `isUserSubjectToGDPR == true`, the
    /// SDK stops sending events and clears the local queue.
    public var hasConsentForDataUsage: Bool?

    /// Whether the user granted consent for personalized ads. Forwarded
    /// to ad networks (Google `ad_personalization`). Does not gate
    /// dispatch — the network decides what to do.
    public var hasConsentForAdsPersonalization: Bool?

    /// Whether the user granted consent for ad-related storage (cookies,
    /// IDFA-style identifiers used for ads). Forwarded to ad networks
    /// (Google `ad_storage`). Does not gate dispatch.
    public var hasConsentForAdStorage: Bool?

    public init(
        isUserSubjectToGDPR: Bool,
        hasConsentForDataUsage: Bool? = nil,
        hasConsentForAdsPersonalization: Bool? = nil,
        hasConsentForAdStorage: Bool? = nil
    ) {
        self.isUserSubjectToGDPR = isUserSubjectToGDPR
        self.hasConsentForDataUsage = hasConsentForDataUsage
        self.hasConsentForAdsPersonalization = hasConsentForAdsPersonalization
        self.hasConsentForAdStorage = hasConsentForAdStorage
    }

    /// True when the SDK must stop dispatching: GDPR applies and the user
    /// has affirmatively denied data-usage consent. A `nil` data-usage
    /// flag is treated as "not yet answered" and does not block dispatch
    /// (matches the SDK's "track-by-default unless told otherwise" model).
    var blocksDispatch: Bool {
        isUserSubjectToGDPR && hasConsentForDataUsage == false
    }
}
