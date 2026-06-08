// AFAppFlowKit.swift
// AdaptyFlowKit SDK
//
// First launch coordinator: onboarding → paywall → rating → home.

import UIKit

// MARK: - AFAppFlowKit

/// Coordinator for the complete first launch flow: onboarding → paywall → rating.
///
/// **Usage:**
/// ```swift
/// // AppDelegate
/// AFAppFlowKit.configure(
///     onboardingPlacementId: "onboarding_main",
///     paywallPlacementId: "paywall_after_onboarding",
///     showRatingAfterOnboarding: true
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
    private var showRatingAfterOnboarding: Bool = false

    /// Configures the coordinator.
    public static func configure(
        onboardingPlacementId: String,
        paywallPlacementId: String,
        showPaywallAfterOnboarding: Bool = true,
        showRatingAfterOnboarding: Bool = false
    ) {
        shared.onboardingPlacementId = onboardingPlacementId
        shared.paywallPlacementId = paywallPlacementId
        shared.showPaywallAfterOnboarding = showPaywallAfterOnboarding
        shared.showRatingAfterOnboarding = showRatingAfterOnboarding
    }

    // MARK: - First Launch Flow

    /// Runs the complete first launch flow.
    ///
    /// Sequence:
    /// 1. `AFOnboardingKit.show()` — completes or skips
    /// 2. `AFPaywallKit.show()` — if `showPaywallAfterOnboarding` is `true`
    /// 3. `AFRatingKit.requestIfNeeded()` — if `showRatingAfterOnboarding` is `true`
    ///
    /// Always completes regardless of individual step results.
    @discardableResult
    public func runFirstLaunch(from presenter: UIViewController) async -> AFAppFlowResult {
        // If the user already completed onboarding on a previous launch, skip everything.
        // Prevents the onboarding paywall from re-appearing on every subsequent launch.
        guard !AFOnboardingKit.shared.hasCompleted else {
            print("[AFAppFlowKit] runFirstLaunch — onboarding already completed, skipping entire flow")
            return AFAppFlowResult(onboarding: .skipped, paywall: nil, rating: nil)
        }

        // Step 1: Onboarding
        print("[AFAppFlowKit] runFirstLaunch — starting onboarding (placement: \(onboardingPlacementId))")
        let onboardingResult = await AFOnboardingKit.shared.show(
            placementId: onboardingPlacementId,
            from: presenter
        )
        print("[AFAppFlowKit] runFirstLaunch — onboarding result: \(onboardingResult)")

        var paywallResult: AFPaywallResult?
        if showPaywallAfterOnboarding {
            // Step 2: Paywall — shown only right after onboarding completes for the first time
            print("[AFAppFlowKit] runFirstLaunch — starting paywall (placement: \(paywallPlacementId))")
            paywallResult = await AFPaywallKit.shared.show(
                placementId: paywallPlacementId,
                from: presenter,
                forceShow: true
            )
            print("[AFAppFlowKit] runFirstLaunch — paywall result: \(String(describing: paywallResult))")
        }

        var ratingResult: AFRatingResult?
        if showRatingAfterOnboarding, onboardingResult.isFinished {
            // Step 3: Rating — awaited so callers can navigate to home only after it closes
            print("[AFAppFlowKit] runFirstLaunch — starting rating prompt")
            ratingResult = await AFRatingKit.shared.requestIfNeeded(from: presenter)
            print("[AFAppFlowKit] runFirstLaunch — rating result: \(String(describing: ratingResult))")
        }

        return AFAppFlowResult(
            onboarding: onboardingResult,
            paywall: paywallResult,
            rating: ratingResult
        )
    }
}

// MARK: - AFAppFlowResult

/// Result of the complete first launch flow.
public struct AFAppFlowResult {
    public let onboarding: AFOnboardingResult
    public let paywall: AFPaywallResult?
    public let rating: AFRatingResult?

    public init(
        onboarding: AFOnboardingResult,
        paywall: AFPaywallResult?,
        rating: AFRatingResult? = nil
    ) {
        self.onboarding = onboarding
        self.paywall = paywall
        self.rating = rating
    }

    /// `true` if the user purchased or restored a subscription during the flow.
    public var isSubscribed: Bool {
        paywall?.isSuccess ?? false
    }
}
