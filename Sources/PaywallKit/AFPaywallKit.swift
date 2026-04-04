// AFPaywallKit.swift
// PaywallKit SDK
//
// Main SDK class for managing paywall.

import UIKit

// MARK: - PaywallKit

/// Main SDK class. Singleton for convenience.
///
/// **Usage:**
/// ```swift
/// // AppDelegate — set static properties, then call configure()
/// AFPaywallKit.productIds = ["com.app.premium.yearly"]
/// AFDefaultPaywallAdapter.privacyURL = URL(string: "https://...")
/// AFDefaultPaywallAdapter.termsURL   = URL(string: "https://...")
/// AFPaywallKit.configure(
///     primaryProvider: AFAdaptyProvider(validator: subscriptionService),
///     fallbackUI: MyPaywallViewController.self,
///     validator: subscriptionService
/// )
///
/// // Anywhere
/// let result = await AFPaywallKit.show(placementId: "onboarding", from: self)
/// ```
@MainActor
public final class AFPaywallKit {

    // MARK: - Global Configuration Properties

    /// Product IDs used by the StoreKit fallback provider.
    /// Set before calling `configure()`.
    public static var productIds: [String] = []

    /// Timeout for provider network requests. Default: 15 seconds.
    public static var fetchTimeout: TimeInterval = 15.0

    // MARK: - Singleton

    public static let shared = AFPaywallKit()
    private init() {}

    // MARK: - Internal State

    private var isConfigured = false
    private var primaryProvider: AFPaywallProvider?
    private var fallbackProvider: AFPaywallProvider?
    private var validator: AFSubscriptionValidator?
    private var eventHandler: AFPurchaseEventHandler?

    // MARK: - Presentation lock

    /// Global guard — prevents parallel display of two paywalls simultaneously.
    /// This happens when action-paywall is active, and sceneDidBecomeActive
    /// tries to launch launch-paywall (e.g. after dismissing App Store sheet).
    private var isPresenting = false

    // MARK: - Configure

    /// Configures SDK with a primary provider and custom fallback UI.
    ///
    /// - Parameters:
    ///   - primaryProvider: Main paywall provider (e.g. `AFAdaptyProvider`).
    ///   - fallbackUI: ViewController type conforming to `AFPaywallKitUI` used as fallback.
    ///   - validator: Service that checks active subscription status.
    ///   - eventHandler: Optional purchase events delegate.
    public static func configure(
        primaryProvider: AFPaywallProvider,
        fallbackUI: (any AFPaywallKitUI.Type)?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler? = nil
    ) {
        let fallbackProvider: AFStoreKitProvider? = fallbackUI.map {
            AFStoreKitProvider(
                productIds: productIds,
                validator: validator,
                uiType: $0
            )
        }
        shared.setup(
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }

    /// Full configuration with custom providers (advanced).
    public static func configure(
        primaryProvider: AFPaywallProvider,
        fallbackProvider: AFPaywallProvider?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler? = nil
    ) {
        shared.setup(
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }

    private func setup(
        primaryProvider: AFPaywallProvider,
        fallbackProvider: AFPaywallProvider?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler?
    ) {
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.validator = validator
        self.eventHandler = eventHandler
        self.isConfigured = true
    }

    // MARK: - Present / Show

    /// Shows paywall. First tries primary provider, on error — falls back to StoreKit.
    ///
    /// - Parameters:
    ///   - placementId: Placement ID from Adapty dashboard.
    ///   - presenter: UIViewController from which to present paywall.
    ///   - forceShow: If `true`, shows paywall even with active subscription. Default `false`.
    ///   - onDismiss: Called when user closes paywall without purchasing.
    @discardableResult
    public static func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await shared.present(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    /// Alias for `present()`.
    @discardableResult
    public static func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await present(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    /// Instance method for calling through `AFPaywallKit.shared.show()`.
    @discardableResult
    public func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await Self.show(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    private func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        guard isConfigured else {
            return .failed(.notConfigured)
        }

        guard !isPresenting else {
            return .cancelled
        }

        if !forceShow, let validator = validator {
            let hasActiveSubscription = await validator.isSubscriptionActive()
            if hasActiveSubscription {
                return .alreadyPurchased
            }
        }

        isPresenting = true
        defer { isPresenting = false }

        // 1. Try primary provider
        if let primary = primaryProvider {
            let result = await primary.present(placementId: placementId, from: presenter)

            switch result {
            case .purchased, .restored, .alreadyPurchased:
                handleResult(result)
                return result

            case .cancelled:
                handleResult(result)
                onDismiss?()
                return result

            case .failed:
                break // fall through to fallback
            }
        }

        // 2. Fallback to StoreKit with custom UI
        if let fallback = fallbackProvider {
            let result = await fallback.present(placementId: placementId, from: presenter)
            handleResult(result)
            if case .cancelled = result { onDismiss?() }
            return result
        }

        // 3. No fallback available
        return .failed(.noProducts)
    }

    // MARK: - Event handling

    private func handleResult(_ result: AFPaywallResult) {
        switch result {
        case .purchased, .restored, .alreadyPurchased:
            eventHandler?.onPurchaseSuccess(result: result)
        case .failed(let error):
            eventHandler?.onPurchaseFailure(error: error)
        case .cancelled:
            break
        }
    }
}
