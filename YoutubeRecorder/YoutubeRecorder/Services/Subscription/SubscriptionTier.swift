import Foundation

/// Subscription tier levels — controls feature access.
enum SubscriptionTier: String, Codable, Sendable {
    case free
    case pro
}

// MARK: - Feature Gates

extension SubscriptionTier {
    /// Maximum recording duration in seconds.
    var maxRecordingDuration: TimeInterval {
        switch self {
        case .free: return 300    // 5 minutes
        case .pro:  return .infinity
        }
    }

    /// Whether the user can export captions as .srt files.
    var canExportCaptions: Bool {
        self == .pro
    }

    /// Whether the user can use virtual backgrounds.
    var canUseVirtualBackgrounds: Bool {
        true // Available in all tiers
    }

    /// Whether the user can capture system audio.
    var canCaptureSystemAudio: Bool {
        true // Available in all tiers
    }

    /// Whether the user can use 4K quality.
    var canUse4K: Bool {
        self == .pro
    }

    /// Display name for the tier.
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro:  return "Pro"
        }
    }

    /// Formatted recording limit for display.
    var recordingLimitText: String {
        switch self {
        case .free: return "5 min"
        case .pro:  return "Unlimited"
        }
    }
}

// MARK: - Product IDs

/// StoreKit 2 product identifiers.
enum SubscriptionProductID {
    static let proMonthly = "pro_monthly"
    static let proYearly = "pro_yearly"

    static let all: Set<String> = [proMonthly, proYearly]
}
