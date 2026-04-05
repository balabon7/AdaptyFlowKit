// AFOnboardingProvider.swift
// AdaptyFlowKit SDK
//
// Onboarding provider protocol. Mirrors PaywallProvider.swift.

import UIKit

// MARK: - OnboardingProvider

/// Onboarding provider abstraction.
/// Implement to connect Adapty, custom server, or static screens.
public protocol AFOnboardingProvider: AnyObject, Sendable {

    /// Shows onboarding.
    /// - Returns: `AFOnboardingResult` after completion.
    @MainActor
    func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFOnboardingResult
}

// MARK: - OnboardingEventHandler

/// Protocol for handling onboarding events (analytics).
public protocol AFOnboardingEventHandler: AnyObject {

    @MainActor
    func onOnboardingCompleted(placementId: String)

    @MainActor
    func onOnboardingSkipped(placementId: String)

    @MainActor
    func onOnboardingFailed(error: AFOnboardingKitError, placementId: String)
}

// Default no-op implementations
public extension AFOnboardingEventHandler {
    func onOnboardingCompleted(placementId: String) {}
    func onOnboardingSkipped(placementId: String) {}
    func onOnboardingFailed(error: AFOnboardingKitError, placementId: String) {}
}
