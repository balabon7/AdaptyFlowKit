// AFOnboardingKit+Types.swift
// AdaptyFlowKit SDK
//
// Types for OnboardingKit. Mirrors PaywallKit+Types.swift.

import Foundation

// MARK: - OnboardingResult

/// Result of showing onboarding.
public enum AFOnboardingResult: Sendable {
    case completed    // User completed to the end
    case skipped      // User pressed "Skip" — onboarding is considered completed
    case failed(AFOnboardingKitError)
}

extension AFOnboardingResult {
    /// `true` if onboarding is completed in any positive scenario.
    public var isFinished: Bool {
        switch self {
        case .completed, .skipped: return true
        case .failed: return false
        }
    }
}

// MARK: - OnboardingKitError

public enum AFOnboardingKitError: LocalizedError, Sendable {
    case notConfigured
    case fetchTimeout
    case displayTimeout
    case noFallbackUI
    case providerError(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .notConfigured:   return "[AFOnboardingKit] SDK not configured. Call AFOnboardingKit.configure() first."
        case .fetchTimeout:    return "[AFOnboardingKit] Adapty fetch timed out."
        case .displayTimeout:  return "[AFOnboardingKit] Onboarding did not finish loading in time."
        case .noFallbackUI:    return "[AFOnboardingKit] Primary provider failed and no fallback UI registered."
        case .providerError(let e): return "[AFOnboardingKit] Provider error: \(e.localizedDescription)"
        case .unknown:         return "[AFOnboardingKit] Unknown error."
        }
    }
}

// MARK: - OnboardingKitConfiguration

/// AFOnboardingKit configuration. Passed once during configure().
public struct AFOnboardingKitConfiguration: Sendable {

    /// Timeout for loading onboarding from server (fetch + configuration).
    public let fetchTimeout: TimeInterval

    /// Timeout after showing controller — if `didFinishLoading` never comes
    /// (octopusbuilder bug). SDK falls back or considers onboarding loaded.
    public let displayTimeout: TimeInterval

    /// Skip network check. For testing.
    public let skipNetworkCheck: Bool

    /// Logger — same as in PaywallKit.
    public let logger: AFPaywallKitLogger?

    public init(
        fetchTimeout: TimeInterval = 10.0,
        displayTimeout: TimeInterval = 15.0,
        skipNetworkCheck: Bool = false,
        logger: AFPaywallKitLogger? = nil
    ) {
        self.fetchTimeout = fetchTimeout
        self.displayTimeout = displayTimeout
        self.skipNetworkCheck = skipNetworkCheck
        self.logger = logger
    }
}

// MARK: - OnboardingPermissionHandler

/// Protocol for handling permission requests from Adapty onboarding.
///
/// Adapty onboarding can send custom actions like "request_notifications"
/// or "request_tracking". Instead of handling them in SDK or ViewController,
/// you implement this protocol and register it in configure().
///
/// ```swift
/// final class MyPermissionHandler: AFOnboardingPermissionHandler {
///     func handlePermission(_ action: AFOnboardingPermissionAction) {
///         switch action {
///         case .notifications: requestNotifications()
///         case .tracking:      requestATT()
///         case .custom(let id): print("custom: \(id)")
///         }
///     }
/// }
/// ```
public protocol AFOnboardingPermissionHandler: AnyObject {
    @MainActor
    func handlePermission(_ action: AFOnboardingPermissionAction)
}

// MARK: - AFOnboardingPermissionAction

/// Permission action type from Adapty custom action.
public enum AFOnboardingPermissionAction: Sendable {
    case notifications              // "request_notifications"
    case tracking                   // "request_tracking"
    case custom(id: String)         // Any other action id
}

extension AFOnboardingPermissionAction {
    /// Converts string id from Adapty into typed action.
    init(actionId: String) {
        switch actionId {
        case "request_notifications": self = .notifications
        case "request_tracking":      self = .tracking
        default:                      self = .custom(id: actionId)
        }
    }
}
