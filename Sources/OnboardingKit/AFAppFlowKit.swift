// AFAppFlowKit.swift
// AdaptyFlowKit SDK
//
// First launch coordinator: onboarding → paywall → home.

import UIKit

// MARK: - AFAppFlowKit

/// Coordinator for the complete first launch flow: onboarding → paywall.
///
/// **Usage:**
/// ```swift
/// // AppDelegate
/// AFAppFlowKit.configure(
///     onboardingPlacementId: "onboarding_main",
///     paywallPlacementId: "paywall_after_onboarding"
/// )
///
/// // RootViewController
/// Task {
///     let result = await AFAppFlowKit.shared.runFirstLaunch(from: self)
///     navigateToMainScreen()
///
///     if result.isSubscribed {
///         // User purchased during onboarding flow
///     }
/// }
/// ```
@MainActor
public final class AFAppFlowKit {

    public static let shared = AFAppFlowKit()
    private init() {}

    // MARK: - Configuration

    private var onboardingPlacementId: String = ""
    private var paywallPlacementId: String = ""
    private var showPaywallAfterOnboarding: Bool = true

    /// Configures the coordinator.
    public static func configure(
        onboardingPlacementId: String,
        paywallPlacementId: String,
        showPaywallAfterOnboarding: Bool = true
    ) {
        shared.onboardingPlacementId = onboardingPlacementId
        shared.paywallPlacementId = paywallPlacementId
        shared.showPaywallAfterOnboarding = showPaywallAfterOnboarding
    }

    // MARK: - First Launch Flow

    /// Runs the complete first launch flow.
    ///
    /// Sequence:
    /// 1. `AFOnboardingKit.show()` — completes or skips
    /// 2. `AFPaywallKit.show()` — if `showPaywallAfterOnboarding` is `true`
    ///
    /// Always completes regardless of individual step results.
    @discardableResult
    public func runFirstLaunch(from presenter: UIViewController) async -> AFAppFlowResult {

        // Step 1: Onboarding
        let onboardingResult = await AFOnboardingKit.shared.show(
            placementId: onboardingPlacementId,
            from: presenter
        )

        guard showPaywallAfterOnboarding else {
            return AFAppFlowResult(onboarding: onboardingResult, paywall: nil)
        }

        // Step 2: Paywall — forceShow: true allows user to restore if already subscribed
        let paywallResult = await AFPaywallKit.shared.show(
            placementId: paywallPlacementId,
            from: presenter,
            forceShow: true
        )

        return AFAppFlowResult(onboarding: onboardingResult, paywall: paywallResult)
    }
}

// MARK: - AFAppFlowResult

/// Result of the complete first launch flow.
public struct AFAppFlowResult {
    public let onboarding: AFOnboardingResult
    public let paywall: AFPaywallResult?

    /// `true` if the user purchased or restored a subscription during the flow.
    public var isSubscribed: Bool {
        paywall?.isSuccess ?? false
    }
}
