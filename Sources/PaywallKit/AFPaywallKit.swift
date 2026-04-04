// AFPaywallKit.swift
// PaywallKit SDK
//
// Main SDK class for managing paywall.

import UIKit

// MARK: - PaywallKit

/// Main SDK class. Singleton for convenience.
@MainActor
public final class AFPaywallKit {

    // MARK: - Singleton

    public static let shared = AFPaywallKit()
    private init() {}

    // MARK: - Configuration

    private var configuration: AFPaywallKitConfiguration?
    private var primaryProvider: AFPaywallProvider?
    private var fallbackProvider: AFPaywallProvider?
    private var validator: AFSubscriptionValidator?
    private var eventHandler: AFPurchaseEventHandler?
    private var logger: AFPaywallKitLogger = AFConsoleLogger()

    // MARK: - Current presentation state

    private var currentOnDismissCallback: (() -> Void)?

    // MARK: - Presentation lock

    /// Global guard — prevents parallel display of two paywalls simultaneously.
    /// This happens when action-paywall is active, and sceneDidBecomeActive
    /// tries to launch launch-paywall (for example after dismissing App Store sheet).
    private var isPresenting = false

    // MARK: - Configure

    /// Configures SDK with Adapty as primary provider and StoreKit as fallback.
    ///
    /// **Example:**
    /// ```swift
    /// PaywallKit.configure(
    ///     configuration: .init(productIds: ["com.app.premium.yearly"]),
    ///     primaryProvider: AdaptyProvider(validator: subscriptionService),
    ///     fallbackUI: MyPaywallViewController.self,  // ← your UI for fallback
    ///     validator: subscriptionService
    /// )
    /// ```
    public static func configure(
        configuration: AFPaywallKitConfiguration,
        primaryProvider: AFPaywallProvider,
        fallbackUI: (any AFPaywallKitUI.Type)?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler? = nil
    ) {
        let fallbackProvider: AFStoreKitProvider? = fallbackUI.map {
            AFStoreKitProvider(
                productIds: configuration.productIds,
                validator: validator,
                uiType: $0
            )
        }

        shared.configure(
            configuration: configuration,
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }

    /// Full configuration with custom providers.
    public static func configure(
        configuration: AFPaywallKitConfiguration,
        primaryProvider: AFPaywallProvider,
        fallbackProvider: AFPaywallProvider?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler? = nil
    ) {
        shared.configure(
            configuration: configuration,
            primaryProvider: primaryProvider,
            fallbackProvider: fallbackProvider,
            validator: validator,
            eventHandler: eventHandler
        )
    }

    private func configure(
        configuration: AFPaywallKitConfiguration,
        primaryProvider: AFPaywallProvider,
        fallbackProvider: AFPaywallProvider?,
        validator: AFSubscriptionValidator,
        eventHandler: AFPurchaseEventHandler?
    ) {
        self.configuration = configuration
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.validator = validator
        self.eventHandler = eventHandler

        if let customLogger = configuration.logger {
            self.logger = customLogger
        }
    }

    // MARK: - Present

    /// Shows paywall. First tries Adapty, on error — fallback to StoreKit.
    ///
    /// **Example:**
    /// ```swift
    /// let result = await PaywallKit.present(
    ///     placementId: "onboarding",
    ///     from: self
    /// )
    /// if result.isSuccess {
    ///     // User subscribed
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - placementId: Placement ID from Adapty
    ///   - presenter: UIViewController from which to show paywall
    ///   - forceShow: If `true`, shows paywall even if there's a subscription (for restore/settings). Default `false`.
    ///   - onDismiss: Optional callback called after paywall is dismissed (closed by user).
    @discardableResult
    public static func present(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await shared.present(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    /// Alias for `present()` — shows paywall.
    @discardableResult
    public static func show(
        placementId: String,
        from presenter: UIViewController,
        forceShow: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) async -> AFPaywallResult {
        await present(placementId: placementId, from: presenter, forceShow: forceShow, onDismiss: onDismiss)
    }

    // MARK: - Instance methods (for calling through shared)

    /// Instance method for calling through `PaywallKit.shared.show()`.
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
        guard configuration != nil else {
            return .failed(.notConfigured)
        }

        // Global guard against parallel presentation.
        // Reason: sceneDidBecomeActive can trigger while action-paywall is still active
        // (after dismissing App Store sheet user returns to foreground).
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
        currentOnDismissCallback = onDismiss

        defer {
            isPresenting = false
            currentOnDismissCallback = nil
        }

        // 1. Try primary provider (Adapty)
        if let primary = primaryProvider {
            let result = await primary.present(placementId: placementId, from: presenter)

            switch result {
            case .purchased, .restored, .alreadyPurchased:
                handleResult(result)
                return result

            case .cancelled:
                handleResult(result)
                // Call onDismiss for cancelled (user closed paywall)
                onDismiss?()
                return result

            case .failed:
                // Fall back to fallback
                break
            }
        }

        // 2. Fallback to StoreKit with custom UI
        if let fallback = fallbackProvider {
            let result = await fallback.present(placementId: placementId, from: presenter)
            handleResult(result)

            // Call onDismiss for cancelled (user closed paywall)
            if case .cancelled = result {
                onDismiss?()
            }

            return result
        }

        // 3. No fallback — return error
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
