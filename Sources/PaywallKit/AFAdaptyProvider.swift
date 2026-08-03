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
            let flow = try await withTimeout(fetchTimeout) {
                try await Adapty.getFlow(placementId: placementId)
            }

            let products = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywallProducts(flow: flow)
            }

            let configuration = try await AdaptyUI.getFlowConfiguration(
                forFlow: flow,
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
        configuration: AdaptyUI.FlowConfiguration,
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
                let controller = try AdaptyUI.flowController(
                    with: configuration,
                    delegate: delegate,
                    showDebugOverlay: false
                )
                controller.modalPresentationStyle = .fullScreen
                delegate.retain(on: controller)
                presenter.present(controller, animated: true)

                // UIKit may silently reject present() while the hierarchy is
                // transitioning. Complete with an error so PaywallKit can release
                // its presentation lease and try the StoreKit fallback.
                Task { @MainActor in
                    await Task.yield()
                    guard controller.presentingViewController == nil else { return }
                    completionHandler.resume(with: .failed(.providerError(
                        NSError(
                            domain: "AFAdaptyProvider",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "UIKit rejected paywall presentation"]
                        )
                    )))
                }
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
private final class AFAdaptyEventBridge: NSObject, AdaptyFlowControllerDelegate {

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

    func flowController(
        _ controller: AdaptyFlowController,
        didFinishPurchase product: AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        Task { @MainActor in
            guard let profile = purchaseResult.profile else {
                // Adapty calls didFinishPurchase with nil profile when the user cancels
                // the Apple ID / password sheet — transaction did not complete.
                // Keep paywall open so the user can retry or close manually.
                print("[AdaptyProvider] didFinishPurchase: profile=nil — Apple sheet cancelled, keeping paywall open")
                return
            }

            if let service = validator as? AFProfileApplicable {
                service.apply(profile: profile)
            }

            let premiumIsActive = profile.accessLevels["premium"]?.isActive == true
            print("[AdaptyProvider] didFinishPurchase: product=\(product.vendorProductId), profile.premium=\(premiumIsActive)")

            let validatorIsActive = await validator.isSubscriptionActive()
            print("[AdaptyProvider] didFinishPurchase: validatorIsActive=\(validatorIsActive)")

            let isActive = premiumIsActive || validatorIsActive
            print("[AdaptyProvider] didFinishPurchase: isActive=\(isActive) → \(isActive ? ".purchased" : ".failed(.subscriptionNotActive)")")

            self.dismiss(controller) {
                self.completion.resume(with: isActive ? .purchased : .failed(.subscriptionNotActive))
            }
        }
    }

    func flowController(
        _ controller: AdaptyFlowController,
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

    func flowController(
        _ controller: AdaptyFlowController,
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

    func flowController(
        _ controller: AdaptyFlowController,
        didFailRestoreWith error: AdaptyError
    ) {
        dismiss(controller) {
            self.completion.resume(with: .failed(.providerError(error)))
        }
    }

    // MARK: - Actions

    func flowController(
        _ controller: AdaptyFlowController,
        didPerform action: AdaptyUI.Action
    ) {
        switch action {
        case .close:
            dismiss(controller) { self.completion.resume(with: .cancelled) }
        case .openURL(let url, _):
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        case .custom:
            break
        }
    }

    // MARK: - Errors

    func flowController(
        _ controller: AdaptyFlowController,
        didReceiveError error: AdaptyUIError
    ) {
        dismiss(controller) { self.completion.resume(with: .failed(.providerError(error))) }
    }

    func flowController(
        _ controller: AdaptyFlowController,
        didFailLoadingProductsWith error: AdaptyError
    ) -> Bool {
        return false
    }

    // MARK: - Lifecycle (no-op)

    func flowControllerDidAppear(_ controller: AdaptyFlowController) {}
    func flowControllerDidDisappear(_ controller: AdaptyFlowController) {}
    func flowController(_ controller: AdaptyFlowController, didSelectProduct product: AdaptyPaywallProduct) {}
    func flowController(_ controller: AdaptyFlowController, didStartPurchase product: AdaptyPaywallProduct) {}
    func flowControllerDidStartRestore(_ controller: AdaptyFlowController) {}
    func flowController(_ controller: AdaptyFlowController, didPartiallyLoadProducts failedIds: [String]) {}
    func flowController(_ controller: AdaptyFlowController, didFinishWebPaymentNavigation product: AdaptyPaywallProduct?, error: AdaptyError?) {}
    func flowController(_ controller: AdaptyFlowController, didReceiveAnalyticEvent name: String, params: [String: any Sendable]) {}

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
