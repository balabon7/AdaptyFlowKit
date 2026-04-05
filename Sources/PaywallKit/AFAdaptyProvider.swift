// AFAdaptyProvider.swift
// AdaptyFlowKit SDK
//
// Implementation of PaywallProvider for Adapty SDK.

import UIKit
import Adapty
import AdaptyUI

// MARK: - AFAdaptyProvider

/// Paywall provider based on Adapty SDK.
/// Conforms to `AFPaywallProvider` — fully replaceable with a custom implementation.
public final class AFAdaptyProvider: AFPaywallProvider {

    // MARK: - Dependencies

    private let validator: AFSubscriptionValidator
    private let fetchTimeout: TimeInterval

    // MARK: - Init

    public init(
        validator: AFSubscriptionValidator,
        fetchTimeout: TimeInterval = 15.0
    ) {
        self.validator = validator
        self.fetchTimeout = fetchTimeout
    }

    // MARK: - AFPaywallProvider

    @MainActor
    public func present(
        placementId: String,
        from presenter: UIViewController
    ) async -> AFPaywallResult {
        do {
            let paywall = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywall(placementId: placementId)
            }

            let products = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywallProducts(paywall: paywall)
            }

            let configuration = try await AdaptyUI.getPaywallConfiguration(
                forPaywall: paywall,
                loadTimeout: nil,
                products: products,
                observerModeResolver: nil,
                tagResolver: nil,
                timerResolver: nil,
                assetsResolver: nil
            )

            return await showController(configuration: configuration, from: presenter)

        } catch let error as AFPaywallKitError {
            return .failed(error)
        } catch {
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    @MainActor
    private func showController(
        configuration: AdaptyUI.PaywallConfiguration,
        from presenter: UIViewController
    ) async -> AFPaywallResult {
        // UIViewController.present() silently fails if presenter is not in the window hierarchy
        // (no throw, no callback) — continuation would hang forever.
        // Check in advance so PaywallKit can fall back to the StoreKit provider.
        guard presenter.view.window != nil else {
            return .failed(.providerError(
                NSError(
                    domain: "AFAdaptyProvider",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Presenter is not in the window hierarchy"]
                )
            ))
        }

        return await withCheckedContinuation { continuation in
            let completionHandler = AFSingleFireContinuation(continuation)
            let delegate = AFAdaptyEventBridge(
                completion: completionHandler,
                validator: validator
            )

            do {
                let controller = try AdaptyUI.paywallController(
                    with: configuration,
                    delegate: delegate,
                    showDebugOverlay: false
                )
                controller.modalPresentationStyle = .fullScreen
                delegate.retain(on: controller)
                presenter.present(controller, animated: true)
            } catch {
                completionHandler.resume(with: .failed(.providerError(error)))
            }
        }
    }

    // MARK: - Timeout

    private func withTimeout<T>(
        _ seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AFPaywallKitError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

// MARK: - AFAdaptyEventBridge

/// Receives events from AdaptyUI and converts them to `AFPaywallResult`.
/// Lives exactly as long as the controller via AssociatedObject.
private final class AFAdaptyEventBridge: NSObject, AdaptyPaywallControllerDelegate {

    private let completion: AFSingleFireContinuation<AFPaywallResult>
    private let validator: AFSubscriptionValidator

    init(completion: AFSingleFireContinuation<AFPaywallResult>, validator: AFSubscriptionValidator) {
        self.completion = completion
        self.validator = validator
    }

    /// Attaches self to the controller's lifetime via AssociatedObject.
    func retain(on controller: UIViewController) {
        objc_setAssociatedObject(
            controller,
            &AFAdaptyEventBridge.retainKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
    private static var retainKey: UInt8 = 0

    // MARK: - Purchase

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        Task { @MainActor in
            guard let profile = purchaseResult.profile else {
                // Adapty calls didFinishPurchase with nil profile when the user cancels
                // the Apple ID / password sheet — transaction did not complete.
                // Keep paywall open so the user can retry or close manually.
                return
            }

            if let service = validator as? AFProfileApplicable {
                service.apply(profile: profile)
            }

            let premiumIsActive = profile.accessLevels["premium"]?.isActive == true
            let validatorIsActive = await validator.isSubscriptionActive()
            let isActive = premiumIsActive || validatorIsActive

            self.dismiss(controller) {
                self.completion.resume(with: isActive ? .purchased : .failed(.subscriptionNotActive))
            }
        }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        // Payment cancelled by user — keep paywall open
        guard error.adaptyErrorCode != .paymentCancelled else { return }
        dismiss(controller) {
            self.completion.resume(with: .failed(.providerError(error)))
        }
    }

    // MARK: - Restore

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishRestoreWith profile: AdaptyProfile
    ) {
        Task { @MainActor in
            if let service = validator as? AFProfileApplicable {
                service.apply(profile: profile)
            }
            let isActive = profile.accessLevels["premium"]?.isActive == true
            self.dismiss(controller) {
                self.completion.resume(with: isActive ? .restored : .failed(.noActiveSubscription))
            }
        }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRestoreWith error: AdaptyError
    ) {
        dismiss(controller) {
            self.completion.resume(with: .failed(.providerError(error)))
        }
    }

    // MARK: - Actions

    func paywallController(
        _ controller: AdaptyPaywallController,
        didPerform action: AdaptyUI.Action
    ) {
        switch action {
        case .close:
            dismiss(controller) { self.completion.resume(with: .cancelled) }
        case .openURL(let url):
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        case .custom:
            break
        }
    }

    // MARK: - Errors

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRenderingWith error: AdaptyUIError
    ) {
        dismiss(controller) { self.completion.resume(with: .failed(.providerError(error))) }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailLoadingProductsWith error: AdaptyError
    ) -> Bool {
        return true // Allow showing paywall without prices
    }

    // MARK: - Lifecycle (no-op)

    func paywallControllerDidAppear(_ controller: AdaptyPaywallController) {}
    func paywallControllerDidDisappear(_ controller: AdaptyPaywallController) {}
    func paywallController(_ controller: AdaptyPaywallController, didSelectProduct product: AdaptyPaywallProductWithoutDeterminingOffer) {}
    func paywallController(_ controller: AdaptyPaywallController, didStartPurchase product: AdaptyPaywallProduct) {}
    func paywallControllerDidStartRestore(_ controller: AdaptyPaywallController) {}
    func paywallController(_ controller: AdaptyPaywallController, didPartiallyLoadProducts failedIds: [String]) {}
    func paywallController(_ controller: AdaptyPaywallController, didFinishWebPaymentNavigation product: AdaptyPaywallProduct?, error: AdaptyError?) {}

    // MARK: - Helper

    private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
        controller.dismiss(animated: true, completion: completion)
    }
}

// MARK: - AFProfileApplicable

/// Optional protocol for `AFSubscriptionValidator` that can accept an `AdaptyProfile`.
/// Allows bridging Adapty profile updates to your subscription service without a hard dependency.
public protocol AFProfileApplicable {
    func apply(profile: AdaptyProfile)
}
