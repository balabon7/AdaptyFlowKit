// AFAdaptyProvider.swift
// AdaptyFlowKit SDK
//
// Implementation of PaywallProvider for Adapty SDK.
// Isolated from the rest of the SDK — replacement takes 5 minutes.

import UIKit
import Adapty
import AdaptyUI

// MARK: - AFAdaptyProvider

/// Provider based on Adapty SDK.
/// Conforms to `AFPaywallProvider` — fully replaceable.
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
        let startTime = CFAbsoluteTimeGetCurrent()
        print(" [AdaptyProvider] present() started for placementId: \(placementId)")
        
        do {
            // 1. Load paywall and products in parallel where possible
            print(" [AdaptyProvider] Fetching paywall from Adapty...")
            let paywallStartTime = CFAbsoluteTimeGetCurrent()
            
            let paywall = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywall(placementId: placementId)
            }
            
            let paywallDuration = CFAbsoluteTimeGetCurrent() - paywallStartTime
            print(" [AdaptyProvider] Paywall fetch took: \(String(format: "%.2f", paywallDuration))s")

            print(" [AdaptyProvider] Fetching products...")
            let productsStartTime = CFAbsoluteTimeGetCurrent()
            
            let products = try await withTimeout(fetchTimeout) {
                try await Adapty.getPaywallProducts(paywall: paywall)
            }
            
            let productsDuration = CFAbsoluteTimeGetCurrent() - productsStartTime
            print(" [AdaptyProvider] Products fetch took: \(String(format: "%.2f", productsDuration))s")

            // 2. Build configuration
            print(" [AdaptyProvider] Building paywall configuration...")
            let configStartTime = CFAbsoluteTimeGetCurrent()
            
            let configuration = try await AdaptyUI.getPaywallConfiguration(
                forPaywall: paywall,
                loadTimeout: nil,
                products: products,
                observerModeResolver: nil,
                tagResolver: nil,
                timerResolver: nil,
                assetsResolver: nil
            )
            
            let configDuration = CFAbsoluteTimeGetCurrent() - configStartTime
            print(" [AdaptyProvider] Configuration build took: \(String(format: "%.2f", configDuration))s")

            // 3. Show UI via continuation
            print(" [AdaptyProvider] Showing paywall controller...")
            let showStartTime = CFAbsoluteTimeGetCurrent()
            
            let result = await showController(configuration: configuration, from: presenter)
            
            let showDuration = CFAbsoluteTimeGetCurrent() - showStartTime
            let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
            print(" [AdaptyProvider] Showing controller took: \(String(format: "%.2f", showDuration))s")
            print(" [AdaptyProvider] Total present() duration: \(String(format: "%.2f", totalDuration))s")
            
            return result

        } catch let error as AFPaywallKitError {
            let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
            print(" [AdaptyProvider] Failed with AFPaywallKitError after \(String(format: "%.2f", totalDuration))s: \(error)")
            return .failed(error)
        } catch {
            let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
            print(" [AdaptyProvider] Failed with error after \(String(format: "%.2f", totalDuration))s: \(error)")
            return .failed(.providerError(error))
        }
    }

    // MARK: - Private

    @MainActor
    private func showController(
        configuration: AdaptyUI.PaywallConfiguration,
        from presenter: UIViewController
    ) async -> AFPaywallResult {
        print(" [AdaptyProvider] showController() started")
        
        // UIViewController.present() silently fails if presenter is not in the window hierarchy
        // (only logs to console, no throw/callback) — continuation will hang forever.
        // Therefore we check in advance and return .failed so PaywallKit can go to fallback.
        guard presenter.view.window != nil else {
            print(" [AdaptyProvider] Presenter is not in window hierarchy!")
            return .failed(.providerError(
                NSError(
                    domain: "PaywallKit",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Presenter is not in the window hierarchy"]
                )
            ))
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        
        return await withCheckedContinuation { continuation in
            let completionHandler = AFSingleFireContinuation(continuation)
            let delegate = AFAdaptyEventBridge(
                completion: completionHandler,
                validator: validator,
                startTime: startTime
            )

            do {
                print(" [AdaptyProvider] Creating paywall controller...")
                let controllerStartTime = CFAbsoluteTimeGetCurrent()
                
                let controller = try AdaptyUI.paywallController(
                    with: configuration,
                    delegate: delegate,
                    showDebugOverlay: false
                )
                
                let controllerDuration = CFAbsoluteTimeGetCurrent() - controllerStartTime
                print(" [AdaptyProvider] Controller creation took: \(String(format: "%.2f", controllerDuration))s")
                
                controller.modalPresentationStyle = .fullScreen

                // Attach delegate to controller — safely, without objc_setAssociatedObject
                delegate.retain(on: controller)

                print(" [AdaptyProvider] Presenting controller...")
                let presentStartTime = CFAbsoluteTimeGetCurrent()
                
                presenter.present(controller, animated: true) {
                    let presentDuration = CFAbsoluteTimeGetCurrent() - presentStartTime
                    print(" [AdaptyProvider] Controller presentation animation took: \(String(format: "%.2f", presentDuration))s")
                }
            } catch {
                print(" [AdaptyProvider] Failed to create controller: \(error)")
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
/// Lives exactly as long as the controller — without external retainers.
private final class AFAdaptyEventBridge: NSObject, AdaptyPaywallControllerDelegate {

    private let completion: AFSingleFireContinuation<AFPaywallResult>
    private let validator: AFSubscriptionValidator
    private let startTime: CFAbsoluteTime

    init(completion: AFSingleFireContinuation<AFPaywallResult>, validator: AFSubscriptionValidator, startTime: CFAbsoluteTime) {
        self.completion = completion
        self.validator = validator
        self.startTime = startTime
    }

    /// Attaches self to UIViewController via AssociatedObject.
    /// This is the only place where we use objc runtime — and it's justified.
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
                // Adapty calls didFinishPurchase with nil profile when user cancels
                // Apple ID / password sheet — transaction did not complete.
                // Keep paywall open (like didFailPurchase with .paymentCancelled).
                // Do NOT resume continuation — user can try again or close themselves.
                print("[PaywallKit][debug] didFinishPurchase: nil profile for '\(product.vendorProductId)' — Apple ID sheet cancelled. Keeping paywall open.")
                return
            }

            // Apply profile to SubscriptionService
            if let service = validator as? AFProfileApplicable {
                service.apply(profile: profile)
            }

            // Check activation
            let premiumIsActive = profile.accessLevels["premium"]?.isActive == true
            let validatorIsActive = await validator.isSubscriptionActive()
            let isActive = premiumIsActive || validatorIsActive

            dismiss(controller) {
                self.completion.resume(with: isActive ? .purchased : .failed(.subscriptionNotActive))
            }
        }
    }

    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        // Cancellation by user — keep paywall open
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
            dismiss(controller) {
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
            print(" [AdaptyProvider] User closed paywall")
            dismiss(controller) { self.completion.resume(with: .cancelled) }

        case .openURL(let url):
            print(" [AdaptyProvider] Opening URL: \(url)")
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)

        case .custom:
            break
        }
    }

    // MARK: - Errors (non-fatal)

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

    // MARK: - Lifecycle (no-op — add logger if needed)

    func paywallControllerDidAppear(_ controller: AdaptyPaywallController) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print(" [AdaptyProvider] Paywall appeared on screen after \(String(format: "%.2f", duration))s from showController() start")
    }
    
    func paywallControllerDidDisappear(_ controller: AdaptyPaywallController) {
        print(" [AdaptyProvider] Paywall disappeared from screen")
    }
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

/// Optional protocol for AFSubscriptionValidator that can accept AdaptyProfile.
/// Allows bridging between Adapty and your service without hard dependency.
public protocol AFProfileApplicable {
    func apply(profile: AdaptyProfile)
}
