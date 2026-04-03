// AFAppFlowKit.swift
// AdaptyFlowKit SDK
//
// First launch coordinator: onboarding → paywall → home.
// Replaces the logic from CustomNavigationController.runFirstLaunchFlow().
//
// ─────────────────────────────────────────────────────────────────
// PROBLEM in the original:
//   CustomNavigationController knew about OnboardingService, PaywallService,
//   display order, and even about hasCompletedOnboarding — SRP completely violated.
//
// SOLUTION:
//   AppFlowKit — separate coordinator. NavigationController only asks:
//   "where to start?" and calls flow.run(). Nothing more.
// ─────────────────────────────────────────────────────────────────

import UIKit

// MARK: - AppFlowKit

/// First launch coordinator.
///
/// **Usage in NavigationController:**
/// ```swift
/// override func viewDidLoad() {
///     super.viewDidLoad()
///
///     if OnboardingKit.shared.hasCompleted {
///         goToHome()
///         if showPaywallOnLaunch {
///             Task { await PaywallKit.shared.show(placementId: "launch", from: topVC) }
///         }
///     } else {
///         Task {
///             let result = await AppFlowKit.shared.runFirstLaunch(from: placeholderVC)
///             goToHome()
///         }
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
    ///
    /// ```swift
    /// AppFlowKit.configure(
    ///     onboardingPlacementId: "onboarding_main",
    ///     paywallPlacementId: "paywall_after_onboarding",
    ///     showPaywallAfterOnboarding: true
    /// )
    /// ```
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
    /// 1. OnboardingKit.show() — if completed/skipped → step 2
    /// 2. PaywallKit.show() — if enabled
    ///
    /// Returns after both steps are completed.
    /// Regardless of results — the flow always completes.
    ///
    /// ```swift
    /// Task {
    ///     await AppFlowKit.shared.runFirstLaunch(from: placeholderVC)
    ///     goToHome()   // ← you call this yourself after return
    /// }
    /// ```
    @discardableResult
    public func runFirstLaunch(from presenter: UIViewController) async -> AFAppFlowResult {

        // ── Step 1: Onboarding ──
        let onboardingResult = await AFOnboardingKit.shared.show(
            placementId: onboardingPlacementId,
            from: presenter
        )

        log("Onboarding: \(onboardingResult)")

        // ── Step 2: Paywall (only if enabled) ──
        guard showPaywallAfterOnboarding else {
            return AFAppFlowResult(onboarding: onboardingResult, paywall: nil)
        }

        // Show paywall with forceShow: true after onboarding
        // This allows the user to restore purchases if they already exist
        let paywallResult = await AFPaywallKit.shared.show(
            placementId: paywallPlacementId,
            from: presenter,
            forceShow: true  // Show even if subscription exists (for restore)
        )

        log("Paywall: \(paywallResult)")

        return AFAppFlowResult(onboarding: onboardingResult, paywall: paywallResult)
    }

    // MARK: - Helper

    private func log(_ message: String) {
        print("[AppFlowKit] \(message)")
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
